import Foundation
import CoreLocation
import CxxStdlib
import DeriveeCore

/// Actor-isolated high-performance bridge between Swift / SwiftUI and the native C++20 RAPTOR routing engine.
/// All heavy graph traversals run via `Task.detached(priority: .userInitiated)` to prevent main actor priority inversion.
public actor RoutingEngineBridge {
    
    // MARK: - Internal Native State
    
    private var engine: RaptorEngine
    private var timetableData: Data?
    private var ultraData: Data?
    private var walkGraphData: Data?
    private var metadataProvider: (any StopMetadataProvider)?
    private var gbfsService: GBFSSyncService?
    
    // MARK: - Lifecycle & Initialization
    
    public init(
        metadataProvider: (any StopMetadataProvider)? = nil,
        gbfsService: GBFSSyncService? = nil
    ) {
        self.engine = RaptorEngine()
        self.metadataProvider = metadataProvider
        self.gbfsService = gbfsService
    }
    
    public func setMetadataProvider(_ provider: any StopMetadataProvider) {
        self.metadataProvider = provider
    }
    
    public func setGbfsService(_ service: GBFSSyncService?) {
        self.gbfsService = service
    }
    
    /// Resets all loaded binary memory references and recreates the C++ engine instance.
    /// Essential for clean city switching during Coordinated Two-Phase Barrier.
    public func reset() {
        self.timetableData = nil
        self.ultraData = nil
        self.walkGraphData = nil
        self.engine = RaptorEngine()
    }
    
    // MARK: - Binary Data Loading
    
    /// Loads memory-mapped binary timetable blob directly into the C++ engine.
    @discardableResult
    public func loadTimetableBlob(_ data: Data) -> Bool {
        self.timetableData = data
        let success = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            return self.engine.load_timetable_blob(base, raw.count)
        }
        return success
    }
    
    /// Loads timetable from disk URL using Darwin kernel clean memory (`.alwaysMapped`).
    @discardableResult
    public func loadTimetable(from fileURL: URL) throws -> Bool {
        let data = try Data(contentsOf: fileURL, options: .alwaysMapped)
        return loadTimetableBlob(data)
    }
    
    /// Loads binary ULTRA transfer shortcuts blob (.csr).
    @discardableResult
    public func loadUltraBlob(_ data: Data) -> Bool {
        self.ultraData = data
        let success = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            return self.engine.load_ultra_blob(base, raw.count)
        }
        return success
    }
    
    /// Loads binary ULTRA transfers from disk URL.
    @discardableResult
    public func loadUltra(from fileURL: URL) throws -> Bool {
        let data = try Data(contentsOf: fileURL, options: .alwaysMapped)
        return loadUltraBlob(data)
    }

    /// Loads memory-mapped binary walk graph blob directly into the C++ engine.
    @discardableResult
    public func loadWalkGraphBlob(_ data: Data) -> Bool {
        self.walkGraphData = data
        let success = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            return self.engine.load_walk_graph_blob(base, raw.count)
        }
        return success
    }

    /// Loads walk graph from disk URL using Darwin kernel clean memory (`.alwaysMapped`).
    @discardableResult
    public func loadWalkGraph(from fileURL: URL) throws -> Bool {
        let data = try Data(contentsOf: fileURL, options: .alwaysMapped)
        return loadWalkGraphBlob(data)
    }
    
    // MARK: - State Inspection
    
    public var isLoaded: Bool {
        engine.is_loaded()
    }
    
    public var isUltraLoaded: Bool {
        engine.is_ultra_loaded()
    }

    public var isWalkGraphLoaded: Bool {
        engine.is_walk_graph_loaded()
    }

    public var walkNodesCount: Int {
        Int(engine.walk_nodes_count())
    }

    public var walkEdgesCount: Int {
        Int(engine.walk_edges_count())
    }
    
    public var stopsCount: Int {
        Int(engine.stops_count())
    }
    
    public var routesCount: Int {
        Int(engine.routes_count())
    }
    
    public var tripsCount: Int {
        Int(engine.trips_count())
    }
    
    public var registeredDelaysCount: Int {
        Int(engine.registered_delays_count())
    }
    
    // MARK: - Real-Time Delays & Disruptions
    
    public func updateRealtimeDelay(tripId: UInt32, delaySeconds: Int32) {
        engine.update_realtime_delay(tripId, delaySeconds)
    }
    
    public func clearRealtimeDelays() {
        engine.clear_realtime_delays()
    }
    
    public func getRealtimeDelay(tripId: UInt32) -> Int32 {
        engine.get_realtime_delay(tripId)
    }
    
    public func setStopDisrupted(stopId: UInt32, disrupted: Bool) {
        engine.set_stop_disrupted(stopId, disrupted)
    }
    
    public func isStopActive(stopId: UInt32) -> Bool {
        engine.is_stop_active(stopId)
    }
    
    public func setRouteSegmentDisrupted(routeId: UInt32, fromStop: UInt32, toStop: UInt32, disrupted: Bool) {
        engine.set_route_segment_disrupted(routeId, fromStop, toStop, disrupted)
    }
    
    public func isRouteSegmentActive(routeId: UInt32, fromStop: UInt32, toStop: UInt32) -> Bool {
        engine.is_route_segment_active(routeId, fromStop, toStop)
    }
    
    public func clearDisruptions() {
        engine.clear_disruptions()
    }
    
    // MARK: - Candidate Stops Discovery
    
    public func findCandidateStops(
        latitude: Double,
        longitude: Double,
        maxRadiusMeters: Double = 1000.0,
        requiredFlags: UInt16 = 0,
        maxResults: Int = 16
    ) -> [CandidateStop] {
        guard engine.is_loaded() else { return [] }
        let cxxStops = engine.find_candidate_stops(
            Float(latitude),
            Float(longitude),
            Float(maxRadiusMeters),
            requiredFlags,
            maxResults
        )
        
        var results: [CandidateStop] = []
        results.reserveCapacity(cxxStops.size())
        for s in cxxStops {
            results.append(s)
        }
        return results
    }
    
    // MARK: - Asynchronous Multimodal Pathfinding
    
    /// Computes multi-criteria Pareto-optimal journeys between two locations.
    /// Runs asynchronously at `.userInitiated` priority in detached background tasks.
    public func computeJourneys(
        origin: RoutingLocation,
        destination: RoutingLocation,
        departureTime: Date = Date(),
        profile: RoutingProfile = .mostReliable,
        options: RoutingOptions = .default
    ) async -> [JourneyItinerary] {
        guard engine.is_loaded() || engine.is_walk_graph_loaded() else { return [] }
        
        // Convert Date to seconds past midnight
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute, .second], from: departureTime)
        let depSeconds = UInt32((comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0))
        
        return await Task.detached(priority: .userInitiated) { [self] in
            await self.internalComputeJourneys(
                origin: origin,
                destination: destination,
                departureTimestampSec: depSeconds,
                profile: profile,
                options: options
            )
        }.value
    }
    
    /// Low-level single-query RAPTOR search between two discrete stop IDs.
    public func computeStopToStopJourney(
        originStopId: UInt32,
        destinationStopId: UInt32,
        departureTimestampSec: UInt32,
        maxTransfers: UInt16 = 4,
        flags: UInt16 = 0
    ) async -> [JourneyItinerary] {
        guard engine.is_loaded() else { return [] }
        
        return await Task.detached(priority: .userInitiated) { [self] in
            var params = QueryParams()
            params.origin_stop_id = originStopId
            params.destination_stop_id = destinationStopId
            params.departure_timestamp = departureTimestampSec
            params.max_transfers = maxTransfers
            params.flags = flags
            
            let cxxSegments = await self.engine.compute_journey(params)
            if cxxSegments.empty() { return [] }
            
            var segments: [JourneySegment] = []
            segments.reserveCapacity(cxxSegments.size())
            for seg in cxxSegments {
                segments.append(seg)
            }
            
            let itinerary = await self.buildItineraryFromSegments(
                segments: segments,
                originName: self.metadataProvider?.stopName(for: originStopId) ?? "Stop #\(originStopId)",
                destinationName: self.metadataProvider?.stopName(for: destinationStopId) ?? "Stop #\(destinationStopId)",
                departureTimeSec: departureTimestampSec,
                profile: .fastest
            )
            return [itinerary]
        }.value
    }
    
    // MARK: - Internal Query Orchestrator
    
    // MARK: - Micro-Climate Config Helper
    
    private func makeCxxMicroClimateConfig(from options: RoutingOptions, profile: RoutingProfile) -> derivee.climate.MicroClimateConfig {
        var cfg = derivee.climate.MicroClimateConfig()
        
        let effectiveMode: ThermalComfortMode
        if profile == .summerShaded {
            effectiveMode = .summerShaded
        } else if profile == .winterSunlit {
            effectiveMode = .winterSunlit
        } else {
            effectiveMode = options.thermalComfortMode
        }
        
        switch effectiveMode {
        case .neutral:
            cfg.mode = derivee.climate.ThermalComfortMode.Neutral
        case .summerShaded:
            cfg.mode = derivee.climate.ThermalComfortMode.SummerShaded
        case .winterSunlit:
            cfg.mode = derivee.climate.ThermalComfortMode.WinterSunlit
        }
        
        if let cond = options.microClimate {
            cfg.ambient_temp_c = Float(cond.ambientTemperatureCelsius)
            cfg.relative_humidity = Float(cond.relativeHumidity)
            cfg.wind_speed_mps = Float(cond.windSpeedMps)
            cfg.direct_irradiance_wm2 = Float(cond.directIrradianceWm2)
            if let alt = cond.customSolarAltitudeRad, let az = cond.customSolarAzimuthRad {
                cfg.has_custom_solar = true
                cfg.solar_altitude_rad = Float(alt)
                cfg.solar_azimuth_rad = Float(az)
            }
        }
        return cfg
    }

    private func internalComputeJourneys(
        origin: RoutingLocation,
        destination: RoutingLocation,
        departureTimestampSec: UInt32,
        profile: RoutingProfile,
        options: RoutingOptions
    ) async -> [JourneyItinerary] {
        var itineraries: [JourneyItinerary] = []
        let microclimateCfg = makeCxxMicroClimateConfig(from: options, profile: profile)
        
        // 1. Direct Walking Itinerary Evaluation
        if options.includeDirectWalk,
           let origCoord = origin.coordinate,
           let destCoord = destination.coordinate {
            let directResult = engine.compute_direct_walk(
                Float(origCoord.latitude), Float(origCoord.longitude),
                Float(destCoord.latitude), Float(destCoord.longitude),
                2000.0,
                options.flags,
                microclimateCfg
            )
            let distMeters = directResult.distance_meters
            
            // Allow direct walk if within 2.0 km
            if distMeters > 0.0 && distMeters <= 2000.0 {
                let walkDurSec = directResult.walk_duration_sec > 0 ?
                    directResult.walk_duration_sec :
                    BoundedAStarRouter.calculate_walk_duration_sec(distMeters, Float(options.walkingSpeedMps))
                let arrSec = departureTimestampSec + walkDurSec
                
                let comfortSummary: String?
                if directResult.shade_percentage >= 60.0 {
                    comfortSummary = String(format: "Shaded Tree Canopy & Canyon (%.0f%% Shade, PET %.0f°C)", directResult.shade_percentage, directResult.pet_index_celsius)
                } else {
                    comfortSummary = String(format: "Sunlit Direct Route (%.0f%% Shade, PET %.0f°C)", directResult.shade_percentage, directResult.pet_index_celsius)
                }
                
                let origCLLoc = CLLocationCoordinate2D(latitude: origCoord.latitude, longitude: origCoord.longitude)
                let destCLLoc = CLLocationCoordinate2D(latitude: destCoord.latitude, longitude: destCoord.longitude)
                let anchors = LandmarkWalkingGuidanceEngine.shared.generateAnchors(
                    originName: origin.displayName,
                    destinationName: destination.displayName,
                    originCoord: origCLLoc,
                    destinationCoord: destCLLoc,
                    distanceMeters: UInt32(distMeters),
                    durationSec: walkDurSec,
                    shadePercentage: directResult.shade_percentage,
                    petIndexCelsius: directResult.pet_index_celsius,
                    isShadedRoute: profile == .summerShaded
                )
                
                let directWalkLeg = JourneyLeg(
                    mode: .walk,
                    originName: origin.displayName,
                    destinationName: destination.displayName,
                    departureTimeSec: departureTimestampSec,
                    arrivalTimeSec: arrSec,
                    distanceMeters: UInt32(distMeters),
                    landmarkCue: anchors.first?.prompt ?? (directResult.path_found ? "Direct pedestrian path via street network" : "Direct pedestrian path to destination"),
                    landmarkAnchors: anchors,
                    shadePercentage: directResult.shade_percentage,
                    petIndexCelsius: directResult.pet_index_celsius,
                    thermalComfortSummary: comfortSummary
                )
                
                var savingsText: String?
                if profile == .summerShaded && directResult.shade_percentage >= 60.0 {
                    savingsText = String(format: "%.0f%% Shaded Cooling Path", directResult.shade_percentage)
                } else if profile == .winterSunlit && directResult.shade_percentage <= 40.0 {
                    savingsText = String(format: "%.0f%% Sunlit Warmth Path", 100.0 - directResult.shade_percentage)
                }
                
                let directWalkItinerary = JourneyItinerary(
                    profile: profile,
                    departureTimeSec: departureTimestampSec,
                    arrivalTimeSec: arrSec,
                    p10ArrivalSec: arrSec,
                    p50ArrivalSec: arrSec,
                    p90ArrivalSec: arrSec,
                    totalCost: 0.0,
                    legs: [directWalkLeg],
                    disruptions: [],
                    confidenceTier: .verified,
                    averageShadePercentage: directResult.shade_percentage,
                    averagePetIndexCelsius: directResult.pet_index_celsius,
                    thermalComfortSavingsText: savingsText
                )
                itineraries.append(directWalkItinerary)
            }
        }
        
        // 2. Discover Candidate Boarding and Alighting Stops
        let candidateOrigins = resolveCandidateStops(location: origin, options: options, microclimate: microclimateCfg)
        let candidateDests = resolveCandidateStops(location: destination, options: options, microclimate: microclimateCfg)
        
        if candidateOrigins.isEmpty || candidateDests.isEmpty {
            return itineraries
        }
        
        // 3. Multimodal Range-RAPTOR Sweeps across Candidate Stop Pairs
        for origStop in candidateOrigins.prefix(options.maxCandidateStops) {
            for destStop in candidateDests.prefix(options.maxCandidateStops) {
                if origStop.stop_id == destStop.stop_id { continue }
                
                let stopDepTime = departureTimestampSec + origStop.walk_duration_sec
                var rangeParams = RangeQueryParams()
                rangeParams.origin_stop_id = origStop.stop_id
                rangeParams.destination_stop_id = destStop.stop_id
                rangeParams.departure_start_timestamp = stopDepTime
                rangeParams.departure_end_timestamp = stopDepTime + options.departureWindowSeconds
                rangeParams.max_transfers = options.maxTransfers
                rangeParams.flags = options.flags
                rangeParams.stochastic_horizon_sec = options.stochasticHorizonSeconds
                rangeParams.sampling_step_sec = options.samplingStepSeconds
                
                let paretoSet = engine.compute_range_journeys(rangeParams)
                if paretoSet.empty() { continue }
                
                for i in 0..<paretoSet.size() {
                    let journey = paretoSet[i]
                    
                    var segments: [JourneySegment] = []
                    segments.reserveCapacity(journey.segments.size())
                    for seg in journey.segments {
                        segments.append(seg)
                    }
                    if segments.isEmpty { continue }
                    
                    // Build full multimodal legs (Initial Walk/Bike + Transit Segments + Final Walk)
                    let candidateItinerary = await buildMultimodalItinerary(
                        origin: origin,
                        destination: destination,
                        origStop: origStop,
                        destStop: destStop,
                        segments: segments,
                        cost: journey.cost,
                        nominalDepSec: departureTimestampSec,
                        profile: profile
                    )
                    
                    itineraries.append(candidateItinerary)
                }
            }
        }
        
        // 4. Multi-Profile Sorting & Deduplication
        return filterAndRankItineraries(itineraries, for: profile)
    }
    
    // MARK: - Candidate Resolution Helper
    
    private func resolveCandidateStops(
        location: RoutingLocation,
        options: RoutingOptions,
        microclimate: derivee.climate.MicroClimateConfig
    ) -> [CandidateStop] {
        switch location {
        case .stop(let id, _):
            let s = engine.get_stop(id)
            return [CandidateStop(id, 0.0, 0, s.latitude, s.longitude, options.flags, 0.0, 0.0)]
        case .coordinate(let lat, let lon, _):
            let cxxCandidates = engine.find_candidate_stops(
                Float(lat), Float(lon), Float(options.maxWalkDistanceMeters), options.flags, options.maxCandidateStops, microclimate
            )
            var candidates: [CandidateStop] = []
            candidates.reserveCapacity(cxxCandidates.size())
            for c in cxxCandidates {
                candidates.append(c)
            }
            return candidates
        }
    }
    
    // MARK: - Itinerary Synthesis
    
    private func buildMultimodalItinerary(
        origin: RoutingLocation,
        destination: RoutingLocation,
        origStop: CandidateStop,
        destStop: CandidateStop,
        segments: [JourneySegment],
        cost: ParetoCost,
        nominalDepSec: UInt32,
        profile: RoutingProfile
    ) async -> JourneyItinerary {
        var legs: [JourneyLeg] = []
        var containsRealtime = false
        var disruptions: [JourneyDisruption] = []
        var bikeLegSynthesized = false
        
        // 1. Check for GBFS Bike-Share Chaining if profile is .multiModalBikeRail
        if profile == .multiModalBikeRail,
           let origCoord = origin.coordinate,
           let gbfs = self.gbfsService,
           origStop.distance_meters > 200.0 {
            
            let stopCoord = metadataProvider?.stopCoordinate(for: origStop.stop_id) ?? (Double(origStop.latitude), Double(origStop.longitude))
            let originCLLocation = CLLocationCoordinate2D(latitude: origCoord.latitude, longitude: origCoord.longitude)
            let stopCLLocation = CLLocationCoordinate2D(latitude: stopCoord.latitude, longitude: stopCoord.longitude)
            
            if let pickStations = try? await gbfs.fetchCandidateStations(near: originCLLocation, radiusMeters: 500),
               let dropStations = try? await gbfs.fetchCandidateStations(near: stopCLLocation, radiusMeters: 500),
               let pickStation = pickStations.first(where: { $0.numBikesAvailable >= 1 }),
               let dropStation = dropStations.first(where: { $0.numDocksAvailable >= 1 }) {
                
                let walkToPickDist = BoundedAStarRouter.calculate_distance_meters(
                    Float(origCoord.latitude), Float(origCoord.longitude),
                    Float(pickStation.coordinate.latitude), Float(pickStation.coordinate.longitude)
                )
                let walkToPickDur = UInt32(walkToPickDist / 1.3)
                
                let bikeDist = BoundedAStarRouter.calculate_distance_meters(
                    Float(pickStation.coordinate.latitude), Float(pickStation.coordinate.longitude),
                    Float(dropStation.coordinate.latitude), Float(dropStation.coordinate.longitude)
                )
                let bikeDur = UInt32(bikeDist / 4.5) + 60 // 60s unlock/dock buffer
                
                let walkFromDropDist = BoundedAStarRouter.calculate_distance_meters(
                    Float(dropStation.coordinate.latitude), Float(dropStation.coordinate.longitude),
                    Float(stopCoord.latitude), Float(stopCoord.longitude)
                )
                let walkFromDropDur = UInt32(walkFromDropDist / 1.3)
                
                let t0 = nominalDepSec
                let t1 = t0 + walkToPickDur
                let t2 = t1 + bikeDur
                let t3 = t2 + walkFromDropDur
                
                // Walk to origin bike dock
                legs.append(JourneyLeg(
                    mode: .walk,
                    originName: origin.displayName,
                    destinationName: pickStation.name,
                    departureTimeSec: t0,
                    arrivalTimeSec: t1,
                    distanceMeters: UInt32(walkToPickDist),
                    landmarkCue: "Walk to bike station (\(pickStation.numBikesAvailable) bikes available)"
                ))
                
                // Bike share leg
                let dockStatusCue = dropStation.numDocksAvailable > 3 ? "Dock verified (>3 empty docks)" : "Dock caution (\(dropStation.numDocksAvailable) docks available)"
                legs.append(JourneyLeg(
                    mode: .bikeShare,
                    originName: pickStation.name,
                    destinationName: dropStation.name,
                    departureTimeSec: t1,
                    arrivalTimeSec: t2,
                    distanceMeters: UInt32(bikeDist),
                    landmarkCue: dockStatusCue
                ))
                
                // Walk from destination bike dock to transit entrance
                let origStopName = metadataProvider?.stopName(for: origStop.stop_id) ?? "Stop #\(origStop.stop_id)"
                legs.append(JourneyLeg(
                    mode: .walk,
                    originName: dropStation.name,
                    destinationName: origStopName,
                    departureTimeSec: t2,
                    arrivalTimeSec: t3,
                    distanceMeters: UInt32(walkFromDropDist),
                    landmarkCue: "Station entrance from bike dock"
                ))
                
                bikeLegSynthesized = true
            }
        }
        
        // Fallback: Standard Initial Walk Leg
        if !bikeLegSynthesized && origStop.distance_meters > 5.0 {
            let initialWalkArr = nominalDepSec + origStop.walk_duration_sec
            let origStopName = metadataProvider?.stopName(for: origStop.stop_id) ?? "Stop #\(origStop.stop_id)"
            
            let comfortSummary: String?
            if origStop.shade_percentage >= 60.0 {
                comfortSummary = String(format: "Shaded Tree Canopy & Canyon (%.0f%% Shade, PET %.0f°C)", origStop.shade_percentage, origStop.pet_index_celsius)
            } else {
                comfortSummary = String(format: "Sunlit Direct Route (%.0f%% Shade, PET %.0f°C)", origStop.shade_percentage, origStop.pet_index_celsius)
            }
            
            let origCLLoc = origin.coordinate.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            let stopCoord = metadataProvider?.stopCoordinate(for: origStop.stop_id)
            let stopCLLoc = stopCoord.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                ?? CLLocationCoordinate2D(latitude: Double(origStop.latitude), longitude: Double(origStop.longitude))
            
            let origAnchors = LandmarkWalkingGuidanceEngine.shared.generateAnchors(
                originName: origin.displayName,
                destinationName: origStopName,
                originCoord: origCLLoc,
                destinationCoord: stopCLLoc,
                distanceMeters: UInt32(origStop.distance_meters),
                durationSec: origStop.walk_duration_sec,
                shadePercentage: origStop.shade_percentage,
                petIndexCelsius: origStop.pet_index_celsius,
                isShadedRoute: profile == .summerShaded
            )
            
            legs.append(
                JourneyLeg(
                    mode: .walk,
                    originName: origin.displayName,
                    destinationName: origStopName,
                    departureTimeSec: nominalDepSec,
                    arrivalTimeSec: initialWalkArr,
                    distanceMeters: UInt32(origStop.distance_meters),
                    landmarkCue: origAnchors.first?.prompt ?? metadataProvider?.landmarkCue(for: origStop.stop_id),
                    landmarkAnchors: origAnchors,
                    shadePercentage: origStop.shade_percentage,
                    petIndexCelsius: origStop.pet_index_celsius,
                    thermalComfortSummary: comfortSummary
                )
            )
        }
        
        // 2. Transit and Transfer Legs
        for seg in segments {
            let boardName = metadataProvider?.stopName(for: seg.board_stop_id) ?? "Stop #\(seg.board_stop_id)"
            let exitName = metadataProvider?.stopName(for: seg.exit_stop_id) ?? "Stop #\(seg.exit_stop_id)"
            
            if seg.is_transfer_leg() {
                let boardCoord = metadataProvider?.stopCoordinate(for: seg.board_stop_id).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let exitCoord = metadataProvider?.stopCoordinate(for: seg.exit_stop_id).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let transferAnchors = LandmarkWalkingGuidanceEngine.shared.generateAnchors(
                    originName: boardName,
                    destinationName: exitName,
                    originCoord: boardCoord,
                    destinationCoord: exitCoord,
                    distanceMeters: UInt32(seg.transfer_distance_m),
                    durationSec: seg.arrival_time > seg.departure_time ? (seg.arrival_time - seg.departure_time) : 120,
                    shadePercentage: 100.0,
                    petIndexCelsius: 22.0,
                    isShadedRoute: true
                )
                
                legs.append(
                    JourneyLeg(
                        mode: .walk,
                        originName: boardName,
                        destinationName: exitName,
                        departureTimeSec: seg.departure_time,
                        arrivalTimeSec: seg.arrival_time,
                        distanceMeters: UInt32(seg.transfer_distance_m),
                        isTransferWalk: true,
                        landmarkCue: transferAnchors.first?.prompt ?? "Transfer via pedestrian connection",
                        landmarkAnchors: transferAnchors
                    )
                )
            } else {
                let routeNameStr = metadataProvider?.routeName(for: seg.route_id) ?? "\(seg.route_id)"
                let lineInfo = TransitRouteData.lineInfo(for: routeNameStr)
                let delay = engine.get_realtime_delay(seg.trip_id)
                if delay != 0 {
                    containsRealtime = true
                }
                
                let carPosition: String? = (lineInfo.modalClass == .subway) ? "Board middle car for convenient egress" : nil
                
                legs.append(
                    JourneyLeg(
                        mode: (lineInfo.modalClass == .bus) ? .bus : .subway,
                        originName: boardName,
                        destinationName: exitName,
                        departureTimeSec: seg.departure_time,
                        arrivalTimeSec: seg.arrival_time,
                        routeId: routeNameStr,
                        headsign: "\(routeNameStr) Train",
                        lineInfo: lineInfo,
                        confidenceTier: (delay != 0) ? .verified : .staticSchedule,
                        recommendedCarPosition: carPosition
                    )
                )
            }
        }
        
        // 3. Final Walk Leg
        let lastTransitArr = segments.last?.arrival_time ?? nominalDepSec
        let destStopName = metadataProvider?.stopName(for: destStop.stop_id) ?? "Stop #\(destStop.stop_id)"
        let finalArr = lastTransitArr + destStop.walk_duration_sec
        
        if destStop.distance_meters > 5.0 {
            let exitCode = metadataProvider?.exitCode(for: destStop.stop_id)
            let destComfortSummary: String?
            if destStop.shade_percentage >= 60.0 {
                destComfortSummary = String(format: "Shaded Tree Canopy & Canyon (%.0f%% Shade, PET %.0f°C)", destStop.shade_percentage, destStop.pet_index_celsius)
            } else {
                destComfortSummary = String(format: "Sunlit Direct Route (%.0f%% Shade, PET %.0f°C)", destStop.shade_percentage, destStop.pet_index_celsius)
            }
            
            let stopCoord = metadataProvider?.stopCoordinate(for: destStop.stop_id)
            let stopCLLoc = stopCoord.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                ?? CLLocationCoordinate2D(latitude: Double(destStop.latitude), longitude: Double(destStop.longitude))
            let destCLLoc = destination.coordinate.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            
            let destAnchors = LandmarkWalkingGuidanceEngine.shared.generateAnchors(
                originName: destStopName,
                destinationName: destination.displayName,
                originCoord: stopCLLoc,
                destinationCoord: destCLLoc,
                distanceMeters: UInt32(destStop.distance_meters),
                durationSec: destStop.walk_duration_sec,
                shadePercentage: destStop.shade_percentage,
                petIndexCelsius: destStop.pet_index_celsius,
                isShadedRoute: profile == .summerShaded
            )
            
            legs.append(
                JourneyLeg(
                    mode: .walk,
                    originName: destStopName,
                    destinationName: destination.displayName,
                    departureTimeSec: lastTransitArr,
                    arrivalTimeSec: finalArr,
                    distanceMeters: UInt32(destStop.distance_meters),
                    landmarkCue: destAnchors.first?.prompt,
                    landmarkAnchors: destAnchors,
                    exitCode: exitCode,
                    shadePercentage: destStop.shade_percentage,
                    petIndexCelsius: destStop.pet_index_celsius,
                    thermalComfortSummary: destComfortSummary
                )
            )
        }
        
        // 4. Statistical Confidence Bounds
        let p50 = finalArr
        let varianceDis = cost.variance_disutility
        let p10 = (p50 > 120 + varianceDis / 2) ? (p50 - min(120, varianceDis / 2)) : p50
        let p90 = p50 + max(60, varianceDis)
        
        var savingsText: String?
        if profile == .summerShaded {
            let walkShades = legs.compactMap { $0.shadePercentage }
            if let first = walkShades.first, first >= 60.0 {
                savingsText = String(format: "%.0f%% Shaded Cooling Path", first)
            }
        } else if profile == .winterSunlit {
            let walkShades = legs.compactMap { $0.shadePercentage }
            if let first = walkShades.first, first <= 40.0 {
                savingsText = String(format: "%.0f%% Sunlit Warmth Path", 100.0 - first)
            }
        }
        
        return JourneyItinerary(
            profile: profile,
            departureTimeSec: nominalDepSec,
            arrivalTimeSec: finalArr,
            p10ArrivalSec: p10,
            p50ArrivalSec: p50,
            p90ArrivalSec: p90,
            totalCost: 2.90,
            legs: legs,
            disruptions: disruptions,
            confidenceTier: containsRealtime ? .verified : .staticSchedule,
            thermalComfortSavingsText: savingsText
        )
    }
    
    private func buildItineraryFromSegments(
        segments: [JourneySegment],
        originName: String,
        destinationName: String,
        departureTimeSec: UInt32,
        profile: RoutingProfile
    ) -> JourneyItinerary {
        var legs: [JourneyLeg] = []
        var containsRealtime = false
        
        for seg in segments {
            let boardName = metadataProvider?.stopName(for: seg.board_stop_id) ?? "Stop #\(seg.board_stop_id)"
            let exitName = metadataProvider?.stopName(for: seg.exit_stop_id) ?? "Stop #\(seg.exit_stop_id)"
            
            if seg.is_transfer_leg() {
                legs.append(
                    JourneyLeg(
                        mode: .walk,
                        originName: boardName,
                        destinationName: exitName,
                        departureTimeSec: seg.departure_time,
                        arrivalTimeSec: seg.arrival_time,
                        distanceMeters: UInt32(seg.transfer_distance_m),
                        isTransferWalk: true
                    )
                )
            } else {
                let routeNameStr = metadataProvider?.routeName(for: seg.route_id) ?? "\(seg.route_id)"
                let lineInfo = TransitRouteData.lineInfo(for: routeNameStr)
                let delay = engine.get_realtime_delay(seg.trip_id)
                if delay != 0 {
                    containsRealtime = true
                }
                
                legs.append(
                    JourneyLeg(
                        mode: (lineInfo.modalClass == .bus) ? .bus : .subway,
                        originName: boardName,
                        destinationName: exitName,
                        departureTimeSec: seg.departure_time,
                        arrivalTimeSec: seg.arrival_time,
                        routeId: routeNameStr,
                        headsign: "\(routeNameStr) Train",
                        lineInfo: lineInfo,
                        confidenceTier: (delay != 0) ? .verified : .staticSchedule
                    )
                )
            }
        }
        
        let finalArr = segments.last?.arrival_time ?? departureTimeSec
        return JourneyItinerary(
            profile: profile,
            departureTimeSec: departureTimeSec,
            arrivalTimeSec: finalArr,
            p10ArrivalSec: finalArr,
            p50ArrivalSec: finalArr,
            p90ArrivalSec: finalArr + 120,
            totalCost: 2.90,
            legs: legs,
            confidenceTier: containsRealtime ? .verified : .staticSchedule
        )
    }
    
    // MARK: - Ranking & Deduplication
    
    private func filterAndRankItineraries(_ items: [JourneyItinerary], for profile: RoutingProfile) -> [JourneyItinerary] {
        var seen = Set<String>()
        var unique: [JourneyItinerary] = []
        
        for item in items {
            // Fingerprint based on leg modes, routes, and arrival minute
            let legSummary = item.legs.map { "\($0.mode.rawValue)-\($0.routeId ?? "")-\($0.originName)" }.joined(separator: "|")
            let arrivalMin = item.arrivalTimeSec / 60
            let key = "\(arrivalMin)-\(item.transferCount)-\(legSummary)"
            
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(item)
            }
        }
        
        switch profile {
        case .mostReliable:
            return unique.sorted { a, b in
                if a.uncertaintyMinutes == b.uncertaintyMinutes {
                    return a.arrivalTimeSec < b.arrivalTimeSec
                }
                return a.uncertaintyMinutes < b.uncertaintyMinutes
            }
        case .fastest:
            return unique.sorted { a, b in
                a.arrivalTimeSec < b.arrivalTimeSec
            }
        case .fewestTransfers:
            return unique.sorted { a, b in
                if a.transferCount == b.transferCount {
                    return a.arrivalTimeSec < b.arrivalTimeSec
                }
                return a.transferCount < b.transferCount
            }
        case .stepFree:
            let stepFreeRoutes = unique.filter { item in
                !item.legs.contains(where: { $0.isTransferWalk && $0.distanceMeters > 300 })
            }
            return (stepFreeRoutes.isEmpty ? unique : stepFreeRoutes).sorted { a, b in
                a.arrivalTimeSec < b.arrivalTimeSec
            }
        case .multiModalBikeRail:
            return unique.sorted { a, b in
                let aHasBike = a.bikingDistanceMeters > 0
                let bHasBike = b.bikingDistanceMeters > 0
                if aHasBike != bHasBike {
                    return aHasBike && !bHasBike
                }
                return a.arrivalTimeSec < b.arrivalTimeSec
            }
        case .summerShaded:
            return unique.sorted { a, b in
                let aShade = a.averageShadePercentage ?? 0.0
                let bShade = b.averageShadePercentage ?? 0.0
                if abs(aShade - bShade) > 5.0 {
                    return aShade > bShade // Higher shade first
                }
                return a.arrivalTimeSec < b.arrivalTimeSec
            }
        case .winterSunlit:
            return unique.sorted { a, b in
                let aShade = a.averageShadePercentage ?? 0.0
                let bShade = b.averageShadePercentage ?? 0.0
                if abs(aShade - bShade) > 5.0 {
                    return aShade < bShade // Lower shade (more sun) first
                }
                return a.arrivalTimeSec < b.arrivalTimeSec
            }
        }
    }
}
