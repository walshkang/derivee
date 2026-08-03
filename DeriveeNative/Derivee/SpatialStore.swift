import Foundation
import Observation
import GRDB

@Observable
final class SpatialStore {
    var exploredHexes: Set<String> = []
    
    // We retain the cancellable observation so it stays alive
    private var observationTask: AnyDatabaseCancellable?
    
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
                // We receive the array of hexes, update the Set
                self?.exploredHexes = Set(hexesArray)
            }
        )
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
