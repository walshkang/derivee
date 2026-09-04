import Foundation
import Observation
import GRDB
import MapLibre
import H3

@Observable
final class SpatialStore: @unchecked Sendable {
    var activeCitySlug: String = "nyc"
    var activeCityConfig: CityConfig = .nycDefault
    
    var exploredHexes: Set<String> = []
    
    var newlyUnlockedHexLocation: CLLocationCoordinate2D? = nil
    var transientHexShape: MLNShape? = nil
    var currentFogShape: MLNShape? = nil
    
    var discoveredPOIs: Set<String> = []
    var newlyDiscoveredPOIName: String? = nil
    
    // We retain the cancellable observation so it stays alive
    @ObservationIgnored private var observationTask: AnyDatabaseCancellable?
    @ObservationIgnored private var polygonTask: Task<Void, Never>?
    @ObservationIgnored private var previousCount: Int = 0
    @ObservationIgnored private var previousHexes: Set<String> = []
    
    @ObservationIgnored private let dbManager: SpatialDatabaseManager
    @ObservationIgnored private let liveUpdatePriority: TaskPriority
    @ObservationIgnored private let observationScheduler: ValueObservationScheduler
    
    /// Metal spatial memory engine managing the open-addressing GPU hash table (Wave O.2 & O.3)
    public private(set) var spatialEngine: H3SpatialMemoryEngine?
    
    init(
        dbManager: SpatialDatabaseManager = .shared,
        cityConfig: CityConfig = .nycDefault,
        liveUpdatePriority: TaskPriority = .userInitiated,
        observationScheduler: ValueObservationScheduler = .async(onQueue: .main)
    ) {
        self.dbManager = dbManager
        self.activeCityConfig = cityConfig
        self.activeCitySlug = cityConfig.slug
        self.liveUpdatePriority = liveUpdatePriority
        self.observationScheduler = observationScheduler
        self.spatialEngine = try? H3SpatialMemoryEngine()
        CameraBounds.setActiveConfig(cityConfig)
        startObservation(for: cityConfig.slug)
        
        Task {
            do {
                let pois = try await dbManager.loadDiscoveredPOIs()
                await MainActor.run {
                    self.discoveredPOIs = pois
                }
            } catch {
                print("Failed to load discovered POIs: \(error)")
            }
        }
    }
    
    deinit {
        print("🔴 [SpatialStore] deinit fired! Instance deallocated: \(ObjectIdentifier(self))")
    }
    
    @MainActor
    func setActiveCity(_ config: CityConfig) {
        guard config.slug != activeCitySlug else { return }
        logPipeline("🏙️ [SpatialStore] Hot-swapping active city to: \(config.displayName) (\(config.slug))")
        self.activeCityConfig = config
        self.activeCitySlug = config.slug
        CameraBounds.setActiveConfig(config)
        self.previousCount = 0
        self.previousHexes.removeAll()
        self.exploredHexes.removeAll()
        self.currentFogShape = nil
        self.transientHexShape = nil
        self.newlyUnlockedHexLocation = nil
        
        Task { [weak self, dbWriter = dbManager.dbWriter, slug = config.slug] in
            guard let self = self, let engine = self.spatialEngine else { return }
            try? await engine.reset()
            try? await engine.hydrateFromDatabase(dbWriter: dbWriter, citySlug: slug)
        }
        
        startObservation(for: config.slug)
    }
    
    private func startObservation(for citySlug: String) {
        observationTask?.cancel()
        observationTask = nil
        
        let tableName = SpatialDatabaseManager.tableName(for: citySlug)
        logPipeline("🔍 [SpatialStore] startObservation attaching to table \(tableName) in dbWriter pool: \(ObjectIdentifier(dbManager.dbWriter as AnyObject))")
        
        let observation = ValueObservation.tracking { db in
            let hexes = try String.fetchAll(db, sql: "SELECT h3_index FROM \(tableName)")
            logPipeline("🔍 [GRDB Pipeline] ValueObservation fetched \(hexes.count) hexes from \(tableName) on Thread: \(Thread.current)")
            return hexes
        }
        .handleEvents(
            willTrackRegion: { region in logPipeline("🔍 [GRDB Pipeline] willTrackRegion: \(region)") },
            databaseDidChange: { logPipeline("🔍 [GRDB Pipeline] databaseDidChange fired for \(tableName)!") }
        )
        
        observationTask = observation.start(
            in: dbManager.dbWriter,
            scheduling: self.observationScheduler,
            onError: { error in
                logPipeline("SpatialStore Observation error on \(tableName): \(error)")
            },
            onChange: { [weak self] hexesArray in
                guard let self = self else { return }
                logPipeline("📍 [S4 - onChange] fired with \(hexesArray.count) hexes for \(citySlug) on Thread: \(Thread.current)")
                
                let newSet = Set(hexesArray)
                let newCount = newSet.count
                let oldCount = self.previousCount
                
                var newlyUnlockedCell: UInt64? = nil
                if oldCount > 0 && newCount > oldCount {
                    if let newlyUnlocked = newSet.subtracting(self.previousHexes).first,
                       let cell = UInt64(newlyUnlocked, radix: 16) {
                        newlyUnlockedCell = cell
                    }
                }
                
                self.exploredHexes = newSet
                self.previousCount = newCount
                self.previousHexes = newSet
                
                if oldCount == 0 {
                    Task { [weak self, dbWriter = self.dbManager.dbWriter, slug = citySlug] in
                        guard let self = self, let engine = self.spatialEngine else { return }
                        try? await engine.hydrateFromDatabase(dbWriter: dbWriter, citySlug: slug)
                    }
                } else if let cell = newlyUnlockedCell {
                    Task { [weak self] in
                        guard let self = self, let engine = self.spatialEngine else { return }
                        let timestamp = UInt32(Date().timeIntervalSince1970)
                        try? await engine.ingestHexIndices([(h3Index: cell, timestamp: timestamp)])
                    }
                }
                
                self.recomputeFogShape(hexes: newSet, newlyUnlockedCell: newlyUnlockedCell, isInitial: oldCount == 0)
            }
        )
    }
    
    private func recomputeFogShape(hexes: Set<String>, newlyUnlockedCell: UInt64?, isInitial: Bool = false) {
        polygonTask?.cancel()
        let taskPriority: TaskPriority = isInitial ? .userInitiated : self.liveUpdatePriority
        let currentBounds = self.activeCityConfig.bounds
        polygonTask = Task.detached(priority: taskPriority) {
            logPipeline("📍 [S5 - recomputeFogShape ENTER] at \(Date()), priority=\(taskPriority), hexCount=\(hexes.count), isCancelled=\(Task.isCancelled)")
            // VERIFIED: MapLibre Native (iOS) requires Clockwise (CW) winding order for exterior bounds.
            // Tested & hardened in Wave I.2 (WI2-WINDING) & Wave M.5.1 (WM5.1-GLOBAL-FOG).
            // JITTER APPLIED: MapLibre ignores updates to polygons if the exterior bounding box 
            // hasn't changed. We jitter the top-left corner slightly to force a cache invalidation 
            // and redraw the new holes.
            let jitter = Double.random(in: 0...0.00001)
            let bounds = FogPolygonMath.makeWorldBounds(jitter: jitter)
            
            let fogGeometry = FogPolygonMath.dissolveHexesToFogGeometry(hexes: hexes, bounds: bounds)
            
            if Task.isCancelled {
                logPipeline("📍 [S5 - recomputeFogShape CANCELLED] before polygon construction, hexCount=\(hexes.count)")
                return
            }
            let capturedCutoutCount = fogGeometry.worldMaskPolygon.interiorPolygons?.count ?? 0
            let capturedIslandCount = fogGeometry.islandPolygons.count
            print("Generated \(capturedCutoutCount) cutout holes and \(capturedIslandCount) fog islands")
            
            let fogShape = fogGeometry.compositeShape
            
            // If a new hex was unlocked, get its center coordinate
            var newHexLocation: CLLocationCoordinate2D? = nil
            var transientHexPolygon: MLNPolygon? = nil
            if let cell = newlyUnlockedCell {
                do {
                    let coord = try H3.cellToLatLng(cell: cell)
                    newHexLocation = CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
                    
                    let boundary = try H3.cellToBoundary(cell: cell)
                    var polyCoords = boundary.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    if polyCoords.count > 0, let first = polyCoords.first {
                        polyCoords.append(first)
                    }
                    if polyCoords.count >= 4 {
                        transientHexPolygon = MLNPolygon(coordinates: polyCoords, count: UInt(polyCoords.count))
                    }
                } catch {
                    // Ignore
                }
            }
            
            let capturedNewHexLocation = newHexLocation
            let capturedTransientShape = transientHexPolygon
            print("✅ recomputeFogShape EXIT at \(Date())")
            await MainActor.run { [weak self] in
                if Task.isCancelled {
                    logPipeline("📍 [S5 - recomputeFogShape CANCELLED] inside MainActor.run, hexCount=\(hexes.count)")
                    return
                }
                logPipeline("📍 [S5 - recomputeFogShape COMPLETE] Rendering \(capturedCutoutCount) cutout holes and \(capturedIslandCount) fog islands, setting currentFogShape")
                self?.currentFogShape = fogShape
                self?.transientHexShape = capturedTransientShape
                if let loc = capturedNewHexLocation {
                    self?.newlyUnlockedHexLocation = loc
                }
            }
        }
    }
    
    func insertHex(_ h3Index: String, citySlug: String? = nil, enforceLandOnly: Bool = true) {
        let targetSlug = citySlug ?? activeCitySlug
        Task {
            do {
                try await self.dbManager.insertDiscoveredHex(h3Index: h3Index, citySlug: targetSlug, enforceLandOnly: enforceLandOnly)
            } catch {
                print("Failed to insert hex \(h3Index) for \(targetSlug): \(error)")
            }
        }
    }
    
    func discoverPOI(id: String, name: String) {
        guard !discoveredPOIs.contains(id) else { return }
        
        discoveredPOIs.insert(id)
        newlyDiscoveredPOIName = name
        
        Task {
            do {
                try await self.dbManager.insertDiscoveredPOI(id)
            } catch {
                print("Failed to save discovered POI \(id): \(error)")
            }
        }
    }
    
    public func getExploredCoordinates() -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(exploredHexes.count)
        for hex in exploredHexes {
            if let cell = UInt64(hex, radix: 16),
               let coord = try? H3.cellToLatLng(cell: cell) {
                coords.append(CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude))
            }
        }
        return coords
    }
    
    @MainActor
    func clearData() {
        exploredHexes.removeAll()
        previousHexes.removeAll()
        previousCount = 0
        discoveredPOIs.removeAll()
        newlyDiscoveredPOIName = nil
        currentFogShape = nil
        transientHexShape = nil
    }
}
