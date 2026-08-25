import Foundation
import CoreLocation

// MARK: - Stats Browsing Mode

public enum StatsBrowsingMode: Equatable, Hashable, Sendable {
    case city(slug: String)
    case allMetros
    
    public var slug: String? {
        switch self {
        case .city(let s): return s
        case .allMetros: return nil
        }
    }
    
    public var isAllMetros: Bool {
        switch self {
        case .allMetros: return true
        case .city: return false
        }
    }
}

// MARK: - City Overview Progress (Per-City Summary in All Metros Mode)

public struct CityOverviewProgress: Identifiable, Sendable, Equatable {
    public var id: String { slug }
    public let slug: String
    public let displayName: String
    public let region: String
    public let clearedHexes: Int
    public let totalHexes: Int
    public let isInstalled: Bool
    public let centerCoordinate: CLLocationCoordinate2D
    public let bounds: CityBounds?
    
    public var percentage: Double {
        guard totalHexes > 0 else { return 0 }
        return min(100.0, (Double(clearedHexes) / Double(totalHexes)) * 100.0)
    }
    
    public var formattedPercentage: String {
        if percentage == 0.0 {
            return "0.0%"
        } else if percentage < 0.01 {
            return "< 0.01%"
        } else if percentage < 0.1 {
            return String(format: "%.2f%%", percentage)
        } else {
            return String(format: "%.1f%%", percentage)
        }
    }
    
    public init(
        slug: String,
        displayName: String,
        region: String,
        clearedHexes: Int,
        totalHexes: Int,
        isInstalled: Bool,
        centerCoordinate: CLLocationCoordinate2D,
        bounds: CityBounds? = nil
    ) {
        self.slug = slug
        self.displayName = displayName
        self.region = region
        self.clearedHexes = clearedHexes
        self.totalHexes = totalHexes
        self.isInstalled = isInstalled
        self.centerCoordinate = centerCoordinate
        self.bounds = bounds
    }
    
    public static func == (lhs: CityOverviewProgress, rhs: CityOverviewProgress) -> Bool {
        return lhs.slug == rhs.slug &&
               lhs.displayName == rhs.displayName &&
               lhs.region == rhs.region &&
               lhs.clearedHexes == rhs.clearedHexes &&
               lhs.totalHexes == rhs.totalHexes &&
               lhs.isInstalled == rhs.isInstalled &&
               lhs.centerCoordinate.latitude == rhs.centerCoordinate.latitude &&
               lhs.centerCoordinate.longitude == rhs.centerCoordinate.longitude &&
               lhs.bounds == rhs.bounds
    }
}

// MARK: - All Metros Summary Aggregate Data

public struct AllMetrosSummaryData: Sendable, Equatable {
    public let totalGlobalClearedHexes: Int
    public let totalGlobalHexes: Int
    public let totalDriftDistanceKm: Double
    public let citiesExploredCount: Int
    public let totalCitiesCount: Int
    public let cityOverviews: [CityOverviewProgress]
    
    public var globalPercentage: Double {
        guard totalGlobalHexes > 0 else { return 0 }
        return min(100.0, (Double(totalGlobalClearedHexes) / Double(totalGlobalHexes)) * 100.0)
    }
    
    public var formattedGlobalPercentage: String {
        if globalPercentage == 0.0 {
            return "0.0%"
        } else if globalPercentage < 0.01 {
            return "< 0.01%"
        } else if globalPercentage < 0.1 {
            return String(format: "%.2f%%", globalPercentage)
        } else {
            return String(format: "%.1f%%", globalPercentage)
        }
    }
    
    public var formattedDriftDistance: String {
        if totalDriftDistanceKm < 10.0 {
            return String(format: "%.1f km", totalDriftDistanceKm)
        } else {
            return "\(Int(round(totalDriftDistanceKm))) km"
        }
    }
    
    public init(
        totalGlobalClearedHexes: Int,
        totalGlobalHexes: Int,
        totalDriftDistanceKm: Double,
        citiesExploredCount: Int,
        totalCitiesCount: Int,
        cityOverviews: [CityOverviewProgress]
    ) {
        self.totalGlobalClearedHexes = totalGlobalClearedHexes
        self.totalGlobalHexes = totalGlobalHexes
        self.totalDriftDistanceKm = totalDriftDistanceKm
        self.citiesExploredCount = citiesExploredCount
        self.totalCitiesCount = totalCitiesCount
        self.cityOverviews = cityOverviews
    }
}

// MARK: - Multi-City GPX Import Result

public struct MultiCityImportResult: Sendable, Equatable {
    public let totalHexesImported: Int
    public let cityHexCounts: [String: Int] // slug -> count
    
    public var citiesCount: Int {
        cityHexCounts.filter { $0.value > 0 }.count
    }
    
    public init(totalHexesImported: Int, cityHexCounts: [String: Int]) {
        self.totalHexesImported = totalHexesImported
        self.cityHexCounts = cityHexCounts
    }
}
