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
            // 1. Ensure bundled city pack (NYC) is unpacked and ready in CityPacks/nyc/
            _ = try CityPackManager.shared.ensureBundledPackExtracted()
            
            // Simulate smooth progress transition
            try await Task.sleep(nanoseconds: 500_000_000)
            progress = 0.6
            
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
