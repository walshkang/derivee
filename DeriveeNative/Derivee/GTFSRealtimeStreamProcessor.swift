import Foundation
import SwiftProtobuf

// MARK: - Occupancy Status Model

/// Clean occupancy status representation decoupled from protobuf internals.
public enum VehicleOccupancyStatus: Int, Sendable, Codable, Equatable {
    case empty = 0
    case manySeatsAvailable = 1
    case fewSeatsAvailable = 2
    case standingRoomOnly = 3
    case crushedStandingRoomOnly = 4
    case full = 5
    case notAcceptingPassengers = 6
    case noDataAvailable = 7
    case notBoardable = 8
    
    init(protobufStatus: TransitRealtime_VehiclePosition.OccupancyStatus) {
        switch protobufStatus {
        case .empty: self = .empty
        case .manySeatsAvailable: self = .manySeatsAvailable
        case .fewSeatsAvailable: self = .fewSeatsAvailable
        case .standingRoomOnly: self = .standingRoomOnly
        case .crushedStandingRoomOnly: self = .crushedStandingRoomOnly
        case .full: self = .full
        case .notAcceptingPassengers: self = .notAcceptingPassengers
        case .noDataAvailable: self = .noDataAvailable
        case .notBoardable: self = .notBoardable
        }
    }
}

// MARK: - Processed GTFS-RT Models

/// A structured, midnight-safe representation of a real-time stop arrival/departure event.
public struct ProcessedStopTimeUpdate: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let tripId: String
    public let stopId: String
    public let stopSequence: UInt32?
    public let arrivalEpoch: Int64?
    public let departureEpoch: Int64?
    public let arrivalDelaySeconds: Int32?
    public let departureDelaySeconds: Int32?
    public let effectiveDelaySeconds: Int32
    public let effectiveDelayMinutes: Int32
    public let scheduleRelationship: SpatialDatabaseManager.ScheduleRelationship
    public let departureOccupancyStatus: VehicleOccupancyStatus?
    public let isPropagated: Bool
    
    public init(
        tripId: String,
        stopId: String,
        stopSequence: UInt32? = nil,
        arrivalEpoch: Int64? = nil,
        departureEpoch: Int64? = nil,
        arrivalDelaySeconds: Int32? = nil,
        departureDelaySeconds: Int32? = nil,
        effectiveDelaySeconds: Int32 = 0,
        scheduleRelationship: SpatialDatabaseManager.ScheduleRelationship = .scheduled,
        departureOccupancyStatus: VehicleOccupancyStatus? = nil,
        isPropagated: Bool = false
    ) {
        let seqStr = stopSequence.map(String.init) ?? "0"
        self.id = "\(tripId)_\(stopId)_\(seqStr)"
        self.tripId = tripId
        self.stopId = stopId
        self.stopSequence = stopSequence
        self.arrivalEpoch = arrivalEpoch
        self.departureEpoch = departureEpoch
        self.arrivalDelaySeconds = arrivalDelaySeconds
        self.departureDelaySeconds = departureDelaySeconds
        self.effectiveDelaySeconds = effectiveDelaySeconds
        self.effectiveDelayMinutes = Int32(round(Double(effectiveDelaySeconds) / 60.0))
        self.scheduleRelationship = scheduleRelationship
        self.departureOccupancyStatus = departureOccupancyStatus
        self.isPropagated = isPropagated
    }
}

/// A structured, midnight-safe representation of an active transit trip update.
public struct ProcessedTripUpdate: Identifiable, Sendable, Equatable {
    public var id: String { tripId }
    public let tripId: String
    public let routeId: String
    public let directionId: Int?
    public let vehicleId: String?
    public let feedTimestamp: UInt64
    public let tripDelaySeconds: Int32
    public let tripDelayMinutes: Int32
    public let scheduleRelationship: SpatialDatabaseManager.ScheduleRelationship
    public let stopTimeUpdates: [ProcessedStopTimeUpdate]
    public let updatedAt: Date
    
    public init(
        tripId: String,
        routeId: String,
        directionId: Int? = nil,
        vehicleId: String? = nil,
        feedTimestamp: UInt64 = 0,
        tripDelaySeconds: Int32 = 0,
        scheduleRelationship: SpatialDatabaseManager.ScheduleRelationship = .scheduled,
        stopTimeUpdates: [ProcessedStopTimeUpdate] = [],
        updatedAt: Date = Date()
    ) {
        self.tripId = tripId
        self.routeId = routeId
        self.directionId = directionId
        self.vehicleId = vehicleId
        self.feedTimestamp = feedTimestamp
        self.tripDelaySeconds = tripDelaySeconds
        self.tripDelayMinutes = Int32(round(Double(tripDelaySeconds) / 60.0))
        self.scheduleRelationship = scheduleRelationship
        self.stopTimeUpdates = stopTimeUpdates
        self.updatedAt = updatedAt
    }
}

/// Summary metrics emitted after processing a GTFS-RT feed update.
public struct ProcessedFeedSummary: Sendable, Equatable {
    public let feedHeaderTimestamp: UInt64
    public let processedTripsCount: Int
    public let totalStopTimeUpdatesCount: Int
    public let activeDisruptionsCount: Int
    public let averageDelaySeconds: Double
    public let maxDelaySeconds: Int32
    public let minDelaySeconds: Int32
    public let processedAt: Date
    
    public init(
        feedHeaderTimestamp: UInt64 = 0,
        processedTripsCount: Int = 0,
        totalStopTimeUpdatesCount: Int = 0,
        activeDisruptionsCount: Int = 0,
        averageDelaySeconds: Double = 0.0,
        maxDelaySeconds: Int32 = 0,
        minDelaySeconds: Int32 = 0,
        processedAt: Date = Date()
    ) {
        self.feedHeaderTimestamp = feedHeaderTimestamp
        self.processedTripsCount = processedTripsCount
        self.totalStopTimeUpdatesCount = totalStopTimeUpdatesCount
        self.activeDisruptionsCount = activeDisruptionsCount
        self.averageDelaySeconds = averageDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.minDelaySeconds = minDelaySeconds
        self.processedAt = processedAt
    }
}

// MARK: - Stream Processor Actor

/// High-performance, concurrency-safe stream processor for live GTFS-RT Protobuf feeds.
///
/// Ingests `TransitRealtime_FeedMessage` payloads, computes midnight-safe circular delays using
/// `GTFSMidnightResolver`, applies downstream delay propagation across stop sequences, and maintains
/// in-memory spatial indices for real-time trip delay queries.
public actor GTFSRealtimeStreamProcessor {
    
    public static let shared = GTFSRealtimeStreamProcessor()
    
    // MARK: - In-Memory State
    
    private var activeTrips: [String: ProcessedTripUpdate] = [:]
    private var stopLookup: [String: [ProcessedStopTimeUpdate]] = [:]
    private var routeLookup: [String: Set<String>] = [:]
    private var lastFeedTimestamp: UInt64 = 0
    
    public init() {}
    
    // MARK: - Ingestion Pipeline
    
    /// Ingests binary Protobuf GTFS-RT feed message data, updates in-memory delay state, and returns a summary.
    ///
    /// - Parameters:
    ///   - data: Binary protobuf payload conforming to `TransitRealtime_FeedMessage`.
    ///   - referenceDate: Reference current date for relative delay adjustments (defaults to `Date()`).
    /// - Returns: A `ProcessedFeedSummary` describing the processed updates.
    @discardableResult
    public func ingestFeedMessage(data: Data, referenceDate: Date = Date()) throws -> ProcessedFeedSummary {
        let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: data)
        let headerTimestamp = feedMessage.hasHeader && feedMessage.header.hasTimestamp ? feedMessage.header.timestamp : UInt64(referenceDate.timeIntervalSince1970)
        
        var tripUpdates: [TransitRealtime_TripUpdate] = []
        for entity in feedMessage.entity {
            if entity.hasTripUpdate {
                tripUpdates.append(entity.tripUpdate)
            }
        }
        
        return ingestTripUpdates(tripUpdates, headerTimestamp: headerTimestamp, referenceDate: referenceDate)
    }
    
    /// Ingests an array of deserialized `TransitRealtime_TripUpdate` entities.
    @discardableResult
    func ingestTripUpdates(
        _ updates: [TransitRealtime_TripUpdate],
        headerTimestamp: UInt64,
        referenceDate: Date = Date()
    ) -> ProcessedFeedSummary {
        self.lastFeedTimestamp = headerTimestamp
        
        var totalStopUpdates = 0
        var totalDelaySum: Int64 = 0
        var totalDelayCount = 0
        var maxDelay: Int32 = 0
        var minDelay: Int32 = 0
        var hasRecordedDelay = false
        var disruptionsCount = 0
        
        for tripUpdate in updates {
            guard let processed = processSingleTripUpdate(tripUpdate, headerTimestamp: headerTimestamp, referenceDate: referenceDate) else {
                continue
            }
            
            // Remove previous entries for this trip from stopLookup
            if let oldTrip = activeTrips[processed.tripId] {
                for stopUpdate in oldTrip.stopTimeUpdates {
                    if var existing = stopLookup[stopUpdate.stopId] {
                        existing.removeAll { $0.tripId == processed.tripId }
                        stopLookup[stopUpdate.stopId] = existing.isEmpty ? nil : existing
                    }
                }
            }
            
            // Insert new trip
            activeTrips[processed.tripId] = processed
            
            // Update route index
            var tripsForRoute = routeLookup[processed.routeId] ?? Set<String>()
            tripsForRoute.insert(processed.tripId)
            routeLookup[processed.routeId] = tripsForRoute
            
            // Update stop index
            for stopUpdate in processed.stopTimeUpdates {
                var existing = stopLookup[stopUpdate.stopId] ?? []
                existing.append(stopUpdate)
                stopLookup[stopUpdate.stopId] = existing
                
                totalStopUpdates += 1
                totalDelaySum += Int64(stopUpdate.effectiveDelaySeconds)
                totalDelayCount += 1
                
                if !hasRecordedDelay {
                    maxDelay = stopUpdate.effectiveDelaySeconds
                    minDelay = stopUpdate.effectiveDelaySeconds
                    hasRecordedDelay = true
                } else {
                    if stopUpdate.effectiveDelaySeconds > maxDelay {
                        maxDelay = stopUpdate.effectiveDelaySeconds
                    }
                    if stopUpdate.effectiveDelaySeconds < minDelay {
                        minDelay = stopUpdate.effectiveDelaySeconds
                    }
                }
            }
            
            if processed.scheduleRelationship == .canceled || processed.scheduleRelationship == .unscheduled {
                disruptionsCount += 1
            } else {
                for stopUpdate in processed.stopTimeUpdates {
                    if stopUpdate.scheduleRelationship == .canceled || stopUpdate.scheduleRelationship == .unscheduled {
                        disruptionsCount += 1
                    }
                }
            }
        }
        
        let avgDelay = totalDelayCount > 0 ? Double(totalDelaySum) / Double(totalDelayCount) : 0.0
        
        return ProcessedFeedSummary(
            feedHeaderTimestamp: headerTimestamp,
            processedTripsCount: activeTrips.count,
            totalStopTimeUpdatesCount: totalStopUpdates,
            activeDisruptionsCount: disruptionsCount,
            averageDelaySeconds: avgDelay,
            maxDelaySeconds: maxDelay,
            minDelaySeconds: minDelay,
            processedAt: referenceDate
        )
    }
    
    // MARK: - Single Trip Processing & Downstream Propagation
    
    private func processSingleTripUpdate(
        _ tripUpdate: TransitRealtime_TripUpdate,
        headerTimestamp: UInt64,
        referenceDate: Date
    ) -> ProcessedTripUpdate? {
        guard tripUpdate.hasTrip, tripUpdate.trip.hasTripID, !tripUpdate.trip.tripID.isEmpty else {
            return nil
        }
        
        let tripId = tripUpdate.trip.tripID
        let routeId = tripUpdate.trip.hasRouteID ? tripUpdate.trip.routeID : ""
        let directionId: Int? = tripUpdate.trip.hasDirectionID ? Int(tripUpdate.trip.directionID) : nil
        let vehicleId: String? = tripUpdate.hasVehicle && tripUpdate.vehicle.hasID ? tripUpdate.vehicle.id : nil
        
        let tripRel: SpatialDatabaseManager.ScheduleRelationship = {
            guard tripUpdate.trip.hasScheduleRelationship else { return .scheduled }
            switch tripUpdate.trip.scheduleRelationship {
            case .scheduled: return .scheduled
            case .added: return .added
            case .unscheduled: return .unscheduled
            case .canceled: return .canceled
            case .duplicated: return .duplicated
            default: return .scheduled
            }
        }()
        
        // Initial baseline delay from trip-level descriptor (if present)
        var runningDelaySeconds: Int32 = tripUpdate.hasDelay ? tripUpdate.delay : 0
        var hasExplicitDelay = tripUpdate.hasDelay
        
        var processedStopUpdates: [ProcessedStopTimeUpdate] = []
        
        for stopUpdate in tripUpdate.stopTimeUpdate {
            let stopId = stopUpdate.stopID.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stopId.isEmpty else { continue }
            
            let stopSequence: UInt32? = stopUpdate.hasStopSequence ? stopUpdate.stopSequence : nil
            
            let stopRel: SpatialDatabaseManager.ScheduleRelationship = {
                guard stopUpdate.hasScheduleRelationship else { return tripRel }
                switch stopUpdate.scheduleRelationship {
                case .scheduled, .noData: return tripRel
                case .skipped: return .canceled
                case .unscheduled: return .unscheduled
                }
            }()
            
            var arrivalEpoch: Int64? = nil
            var arrivalDelay: Int32? = nil
            var departureEpoch: Int64? = nil
            var departureDelay: Int32? = nil
            
            // 1. Process Arrival Event
            if stopUpdate.hasArrival {
                let arr = stopUpdate.arrival
                if arr.hasTime {
                    arrivalEpoch = arr.time
                }
                if arr.hasDelay {
                    arrivalDelay = arr.delay
                    runningDelaySeconds = arr.delay
                    hasExplicitDelay = true
                } else if arr.hasTime && arr.hasScheduledTime {
                    let delaySec = GTFSMidnightResolver.calculateSignedCircularDelaySeconds(
                        liveSeconds: arr.time,
                        scheduledSeconds: arr.scheduledTime
                    )
                    arrivalDelay = Int32(delaySec)
                    runningDelaySeconds = arrivalDelay!
                    hasExplicitDelay = true
                }
            }
            
            // 2. Process Departure Event
            if stopUpdate.hasDeparture {
                let dep = stopUpdate.departure
                if dep.hasTime {
                    departureEpoch = dep.time
                }
                if dep.hasDelay {
                    departureDelay = dep.delay
                    runningDelaySeconds = dep.delay
                    hasExplicitDelay = true
                } else if dep.hasTime && dep.hasScheduledTime {
                    let delaySec = GTFSMidnightResolver.calculateSignedCircularDelaySeconds(
                        liveSeconds: dep.time,
                        scheduledSeconds: dep.scheduledTime
                    )
                    departureDelay = Int32(delaySec)
                    runningDelaySeconds = departureDelay!
                    hasExplicitDelay = true
                }
            }
            
            // 3. Effective Delay Resolution & Downstream Propagation
            let effectiveDelay: Int32
            let isPropagated: Bool
            
            if let dep = departureDelay {
                effectiveDelay = dep
                isPropagated = false
            } else if let arr = arrivalDelay {
                effectiveDelay = arr
                isPropagated = false
            } else if hasExplicitDelay {
                // Inherited from previous stop or trip-level delay
                effectiveDelay = runningDelaySeconds
                isPropagated = true
            } else {
                effectiveDelay = 0
                isPropagated = false
            }
            
            let occupancy: VehicleOccupancyStatus? = stopUpdate.hasDepartureOccupancyStatus ? VehicleOccupancyStatus(protobufStatus: stopUpdate.departureOccupancyStatus) : nil
            
            let processedStop = ProcessedStopTimeUpdate(
                tripId: tripId,
                stopId: stopId,
                stopSequence: stopSequence,
                arrivalEpoch: arrivalEpoch,
                departureEpoch: departureEpoch,
                arrivalDelaySeconds: arrivalDelay,
                departureDelaySeconds: departureDelay,
                effectiveDelaySeconds: effectiveDelay,
                scheduleRelationship: stopRel,
                departureOccupancyStatus: occupancy,
                isPropagated: isPropagated
            )
            
            processedStopUpdates.append(processedStop)
        }
        
        let primaryTripDelay = runningDelaySeconds
        
        return ProcessedTripUpdate(
            tripId: tripId,
            routeId: routeId,
            directionId: directionId,
            vehicleId: vehicleId,
            feedTimestamp: headerTimestamp,
            tripDelaySeconds: primaryTripDelay,
            scheduleRelationship: tripRel,
            stopTimeUpdates: processedStopUpdates,
            updatedAt: referenceDate
        )
    }
    
    // MARK: - Query APIs
    
    /// Returns the processed trip update for a specific trip ID, if present.
    public func getTripUpdate(tripId: String) -> ProcessedTripUpdate? {
        return activeTrips[tripId]
    }
    
    /// Returns the latest known delay in seconds for a specific trip ID.
    public func getDelay(tripId: String) -> Int32? {
        return activeTrips[tripId]?.tripDelaySeconds
    }
    
    /// Returns the delay in seconds for a specific trip at a specific stop ID.
    public func getDelay(tripId: String, stopId: String) -> Int32? {
        guard let trip = activeTrips[tripId] else { return nil }
        let clean = stopId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let stop = trip.stopTimeUpdates.first(where: { $0.stopId.uppercased() == clean }) {
            return stop.effectiveDelaySeconds
        }
        return trip.tripDelaySeconds
    }
    
    /// Returns all live departures registered for a specific stop ID, sorted by earliest arrival/departure.
    public func getLiveDepartures(forStop stopId: String) -> [ProcessedStopTimeUpdate] {
        let clean = stopId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let updates = stopLookup[clean] ?? []
        return updates.sorted {
            let t0 = $0.departureEpoch ?? $0.arrivalEpoch ?? 0
            let t1 = $1.departureEpoch ?? $1.arrivalEpoch ?? 0
            return t0 < t1
        }
    }
    
    /// Returns all active trips operating on a given route ID.
    public func getTrips(forRoute routeId: String) -> [ProcessedTripUpdate] {
        let clean = routeId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tripIds = routeLookup[clean] else { return [] }
        return tripIds.compactMap { activeTrips[$0] }
    }
    
    /// Returns a flat dictionary of `tripId -> delaySeconds` for all active trips (for feeding `RaptorEngine`).
    public func getActiveTripDelays() -> [String: Int32] {
        var delays: [String: Int32] = [:]
        for (tripId, trip) in activeTrips {
            delays[tripId] = trip.tripDelaySeconds
        }
        return delays
    }
    
    /// Returns a set of all stop IDs that currently have canceled or disrupted service.
    public func getDisruptedStops() -> Set<String> {
        var disrupted = Set<String>()
        for (_, trip) in activeTrips {
            if trip.scheduleRelationship == .canceled {
                for stop in trip.stopTimeUpdates {
                    disrupted.insert(stop.stopId)
                }
            } else {
                for stop in trip.stopTimeUpdates where stop.scheduleRelationship == .canceled {
                    disrupted.insert(stop.stopId)
                }
            }
        }
        return disrupted
    }
    
    // MARK: - Cache Eviction & Cleanup
    
    /// Evicts trips updated before `cutoffDate`. Returns number of evicted trips.
    @discardableResult
    public func pruneStaleTrips(olderThan cutoffDate: Date) -> Int {
        var evictedCount = 0
        var tripsToRemove: [String] = []
        
        for (tripId, trip) in activeTrips {
            if trip.updatedAt < cutoffDate {
                tripsToRemove.append(tripId)
            }
        }
        
        for tripId in tripsToRemove {
            if let trip = activeTrips.removeValue(forKey: tripId) {
                evictedCount += 1
                // Clean routeLookup
                if var routeTrips = routeLookup[trip.routeId] {
                    routeTrips.remove(tripId)
                    routeLookup[trip.routeId] = routeTrips.isEmpty ? nil : routeTrips
                }
                // Clean stopLookup
                for stop in trip.stopTimeUpdates {
                    if var stopUpdates = stopLookup[stop.stopId] {
                        stopUpdates.removeAll { $0.tripId == tripId }
                        stopLookup[stop.stopId] = stopUpdates.isEmpty ? nil : stopUpdates
                    }
                }
            }
        }
        
        return evictedCount
    }
    
    /// Evicts trips that haven't received an update within `olderThanSeconds`.
    @discardableResult
    public func pruneStale(olderThanSeconds: TimeInterval, referenceDate: Date = Date()) -> Int {
        let cutoff = referenceDate.addingTimeInterval(-olderThanSeconds)
        return pruneStaleTrips(olderThan: cutoff)
    }
    
    /// Clears all active in-memory trip and stop indices.
    public func reset() {
        activeTrips.removeAll()
        stopLookup.removeAll()
        routeLookup.removeAll()
        lastFeedTimestamp = 0
    }
}
