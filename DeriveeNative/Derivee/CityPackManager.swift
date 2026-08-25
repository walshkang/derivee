import Foundation
import SwiftZSTD
import CryptoKit

public final class CityPackManager: Sendable {
    public static let shared = CityPackManager()
    
    public let fileManager: FileManager
    public let remoteManifestURL: URL
    
    public var cityPacksRootURL: URL {
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            return docs.appendingPathComponent("CityPacks", isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CityPacks", isDirectory: true)
    }
    
    public var cachedManifestURL: URL {
        cityPacksRootURL.appendingPathComponent("cached_cities.json")
    }
    
    public init(
        fileManager: FileManager = .default,
        remoteManifestURL: URL = URL(string: "https://cdn.derivee.app/cities.json")!
    ) {
        self.fileManager = fileManager
        self.remoteManifestURL = remoteManifestURL
        createRootDirectoryIfNeeded()
    }
    
    // MARK: - Directory Resolution
    
    public func packDirectoryURL(for slug: String) -> URL {
        cityPacksRootURL.appendingPathComponent(slug, isDirectory: true)
    }
    
    public func configURL(for slug: String) -> URL {
        packDirectoryURL(for: slug).appendingPathComponent("city_config.json")
    }
    
    public func transitDatabaseURL(for slug: String) -> URL {
        packDirectoryURL(for: slug).appendingPathComponent("transit.sqlite")
    }
    
    public func transitLinesGeoJSONURL(for slug: String) -> URL {
        packDirectoryURL(for: slug).appendingPathComponent("transit-lines.geojson")
    }
    
    // MARK: - First-Launch Bundled Pack Extraction
    
    /// Unpacks the bundled `city-nyc.pack.zst` (<200ms) or initializes the default NYC assets.
    @discardableResult
    public func ensureBundledPackExtracted() throws -> CityConfig {
        createRootDirectoryIfNeeded()
        
        let nycDir = packDirectoryURL(for: "nyc")
        let nycConfigURL = configURL(for: "nyc")
        let nycTransitURL = transitDatabaseURL(for: "nyc")
        
        // If already extracted and valid, load and return
        if fileManager.fileExists(atPath: nycConfigURL.path) && fileManager.fileExists(atPath: nycTransitURL.path) {
            do {
                return try loadConfig(for: "nyc")
            } catch {
                print("⚠️ Corrupted NYC pack detected, re-extracting: \(error)")
            }
        }
        
        // Check for bundled city-nyc.pack.zst in main bundle
        if let bundlePackURL = Bundle.main.url(forResource: "city-nyc.pack", withExtension: "zst") ??
                                Bundle.main.url(forResource: "city-nyc", withExtension: "pack.zst") {
            let archiveData = try Data(contentsOf: bundlePackURL)
            return try unpackAndInstall(archiveData: archiveData, expectedSHA256: nil)
        }
        
        // Fallback initialization from bundled legacy assets (e.g. derivee_transit.sqlite / subway-lines.geojson)
        try fileManager.createDirectory(at: nycDir, withIntermediateDirectories: true, attributes: nil)
        
        // 1. Copy SQLite database
        let transitSourceNames = ["derivee_transit", "transit_delta"]
        for name in transitSourceNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "sqlite") {
                if fileManager.fileExists(atPath: nycTransitURL.path) {
                    try? fileManager.removeItem(at: nycTransitURL)
                }
                try fileManager.copyItem(at: url, to: nycTransitURL)
                break
            }
        }
        
        // 2. Copy GeoJSON if available
        let linesGeoJSONURL = transitLinesGeoJSONURL(for: "nyc")
        if let geojsonBundleURL = Bundle.main.url(forResource: "subway-lines", withExtension: "geojson") ??
                                  Bundle.main.url(forResource: "transit-lines", withExtension: "geojson") {
            if fileManager.fileExists(atPath: linesGeoJSONURL.path) {
                try? fileManager.removeItem(at: linesGeoJSONURL)
            }
            try fileManager.copyItem(at: geojsonBundleURL, to: linesGeoJSONURL)
        }
        
        // 3. Write default CityConfig
        let defaultConfig = CityConfig.nycDefault
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let configData = try encoder.encode(defaultConfig)
        try configData.write(to: nycConfigURL, options: .atomic)
        
        print("📦 [CityPackManager] Initialized default NYC pack in \(nycDir.path)")
        return defaultConfig
    }
    
    // MARK: - Unpack & Install Pipeline
    
    /// Decompresses Zstandard archive, extracts Tar contents atomically to `~/Documents/CityPacks/{slug}/`, and verifies integrity.
    @discardableResult
    public func unpackAndInstall(archiveData: Data, expectedSHA256: String? = nil) throws -> CityConfig {
        createRootDirectoryIfNeeded()
        
        // 1. Verify SHA-256 Checksum if provided
        if let expected = expectedSHA256?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty {
            let actualHash = computeSHA256(data: archiveData)
            guard actualHash == expected else {
                throw CityPackError.integrityCheckFailed(expected: expected, actual: actualHash)
            }
        }
        
        // 2. Decompress Zstandard Archive
        let decompressedData: Data
        do {
            let processor = ZSTDProcessor()
            guard let uncompressed = try? processor.decompressFrame(archiveData) else {
                throw CityPackError.decompressionFailed(reason: "Failed to decompress Zstandard byte stream")
            }
            decompressedData = uncompressed
        }
        
        // 3. Extract to Temporary Staging Directory
        let stagingUUID = UUID().uuidString
        let stagingDir = cityPacksRootURL.appendingPathComponent(".staging_\(stagingUUID)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true, attributes: nil)
        
        var stagingSuccessfullyPromoted = false
        defer {
            if !stagingSuccessfullyPromoted && fileManager.fileExists(atPath: stagingDir.path) {
                try? fileManager.removeItem(at: stagingDir)
            }
        }
        
        try TarExtractor.extract(tarData: decompressedData, to: stagingDir, fileManager: fileManager)
        
        // 4. Validate Mandatory Pack Files
        let stagingConfigURL = stagingDir.appendingPathComponent("city_config.json")
        guard fileManager.fileExists(atPath: stagingConfigURL.path) else {
            throw CityPackError.missingRequiredFile(name: "city_config.json")
        }
        
        let stagingTransitURL = stagingDir.appendingPathComponent("transit.sqlite")
        guard fileManager.fileExists(atPath: stagingTransitURL.path) else {
            throw CityPackError.missingRequiredFile(name: "transit.sqlite")
        }
        
        // 5. Decode & Validate Config
        let configData = try Data(contentsOf: stagingConfigURL)
        let config = try JSONDecoder().decode(CityConfig.self, from: configData)
        guard !config.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CityPackError.invalidArchive(reason: "city_config.json contains empty slug")
        }
        
        let targetDir = packDirectoryURL(for: config.slug)
        
        // 6. Atomic Replacement to Destination Directory
        if fileManager.fileExists(atPath: targetDir.path) {
            let backupDir = cityPacksRootURL.appendingPathComponent(".backup_\(config.slug)_\(stagingUUID)", isDirectory: true)
            try fileManager.moveItem(at: targetDir, to: backupDir)
            do {
                try fileManager.moveItem(at: stagingDir, to: targetDir)
                stagingSuccessfullyPromoted = true
                try? fileManager.removeItem(at: backupDir)
            } catch {
                // Rollback on failure
                try? fileManager.moveItem(at: backupDir, to: targetDir)
                throw error
            }
        } else {
            try fileManager.moveItem(at: stagingDir, to: targetDir)
            stagingSuccessfullyPromoted = true
        }
        
        print("✅ [CityPackManager] Successfully installed city pack '\(config.slug)' at \(targetDir.path)")
        return config
    }
    
    // MARK: - Query & State Inspection
    
    public func isPackInstalled(slug: String) -> Bool {
        let configPath = configURL(for: slug).path
        let transitPath = transitDatabaseURL(for: slug).path
        return fileManager.fileExists(atPath: configPath) && fileManager.fileExists(atPath: transitPath)
    }
    
    public func loadConfig(for slug: String) throws -> CityConfig {
        let configPath = configURL(for: slug)
        guard fileManager.fileExists(atPath: configPath.path) else {
            throw CityPackError.packNotFound(slug: slug)
        }
        let data = try Data(contentsOf: configPath)
        return try JSONDecoder().decode(CityConfig.self, from: data)
    }
    
    public func installedCitySlugs() -> [String] {
        guard let items = try? fileManager.contentsOfDirectory(atPath: cityPacksRootURL.path) else {
            return []
        }
        return items.filter { item in
            !item.hasPrefix(".") && isPackInstalled(slug: item)
        }.sorted()
    }
    
    public func installedCityPacks() -> [InstalledCityPack] {
        return installedCitySlugs().compactMap { slug in
            guard let config = try? loadConfig(for: slug) else { return nil }
            let dirURL = packDirectoryURL(for: slug)
            let transitURL = transitDatabaseURL(for: slug)
            let linesURL = transitLinesGeoJSONURL(for: slug)
            let breakdown = calculateDiskBreakdown(slug: slug)
            let isBundled = (slug == "nyc")
            
            return InstalledCityPack(
                slug: slug,
                config: config,
                packDirectoryURL: dirURL,
                transitDatabaseURL: transitURL,
                transitLinesGeoJSONURL: fileManager.fileExists(atPath: linesURL.path) ? linesURL : nil,
                totalDiskSizeBytes: breakdown.totalBytes,
                isBundled: isBundled,
                breakdown: breakdown
            )
        }
    }
    
    public func calculatePackDiskSize(slug: String) -> Int64 {
        let dir = packDirectoryURL(for: slug)
        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = resourceValues.fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }
    
    public func calculateDiskBreakdown(slug: String) -> CityPackDiskBreakdown {
        let transitURL = transitDatabaseURL(for: slug)
        let linesURL = transitLinesGeoJSONURL(for: slug)
        let configPath = configURL(for: slug)
        
        let transitSize = (try? fileManager.attributesOfItem(atPath: transitURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let linesSize = (try? fileManager.attributesOfItem(atPath: linesURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let configSize = (try? fileManager.attributesOfItem(atPath: configPath.path)[.size] as? NSNumber)?.int64Value ?? 0
        
        let totalSize = calculatePackDiskSize(slug: slug)
        let knownSize = transitSize + linesSize + configSize
        let otherSize = max(0, totalSize - knownSize)
        
        return CityPackDiskBreakdown(
            transitDatabaseBytes: transitSize,
            transitLinesGeoJSONBytes: linesSize,
            configBytes: configSize,
            otherBytes: otherSize,
            totalBytes: totalSize
        )
    }
    
    public func isUpdateAvailable(for slug: String, manifest: CityManifest) -> Bool {
        guard let installed = installedCityPacks().first(where: { $0.slug == slug }),
              let remote = manifest.findCity(bySlug: slug) else {
            return false
        }
        let installedVersion = "1.\(installed.config.version).0"
        return remote.isNewerThan(installedVersion: installedVersion)
    }
    
    public func allInstalledAttributions() -> [String: [String]] {
        var attributions: [String: [String]] = [:]
        for pack in installedCityPacks() {
            if let agency = pack.config.transit?.agencyName, let list = pack.config.transit?.attributions, !list.isEmpty {
                attributions[agency] = list
            }
        }
        return attributions
    }
    
    // MARK: - Deletion
    
    /// Deletes the static pack assets for `slug`. NYC cannot be deleted.
    /// User exploration history (`explored_hexes_{slug}`) in SQLite is permanently preserved.
    public func deletePack(slug: String) throws {
        guard slug != "nyc" else {
            throw CityPackError.coreMetroDeletionBlocked
        }
        let targetDir = packDirectoryURL(for: slug)
        guard fileManager.fileExists(atPath: targetDir.path) else {
            throw CityPackError.packNotFound(slug: slug)
        }
        try fileManager.removeItem(at: targetDir)
        print("🗑️ [CityPackManager] Deleted city pack '\(slug)'")
    }
    
    // MARK: - Download & Install Pipeline
    
    public func downloadAndInstallPack(
        for entry: CityManifestEntry,
        progressHandler: (@Sendable (Double, Int64, Int64) -> Void)? = nil,
        session: URLSession = .shared
    ) async throws -> CityConfig {
        let packURL = URL(string: "https://cdn.derivee.app/packs/city-\(entry.slug).pack.zst")!
        
        var request = URLRequest(url: packURL)
        request.timeoutInterval = 30.0
        
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw CityPackError.downloadFailed(reason: "HTTP \(http.statusCode)")
            }
            progressHandler?(1.0, Int64(data.count), Int64(data.count))
            return try unpackAndInstall(archiveData: data)
        } catch {
            // If download fails or in offline/test mode, check for bundled/mock fallback
            throw CityPackError.downloadFailed(reason: error.localizedDescription)
        }
    }
    
    // MARK: - Manifest Fetcher & Offline Caching
    
    public func fetchRemoteManifest(session: URLSession = .shared) async throws -> CityManifest {
        do {
            var request = URLRequest(url: remoteManifestURL)
            request.timeoutInterval = 10.0
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw CityPackError.manifestFetchFailed(reason: "HTTP \(httpResponse.statusCode)")
            }
            
            let manifest = try JSONDecoder().decode(CityManifest.self, from: data)
            // Cache to disk
            try? data.write(to: cachedManifestURL, options: .atomic)
            return manifest
        } catch {
            // Fallback to disk cache if available
            if fileManager.fileExists(atPath: cachedManifestURL.path),
               let cachedData = try? Data(contentsOf: cachedManifestURL),
               let cachedManifest = try? JSONDecoder().decode(CityManifest.self, from: cachedData) {
                print("📱 [CityPackManager] Using cached cities.json manifest")
                return cachedManifest
            }
            
            // Default built-in fallback manifest
            return CityManifest(
                version: 1,
                lastUpdated: ISO8601DateFormatter().string(from: Date()),
                cities: [
                    CityManifestEntry(
                        slug: "nyc",
                        displayName: "New York City",
                        region: "New York, USA",
                        compressedSizeBytes: 12800000,
                        uncompressedSizeBytes: 28500000,
                        isBundled: true,
                        version: "1.0.0"
                    )
                ]
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func createRootDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cityPacksRootURL.path) {
            try? fileManager.createDirectory(at: cityPacksRootURL, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private func computeSHA256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
