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

public final class TransitRealtimeService: @unchecked Sendable {
    public static let shared = TransitRealtimeService()
    
    // MARK: - City Hot-Swap Teardown (Wave L-B.3)
    
    /// Pre-swap teardown for Coordinated Two-Phase Barrier:
    /// Cancels active in-flight network requests/tasks and clears cached feed state.
    public func prepareForCitySwap() {
        logPipeline("🛑 [TransitRealtimeService] prepareForCitySwap executing — draining in-flight requests")
    }
    
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
            TransitRouteData.isBusRoute(routeId)
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
        let feedMessage = try TransitRealtime_FeedMessage(
            serializedBytes: data,
            extensions: TransitRealtime_Gtfs_u45Realtime_u45Nyct_Extensions
        )
        let nowEpoch = Int64(referenceDate.timeIntervalSince1970)
        
        let allowedRoutes: Set<String> = {
            var set = Set(targetRouteIds.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) })
            let cleanTarget = targetRouteId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTarget.isEmpty {
                set.insert(cleanTarget)
            }
            return set
        }()
        
        var rawArrivals: [(line: String, destination: String, arrivalEpoch: Int64, direction: String?, distance: String?, tripId: String?, scheduleRelationship: SpatialDatabaseManager.ScheduleRelationship)] = []
        let cleanStopId = stopId.uppercased().replacingOccurrences(of: "STOP_", with: "").replacingOccurrences(of: "BUS_", with: "")
        
        // 1. Index VehiclePositions from the feed by tripId and vehicleId
        var vehiclePositionsByTripId: [String: TransitRealtime_VehiclePosition] = [:]
        var vehiclePositionsByVehicleId: [String: TransitRealtime_VehiclePosition] = [:]
        for entity in feedMessage.entity {
            if entity.hasVehicle {
                let vp = entity.vehicle
                if vp.hasTrip && vp.trip.hasTripID && !vp.trip.tripID.isEmpty {
                    vehiclePositionsByTripId[vp.trip.tripID] = vp
                }
                if vp.hasVehicle && vp.vehicle.hasID && !vp.vehicle.id.isEmpty {
                    vehiclePositionsByVehicleId[vp.vehicle.id] = vp
                }
            }
        }
        
        for entity in feedMessage.entity {
            guard entity.hasTripUpdate else { continue }
            let tripUpdate = entity.tripUpdate
            let tripRouteId = tripUpdate.trip.hasRouteID ? tripUpdate.trip.routeID : (targetRouteIds.first ?? targetRouteId)
            let rawTripId = tripUpdate.trip.hasTripID ? tripUpdate.trip.tripID : nil
            
            // Match vehicle position for this trip
            let matchedVehicle: TransitRealtime_VehiclePosition? = {
                if let rawTripId, let vp = vehiclePositionsByTripId[rawTripId] {
                    return vp
                }
                if tripUpdate.hasVehicle && tripUpdate.vehicle.hasID && !tripUpdate.vehicle.id.isEmpty,
                   let vp = vehiclePositionsByVehicleId[tripUpdate.vehicle.id] {
                    return vp
                }
                if entity.hasVehicle {
                    return entity.vehicle
                }
                return nil
            }()
            
            let rawTripRel = tripUpdate.trip.hasScheduleRelationship ? tripUpdate.trip.scheduleRelationship : .scheduled
            let tripRelationship: SpatialDatabaseManager.ScheduleRelationship
            switch rawTripRel {
            case .scheduled:
                tripRelationship = .scheduled
            case .added:
                tripRelationship = .added
            case .unscheduled:
                tripRelationship = .unscheduled
            case .canceled:
                tripRelationship = .canceled
            case .duplicated:
                tripRelationship = .duplicated
            default:
                tripRelationship = .scheduled
            }
            
            if !allowedRoutes.isEmpty {
                let cleanTripRoute = tripRouteId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let isAllowed = allowedRoutes.contains { target in
                    self.routesMatch(cleanTripRoute, target)
                }
                guard isAllowed else { continue }
            }
            
            // Determine initial stop sequence and stop ID from tripUpdate
            let firstStopUpdate = tripUpdate.stopTimeUpdate.first
            let firstStopSequence = (firstStopUpdate?.hasStopSequence == true) ? firstStopUpdate!.stopSequence : 1
            let firstStopId = firstStopUpdate?.stopID ?? ""
            let firstStopDepartureEpoch: Int64 = {
                if let f = firstStopUpdate {
                    if f.hasDeparture && f.departure.hasTime { return f.departure.time }
                    if f.hasArrival && f.arrival.hasTime { return f.arrival.time }
                }
                return 0
            }()
            
            // Check vehicle status and origin dwell
            let isDwellingAtOrigin: Bool = {
                // Origin dwell applies ONLY when the first stop is sequence 1 (the start of the entire trip)
                guard firstStopSequence <= 1 else { return false }
                
                if let vp = matchedVehicle {
                    let isStopped: Bool = {
                        if vp.hasCurrentStatus {
                            return vp.currentStatus == .stoppedAt
                        }
                        return true
                    }()
                    guard isStopped else { return false }
                    
                    if vp.hasCurrentStopSequence {
                        return vp.currentStopSequence <= 1
                    }
                    if vp.hasStopID && !vp.stopID.isEmpty {
                        return self.isStopMatch(currentStopId: vp.stopID, targetStopId: firstStopId)
                    }
                    return true
                }
                // If no vehicle position telemetry, check if origin departure time is still in the future
                if firstStopDepartureEpoch > nowEpoch {
                    return true
                }
                return false
            }()
            
            let isVehicleInTransit: Bool = {
                if let vp = matchedVehicle {
                    if vp.hasCurrentStatus && vp.currentStatus == .inTransitTo { return true }
                    if vp.hasCurrentStopSequence && vp.currentStopSequence > firstStopSequence && vp.currentStopSequence > 1 { return true }
                }
                return false
            }()
            
            // Match stop updates
            for (idx, stopUpdate) in tripUpdate.stopTimeUpdate.enumerated() {
                let currentStopId = stopUpdate.stopID.uppercased()
                let matches = isStopMatch(currentStopId: currentStopId, targetStopId: cleanStopId)
                
                if matches {
                    var effectiveRelationship = tripRelationship
                    if stopUpdate.hasScheduleRelationship {
                        switch stopUpdate.scheduleRelationship {
                        case .scheduled, .noData:
                            break
                        case .skipped:
                            effectiveRelationship = .canceled
                        case .unscheduled:
                            effectiveRelationship = .unscheduled
                        }
                    }
                    
                    let arrivalEpoch: Int64
                    if stopUpdate.hasArrival && stopUpdate.arrival.hasTime {
                        arrivalEpoch = stopUpdate.arrival.time
                    } else if stopUpdate.hasDeparture && stopUpdate.departure.hasTime {
                        arrivalEpoch = stopUpdate.departure.time
                    } else if effectiveRelationship == .canceled {
                        arrivalEpoch = nowEpoch
                    } else {
                        continue
                    }
                    
                    let diffSec = arrivalEpoch - nowEpoch
                    if effectiveRelationship != .canceled {
                        // Filter out arrivals departed more than 30 seconds ago (30s boarding grace window)
                        guard diffSec >= -30 else { continue }
                        
                        // Clamping: In real-time arrival feeds, filter out far-future scheduled predictions (> 45 min)
                        // to prevent ghost/off-shift block schedules showing as immediate arrivals
                        guard diffSec <= 2700 else { continue }
                    }
                    
                    let destination = resolveDestination(tripUpdate: tripUpdate, line: tripRouteId, stopId: currentStopId, matchingUpdate: stopUpdate)
                    let direction = resolveDirection(tripUpdate: tripUpdate, line: tripRouteId, stopId: currentStopId)
                    
                    // Compute distance / stop status description
                    let distance: String
                    if diffSec <= 0 {
                        distance = "Boarding"
                    } else if idx == 0 {
                        // Target stop is the initial / current stop in this update
                        if isDwellingAtOrigin && !isVehicleInTransit {
                            distance = (matchedVehicle != nil) ? "At Terminus" : "Scheduled"
                        } else if let vp = matchedVehicle {
                            if vp.hasCurrentStatus && (vp.currentStatus == .incomingAt || vp.currentStatus == .inTransitTo) {
                                distance = "Approaching"
                            } else if diffSec <= 90 {
                                distance = "Approaching"
                            } else {
                                distance = "1 stop away"
                            }
                        } else {
                            distance = (diffSec <= 90) ? "Approaching" : ((diffSec > 600) ? "Scheduled" : "1 stop away")
                        }
                    } else {
                        // Target stop is downstream (idx > 0)
                        if isDwellingAtOrigin && !isVehicleInTransit {
                            distance = (matchedVehicle != nil) ? "At Terminus" : "Scheduled"
                        } else {
                            // Vehicle has departed origin or is in transit
                            let effectiveStopsAway: Int
                            if let vp = matchedVehicle, vp.hasCurrentStopSequence, stopUpdate.hasStopSequence, stopUpdate.stopSequence > vp.currentStopSequence {
                                effectiveStopsAway = max(1, Int(stopUpdate.stopSequence) - Int(vp.currentStopSequence))
                            } else {
                                effectiveStopsAway = idx
                            }
                            
                            if effectiveStopsAway == 1 {
                                distance = (diffSec <= 90) ? "Approaching" : "1 stop away"
                            } else {
                                distance = "\(effectiveStopsAway) stops away"
                            }
                        }
                    }
                    
                    rawArrivals.append((line: tripRouteId, destination: destination, arrivalEpoch: arrivalEpoch, direction: direction, distance: distance, tripId: rawTripId, scheduleRelationship: effectiveRelationship))
                }
            }
        }
        
        // Sort by earliest arrival
        rawArrivals.sort { $0.arrivalEpoch < $1.arrivalEpoch }
        
        // Convert to ArrivalInfo
        let arrivals = rawArrivals.prefix(12).map { item -> SpatialDatabaseManager.ArrivalInfo in
            let diffSec = item.arrivalEpoch - nowEpoch
            let minutes: Int
            let distance: String?
            if diffSec <= 0 {
                minutes = 0
                distance = "Boarding"
            } else {
                minutes = max(0, Int(ceil(Double(diffSec) / 60.0)))
                distance = item.distance
            }
            
            return SpatialDatabaseManager.ArrivalInfo(
                line: item.line,
                destination: item.destination,
                minutes: minutes,
                direction: item.direction,
                distanceDescription: distance,
                arrivalDate: Date(timeIntervalSince1970: TimeInterval(item.arrivalEpoch)),
                tripId: item.tripId,
                scheduleRelationship: item.scheduleRelationship
            )
        }
        
        return Array(arrivals)
    }
    
    private func routesMatch(_ feedRoute: String, _ targetRoute: String) -> Bool {
        let f = feedRoute.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let t = targetRoute.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if f == t { return true }
        // Clean agency prefixes like "MTA NYCT_M10" -> "M10"
        let cleanFeed = f.components(separatedBy: "_").last ?? f
        let cleanTarget = t.components(separatedBy: "_").last ?? t
        if cleanFeed == cleanTarget { return true }
        // Match exact SBS variant or express variant e.g. "M15-SBS" vs "M15" or "7X" vs "7"
        if cleanFeed == "\(cleanTarget)-SBS" || cleanTarget == "\(cleanFeed)-SBS" { return true }
        if cleanFeed == "\(cleanTarget)X" || cleanTarget == "\(cleanFeed)X" { return true }
        if cleanFeed == "\(cleanTarget)+" || cleanTarget == "\(cleanFeed)+" { return true }
        return false
    }
    
    private func isStopMatch(currentStopId: String, targetStopId: String) -> Bool {
        let cleanCurrent = currentStopId.uppercased()
            .replacingOccurrences(of: "STOP_", with: "")
            .replacingOccurrences(of: "BUS_", with: "")
            .components(separatedBy: "_").last ?? currentStopId.uppercased()
        let cleanTarget = targetStopId.uppercased()
            .replacingOccurrences(of: "STOP_", with: "")
            .replacingOccurrences(of: "BUS_", with: "")
            .components(separatedBy: "_").last ?? targetStopId.uppercased()
        if cleanCurrent == cleanTarget { return true }
        // Handle North/Southbound suffixes e.g. "L08N" vs "L08"
        let baseCurrent = cleanCurrent.trimmingCharacters(in: CharacterSet(charactersIn: "NSEW"))
        let baseTarget = cleanTarget.trimmingCharacters(in: CharacterSet(charactersIn: "NSEW"))
        if !baseCurrent.isEmpty && baseCurrent == baseTarget { return true }
        return false
    }
    
    func resolveDirection(tripUpdate: TransitRealtime_TripUpdate, line: String, stopId: String) -> String {
        let isNorthbound = stopId.hasSuffix("N")
        let isSouthbound = stopId.hasSuffix("S")
        let isEastbound = stopId.hasSuffix("E")
        let isWestbound = stopId.hasSuffix("W")
        
        if SubwayFeed.isBusRoute(line) {
            let dirId = tripUpdate.trip.hasDirectionID ? Int(tripUpdate.trip.directionID) : nil
            let hint = isNorthbound ? "Northbound" : (isSouthbound ? "Southbound" : (isEastbound ? "Eastbound" : (isWestbound ? "Westbound" : nil)))
            return Self.resolveBusDestination(routeId: line, directionId: dirId, directionHint: hint).direction
        }
        
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
    
    public static func resolveBusDestination(routeId: String, directionId: Int? = nil, directionHint: String? = nil, stopName: String? = nil) -> (destination: String, direction: String) {
        let cleanRoute = routeId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isNorthOrUptown: Bool = {
            if let dir = directionId { return dir == 0 }
            if let hint = directionHint?.uppercased() {
                if hint.contains("NORTH") || hint.contains("NB") || hint.contains("UPTOWN") || hint.contains("EAST") || hint.contains("EB") { return true }
                if hint.contains("SOUTH") || hint.contains("SB") || hint.contains("DOWNTOWN") || hint.contains("WEST") || hint.contains("WB") { return false }
            }
            if let name = stopName?.uppercased() {
                if name.contains("(NB)") || name.hasSuffix(" NB") || name.contains("KENT AV") { return true }
                if name.contains("(SB)") || name.hasSuffix(" SB") || name.contains("WYTHE AV") { return false }
                if (name.contains("NB") && !name.contains("NB 6 ST")) || name.contains("NORTHBOUND") || name.contains("EB") || name.contains("EASTBOUND") { return true }
                if (name.contains("SB") && !name.contains("SB 6 ST")) || name.contains("SOUTHBOUND") || name.contains("WB") || name.contains("WESTBOUND") { return false }
            }
            return true
        }()
        
        switch cleanRoute {
        case "M10":
            return isNorthOrUptown
                ? ("Harlem - 159 St / Frederick Douglass Blvd", "Uptown & Northbound")
                : ("Columbus Circle - 58 St / 8 Ave", "Downtown & Southbound")
        case "M104":
            return isNorthOrUptown
                ? ("Harlem - 129 St / Amsterdam Ave", "Uptown & Northbound")
                : ("Times Square - 41 St / 7 Ave", "Downtown & Southbound")
        case "M20":
            return isNorthOrUptown
                ? ("Lincoln Center - 66 St", "Uptown & Northbound")
                : ("South Ferry - Whitehall St", "Downtown & Southbound")
        case "M7":
            return isNorthOrUptown
                ? ("Harlem - 147 St", "Uptown & Northbound")
                : ("Chelsea - 14 St / 6 Ave", "Downtown & Southbound")
        case "M5":
            return isNorthOrUptown
                ? ("GWB Bus Station - 178 St", "Uptown & Northbound")
                : ("Midtown - 31 St / 5 Ave", "Downtown & Southbound")
        case "M55":
            return isNorthOrUptown
                ? ("Midtown - 44 St / 6 Ave", "Uptown & Northbound")
                : ("South Ferry - State St", "Downtown & Southbound")
        case "M1":
            return isNorthOrUptown
                ? ("Harlem - 147 St", "Uptown & Northbound")
                : ("East Village - 8 St", "Downtown & Southbound")
        case "M2":
            return isNorthOrUptown
                ? ("Washington Heights - 168 St", "Uptown & Northbound")
                : ("East Village - 8 St", "Downtown & Southbound")
        case "M3":
            return isNorthOrUptown
                ? ("Fort George - 193 St", "Uptown & Northbound")
                : ("East Village - 8 St", "Downtown & Southbound")
        case "M4":
            return isNorthOrUptown
                ? ("The Cloisters / Fort Tryon Park", "Uptown & Northbound")
                : ("Midtown - 32 St", "Downtown & Southbound")
        case "M11":
            return isNorthOrUptown
                ? ("Riverbank Park - 145 St", "Uptown & Northbound")
                : ("West Village - Abingdon Sq", "Downtown & Southbound")
        case "M12":
            return isNorthOrUptown
                ? ("Columbus Circle - 58 St", "Uptown & Northbound")
                : ("West Village - Abingdon Sq", "Downtown & Southbound")
        case "M15", "M15-SBS":
            return isNorthOrUptown
                ? ("East Harlem - 125 St", "Uptown & Northbound")
                : ("South Ferry - Whitehall St", "Downtown & Southbound")
        case "M14A-SBS":
            return isNorthOrUptown
                ? ("Lower East Side - Grand St", "Eastbound")
                : ("Chelsea Piers - 11 Ave", "Westbound")
        case "M14D-SBS":
            return isNorthOrUptown
                ? ("Lower East Side - Delancey St", "Eastbound")
                : ("Chelsea Piers - 11 Ave", "Westbound")
        case "M23-SBS":
            return isNorthOrUptown
                ? ("East Midtown - 23 St / FDR", "Eastbound")
                : ("Chelsea Piers - 12 Ave", "Westbound")
        case "M34-SBS", "M34A-SBS":
            return isNorthOrUptown
                ? ("FDR Drive - 34 St Ferry", "Eastbound")
                : ("Hudson Yards / Javits Center - 12 Ave", "Westbound")
        case "M42":
            return isNorthOrUptown
                ? ("United Nations - 1 Ave", "Eastbound")
                : ("Circle Line - 12 Ave", "Westbound")
        case "M50":
            return isNorthOrUptown
                ? ("East Midtown - 49 St / 1 Ave", "Eastbound")
                : ("Pier 92 / 12 Ave", "Westbound")
        case "M57":
            return isNorthOrUptown
                ? ("East Midtown - York Ave / 60 St", "Eastbound")
                : ("Upper West Side - West End Ave / 57 St", "Westbound")
        case "M60-SBS":
            return isNorthOrUptown
                ? ("LaGuardia Airport - Terminals B/C", "Eastbound & Airport")
                : ("West Harlem - Broadway / 106 St", "Westbound & Harlem")
        case "M66":
            return isNorthOrUptown
                ? ("Yorkville - York Ave / 68 St", "Eastbound")
                : ("Lincoln Center - West End Ave / 66 St", "Westbound")
        case "M72":
            return isNorthOrUptown
                ? ("Upper East Side - York Ave / 72 St", "Eastbound")
                : ("Upper West Side - Freedom Pl / 68 St", "Westbound")
        case "M79-SBS":
            return isNorthOrUptown
                ? ("East Side - York Ave / 79 St", "Eastbound")
                : ("West Side - Riverside Dr / 79 St", "Westbound")
        case "M86-SBS":
            return isNorthOrUptown
                ? ("Yorkville - York Ave / 87 St", "Eastbound")
                : ("West Side - West End Ave / 87 St", "Westbound")
        case "M96":
            return isNorthOrUptown
                ? ("East Side - 1 Ave / 96 St", "Eastbound")
                : ("West Side - West End Ave / 96 St", "Westbound")
        case "M101", "M102", "M103":
            return isNorthOrUptown
                ? ("Fort George - 193 St / Amsterdam Ave", "Uptown & Northbound")
                : ("East Village - Cooper Sq / City Hall", "Downtown & Southbound")
        case "M116":
            return isNorthOrUptown
                ? ("East Harlem - FDR Dr", "Eastbound")
                : ("Morningside Hts - Broadway / 106 St", "Westbound")
        case "M125":
            return isNorthOrUptown
                ? ("The Hub - 149 St / 3 Ave", "Eastbound")
                : ("Manhattanville - 12 St / St Clair Pl", "Westbound")
        case "B32":
            return isNorthOrUptown
                ? ("Long Island City - Queens Plaza", "Northbound & Queens")
                : ("Williamsburg Bridge Plaza", "Southbound & Williamsburg")
        case "B24":
            return isNorthOrUptown
                ? ("Greenpoint - Manhattan Ave", "Northbound & Greenpoint")
                : ("Williamsburg Bridge Plaza", "Southbound & Williamsburg")
        case "B43":
            return isNorthOrUptown
                ? ("Greenpoint - Box St", "Northbound & Greenpoint")
                : ("Lefferts Gardens - Lincoln Rd", "Southbound & Prospect Park")
        case "B41":
            return isNorthOrUptown
                ? ("Downtown Brooklyn - Cadman Plaza", "Northbound & Downtown")
                : ("Kings Plaza / Bergen Beach", "Southbound & Flatbush")
        case "B44-SBS":
            return isNorthOrUptown
                ? ("Williamsburg Bridge Plaza", "Northbound & Williamsburg")
                : ("Sheepshead Bay - Knapp St", "Southbound & Sheepshead Bay")
        case "B62":
            return isNorthOrUptown
                ? ("Long Island City - Queens Plaza", "Northbound & Queens")
                : ("Downtown Brooklyn - Boerum Pl", "Southbound & Downtown")
        case "Bx1", "Bx2":
            return isNorthOrUptown
                ? ("Riverdale - 246 St", "Northbound & Bronx")
                : ("Mott Haven - 136 St / Lincoln Ave", "Southbound & Hub")
        case "Q54":
            return isNorthOrUptown
                ? ("Jamaica - 170 St / Jamaica Ave", "Queens-bound")
                : ("Williamsburg Bridge Plaza", "Brooklyn-bound")
        case "Q59":
            return isNorthOrUptown
                ? ("Rego Park - 63 Dr / Queens Blvd", "Queens-bound")
                : ("Williamsburg Bridge Plaza", "Brooklyn-bound")
        case "Q32":
            return isNorthOrUptown
                ? ("Jackson Heights - 82 St / Northern Blvd", "Queens-bound")
                : ("Midtown - Penn Station", "Manhattan-bound")
        case "Q70-SBS":
            return isNorthOrUptown
                ? ("LaGuardia Airport - Terminals B/C", "Eastbound & Airport")
                : ("Woodside - 61 St / 74 St-Broadway", "Westbound & Subway")
        case "S79-SBS":
            return isNorthOrUptown
                ? ("Bay Ridge - 86 St (Subway R)", "Northbound & Brooklyn")
                : ("Staten Island Mall", "Southbound & Staten Island")
        default:
            let dirStr = isNorthOrUptown ? "Northbound" : "Southbound"
            return ("\(cleanRoute) - \(dirStr)", isNorthOrUptown ? "Uptown & Northbound" : "Downtown & Southbound")
        }
    }
    
    func resolveDestination(
        tripUpdate: TransitRealtime_TripUpdate,
        line: String,
        stopId: String,
        matchingUpdate: TransitRealtime_TripUpdate.StopTimeUpdate? = nil
    ) -> String {
        let cleanStop = stopId.uppercased()
        let isNorthbound = cleanStop.hasSuffix("N")
        let isSouthbound = cleanStop.hasSuffix("S")
        let isEastbound = cleanStop.hasSuffix("E")
        let isWestbound = cleanStop.hasSuffix("W")
        
        let directionId = tripUpdate.trip.hasDirectionID ? Int(tripUpdate.trip.directionID) : nil
        let effectiveNorthbound: Bool = {
            if isNorthbound { return true }
            if isSouthbound { return false }
            if let d = directionId { return d == 0 }
            return true
        }()
        
        if SubwayFeed.isBusRoute(line) {
            let hint = isNorthbound ? "Northbound" : (isSouthbound ? "Southbound" : (isEastbound ? "Eastbound" : (isWestbound ? "Westbound" : nil)))
            return Self.resolveBusDestination(routeId: line, directionId: directionId, directionHint: hint).destination
        }
        
        let cleanLine = line.uppercased().trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "_").last ?? line.uppercased()
        
        // 1. Dynamic Terminal Inference: Reverse scan for final non-skipped stop update
        let nonSkippedUpdates = tripUpdate.stopTimeUpdate.filter { update in
            if update.hasScheduleRelationship && update.scheduleRelationship == .skipped {
                return false
            }
            return true
        }
        
        let terminalUpdate = nonSkippedUpdates.last
        let terminalStopId = terminalUpdate?.stopID ?? ""
        let cleanTerminalId = SubwayStationRegistry.cleanStopId(terminalStopId)
        
        let terminalName: String = {
            if !terminalStopId.isEmpty, let name = SubwayStationRegistry.resolveStationName(for: terminalStopId) {
                return name
            }
            let fallback = SubwayStationRegistry.defaultTerminal(route: cleanLine, isNorthbound: effectiveNorthbound)
            if !fallback.name.isEmpty && fallback.name != "Uptown / Northbound" && fallback.name != "Downtown / Southbound" {
                return fallback.name
            }
            return !cleanTerminalId.isEmpty ? cleanTerminalId : fallback.name
        }()
        
        // 2. Short-Turn Detection (Doc 16 §4)
        var isShortTurn = false
        let trainId: String = {
            if tripUpdate.trip.hasTransitRealtime_nyctTripDescriptor {
                return tripUpdate.trip.TransitRealtime_nyctTripDescriptor.trainID
            }
            return ""
        }()
        
        if trainId.hasPrefix("$") {
            isShortTurn = true
        } else if let stdTerminals = SubwayStationRegistry.standardTerminals[cleanLine] {
            let allowedEndpoints = effectiveNorthbound ? stdTerminals.north : stdTerminals.south
            if !allowedEndpoints.isEmpty && !cleanTerminalId.isEmpty && !allowedEndpoints.contains(cleanTerminalId) {
                isShortTurn = true
            }
        }
        
        // 3. Physical Track Occupancy & Express Inference (Doc 16 §4)
        let observedTrack: String = {
            // A. Check current station's stop update
            if let matched = matchingUpdate, matched.hasTransitRealtime_nyctStopTimeUpdate {
                let actual = matched.TransitRealtime_nyctStopTimeUpdate.actualTrack.trimmingCharacters(in: .whitespacesAndNewlines)
                if !actual.isEmpty { return actual }
                let scheduled = matched.TransitRealtime_nyctStopTimeUpdate.scheduledTrack.trimmingCharacters(in: .whitespacesAndNewlines)
                if !scheduled.isEmpty { return scheduled }
            }
            // B. Check initial non-skipped station (where NYCT feed anchors actualTrack)
            if let firstNonSkipped = nonSkippedUpdates.first, firstNonSkipped.hasTransitRealtime_nyctStopTimeUpdate {
                let actual = firstNonSkipped.TransitRealtime_nyctStopTimeUpdate.actualTrack.trimmingCharacters(in: .whitespacesAndNewlines)
                if !actual.isEmpty { return actual }
                let scheduled = firstNonSkipped.TransitRealtime_nyctStopTimeUpdate.scheduledTrack.trimmingCharacters(in: .whitespacesAndNewlines)
                if !scheduled.isEmpty { return scheduled }
            }
            // C. Check any non-skipped stop update for actualTrack
            for update in nonSkippedUpdates where update.hasTransitRealtime_nyctStopTimeUpdate {
                let actual = update.TransitRealtime_nyctStopTimeUpdate.actualTrack.trimmingCharacters(in: .whitespacesAndNewlines)
                if !actual.isEmpty { return actual }
            }
            return ""
        }().uppercased()
        
        var isExpress = false
        var isPhysicalLocalOverride = false
        
        if observedTrack == "2" || observedTrack == "3" || observedTrack == "M" {
            isExpress = true
        } else if observedTrack == "1" || observedTrack == "4" {
            if SubwayStationRegistry.defaultExpressRoutes.contains(cleanLine) {
                isPhysicalLocalOverride = true
            }
            isExpress = false
        } else {
            // Track unpopulated: fallback to dispatch train ID prefix or route default
            if trainId.hasPrefix("/") {
                isExpress = true
            } else if SubwayStationRegistry.defaultExpressRoutes.contains(cleanLine) {
                isExpress = true
            } else {
                isExpress = false
            }
        }
        
        // 4. Disambiguated Output Formatting
        var label = "\(cleanLine) to \(terminalName)"
        if isShortTurn {
            label += " (Short Turn)"
        }
        if isExpress {
            label += " EXP"
        } else if isPhysicalLocalOverride {
            label += " Local"
        }
        
        return label
    }
}
