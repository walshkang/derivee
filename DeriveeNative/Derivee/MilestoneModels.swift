import Foundation
import CoreLocation

// MARK: - Milestone Categories

public enum MilestoneCategory: String, CaseIterable, Identifiable, Sendable {
    case transitHubs = "transit_hubs"
    case neighborhoodVoyager = "neighborhood_voyager"
    case historicLandmarks = "historic_landmarks"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .transitHubs:
            return "Transit Hubs"
        case .neighborhoodVoyager:
            return "Neighborhood Voyager"
        case .historicLandmarks:
            return "Historic Landmarks"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .transitHubs:
            return "tram.fill"
        case .neighborhoodVoyager:
            return "map.fill"
        case .historicLandmarks:
            return "building.columns.fill"
        }
    }
    
    public var description: String {
        switch self {
        case .transitHubs:
            return "Subway & commuter rail stations connected to the grid"
        case .neighborhoodVoyager:
            return "Exploration footprint across NYC boroughs"
        case .historicLandmarks:
            return "Curated architectural and cultural anchors discovered"
        }
    }
}

// MARK: - Milestone Tier

public struct MilestoneTier: Identifiable, Sendable, Equatable {
    public var id: String { "\(category.rawValue)_tier_\(tierNumber)" }
    public let category: MilestoneCategory
    public let tierNumber: Int
    public let title: String
    public let requirementDescription: String
    public let targetCount: Int
    public let badgeIconName: String
    public let isUnlocked: Bool
    
    public init(
        category: MilestoneCategory,
        tierNumber: Int,
        title: String,
        requirementDescription: String,
        targetCount: Int,
        badgeIconName: String,
        isUnlocked: Bool
    ) {
        self.category = category
        self.tierNumber = tierNumber
        self.title = title
        self.requirementDescription = requirementDescription
        self.targetCount = targetCount
        self.badgeIconName = badgeIconName
        self.isUnlocked = isUnlocked
    }
}

// MARK: - Milestone Progress

public struct MilestoneProgress: Identifiable, Sendable {
    public var id: String { category.rawValue }
    public let category: MilestoneCategory
    public let currentCount: Int
    public let totalCount: Int
    public let tiers: [MilestoneTier]
    
    public var percentage: Double {
        guard totalCount > 0 else { return 0 }
        return min(100.0, (Double(currentCount) / Double(totalCount)) * 100.0)
    }
    
    public var unlockedTierCount: Int {
        tiers.filter { $0.isUnlocked }.count
    }
    
    public var currentTier: MilestoneTier? {
        tiers.last(where: { $0.isUnlocked })
    }
    
    public var nextTier: MilestoneTier? {
        tiers.first(where: { !$0.isUnlocked })
    }
    
    public init(
        category: MilestoneCategory,
        currentCount: Int,
        totalCount: Int,
        tiers: [MilestoneTier]
    ) {
        self.category = category
        self.currentCount = currentCount
        self.totalCount = totalCount
        self.tiers = tiers
    }
}

// MARK: - Borough Progress

public struct BoroughProgress: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let clearedHexes: Int
    public let totalHexes: Int
    public let neighborhoodCount: Int
    public let exploredNeighborhoodCount: Int
    
    public var percentage: Double {
        guard totalHexes > 0 else { return 0 }
        return (Double(clearedHexes) / Double(totalHexes)) * 100.0
    }
    
    public init(
        id: String,
        name: String,
        clearedHexes: Int,
        totalHexes: Int,
        neighborhoodCount: Int,
        exploredNeighborhoodCount: Int
    ) {
        self.id = id
        self.name = name
        self.clearedHexes = clearedHexes
        self.totalHexes = totalHexes
        self.neighborhoodCount = neighborhoodCount
        self.exploredNeighborhoodCount = exploredNeighborhoodCount
    }
}

// MARK: - Landmark Discovery

public struct LandmarkDiscovery: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let borough: String
    public let category: String
    public let landmarkDescription: String
    public let h3Index: String
    public let coordinate: CLLocationCoordinate2D
    public let isDiscovered: Bool
    
    public init(
        id: String,
        name: String,
        borough: String,
        category: String,
        landmarkDescription: String,
        h3Index: String,
        coordinate: CLLocationCoordinate2D,
        isDiscovered: Bool
    ) {
        self.id = id
        self.name = name
        self.borough = borough
        self.category = category
        self.landmarkDescription = landmarkDescription
        self.h3Index = h3Index
        self.coordinate = coordinate
        self.isDiscovered = isDiscovered
    }
}

// MARK: - Exploration Journal Data Aggregate

public struct ExplorationJournalData: Sendable {
    public let totalClearedHexes: Int
    public let totalCityHexes: Int
    public let cityPercentage: Double
    public let milestoneCards: [MilestoneProgress]
    public let boroughProgress: [BoroughProgress]
    public let landmarks: [LandmarkDiscovery]
    
    public init(
        totalClearedHexes: Int,
        totalCityHexes: Int,
        cityPercentage: Double,
        milestoneCards: [MilestoneProgress],
        boroughProgress: [BoroughProgress],
        landmarks: [LandmarkDiscovery]
    ) {
        self.totalClearedHexes = totalClearedHexes
        self.totalCityHexes = totalCityHexes
        self.cityPercentage = cityPercentage
        self.milestoneCards = milestoneCards
        self.boroughProgress = boroughProgress
        self.landmarks = landmarks
    }
}
