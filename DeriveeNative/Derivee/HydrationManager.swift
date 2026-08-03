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
            // 1. Download
            let url = Secrets.transitDeltaURL
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            progress = 0.5
            
            // 2. Decompress
            let processor = ZSTDProcessor()
            let decompressedData = try processor.decompressFrame(data)
            
            progress = 0.8
            
            // 3. Save to Application Support
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let transitDBURL = appSupportURL.appendingPathComponent("derivee_transit.sqlite")
            
            try decompressedData.write(to: transitDBURL, options: .atomic)
            
            // 4. Update Meta Table
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
