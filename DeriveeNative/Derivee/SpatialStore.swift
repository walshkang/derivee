import Foundation
import Observation
import GRDB
import MapLibre
import H3

@Observable
final class SpatialStore: @unchecked Sendable {
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
    
    init(
        dbManager: SpatialDatabaseManager = .shared, 
        liveUpdatePriority: TaskPriority = .userInitiated,
        observationScheduler: ValueObservationScheduler = .async(onQueue: .main)
    ) {
        self.dbManager = dbManager
        self.liveUpdatePriority = liveUpdatePriority
        self.observationScheduler = observationScheduler
        startObservation(dbManager: dbManager)
        
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
    
    private struct ExploredHex: TableRecord, FetchableRecord {
        static let databaseTableName = "explored_hexes"
        let h3_index: String
        
        init(row: GRDB.Row) {
            h3_index = row["h3_index"]
        }
    }
    
    private func startObservation(dbManager: SpatialDatabaseManager) {
        print("🔍 [SpatialStore] startObservation attaching to dbWriter pool: \(ObjectIdentifier(dbManager.dbWriter as AnyObject))")
        let observation = ValueObservation.tracking { db in
            let hexes = try ExploredHex.fetchAll(db).map { $0.h3_index }
            print("🔍 [GRDB Pipeline] ValueObservation fetched \(hexes.count) hexes on Thread: \(Thread.current)")
            return hexes
        }
        .handleEvents(
            willTrackRegion: { region in print("🔍 [GRDB Pipeline] willTrackRegion: \(region)") },
            databaseDidChange: { print("🔍 [GRDB Pipeline] databaseDidChange fired!") }
        )
        
        observationTask = observation.start(
            in: dbManager.dbWriter,
            scheduling: self.observationScheduler,
            onError: { error in
                print("SpatialStore Observation error: \(error)")
            },
            onChange: { [weak self] hexesArray in
                print("🚀 [GRDB Pipeline] onChange fired with \(hexesArray.count) hexes on Thread: \(Thread.current)")
                guard let self = self else { return }
                
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
                
                self.recomputeFogShape(hexes: newSet, newlyUnlockedCell: newlyUnlockedCell, isInitial: oldCount == 0)
            }
        )
    }
    
    private func recomputeFogShape(hexes: Set<String>, newlyUnlockedCell: UInt64?, isInitial: Bool = false) {
        polygonTask?.cancel()
        let taskPriority: TaskPriority = isInitial ? .userInitiated : self.liveUpdatePriority
        polygonTask = Task.detached(priority: taskPriority) {
            print("⏳ recomputeFogShape ENTER at \(Date()) priority=\(taskPriority)")
            // VERIFIED: MapLibre Native (iOS) requires Clockwise (CW) winding order for exterior bounds.
            // Tested & hardened in Wave I.2 (WI2-WINDING).
            // JITTER APPLIED: MapLibre ignores updates to polygons if the exterior bounding box 
            // hasn't changed. We jitter the top-left corner slightly to force a cache invalidation 
            // and redraw the new holes.
            let jitter = Double.random(in: 0...0.00001)
            let bounds = [
                CLLocationCoordinate2D(latitude: 41.5 + jitter, longitude: -74.5 - jitter), // Top Left
                CLLocationCoordinate2D(latitude: 41.5, longitude: -73.0), // Top Right
                CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0), // Bottom Right
                CLLocationCoordinate2D(latitude: 40.0, longitude: -74.5), // Bottom Left
                CLLocationCoordinate2D(latitude: 41.5 + jitter, longitude: -74.5 - jitter)  // Top Left (closed)
            ]
            
            var innerRings: [MLNPolygon] = []
            for hexString in hexes {
                guard let cell = UInt64(hexString, radix: 16) else { continue }
                do {
                    let boundary = try H3.cellToBoundary(cell: cell)
                    var coords = boundary.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    
                    // VERIFIED: MapLibre Native (iOS) interior polygon rings (holes) require CW winding order.
                    // H3 cellToBoundary defaults to CCW; reversing produces CW order.
                    // Tested & hardened in Wave I.2 (WI2-WINDING). Do NOT change without re-testing fog rendering.
                    coords.reverse()
                    
                    if coords.count > 0, let first = coords.first {
                        coords.append(first)
                    }
                    if coords.count >= 4 {
                        innerRings.append(MLNPolygon(coordinates: coords, count: UInt(coords.count)))
                    }
                } catch {
                    // Ignore errors for individual hexes
                }
            }
            
            if Task.isCancelled { return }
            print("Generated \(innerRings.count) interior rings for the fog mask")
            
            let fogPolygon = MLNPolygon(coordinates: bounds, count: UInt(bounds.count), interiorPolygons: innerRings.isEmpty ? nil : innerRings)
            
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
            let capturedRingsCount = innerRings.count
            print("✅ recomputeFogShape EXIT at \(Date())")
            await MainActor.run { [weak self] in
                if Task.isCancelled { return }
                print("DEBUG: Rendering \(capturedRingsCount) interior rings, setting currentFogShape")
                self?.currentFogShape = fogPolygon
                self?.transientHexShape = capturedTransientShape
                if let loc = capturedNewHexLocation {
                    self?.newlyUnlockedHexLocation = loc
                }
            }
        }
    }
    
    func insertHex(_ h3Index: String) {
        Task {
            do {
                try await self.dbManager.insertDiscoveredHex(h3Index: h3Index)
            } catch {
                print("Failed to insert hex \(h3Index): \(error)")
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
