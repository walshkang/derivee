import Foundation
import CoreLocation
import H3

final class GPXProcessor {
    private let dbManager: SpatialDatabaseManager
    
    init(dbManager: SpatialDatabaseManager = .shared) {
        self.dbManager = dbManager
    }
    
    /// Smart Multi-City GPX Auto-Partitioning & Import:
    /// Partitions coordinates by city bounding boxes and inserts into per-city tables in a single atomic SQLite transaction.
    func processAndInsertMultiCity(
        coordinates: [GPXCoordinate],
        manifest: CityManifest = .defaultManifest,
        defaultCitySlug: String = "nyc",
        userLocation: CLLocationCoordinate2D? = nil,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (MultiCityImportResult) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            var partitionedHexes: [String: Set<String>] = [:]
            
            // 1. Convert coordinates to H3 (Resolution 11) and partition by bounding box
            for coord in coordinates {
                let location = CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
                
                // Match against known city bounding boxes in manifest
                let matchedSlug: String
                if let matchedEntry = manifest.findCity(containing: location) {
                    matchedSlug = matchedEntry.slug
                } else {
                    matchedSlug = defaultCitySlug
                }
                
                do {
                    let index = try H3.latLngToCell(latitude: coord.latitude, longitude: coord.longitude, resolution: 11)
                    let indexString = String(index, radix: 16)
                    partitionedHexes[matchedSlug, default: []].insert(indexString)
                } catch {
                    continue
                }
            }
            
            let totalHexCount = partitionedHexes.values.reduce(0) { $0 + $1.count }
            guard totalHexCount > 0 else {
                await MainActor.run {
                    onProgress(1.0)
                    onComplete(MultiCityImportResult(totalHexesImported: 0, cityHexCounts: [:]))
                }
                return
            }
            
            // 2. Prepare dictionary for batch insert
            var insertPayload: [String: [String]] = [:]
            var countsSummary: [String: Int] = [:]
            for (slug, hexSet) in partitionedHexes {
                let array = Array(hexSet)
                insertPayload[slug] = array
                countsSummary[slug] = array.count
            }
            
            // 3. Execute single atomic SQLite transaction
            do {
                await MainActor.run { onProgress(0.5) }
                try await self.dbManager.batchInsertMultiCityHexes(insertPayload)
                await MainActor.run {
                    onProgress(1.0)
                    let result = MultiCityImportResult(
                        totalHexesImported: totalHexCount,
                        cityHexCounts: countsSummary
                    )
                    onComplete(result)
                }
            } catch {
                print("⚠️ [GPXProcessor] Error inserting multi-city hexes: \(error)")
                await MainActor.run {
                    onProgress(1.0)
                    onComplete(MultiCityImportResult(totalHexesImported: 0, cityHexCounts: [:]))
                }
            }
        }
    }
    
    /// Legacy compatibility wrapper
    func processAndInsert(
        coordinates: [GPXCoordinate],
        userLocation: CLLocationCoordinate2D,
        existingHexes: Set<String>,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping () -> Void
    ) {
        processAndInsertMultiCity(
            coordinates: coordinates,
            manifest: .defaultManifest,
            defaultCitySlug: "nyc",
            userLocation: userLocation,
            onProgress: onProgress,
            onComplete: { _ in
                onComplete()
            }
        )
    }
}
