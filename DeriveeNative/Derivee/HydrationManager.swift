import Foundation
import SwiftZSTD
import Observation

@Observable
final class HydrationManager {
    var progress: Double = 0.0
    var isDownloading = false
    var error: Error?
    
    func hydrate() async {
        isDownloading = true
        progress = 0.1
        
        do {
            // 1. Transit DB is now bundled locally and copied by SpatialDatabaseManager on init.
            // We just need to simulate the UI delay and mark hydration as complete.
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            // 2. Update Meta Table
            try await SpatialDatabaseManager.shared.setHydrationComplete()
            
            progress = 1.0
            isDownloading = false
        } catch {
            self.error = error
            isDownloading = false
            print("Hydration failed: \(error)")
        }
    }
}
