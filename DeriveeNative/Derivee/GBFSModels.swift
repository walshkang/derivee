import Foundation
import CoreLocation

// MARK: - GBFS Feed Response DTOs (GBFS v2.3 / v3.0 Specification)

public struct GBFSStationInfoResponse: Decodable, Sendable {
    public let lastUpdated: Int?
    public let ttl: Int?
    public let data: GBFSStationInfoData
    
    enum CodingKeys: String, CodingKey {
        case lastUpdated = "last_updated"
        case ttl
        case data
    }
    
    public init(lastUpdated: Int? = nil, ttl: Int? = nil, data: GBFSStationInfoData) {
        self.lastUpdated = lastUpdated
        self.ttl = ttl
        self.data = data
    }
}

public struct GBFSStationInfoData: Decodable, Sendable {
    public let stations: [GBFSStationInfoRecord]
    
    public init(stations: [GBFSStationInfoRecord]) {
        self.stations = stations
    }
}

public struct GBFSStationInfoRecord: Decodable, Sendable, Equatable {
    public let stationId: String
    public let name: String
    public let lat: Double
    public let lon: Double
    public let capacity: Int
    public let regionId: String?
    public let hasKiosk: Bool
    
    enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
        case name
        case lat
        case lon
        case capacity
        case regionId = "region_id"
        case hasKiosk = "has_kiosk"
    }
    
    public init(
        stationId: String,
        name: String,
        lat: Double,
        lon: Double,
        capacity: Int = 0,
        regionId: String? = nil,
        hasKiosk: Bool = false
    ) {
        self.stationId = stationId
        self.name = name
        self.lat = lat
        self.lon = lon
        self.capacity = capacity
        self.regionId = regionId
        self.hasKiosk = hasKiosk
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stationId = try container.decode(String.self, forKey: .stationId)
        name = try container.decode(String.self, forKey: .name)
        lat = try container.decode(Double.self, forKey: .lat)
        lon = try container.decode(Double.self, forKey: .lon)
        capacity = (try? container.decode(Int.self, forKey: .capacity)) ?? 0
        regionId = try? container.decode(String.self, forKey: .regionId)
        
        if let boolVal = try? container.decode(Bool.self, forKey: .hasKiosk) {
            hasKiosk = boolVal
        } else if let intVal = try? container.decode(Int.self, forKey: .hasKiosk) {
            hasKiosk = (intVal != 0)
        } else {
            hasKiosk = false
        }
    }
}

public struct GBFSStationStatusResponse: Decodable, Sendable {
    public let lastUpdated: Int?
    public let ttl: Int?
    public let data: GBFSStationStatusData
    
    enum CodingKeys: String, CodingKey {
        case lastUpdated = "last_updated"
        case ttl
        case data
    }
    
    public init(lastUpdated: Int? = nil, ttl: Int? = nil, data: GBFSStationStatusData) {
        self.lastUpdated = lastUpdated
        self.ttl = ttl
        self.data = data
    }
}

public struct GBFSStationStatusData: Decodable, Sendable {
    public let stations: [GBFSStationStatusRecord]
    
    public init(stations: [GBFSStationStatusRecord]) {
        self.stations = stations
    }
}

public struct GBFSVehicleTypeAvailable: Decodable, Sendable, Equatable {
    public let vehicleTypeId: String
    public let count: Int
    
    enum CodingKeys: String, CodingKey {
        case vehicleTypeId = "vehicle_type_id"
        case count
    }
    
    public init(vehicleTypeId: String, count: Int) {
        self.vehicleTypeId = vehicleTypeId
        self.count = count
    }
}

public struct GBFSStationStatusRecord: Decodable, Sendable, Equatable {
    public let stationId: String
    public let numBikesAvailable: Int
    public let numEbikesAvailable: Int
    public let numDocksAvailable: Int
    public let isInstalled: Bool
    public let isRenting: Bool
    public let isReturning: Bool
    public let lastReported: Int
    
    enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
        case numBikesAvailable = "num_bikes_available"
        case numEbikesAvailable = "num_ebikes_available"
        case numDocksAvailable = "num_docks_available"
        case isInstalled = "is_installed"
        case isRenting = "is_renting"
        case isReturning = "is_returning"
        case lastReported = "last_reported"
        case vehicleTypesAvailable = "vehicle_types_available"
    }
    
    public init(
        stationId: String,
        numBikesAvailable: Int,
        numEbikesAvailable: Int = 0,
        numDocksAvailable: Int = 0,
        isInstalled: Bool = true,
        isRenting: Bool = true,
        isReturning: Bool = true,
        lastReported: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.stationId = stationId
        self.numBikesAvailable = numBikesAvailable
        self.numEbikesAvailable = numEbikesAvailable
        self.numDocksAvailable = numDocksAvailable
        self.isInstalled = isInstalled
        self.isRenting = isRenting
        self.isReturning = isReturning
        self.lastReported = lastReported
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stationId = try container.decode(String.self, forKey: .stationId)
        numBikesAvailable = (try? container.decode(Int.self, forKey: .numBikesAvailable)) ?? 0
        numDocksAvailable = (try? container.decode(Int.self, forKey: .numDocksAvailable)) ?? 0
        
        // Decode numEbikesAvailable directly or infer from vehicle_types_available
        if let ebikes = try? container.decode(Int.self, forKey: .numEbikesAvailable) {
            numEbikesAvailable = ebikes
        } else if let vTypes = try? container.decode([GBFSVehicleTypeAvailable].self, forKey: .vehicleTypesAvailable) {
            // Check for electric/ebike vehicle type identifiers
            numEbikesAvailable = vTypes
                .filter { $0.vehicleTypeId.localizedCaseInsensitiveContains("ebike") || $0.vehicleTypeId.localizedCaseInsensitiveContains("electric") }
                .reduce(0) { $0 + $1.count }
        } else {
            numEbikesAvailable = 0
        }
        
        isInstalled = Self.decodeFlexibleBool(from: container, key: .isInstalled, defaultValue: true)
        isRenting = Self.decodeFlexibleBool(from: container, key: .isRenting, defaultValue: true)
        isReturning = Self.decodeFlexibleBool(from: container, key: .isReturning, defaultValue: true)
        
        lastReported = (try? container.decode(Int.self, forKey: .lastReported)) ?? Int(Date().timeIntervalSince1970)
    }
    
    private static func decodeFlexibleBool(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys, defaultValue: Bool) -> Bool {
        if let boolVal = try? container.decode(Bool.self, forKey: key) {
            return boolVal
        }
        if let intVal = try? container.decode(Int.self, forKey: key) {
            return intVal != 0
        }
        return defaultValue
    }
}

// MARK: - Domain & Query Models

public enum GBFSVehiclePreference: String, Codable, Sendable, Equatable, Hashable {
    case anyBike
    case standardOnly
    case electricOnly
}

public struct GBFSStation: Identifiable, Sendable, Equatable, Hashable {
    public var id: String { stationId }
    
    public let stationId: String
    public let systemId: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let capacity: Int
    public let regionId: String?
    public let hasKiosk: Bool
    
    public let numBikesAvailable: Int
    public let numEbikesAvailable: Int
    public let numDocksAvailable: Int
    public let isInstalled: Bool
    public let isRenting: Bool
    public let isReturning: Bool
    public let lastReported: Int
    
    public let distanceMeters: Double?
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public var numStandardBikesAvailable: Int {
        max(0, numBikesAvailable - numEbikesAvailable)
    }
    
    public init(
        stationId: String,
        systemId: String,
        name: String,
        latitude: Double,
        longitude: Double,
        capacity: Int = 0,
        regionId: String? = nil,
        hasKiosk: Bool = false,
        numBikesAvailable: Int = 0,
        numEbikesAvailable: Int = 0,
        numDocksAvailable: Int = 0,
        isInstalled: Bool = true,
        isRenting: Bool = true,
        isReturning: Bool = true,
        lastReported: Int = Int(Date().timeIntervalSince1970),
        distanceMeters: Double? = nil
    ) {
        self.stationId = stationId
        self.systemId = systemId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.capacity = capacity
        self.regionId = regionId
        self.hasKiosk = hasKiosk
        self.numBikesAvailable = numBikesAvailable
        self.numEbikesAvailable = numEbikesAvailable
        self.numDocksAvailable = numDocksAvailable
        self.isInstalled = isInstalled
        self.isRenting = isRenting
        self.isReturning = isReturning
        self.lastReported = lastReported
        self.distanceMeters = distanceMeters
    }
}

// MARK: - Gating Evaluation Result

public struct GBFSDockGatingResult: Sendable, Equatable {
    public enum GatingType: String, Sendable {
        case origin
        case destination
        case composite
    }
    
    public enum RejectionReason: String, Sendable, Equatable {
        case stationNotFound
        case notInstalled
        case notRenting
        case notReturning
        case insufficientBikes
        case insufficientEbikes
        case insufficientDocks
        case dataStale
    }
    
    public struct GatingMetrics: Sendable, Equatable {
        public let availableBikes: Int
        public let availableEbikes: Int
        public let availableDocks: Int
        public let isInstalled: Bool
        public let isRenting: Bool
        public let isReturning: Bool
        public let stalenessSeconds: Int
        
        public init(
            availableBikes: Int = 0,
            availableEbikes: Int = 0,
            availableDocks: Int = 0,
            isInstalled: Bool = false,
            isRenting: Bool = false,
            isReturning: Bool = false,
            stalenessSeconds: Int = 0
        ) {
            self.availableBikes = availableBikes
            self.availableEbikes = availableEbikes
            self.availableDocks = availableDocks
            self.isInstalled = isInstalled
            self.isRenting = isRenting
            self.isReturning = isReturning
            self.stalenessSeconds = stalenessSeconds
        }
    }
    
    public let isValid: Bool
    public let stationId: String
    public let gatingType: GatingType
    public let rejectionReasons: [RejectionReason]
    public let metrics: GatingMetrics
    public let fallbackStation: GBFSStation?
    
    public init(
        isValid: Bool,
        stationId: String,
        gatingType: GatingType,
        rejectionReasons: [RejectionReason] = [],
        metrics: GatingMetrics = GatingMetrics(),
        fallbackStation: GBFSStation? = nil
    ) {
        self.isValid = isValid
        self.stationId = stationId
        self.gatingType = gatingType
        self.rejectionReasons = rejectionReasons
        self.metrics = metrics
        self.fallbackStation = fallbackStation
    }
}
