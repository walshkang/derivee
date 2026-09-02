import Foundation
import Observation
import CoreLocation

/// Application-level coordinator managing the on-device Hybrid RAPTOR C++ routing engine lifecycle,
/// thread-safe `.userInitiated` background query execution, active city asset bindings,
/// dynamic GTFS-RT delays, service disruptions, and reactive SwiftUI state.
@Observable
@MainActor
public final class JourneyPlanner {
    
    // MARK: - Shared Singleton
    
    public static let shared = JourneyPlanner()
    
    // MARK: - Reactive UI State
    
    public private(set) var isReady: Bool = false
    public private(set) var isLoading: Bool = false
    public private(set) var activeCitySlug: String = ""
    public private(set) var currentJourneys: [JourneyItinerary] = []
    public var selectedJourney: JourneyItinerary? = nil
    public var selectedProfile: RoutingProfile = .mostReliable {
        didSet {
            recalculateSelectedJourney()
        }
    }
    public private(set) var executionLatencyMs: Double = 0.0
    public private(set) var lastError: String? = nil
    
    // MARK: - Subsystems & Dependencies
    
    public let bridge: RoutingEngineBridge
    private let packManager: CityPackManager
    private let transitEngine: TransitDatabaseEngine
    private let spatialDbManager: SpatialDatabaseManager
    private let gbfsService: GBFSSyncService?
    private var activeMetadataProvider: (any StopMetadataProvider)?
    
    // MARK: - Lifecycle & Initialization
    
    public init(
        bridge: RoutingEngineBridge = RoutingEngineBridge(),
        metadataProvider: (any StopMetadataProvider)? = nil,
        packManager: CityPackManager = .shared,
        transitEngine: TransitDatabaseEngine = .shared,
        spatialDbManager: SpatialDatabaseManager = .shared,
        gbfsService: GBFSSyncService? = .shared
    ) {
        self.bridge = bridge
        self.activeMetadataProvider = metadataProvider
        self.packManager = packManager
        self.transitEngine = transitEngine
        self.spatialDbManager = spatialDbManager
        self.gbfsService = gbfsService
        
        if let provider = metadataProvider {
            Task {
                await bridge.setMetadataProvider(provider)
                if let gbfs = gbfsService {
                    await bridge.setGbfsService(gbfs)
                }
            }
        }
    }
    
    // MARK: - City Lifecycle & Asset Configuration
    
    /// Loads memory-mapped binary routing assets (`timetable.bin`, `ultra_transfers.csr`, `walk_graph.bin`)
    /// for the given city slug, pre-warms database stop metadata, and syncs disruptions.
    public func configureForCity(slug: String) async throws {
        logPipeline("🧭 [JourneyPlanner] Configuring routing engine for city: \(slug)")
        self.isLoading = true
        self.lastError = nil
        
        let fileManager = FileManager.default
        let timetableURL = packManager.timetableURL(for: slug)
        let ultraURL = packManager.ultraTransfersURL(for: slug)
        let walkGraphURL = packManager.walkGraphURL(for: slug)
        
        // 1. Load binary timetable (DRV1 format)
        if fileManager.fileExists(atPath: timetableURL.path) {
            do {
                let ttSuccess = try await bridge.loadTimetable(from: timetableURL)
                logPipeline("🧭 [JourneyPlanner] Timetable loaded: \(ttSuccess)")
            } catch {
                logPipeline("⚠️ [JourneyPlanner] Failed to load timetable: \(error)")
                self.lastError = "Failed to load timetable: \(error.localizedDescription)"
            }
        }
        
        // 2. Load ULTRA transfers (.csr format)
        if fileManager.fileExists(atPath: ultraURL.path) {
            do {
                let ultraSuccess = try await bridge.loadUltra(from: ultraURL)
                logPipeline("🧭 [JourneyPlanner] ULTRA transfers loaded: \(ultraSuccess)")
            } catch {
                logPipeline("⚠️ [JourneyPlanner] Failed to load ULTRA transfers: \(error)")
            }
        }
        
        // 3. Load Walk Graph (.bin format)
        if fileManager.fileExists(atPath: walkGraphURL.path) {
            do {
                let walkSuccess = try await bridge.loadWalkGraph(from: walkGraphURL)
                logPipeline("🧭 [JourneyPlanner] Walk graph loaded: \(walkSuccess)")
            } catch {
                logPipeline("⚠️ [JourneyPlanner] Failed to load walk graph: \(error)")
            }
        }
        
        // 4. Initialize & warm database stop metadata provider
        let provider = SpatialDatabaseStopMetadataProvider()
        do {
            try await provider.warm(using: spatialDbManager.dbWriter, isAttachedMode: true)
            self.activeMetadataProvider = provider
            await bridge.setMetadataProvider(provider)
        } catch {
            logPipeline("⚠️ [JourneyPlanner] Metadata warming error: \(error)")
        }
        
        // 5. Attach GBFS dynamic service
        if let gbfs = gbfsService {
            await bridge.setGbfsService(gbfs)
        }
        
        // 6. Ingest active service disruptions
        await syncActiveDisruptions()
        
        self.activeCitySlug = slug
        self.isReady = await bridge.isLoaded
        self.isLoading = false
        logPipeline("✅ [JourneyPlanner] Engine ready for \(slug). isReady = \(self.isReady)")
    }
    
    /// Prepares the routing engine for a city hot-swap by clearing memory references,
    /// dynamic delays, and active disruptions. Aligns with Wave L Two-Phase Barrier.
    public func prepareForCitySwap() async {
        logPipeline("🛑 [JourneyPlanner] prepareForCitySwap executing")
        self.isReady = false
        self.currentJourneys = []
        self.selectedJourney = nil
        await bridge.clearRealtimeDelays()
        await bridge.clearDisruptions()
        await bridge.reset()
    }
    
    // MARK: - Dynamic State Synchronization
    
    /// Synchronizes active GTFS-RT service disruptions from `TransitDatabaseEngine` into the bridge.
    public func syncActiveDisruptions(epoch: Int64 = Int64(Date().timeIntervalSince1970)) async {
        do {
            let disruptions = try await transitEngine.fetchActiveDisruptions(at: epoch)
            await bridge.clearDisruptions()
            
            for item in disruptions {
                if let sId = item.stopId {
                    // If metadata provider knows numeric index, set stop disrupted
                    if let dbProvider = self.activeMetadataProvider as? SpatialDatabaseStopMetadataProvider,
                       let numIdx = dbProvider.indexOfStop(stopIdString: sId) {
                        await bridge.setStopDisrupted(stopId: numIdx, disrupted: true)
                    } else if let numIdx = UInt32(sId) {
                        await bridge.setStopDisrupted(stopId: numIdx, disrupted: true)
                    }
                }
            }
            logPipeline("🚦 [JourneyPlanner] Synced \(disruptions.count) active disruptions to routing engine")
        } catch {
            logPipeline("⚠️ [JourneyPlanner] Failed to fetch active disruptions: \(error)")
        }
    }
    
    /// Forwards real-time delay updates (e.g. from GTFS-RT trip updates) to the C++ engine.
    public func updateRealtimeDelay(tripId: UInt32, delaySeconds: Int32) async {
        await bridge.updateRealtimeDelay(tripId: tripId, delaySeconds: delaySeconds)
    }
    
    /// Flushes all active real-time delays from the engine.
    public func clearRealtimeDelays() async {
        await bridge.clearRealtimeDelays()
    }
    
    // MARK: - Journey Pathfinding Execution
    
    /// Executes a multi-criteria multimodal pathfinding search between two locations.
    /// Heavy computation runs strictly at `.userInitiated` priority in detached background tasks.
    @discardableResult
    public func planJourneys(
        origin: RoutingLocation,
        destination: RoutingLocation,
        departureTime: Date = Date(),
        profile: RoutingProfile? = nil,
        options: RoutingOptions = .default
    ) async -> [JourneyItinerary] {
        let activeProfile = profile ?? self.selectedProfile
        self.isLoading = true
        self.lastError = nil
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let results = await bridge.computeJourneys(
            origin: origin,
            destination: destination,
            departureTime: departureTime,
            profile: activeProfile,
            options: options
        )
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        self.executionLatencyMs = elapsed
        self.currentJourneys = results
        self.selectedJourney = results.first
        self.isLoading = false
        
        logPipeline("⚡️ [JourneyPlanner] Computed \(results.count) journeys in \(String(format: "%.2f", elapsed))ms for profile: \(activeProfile.displayName)")
        return results
    }
    
    // MARK: - Profile & Selection Management
    
    public func selectProfile(_ profile: RoutingProfile) {
        guard self.selectedProfile != profile else { return }
        self.selectedProfile = profile
    }
    
    public func selectJourney(_ journey: JourneyItinerary) {
        self.selectedJourney = journey
    }
    
    private func recalculateSelectedJourney() {
        if let current = selectedJourney, currentJourneys.contains(current) {
            return
        }
        self.selectedJourney = currentJourneys.first
    }
}
