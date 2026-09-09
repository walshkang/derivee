import Foundation
import CoreLocation

// MARK: - Search Mode Filter

/// Quick-access mode filters for Screen 4A search (Wave PA.4 / design.md §12.2)
public enum SearchModeFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case subway = "Subway"
    case buses = "Buses"
    case rail = "Rail"
    case saved = "Saved"
    
    public var id: String { rawValue }
    
    public var displayName: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "sparkles"
        case .subway: return "tram.fill"
        case .buses: return "bus.fill"
        case .rail: return "train.side.front.car"
        case .saved: return "bookmark.fill"
        }
    }
    
    public func matches(modalClass: TransitModalClass?) -> Bool {
        switch self {
        case .all, .saved:
            return true
        case .subway:
            return modalClass == .subway
        case .buses:
            return modalClass == .bus
        case .rail:
            return modalClass == .lightRail || modalClass == .subway // Heavy/commuter rail mapped under rail
        }
    }
}

// MARK: - Search Result Category

public enum SearchResultCategory: Sendable, Equatable, Hashable {
    case station(stopId: String, modalClass: TransitModalClass)
    case route(routeId: String, modalClass: TransitModalClass, colorHex: String?)
    case landmark(landmarkId: String)
    case recent(RecentSearchDestination)
    case custom(coordinate: CLLocationCoordinate2D)
    
    public static func == (lhs: SearchResultCategory, rhs: SearchResultCategory) -> Bool {
        switch (lhs, rhs) {
        case (.station(let s1, let m1), .station(let s2, let m2)):
            return s1 == s2 && m1 == m2
        case (.route(let r1, let m1, let c1), .route(let r2, let m2, let c2)):
            return r1 == r2 && m1 == m2 && c1 == c2
        case (.landmark(let l1), .landmark(let l2)):
            return l1 == l2
        case (.recent(let r1), .recent(let r2)):
            return r1 == r2
        case (.custom(let c1), .custom(let c2)):
            return c1.latitude == c2.latitude && c1.longitude == c2.longitude
        default:
            return false
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .station(let stopId, let modalClass):
            hasher.combine("station")
            hasher.combine(stopId)
            hasher.combine(modalClass)
        case .route(let routeId, let modalClass, let colorHex):
            hasher.combine("route")
            hasher.combine(routeId)
            hasher.combine(modalClass)
            hasher.combine(colorHex)
        case .landmark(let landmarkId):
            hasher.combine("landmark")
            hasher.combine(landmarkId)
        case .recent(let recent):
            hasher.combine("recent")
            hasher.combine(recent.id)
        case .custom(let coord):
            hasher.combine("custom")
            hasher.combine(coord.latitude)
            hasher.combine(coord.longitude)
        }
    }
}

// MARK: - Search Result Item

public struct SearchResultItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: SearchResultCategory
    public let coordinate: CLLocationCoordinate2D?
    public let modalClass: TransitModalClass?
    public let routes: [String]
    public let badgeColorHex: String?
    public var isSaved: Bool
    
    public init(
        id: String,
        title: String,
        subtitle: String,
        category: SearchResultCategory,
        coordinate: CLLocationCoordinate2D? = nil,
        modalClass: TransitModalClass? = nil,
        routes: [String] = [],
        badgeColorHex: String? = nil,
        isSaved: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.coordinate = coordinate
        self.modalClass = modalClass
        self.routes = routes
        self.badgeColorHex = badgeColorHex
        self.isSaved = isSaved
    }
    
    public static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.category == rhs.category &&
        lhs.coordinate?.latitude == rhs.coordinate?.latitude &&
        lhs.coordinate?.longitude == rhs.coordinate?.longitude &&
        lhs.modalClass == rhs.modalClass &&
        lhs.routes == rhs.routes &&
        lhs.badgeColorHex == rhs.badgeColorHex &&
        lhs.isSaved == rhs.isSaved
    }
    
    /// Maps the search result item to a `RoutingLocation` endpoint for journey planning.
    public var routingLocation: RoutingLocation? {
        switch category {
        case .station(let stopId, _):
            if let coord = coordinate {
                return .coordinate(latitude: coord.latitude, longitude: coord.longitude, name: title)
            } else if let numId = UInt32(stopId) {
                return .stop(stopId: numId, name: title)
            } else {
                return nil
            }
        case .landmark, .custom:
            if let coord = coordinate {
                return .coordinate(latitude: coord.latitude, longitude: coord.longitude, name: title)
            }
            return nil
        case .route:
            if let coord = coordinate {
                return .coordinate(latitude: coord.latitude, longitude: coord.longitude, name: title)
            }
            return nil
        case .recent(let recent):
            return recent.routingLocation
        }
    }
}

// MARK: - Recent Search Destination

public struct RecentSearchDestination: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: String // "station", "route", "landmark", "coordinate"
    public let stopId: String?
    public let routeId: String?
    public let latitude: Double?
    public let longitude: Double?
    public let modalClassRaw: Int?
    public let routes: [String]?
    public let badgeColorHex: String?
    public let timestamp: Date
    
    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: String,
        stopId: String? = nil,
        routeId: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        modalClassRaw: Int? = nil,
        routes: [String]? = nil,
        badgeColorHex: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.stopId = stopId
        self.routeId = routeId
        self.latitude = latitude
        self.longitude = longitude
        self.modalClassRaw = modalClassRaw
        self.routes = routes
        self.badgeColorHex = badgeColorHex
        self.timestamp = timestamp
    }
    
    public init(item: SearchResultItem, timestamp: Date = Date()) {
        self.id = item.id
        self.title = item.title
        self.subtitle = item.subtitle
        self.latitude = item.coordinate?.latitude
        self.longitude = item.coordinate?.longitude
        self.modalClassRaw = item.modalClass?.rawValue
        self.routes = item.routes
        self.badgeColorHex = item.badgeColorHex
        self.timestamp = timestamp
        
        switch item.category {
        case .station(let stopId, _):
            self.kind = "station"
            self.stopId = stopId
            self.routeId = nil
        case .route(let routeId, _, _):
            self.kind = "route"
            self.stopId = nil
            self.routeId = routeId
        case .landmark:
            self.kind = "landmark"
            self.stopId = nil
            self.routeId = nil
        case .custom:
            self.kind = "coordinate"
            self.stopId = nil
            self.routeId = nil
        case .recent(let inner):
            self.kind = inner.kind
            self.stopId = inner.stopId
            self.routeId = inner.routeId
        }
    }
    
    public var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    public var modalClass: TransitModalClass? {
        guard let raw = modalClassRaw else { return nil }
        return TransitModalClass(rawValue: raw)
    }
    
    public var routingLocation: RoutingLocation? {
        if let lat = latitude, let lon = longitude {
            return .coordinate(latitude: lat, longitude: lon, name: title)
        }
        if let stopId = stopId, let num = UInt32(stopId) {
            return .stop(stopId: num, name: title)
        }
        return nil
    }
    
    public func toSearchResultItem(isSaved: Bool = false) -> SearchResultItem {
        let cat: SearchResultCategory
        if kind == "station", let sId = stopId {
            cat = .station(stopId: sId, modalClass: modalClass ?? .subway)
        } else if kind == "route", let rId = routeId {
            cat = .route(routeId: rId, modalClass: modalClass ?? .subway, colorHex: badgeColorHex)
        } else if kind == "landmark" {
            cat = .landmark(landmarkId: id)
        } else if let coord = coordinate {
            cat = .custom(coordinate: coord)
        } else {
            cat = .recent(self)
        }
        
        return SearchResultItem(
            id: id,
            title: title,
            subtitle: subtitle,
            category: cat,
            coordinate: coordinate,
            modalClass: modalClass,
            routes: routes ?? [],
            badgeColorHex: badgeColorHex,
            isSaved: isSaved
        )
    }
}
