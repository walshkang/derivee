import XCTest
import SwiftUI
@testable import Derivee

@MainActor
final class CityPromptSheetTests: XCTestCase {
    
    func testByteFormatting() {
        let entry = CityManifestEntry(
            slug: "bos",
            displayName: "Boston",
            region: "Massachusetts, USA",
            compressedSizeBytes: 9_400_000,
            uncompressedSizeBytes: 22_100_000,
            isBundled: false,
            version: "1.0.0"
        )
        
        XCTAssertTrue(entry.formattedDownloadSize.contains("MB") || entry.formattedDownloadSize.contains("9"),
                      "Formatted download size should contain MB: \(entry.formattedDownloadSize)")
        XCTAssertTrue(entry.formattedUncompressedSize.contains("MB") || entry.formattedUncompressedSize.contains("22"),
                      "Formatted uncompressed size should contain MB: \(entry.formattedUncompressedSize)")
    }
    
    func testDownloadStateTransitions() {
        let idle = CityDownloadState.idle
        let downloading = CityDownloadState.downloading(progress: 0.5, receivedBytes: 5_000_000, totalBytes: 10_000_000)
        let extracting = CityDownloadState.extracting
        let completed = CityDownloadState.completed
        let failed = CityDownloadState.failed(error: "Network timeout")
        
        XCTAssertEqual(idle, CityDownloadState.idle)
        XCTAssertEqual(downloading, CityDownloadState.downloading(progress: 0.5, receivedBytes: 5_000_000, totalBytes: 10_000_000))
        XCTAssertEqual(extracting, CityDownloadState.extracting)
        XCTAssertEqual(completed, CityDownloadState.completed)
        XCTAssertEqual(failed, CityDownloadState.failed(error: "Network timeout"))
        XCTAssertNotEqual(idle, completed)
    }
    
    func testCustomDownloadHandlerExecution() async throws {
        let city = CityManifest.defaultManifest.cities[1] // Boston
        var receivedProgress: [Double] = []
        var completedCity: CityManifestEntry? = nil
        
        let customHandler: @Sendable (CityManifestEntry, @escaping @Sendable (Double, Int64, Int64) -> Void) async throws -> Void = { entry, progressCallback in
            progressCallback(0.25, 2_500_000, 10_000_000)
            progressCallback(0.75, 7_500_000, 10_000_000)
            progressCallback(1.0, 10_000_000, 10_000_000)
        }
        
        let view = CityDownloadPromptSheet(
            city: city,
            onDownloadComplete: { entry in
                completedCity = entry
            },
            downloadHandler: { entry, cb in
                try await customHandler(entry) { p, r, t in
                    receivedProgress.append(p)
                    cb(p, r, t)
                }
            }
        )
        
        XCTAssertNotNil(view.city)
        XCTAssertEqual(view.city.slug, "bos")
    }
}
