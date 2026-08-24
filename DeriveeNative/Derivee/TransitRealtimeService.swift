import Foundation
import SwiftProtobuf

public struct TransitAlert: Identifiable, Sendable, Equatable {
    public let id: String
    public let routeId: String
    public let headerText: String
    public let descriptionText: String?
    public let effect: String
    
    public init(id: String, routeId: String, headerText: String, descriptionText: String? = nil, effect: String = "SERVICE_CHANGE") {
        self.id = id
        self.routeId = routeId
        self.headerText = headerText
        self.descriptionText = descriptionText
        self.effect = effect
    }
}

final class TransitRealtimeService: @unchecked Sendable {
    static let shared = TransitRealtimeService()
    
    enum SubwayFeed: String, CaseIterable, Sendable {
        case numbered = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs"
        case ace = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace"
        case bdfm = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm"
        case g = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g"
        case jz = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz"
        case nqrw = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw"
        case l = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l"
        case sir = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si"
        case bus = "https://gtfsrt.prod.obanyc.com/tripUpdates"
        
        static func isBusRoute(_ routeId: String) -> Bool {
            let clean = routeId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.hasPrefix("M") && clean.count > 1 && clean.dropFirst().first?.isNumber == true { return true }
            if clean.hasPrefix("B") && clean.count > 1 && clean.dropFirst().first?.isNumber == true { return true }
            if clean.hasPrefix("Q") && clean.count > 1 && clean.dropFirst().first?.isNumber == true { return true }
            if clean.hasPrefix("BX") && clean.count > 2 && clean.dropFirst(2).first?.isNumber == true { return true }
            if clean.hasPrefix("S") && clean.count > 1 && clean.dropFirst().first?.isNumber == true { return true }
            if clean.contains("SBS") || clean.contains("BUS") { return true }
            return false
        }
        
        static func feed(for routeId: String) -> SubwayFeed {
            let clean = routeId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if isBusRoute(clean) {
                return .bus
            }
            switch clean {
            case "1", "2", "3", "4", "5", "6", "6X", "7", "7X", "S", "GS":
                return .numbered
            case "A", "C", "E", "H", "FS":
                return .ace
            case "B", "D", "F", "FX", "M":
                return .bdfm
            case "G":
                return .g
            case "J", "Z":
                return .jz
            case "N", "Q", "R", "W":
                return .nqrw
            case "L":
                return .l
            case "SIR":
                return .sir
            default:
                if clean.hasPrefix("6") || clean.hasPrefix("7") { return .numbered }
                return .l
            }
        }
    }
    
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    /// Fetches live GTFS-RT feed for a given route and parses arrivals matching `stopId`.
    func fetchLiveArrivals(for stopId: String, routeId: String) async throws -> [SpatialDatabaseManager.ArrivalInfo] {
        return try await fetchLiveArrivals(for: stopId, routeIds: [routeId])
    }
    
    /// Fetches live GTFS-RT feeds for multiple co-located routes, multiplexing across distinct feeds in parallel.
    func fetchLiveArrivals(for stopId: String, routeIds: [String]) async throws -> [SpatialDatabaseManager.ArrivalInfo] {
        guard !routeIds.isEmpty else { return [] }
        let uniqueFeeds = Array(Set(routeIds.map { SubwayFeed.feed(for: $0) }))
        
        var allArrivals: [SpatialDatabaseManager.ArrivalInfo] = []
        
        try await withThrowingTaskGroup(of: [SpatialDatabaseManager.ArrivalInfo].self) { group in
            for feed in uniqueFeeds {
                group.addTask {
                    guard let url = URL(string: feed.rawValue) else { return [] }
                    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
                    request.httpMethod = "GET"
                    
                    let (data, response) = try await self.session.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        return []
                    }
                    return try self.parseFeedMessage(data: data, stopId: stopId, targetRouteIds: routeIds)
                }
            }
            
            for try await feedArrivals in group {
                allArrivals.append(contentsOf: feedArrivals)
            }
        }
        
        allArrivals.sort { $0.minutes < $1.minutes }
        return Array(allArrivals.prefix(12))
    }
    
    /// Parses binary Protobuf GTFS-RT feed message data into `SpatialDatabaseManager.ArrivalInfo` models
    func parseFeedMessage(
        data: Data,
        stopId: String,
        targetRouteId: String = "",
        targetRouteIds: [String] = [],
        referenceDate: Date = Date()
    ) throws -> [SpatialDatabaseManager.ArrivalInfo] {
        let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: data)
        let nowEpoch = Int64(referenceDate.timeIntervalSince1970)
        
        let allowedRoutes: Set<String> = {
            var set = Set(targetRouteIds.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) })
            let cleanTarget = targetRouteId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTarget.isEmpty {
                set.insert(cleanTarget)
            }
            return set
        }()
        
        var rawArrivals: [(line: String, destination: String, arrivalEpoch: Int64, direction: String?, distance: String?)] = []
        let cleanStopId = stopId.uppercased().replacingOccurrences(of: "STOP_", with: "").replacingOccurrences(of: "BUS_", with: "")
        
        for entity in feedMessage.entity {
            guard entity.hasTripUpdate else { continue }
            let tripUpdate = entity.tripUpdate
            let tripRouteId = tripUpdate.trip.hasRouteID ? tripUpdate.trip.routeID : (targetRouteIds.first ?? targetRouteId)
            
            if !allowedRoutes.isEmpty {
                let cleanTripRoute = tripRouteId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let isAllowed = allowedRoutes.contains(cleanTripRoute) || allowedRoutes.contains(where: { cleanTripRoute.hasPrefix($0) || $0.hasPrefix(cleanTripRoute) })
                guard isAllowed else { continue }
            }
            
            // Match stop updates
            for (idx, stopUpdate) in tripUpdate.stopTimeUpdate.enumerated() {
                let currentStopId = stopUpdate.stopID.uppercased()
                let matches = isStopMatch(currentStopId: currentStopId, targetStopId: cleanStopId)
                
                if matches {
                    let arrivalEpoch: Int64
                    if stopUpdate.hasArrival && stopUpdate.arrival.hasTime {
                        arrivalEpoch = stopUpdate.arrival.time
                    } else if stopUpdate.hasDeparture && stopUpdate.departure.hasTime {
                        arrivalEpoch = stopUpdate.departure.time
                    } else {
                        continue
                    }
                    
                    // Filter out arrivals in the past (> 60s ago)
                    let diffSec = arrivalEpoch - nowEpoch
                    guard diffSec >= -60 else { continue }
                    
                    let destination = resolveDestination(tripUpdate: tripUpdate, line: tripRouteId, stopId: currentStopId)
                    let direction = resolveDirection(tripUpdate: tripUpdate, line: tripRouteId, stopId: currentStopId)
                    let stopsAway = idx > 0 ? "\(idx) stops away" : "Approaching"
                    
                    rawArrivals.append((line: tripRouteId, destination: destination, arrivalEpoch: arrivalEpoch, direction: direction, distance: stopsAway))
                }
            }
        }
        
        // Sort by earliest arrival
        rawArrivals.sort { $0.arrivalEpoch < $1.arrivalEpoch }
        
        // Convert to ArrivalInfo
        let arrivals = rawArrivals.prefix(12).map { item -> SpatialDatabaseManager.ArrivalInfo in
            let diffSec = item.arrivalEpoch - nowEpoch
            let minutes = max(0, Int(ceil(Double(diffSec) / 60.0)))
            return SpatialDatabaseManager.ArrivalInfo(
                line: item.line,
                destination: item.destination,
                minutes: minutes,
                direction: item.direction,
                distanceDescription: item.distance
            )
        }
        
        return Array(arrivals)
    }
    
    private func isStopMatch(currentStopId: String, targetStopId: String) -> Bool {
        let cleanCurrent = currentStopId.uppercased().replacingOccurrences(of: "STOP_", with: "").replacingOccurrences(of: "BUS_", with: "")
        let cleanTarget = targetStopId.uppercased().replacingOccurrences(of: "STOP_", with: "").replacingOccurrences(of: "BUS_", with: "")
        if cleanCurrent == cleanTarget { return true }
        if cleanCurrent.hasPrefix(cleanTarget) || cleanTarget.hasPrefix(cleanCurrent) { return true }
        // Handle North/Southbound suffixes e.g. "L08N" vs "L08"
        let baseCurrent = cleanCurrent.trimmingCharacters(in: CharacterSet(charactersIn: "NSEW"))
        let baseTarget = cleanTarget.trimmingCharacters(in: CharacterSet(charactersIn: "NSEW"))
        if !baseCurrent.isEmpty && baseCurrent == baseTarget { return true }
        return false
    }
    
    public func resolveDirection(tripUpdate: TransitRealtime_TripUpdate, line: String, stopId: String) -> String {
        let isNorthbound = stopId.hasSuffix("N")
        let isSouthbound = stopId.hasSuffix("S")
        let isEastbound = stopId.hasSuffix("E")
        let isWestbound = stopId.hasSuffix("W")
        
        switch line.uppercased() {
        case "L":
            if isNorthbound { return "Manhattan-bound" }
            if isSouthbound { return "Brooklyn-bound" }
        case "G":
            if isNorthbound { return "Queens-bound" }
            if isSouthbound { return "Brooklyn-bound" }
        case "7", "7X":
            if isNorthbound { return "Queens-bound" }
            if isSouthbound { return "Manhattan-bound" }
        case "1", "2", "3":
            if isNorthbound { return "Uptown & Bronx" }
            if isSouthbound { return "Downtown & Brooklyn" }
        case "4", "5", "6", "6X":
            if isNorthbound { return "Uptown & Bronx" }
            if isSouthbound { return "Downtown & Brooklyn" }
        case "A", "C", "E":
            if isNorthbound { return "Uptown & Queens / Bronx" }
            if isSouthbound { return "Downtown & Brooklyn" }
        case "B", "D", "F", "FX", "M":
            if isNorthbound { return "Uptown & Queens / Bronx" }
            if isSouthbound { return "Downtown & Brooklyn" }
        case "N", "Q", "R", "W":
            if isNorthbound { return "Uptown & Queens" }
            if isSouthbound { return "Downtown & Brooklyn" }
        case "J", "Z":
            if isNorthbound { return "Queens-bound" }
            if isSouthbound { return "Manhattan-bound" }
        case "SIR":
            if isNorthbound { return "Inbound (St. George)" }
            if isSouthbound { return "Outbound (Tottenville)" }
        default:
            break
        }
        
        if isNorthbound { return "Northbound" }
        if isSouthbound { return "Southbound" }
        if isEastbound { return "Eastbound" }
        if isWestbound { return "Westbound" }
        
        if SubwayFeed.isBusRoute(line) {
            return "Southbound"
        }
        return "Uptown / Downtown"
    }
    
    public func fetchServiceAlerts(for routeId: String) async -> [TransitAlert] {
        // Generates active/synthetic alerts if line is undergoing planned service adjustments
        let clean = routeId.uppercased()
        switch clean {
        case "L":
            return [
                TransitAlert(id: "L_ALERT_1", routeId: "L", headerText: "Planned Work: Late night single-tracking between 8th Ave and Bedford Ave. Allow additional travel time.")
            ]
        case "7", "7X":
            return [
                TransitAlert(id: "7_ALERT_1", routeId: "7", headerText: "Express service running local between 74 St-Broadway and Queensboro Plaza.")
            ]
        case "A", "C":
            return [
                TransitAlert(id: "A_ALERT_1", routeId: "A", headerText: "Downtown trains run via F line from W 4 St to Jay St-MetroTech.")
            ]
        default:
            return []
        }
    }
    
    public func fetchServiceAlerts(for routeIds: [String]) async -> [TransitAlert] {
        var alerts: [TransitAlert] = []
        var seen = Set<String>()
        for rId in routeIds {
            for alert in await fetchServiceAlerts(for: rId) {
                if !seen.contains(alert.id) {
                    seen.insert(alert.id)
                    alerts.append(alert)
                }
            }
        }
        return alerts
    }
    
    private func resolveDestination(tripUpdate: TransitRealtime_TripUpdate, line: String, stopId: String) -> String {
        let isNorthbound = stopId.hasSuffix("N")
        let isSouthbound = stopId.hasSuffix("S")
        
        switch line.uppercased() {
        case "L":
            if isNorthbound { return "Manhattan - 8th Ave" }
            if isSouthbound { return "Brooklyn - Canarsie / Rockaway Pkwy" }
            return "8th Ave / Canarsie"
        case "G":
            if isNorthbound { return "Queens - Court Sq" }
            if isSouthbound { return "Brooklyn - Church Ave" }
            return "Court Sq / Church Ave"
        case "1":
            if isNorthbound { return "Uptown - Van Cortlandt Park" }
            return "Downtown - South Ferry"
        case "2":
            if isNorthbound { return "Uptown - Wakefield 241 St" }
            return "Brooklyn - Flatbush Ave"
        case "3":
            if isNorthbound { return "Uptown - Harlem 148 St" }
            return "Brooklyn - New Lots Ave"
        case "4", "5", "6", "6X":
            if isNorthbound { return "Uptown / Bronx - Woodlawn / Pelham" }
            return "Downtown / Brooklyn - Crown Hts / Utica"
        case "7", "7X":
            if isNorthbound { return "Queens - Flushing Main St" }
            return "Manhattan - 34 St Hudson Yards"
        case "A":
            if isNorthbound { return "Uptown - Inwood 207 St" }
            return "Far Rockaway / Lefferts Blvd"
        case "C":
            if isNorthbound { return "Uptown - 168 St" }
            return "Brooklyn - Euclid Ave"
        case "E":
            if isNorthbound { return "Queens - Jamaica Center" }
            return "Manhattan - World Trade Center"
        case "N", "Q", "R", "W":
            if isNorthbound { return "Uptown / Queens - Astoria / 96 St" }
            return "Brooklyn - Coney Island / Bay Ridge"
        case "B", "D":
            if isNorthbound { return "Uptown / Bronx - Bedford Pk / Norwood" }
            return "Brooklyn - Brighton Beach / Coney Island"
        case "F", "FX", "M":
            if isNorthbound { return "Queens - Jamaica / Forest Hills" }
            return "Brooklyn - Coney Island / Middle Village"
        case "J", "Z":
            if isNorthbound { return "Queens - Jamaica Center" }
            return "Manhattan - Broad St"
        default:
            if SubwayFeed.isBusRoute(line) {
                return "\(line) Terminal"
            }
            return isNorthbound ? "Uptown / Terminal" : "Downtown / Terminal"
        }
    }
}
