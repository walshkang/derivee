import Foundation
import Observation
import GRDB
import MapLibre
import H3

@Observable
final class SpatialStore {
    var exploredHexes: Set<String> = []
    
    var newlyUnlockedHexLocation: CLLocationCoordinate2D? = nil
    var currentFogShape: MLNShape? = nil
    
    // We retain the cancellable observation so it stays alive
    private var observationTask: AnyDatabaseCancellable?
    private var polygonTask: Task<Void, Never>?
    private var previousCount: Int = 0
    private var previousHexes: Set<String> = []
    
    init(dbManager: SpatialDatabaseManager = .shared) {
        startObservation(dbManager: dbManager)
    }
    
    private func startObservation(dbManager: SpatialDatabaseManager) {
        let request = SQLRequest<String>(sql: "SELECT h3_index FROM explored_hexes")
        let observation = ValueObservation.tracking { db in
            try request.fetchAll(db)
        }
        
        observationTask = observation.start(
            in: dbManager.dbPool,
            onError: { error in
                print("SpatialStore Observation error: \(error)")
            },
            onChange: { [weak self] hexesArray in
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
                
                self.recomputeFogShape(hexes: newSet, newlyUnlockedCell: newlyUnlockedCell)
            }
        )
    }
    
    private func recomputeFogShape(hexes: Set<String>, newlyUnlockedCell: UInt64?) {
        polygonTask?.cancel()
        polygonTask = Task.detached(priority: .background) {
            let bounds = [
                CLLocationCoordinate2D(latitude: 41.5, longitude: -74.5),
                CLLocationCoordinate2D(latitude: 41.5, longitude: -73.0),
                CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0),
                CLLocationCoordinate2D(latitude: 40.0, longitude: -74.5),
                CLLocationCoordinate2D(latitude: 41.5, longitude: -74.5)
            ]
            
            var innerRings: [MLNPolygon] = []
            for hexString in hexes {
                guard let cell = UInt64(hexString, radix: 16) else { continue }
                do {
                    let boundary = try H3.cellToBoundary(cell: cell)
                    var coords = boundary.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    
                    // Force CCW winding order for MapLibre interior rings (holes)
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
            if let cell = newlyUnlockedCell {
                do {
                    let coord = try H3.cellToLatLng(cell: cell)
                    newHexLocation = CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
                } catch {
                    // Ignore
                }
            }
            
            await MainActor.run { [weak self] in
                if Task.isCancelled { return }
                self?.currentFogShape = fogPolygon
                if newHexLocation != nil {
                    DispatchQueue.main.async {
                        self?.newlyUnlockedHexLocation = newHexLocation
                    }
                }
            }
        }
    }
    
    func insertHex(_ h3Index: String) {
        Task {
            do {
                try await SpatialDatabaseManager.shared.insertDiscoveredHex(h3Index: h3Index)
            } catch {
                print("Failed to insert hex \(h3Index): \(error)")
            }
        }
    }
}
