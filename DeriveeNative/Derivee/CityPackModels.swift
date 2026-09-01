import Foundation
import CoreLocation

// MARK: - Bounding Box & Center Models

public struct CityBounds: Codable, Sendable, Equatable, Hashable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double
    
    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }
    
    public func contains(latitude: Double, longitude: Double) -> Bool {
        return latitude >= minLatitude && latitude <= maxLatitude &&
               longitude >= minLongitude && longitude <= maxLongitude
    }
    
    public func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        return contains(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    
    /// Checks if a coordinate is within an elastic rubber-band margin beyond the hard bounds.
    public func isWithinRubberBandLimit(_ coordinate: CLLocationCoordinate2D, margin: Double = 0.05) -> Bool {
        return coordinate.latitude >= (minLatitude - margin) &&
               coordinate.latitude <= (maxLatitude + margin) &&
               coordinate.longitude >= (minLongitude - margin) &&
               coordinate.longitude <= (maxLongitude + margin)
    }
    
    /// Clamps a coordinate to this bounding box's boundaries.
    public func clampedCoordinate(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let clampedLat = min(max(coordinate.latitude, minLatitude), maxLatitude)
        let clampedLon = min(max(coordinate.longitude, minLongitude), maxLongitude)
        return CLLocationCoordinate2D(latitude: clampedLat, longitude: clampedLon)
    }
    
    /// Generates the 5-point counter-clockwise polygon loop representing the exterior bounds.
    public func exteriorCoordinates() -> [CLLocationCoordinate2D] {
        return [
            CLLocationCoordinate2D(latitude: minLatitude, longitude: minLongitude), // SW
            CLLocationCoordinate2D(latitude: minLatitude, longitude: maxLongitude), // SE
            CLLocationCoordinate2D(latitude: maxLatitude, longitude: maxLongitude), // NE
            CLLocationCoordinate2D(latitude: maxLatitude, longitude: minLongitude), // NW
            CLLocationCoordinate2D(latitude: minLatitude, longitude: minLongitude)  // Closed SW
        ]
    }
}

public struct CityCenter: Codable, Sendable, Equatable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public let defaultZoom: Double
    
    public init(latitude: Double, longitude: Double, defaultZoom: Double = 13.0) {
        self.latitude = latitude
        self.longitude = longitude
        self.defaultZoom = defaultZoom
    }
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Transit Configuration Models

public struct RealtimeEndpoint: Codable, Sendable, Equatable, Hashable {
    public let feedId: String
    public let url: String
    public let pollIntervalSeconds: Double
    public let headers: [String: String]?
    
    public init(feedId: String, url: String, pollIntervalSeconds: Double = 15.0, headers: [String: String]? = nil) {
        self.feedId = feedId
        self.url = url
        self.pollIntervalSeconds = pollIntervalSeconds
        self.headers = headers
    }
}

public struct ScheduleValidity: Codable, Sendable, Equatable, Hashable {
    public let startDate: String?
    public let endDate: String?
    public let seasonLabel: String?
    
    public init(startDate: String? = nil, endDate: String? = nil, seasonLabel: String? = nil) {
        self.startDate = startDate
        self.endDate = endDate
        self.seasonLabel = seasonLabel
    }
}

public struct GBFSConfig: Codable, Sendable, Equatable, Hashable {
    public let systemId: String
    public let stationInfoUrl: String
    public let stationStatusUrl: String
    public let pollIntervalSeconds: Double
    public let stalenessThresholdSeconds: Double
    public let headers: [String: String]?
    
    public init(
        systemId: String,
        stationInfoUrl: String,
        stationStatusUrl: String,
        pollIntervalSeconds: Double = 30.0,
        stalenessThresholdSeconds: Double = 600.0,
        headers: [String: String]? = nil
    ) {
        self.systemId = systemId
        self.stationInfoUrl = stationInfoUrl
        self.stationStatusUrl = stationStatusUrl
        self.pollIntervalSeconds = pollIntervalSeconds
        self.stalenessThresholdSeconds = stalenessThresholdSeconds
        self.headers = headers
    }
}

public struct CityTransitConfig: Codable, Sendable, Equatable, Hashable {
    public let agencyName: String
    public let attributions: [String]
    public let realtimeEndpoints: [RealtimeEndpoint]
    public let feedRouteMapping: [String: String]?
    public let scheduleValidity: ScheduleValidity?
    public let gbfs: GBFSConfig?
    
    public init(
        agencyName: String,
        attributions: [String] = [],
        realtimeEndpoints: [RealtimeEndpoint] = [],
        feedRouteMapping: [String: String]? = nil,
        scheduleValidity: ScheduleValidity? = nil,
        gbfs: GBFSConfig? = nil
    ) {
        self.agencyName = agencyName
        self.attributions = attributions
        self.realtimeEndpoints = realtimeEndpoints
        self.feedRouteMapping = feedRouteMapping
        self.scheduleValidity = scheduleValidity
        self.gbfs = gbfs
    }
}

// MARK: - City Config Root

public struct CityConfig: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String { slug }
    
    public let version: Int
    public let slug: String
    public let displayName: String
    public let region: String
    public let bounds: CityBounds
    public let center: CityCenter
    public let transit: CityTransitConfig?
    public let sha256: String?
    
    public init(
        version: Int = 1,
        slug: String,
        displayName: String,
        region: String,
        bounds: CityBounds,
        center: CityCenter,
        transit: CityTransitConfig? = nil,
        sha256: String? = nil
    ) {
        self.version = version
        self.slug = slug
        self.displayName = displayName
        self.region = region
        self.bounds = bounds
        self.center = center
        self.transit = transit
        self.sha256 = sha256
    }
    
    public static let nycDefault = CityConfig(
        version: 1,
        slug: "nyc",
        displayName: "New York City",
        region: "New York, USA",
        bounds: CityBounds(
            minLatitude: 40.0,
            maxLatitude: 41.5,
            minLongitude: -74.5,
            maxLongitude: -73.0
        ),
        center: CityCenter(
            latitude: 40.7128,
            longitude: -74.0060,
            defaultZoom: 13.0
        ),
        transit: CityTransitConfig(
            agencyName: "Metropolitan Transportation Authority",
            attributions: [
                "MTA New York City Transit",
                "Port Authority of NY & NJ",
                "NYC Ferry by Hornblower",
                "Roosevelt Island Operating Corp"
            ],
            realtimeEndpoints: [
                RealtimeEndpoint(
                    feedId: "nyct_subway",
                    url: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
                    pollIntervalSeconds: 15
                )
            ],
            feedRouteMapping: nil,
            scheduleValidity: ScheduleValidity(
                startDate: "2026-06-01",
                endDate: "2026-09-01",
                seasonLabel: "Summer 2026 Timetable"
            ),
            gbfs: GBFSConfig(
                systemId: "citi_bike_nyc",
                stationInfoUrl: "https://gbfs.citibikenyc.com/gbfs/en/station_information.json",
                stationStatusUrl: "https://gbfs.citibikenyc.com/gbfs/en/station_status.json",
                pollIntervalSeconds: 30.0,
                stalenessThresholdSeconds: 600.0
            )
        ),
        sha256: nil
    )
    
    public static let bostonDefault = CityConfig(
        version: 1,
        slug: "bos",
        displayName: "Boston",
        region: "Massachusetts, USA",
        bounds: CityBounds(
            minLatitude: 42.20,
            maxLatitude: 42.50,
            minLongitude: -71.25,
            maxLongitude: -70.90
        ),
        center: CityCenter(
            latitude: 42.3601,
            longitude: -71.0589,
            defaultZoom: 13.0
        ),
        transit: CityTransitConfig(
            agencyName: "Massachusetts Bay Transportation Authority",
            attributions: [
                "MBTA Subway, Bus & Commuter Rail",
                "MassDOT Ferry Operations"
            ],
            gbfs: GBFSConfig(
                systemId: "bluebikes_boston",
                stationInfoUrl: "https://gbfs.bluebikes.com/gbfs/en/station_information.json",
                stationStatusUrl: "https://gbfs.bluebikes.com/gbfs/en/station_status.json",
                pollIntervalSeconds: 30.0,
                stalenessThresholdSeconds: 600.0
            )
        )
    )
    
    public static let chicagoDefault = CityConfig(
        version: 1,
        slug: "chi",
        displayName: "Chicago",
        region: "Illinois, USA",
        bounds: CityBounds(
            minLatitude: 41.60,
            maxLatitude: 42.15,
            minLongitude: -87.95,
            maxLongitude: -87.50
        ),
        center: CityCenter(
            latitude: 41.8781,
            longitude: -87.6298,
            defaultZoom: 13.0
        ),
        transit: CityTransitConfig(
            agencyName: "Chicago Transit Authority",
            attributions: [
                "CTA Subway 'L' & Bus",
                "Metra Commuter Rail"
            ],
            gbfs: GBFSConfig(
                systemId: "divvy_chicago",
                stationInfoUrl: "https://gbfs.divvybikes.com/gbfs/en/station_information.json",
                stationStatusUrl: "https://gbfs.divvybikes.com/gbfs/en/station_status.json",
                pollIntervalSeconds: 30.0,
                stalenessThresholdSeconds: 600.0
            )
        )
    )
}

// MARK: - Remote Manifest Models (`cities.json`)

public struct CityManifestEntry: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String { slug }
    
    public let slug: String
    public let displayName: String
    public let region: String
    public let compressedSizeBytes: Int64
    public let uncompressedSizeBytes: Int64
    public let isBundled: Bool
    public let version: String
    public let bounds: CityBounds?
    public let center: CityCenter?
    
    public init(
        slug: String,
        displayName: String,
        region: String,
        compressedSizeBytes: Int64,
        uncompressedSizeBytes: Int64,
        isBundled: Bool = false,
        version: String = "1.0.0",
        bounds: CityBounds? = nil,
        center: CityCenter? = nil
    ) {
        self.slug = slug
        self.displayName = displayName
        self.region = region
        self.compressedSizeBytes = compressedSizeBytes
        self.uncompressedSizeBytes = uncompressedSizeBytes
        self.isBundled = isBundled
        self.version = version
        self.bounds = bounds
        self.center = center
    }
    
    /// Returns human-readable compressed download size (e.g., "12.8 MB").
    public var formattedDownloadSize: String {
        CityManifest.formatBytes(compressedSizeBytes)
    }
    
    /// Returns human-readable uncompressed disk size (e.g., "28.5 MB").
    public var formattedUncompressedSize: String {
        CityManifest.formatBytes(uncompressedSizeBytes)
    }
}

public struct CityManifest: Codable, Sendable, Equatable {
    public let version: Int
    public let lastUpdated: String
    public let cities: [CityManifestEntry]
    
    public init(version: Int = 1, lastUpdated: String = "2026-08-24T00:00:00Z", cities: [CityManifestEntry] = []) {
        self.version = version
        self.lastUpdated = lastUpdated
        self.cities = cities
    }
    
    /// Finds a city entry matching the given slug.
    public func findCity(bySlug slug: String) -> CityManifestEntry? {
        cities.first { $0.slug == slug }
    }
    
    /// Finds the first city whose bounding box contains the coordinate.
    public func findCity(containing coordinate: CLLocationCoordinate2D) -> CityManifestEntry? {
        cities.first { entry in
            entry.bounds?.contains(coordinate: coordinate) ?? false
        }
    }
    
    /// Converts a byte count to a clean, human-readable string.
    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Default bundled static manifest used for fast offline operation and test environments.
    public static let defaultManifest = CityManifest(
        version: 1,
        lastUpdated: "2026-08-24T00:00:00Z",
        cities: [
            CityManifestEntry(
                slug: "nyc",
                displayName: "New York City",
                region: "New York, USA",
                compressedSizeBytes: 12_800_000,
                uncompressedSizeBytes: 28_500_000,
                isBundled: true,
                version: "1.1.0",
                bounds: CityConfig.nycDefault.bounds,
                center: CityConfig.nycDefault.center
            ),
            CityManifestEntry(
                slug: "bos",
                displayName: "Boston",
                region: "Massachusetts, USA",
                compressedSizeBytes: 9_400_000,
                uncompressedSizeBytes: 22_100_000,
                isBundled: false,
                version: "1.0.0",
                bounds: CityConfig.bostonDefault.bounds,
                center: CityConfig.bostonDefault.center
            ),
            CityManifestEntry(
                slug: "chi",
                displayName: "Chicago",
                region: "Illinois, USA",
                compressedSizeBytes: 11_200_000,
                uncompressedSizeBytes: 25_400_000,
                isBundled: false,
                version: "1.0.0",
                bounds: CityConfig.chicagoDefault.bounds,
                center: CityConfig.chicagoDefault.center
            )
        ]
    )
}

// MARK: - Disk Breakdown Descriptor

public struct CityPackDiskBreakdown: Sendable, Equatable, Hashable {
    public let transitDatabaseBytes: Int64
    public let neighborhoodDatabaseBytes: Int64
    public let transitLinesGeoJSONBytes: Int64
    public let configBytes: Int64
    public let otherBytes: Int64
    public let totalBytes: Int64
    
    public init(
        transitDatabaseBytes: Int64,
        neighborhoodDatabaseBytes: Int64 = 0,
        transitLinesGeoJSONBytes: Int64,
        configBytes: Int64,
        otherBytes: Int64 = 0,
        totalBytes: Int64? = nil
    ) {
        self.transitDatabaseBytes = transitDatabaseBytes
        self.neighborhoodDatabaseBytes = neighborhoodDatabaseBytes
        self.transitLinesGeoJSONBytes = transitLinesGeoJSONBytes
        self.configBytes = configBytes
        self.otherBytes = otherBytes
        self.totalBytes = totalBytes ?? (transitDatabaseBytes + neighborhoodDatabaseBytes + transitLinesGeoJSONBytes + configBytes + otherBytes)
    }
    
    public var formattedTotal: String { CityManifest.formatBytes(totalBytes) }
    public var formattedTransitDB: String { CityManifest.formatBytes(transitDatabaseBytes) }
    public var formattedNeighborhoodDB: String { CityManifest.formatBytes(neighborhoodDatabaseBytes) }
    public var formattedTransitLines: String { CityManifest.formatBytes(transitLinesGeoJSONBytes) }
    public var formattedConfig: String { CityManifest.formatBytes(configBytes) }
    public var formattedOther: String { CityManifest.formatBytes(otherBytes) }
}

extension CityManifestEntry {
    /// Compares this manifest entry's version against an installed version string.
    public func isNewerThan(installedVersion: String) -> Bool {
        return Self.compareVersionStrings(remote: version, installed: installedVersion) > 0
    }
    
    public static func compareVersionStrings(remote: String, installed: String) -> Int {
        let remoteClean = remote.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let installedClean = installed.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        
        let remoteParts = remoteClean.split(separator: ".").compactMap { Int($0) }
        let installedParts = installedClean.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(remoteParts.count, installedParts.count)
        for i in 0..<maxCount {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < installedParts.count ? installedParts[i] : 0
            if r > l { return 1 }
            if r < l { return -1 }
        }
        return 0
    }
}

// MARK: - Installed City Pack Descriptor

public struct InstalledCityPack: Sendable, Equatable, Identifiable {
    public var id: String { slug }
    
    public let slug: String
    public let config: CityConfig
    public let packDirectoryURL: URL
    public let transitDatabaseURL: URL
    public let neighborhoodDatabaseURL: URL?
    public let transitLinesGeoJSONURL: URL?
    public let totalDiskSizeBytes: Int64
    public let isBundled: Bool
    public let breakdown: CityPackDiskBreakdown
    
    public init(
        slug: String,
        config: CityConfig,
        packDirectoryURL: URL,
        transitDatabaseURL: URL,
        neighborhoodDatabaseURL: URL? = nil,
        transitLinesGeoJSONURL: URL?,
        totalDiskSizeBytes: Int64,
        isBundled: Bool,
        breakdown: CityPackDiskBreakdown? = nil
    ) {
        self.slug = slug
        self.config = config
        self.packDirectoryURL = packDirectoryURL
        self.transitDatabaseURL = transitDatabaseURL
        self.neighborhoodDatabaseURL = neighborhoodDatabaseURL
        self.transitLinesGeoJSONURL = transitLinesGeoJSONURL
        self.totalDiskSizeBytes = totalDiskSizeBytes
        self.isBundled = isBundled
        self.breakdown = breakdown ?? CityPackDiskBreakdown(
            transitDatabaseBytes: 0,
            neighborhoodDatabaseBytes: 0,
            transitLinesGeoJSONBytes: 0,
            configBytes: 0,
            otherBytes: 0,
            totalBytes: totalDiskSizeBytes
        )
    }
}

// MARK: - Errors

public enum CityPackError: Error, LocalizedError, Sendable, Equatable {
    case packNotFound(slug: String)
    case invalidArchive(reason: String)
    case integrityCheckFailed(expected: String, actual: String)
    case missingRequiredFile(name: String)
    case coreMetroDeletionBlocked
    case decompressionFailed(reason: String)
    case downloadFailed(reason: String)
    case manifestFetchFailed(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .packNotFound(let slug):
            return "City pack for '\(slug)' was not found on disk."
        case .invalidArchive(let reason):
            return "Invalid city pack archive: \(reason)"
        case .integrityCheckFailed(let expected, let actual):
            return "Archive integrity verification failed. Expected SHA-256 \(expected), got \(actual)."
        case .missingRequiredFile(let name):
            return "City pack is missing required file: '\(name)'."
        case .coreMetroDeletionBlocked:
            return "Core metropolitan pack 'nyc' cannot be deleted."
        case .decompressionFailed(let reason):
            return "Zstandard decompression failed: \(reason)"
        case .downloadFailed(let reason):
            return "Failed to download city pack: \(reason)"
        case .manifestFetchFailed(let reason):
            return "Failed to fetch city manifest: \(reason)"
        }
    }
}
