import Foundation
import CoreLocation
import H3

final class GPXProcessor {
    private let dbManager: SpatialDatabaseManager
    
    init(dbManager: SpatialDatabaseManager = .shared) {
        self.dbManager = dbManager
    }
    
    func processAndInsert(coordinates: [GPXCoordinate], userLocation: CLLocationCoordinate2D, existingHexes: Set<String>, onProgress: @escaping (Double) -> Void, onComplete: @escaping () -> Void) {
        Task.detached(priority: .userInitiated) {
            var newHexes = Set<String>()
            
            // Convert to H3 (Resolution 11) and deduplicate
            for coord in coordinates {
                do {
                    let index = try H3.latLngToCell(latitude: coord.latitude, longitude: coord.longitude, resolution: 11)
                    let indexString = String(index, radix: 16)
                    if !existingHexes.contains(indexString) {
                        newHexes.insert(indexString)
                    }
                } catch {
                    continue
                }
            }
            
            guard !newHexes.isEmpty else {
                await MainActor.run { onComplete() }
                return
            }
            
            // Calculate distance and cluster
            struct HexDistance {
                let h3Index: String
                let distance: CLLocationDistance
            }
            
            let userCLLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            
            var hexDistances: [HexDistance] = []
            for hex in newHexes {
                if let cell = UInt64(hex, radix: 16) {
                    do {
                        let coord = try H3.cellToLatLng(cell: cell)
                        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        let distance = userCLLoc.distance(from: loc)
                        hexDistances.append(HexDistance(h3Index: hex, distance: distance))
                    } catch {
                        continue
                    }
                }
            }
            
            // Sort by distance (nearest first)
            hexDistances.sort { $0.distance < $1.distance }
            
            // Batch into clusters (e.g. 50 hexes per batch) to achieve 1.5 - 2.5s duration
            let totalNew = hexDistances.count
            let batchCount = min(max(totalNew / 20, 10), 30) // ~10 to 30 batches
            let batchSize = max(totalNew / batchCount, 1)
            
            var batches: [[String]] = []
            var currentBatch: [String] = []
            
            for hd in hexDistances {
                currentBatch.append(hd.h3Index)
                if currentBatch.count >= batchSize {
                    batches.append(currentBatch)
                    currentBatch = []
                }
            }
            if !currentBatch.isEmpty {
                batches.append(currentBatch)
            }
            
            // The total animation duration should be around 2 seconds.
            // So we delay between batches.
            let delayPerBatch = 2.0 / Double(batches.count)
            let sleepNanoseconds = UInt64(delayPerBatch * 1_000_000_000)
            
            for (index, batch) in batches.enumerated() {
                do {
                    try await self.dbManager.insertHexesBatch(h3Indices: batch)
                    let progress = Double(index + 1) / Double(batches.count)
                    await MainActor.run { onProgress(progress) }
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    print("Error inserting batch: \(error)")
                }
            }
            
            await MainActor.run { onComplete() }
        }
    }
}
