import Foundation
import CoreLocation

/// Category of high-permanence commercial brands with street-level visual prominence.
public enum CommercialBrandType: String, Sendable, Codable, Equatable, Hashable {
    case coffee = "coffee"
    case pharmacy = "pharmacy"
    case grocery = "grocery"
    case bank = "bank"
    case retail = "retail"
    
    public var iconName: String {
        switch self {
        case .coffee: return "cup.and.saucer.fill"
        case .pharmacy: return "cross.case.fill"
        case .grocery: return "cart.fill"
        case .bank: return "banknote.fill"
        case .retail: return "bag.fill"
        }
    }
}

/// A verified, high-permanence commercial brand anchor situated at a street intersection.
public struct SalientCommercialAnchor: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let brandType: CommercialBrandType
    public let coordinate: CLLocationCoordinate2D
    public let primaryStreet: String
    public let crossStreet: String?
    public let usesDefiniteArticle: Bool
    
    public init(
        id: String,
        name: String,
        brandType: CommercialBrandType,
        coordinate: CLLocationCoordinate2D,
        primaryStreet: String,
        crossStreet: String? = nil,
        usesDefiniteArticle: Bool = true
    ) {
        self.id = id
        self.name = name
        self.brandType = brandType
        self.coordinate = coordinate
        self.primaryStreet = primaryStreet
        self.crossStreet = crossStreet
        self.usesDefiniteArticle = usesDefiniteArticle
    }
    
    public static func == (lhs: SalientCommercialAnchor, rhs: SalientCommercialAnchor) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    /// Formats the brand name with or without the definite article.
    /// e.g. "the Starbucks", "Whole Foods Market", "the Duane Reade"
    public var articulatedName: String {
        usesDefiniteArticle ? "the \(name)" : name
    }
}

/// Curated registry of verified commercial anchors across dense urban walking corridors.
public enum SalientCommercialAnchorCatalog {
    public static let anchors: [SalientCommercialAnchor] = [
        // Midtown 42nd St Corridor
        SalientCommercialAnchor(
            id: "biz_sbux_42_5th",
            name: "Starbucks",
            brandType: .coffee,
            coordinate: CLLocationCoordinate2D(latitude: 40.7538, longitude: -73.9806),
            primaryStreet: "42nd St",
            crossStreet: "5th Ave",
            usesDefiniteArticle: true
        ),
        SalientCommercialAnchor(
            id: "biz_wholefoods_bryant_park",
            name: "Whole Foods Market",
            brandType: .grocery,
            coordinate: CLLocationCoordinate2D(latitude: 40.7539, longitude: -73.9842),
            primaryStreet: "42nd St",
            crossStreet: "6th Ave",
            usesDefiniteArticle: false
        ),
        SalientCommercialAnchor(
            id: "biz_duanereade_42_lex",
            name: "Duane Reade",
            brandType: .pharmacy,
            coordinate: CLLocationCoordinate2D(latitude: 40.7516, longitude: -73.9754),
            primaryStreet: "42nd St",
            crossStreet: "Lexington Ave",
            usesDefiniteArticle: true
        ),
        SalientCommercialAnchor(
            id: "biz_chase_42_madison",
            name: "Chase Bank",
            brandType: .bank,
            coordinate: CLLocationCoordinate2D(latitude: 40.7531, longitude: -73.9790),
            primaryStreet: "42nd St",
            crossStreet: "Madison Ave",
            usesDefiniteArticle: false
        ),
        SalientCommercialAnchor(
            id: "biz_sbux_42_8th",
            name: "Starbucks",
            brandType: .coffee,
            coordinate: CLLocationCoordinate2D(latitude: 40.7570, longitude: -73.9895),
            primaryStreet: "42nd St",
            crossStreet: "8th Ave",
            usesDefiniteArticle: true
        ),
        SalientCommercialAnchor(
            id: "biz_cvs_42_10th",
            name: "CVS Pharmacy",
            brandType: .pharmacy,
            coordinate: CLLocationCoordinate2D(latitude: 40.7594, longitude: -73.9961),
            primaryStreet: "42nd St",
            crossStreet: "10th Ave",
            usesDefiniteArticle: true
        ),
        
        // Broadway & Times Square Corridor
        SalientCommercialAnchor(
            id: "biz_sbux_times_square",
            name: "Starbucks",
            brandType: .coffee,
            coordinate: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
            primaryStreet: "Broadway",
            crossStreet: "47th St",
            usesDefiniteArticle: true
        ),
        SalientCommercialAnchor(
            id: "biz_duanereade_times_square",
            name: "Duane Reade",
            brandType: .pharmacy,
            coordinate: CLLocationCoordinate2D(latitude: 40.7565, longitude: -73.9868),
            primaryStreet: "Broadway",
            crossStreet: "44th St",
            usesDefiniteArticle: true
        ),
        SalientCommercialAnchor(
            id: "biz_bluebottle_bryant",
            name: "Blue Bottle Coffee",
            brandType: .coffee,
            coordinate: CLLocationCoordinate2D(latitude: 40.7523, longitude: -73.9836),
            primaryStreet: "40th St",
            crossStreet: "6th Ave",
            usesDefiniteArticle: false
        ),
        
        // 34th St & Herald Square Corridor
        SalientCommercialAnchor(
            id: "biz_target_herald_sq",
            name: "Target",
            brandType: .retail,
            coordinate: CLLocationCoordinate2D(latitude: 40.7498, longitude: -73.9880),
            primaryStreet: "34th St",
            crossStreet: "6th Ave",
            usesDefiniteArticle: false
        ),
        SalientCommercialAnchor(
            id: "biz_duanereade_penn_station",
            name: "Duane Reade",
            brandType: .pharmacy,
            coordinate: CLLocationCoordinate2D(latitude: 40.7505, longitude: -73.9912),
            primaryStreet: "34th St",
            crossStreet: "7th Ave",
            usesDefiniteArticle: true
        ),
        SalientCommercialAnchor(
            id: "biz_sbux_34_madison",
            name: "Starbucks",
            brandType: .coffee,
            coordinate: CLLocationCoordinate2D(latitude: 40.7478, longitude: -73.9832),
            primaryStreet: "34th St",
            crossStreet: "Madison Ave",
            usesDefiniteArticle: true
        ),
        
        // 5th Ave Flagship Corridor
        SalientCommercialAnchor(
            id: "biz_apple_fifth_ave",
            name: "Apple Store",
            brandType: .retail,
            coordinate: CLLocationCoordinate2D(latitude: 40.7638, longitude: -73.9729),
            primaryStreet: "5th Ave",
            crossStreet: "59th St",
            usesDefiniteArticle: true
        ),
        SalientCommercialAnchor(
            id: "biz_barnes_noble_5th",
            name: "Barnes & Noble",
            brandType: .retail,
            coordinate: CLLocationCoordinate2D(latitude: 40.7562, longitude: -73.9774),
            primaryStreet: "5th Ave",
            crossStreet: "46th St",
            usesDefiniteArticle: false
        ),
        SalientCommercialAnchor(
            id: "biz_chase_5th_44th",
            name: "Chase Bank",
            brandType: .bank,
            coordinate: CLLocationCoordinate2D(latitude: 40.7547, longitude: -73.9796),
            primaryStreet: "5th Ave",
            crossStreet: "44th St",
            usesDefiniteArticle: false
        ),
        
        // Union Square / Downtown Corridor
        SalientCommercialAnchor(
            id: "biz_traderjoes_chelsea",
            name: "Trader Joe's",
            brandType: .grocery,
            coordinate: CLLocationCoordinate2D(latitude: 40.7420, longitude: -73.9950),
            primaryStreet: "6th Ave",
            crossStreet: "21st St",
            usesDefiniteArticle: false
        ),
        SalientCommercialAnchor(
            id: "biz_wholefoods_union_sq",
            name: "Whole Foods Market",
            brandType: .grocery,
            coordinate: CLLocationCoordinate2D(latitude: 40.7352, longitude: -73.9912),
            primaryStreet: "14th St",
            crossStreet: "Broadway",
            usesDefiniteArticle: false
        ),
        SalientCommercialAnchor(
            id: "biz_sbux_union_sq",
            name: "Starbucks",
            brandType: .coffee,
            coordinate: CLLocationCoordinate2D(latitude: 40.7365, longitude: -73.9902),
            primaryStreet: "Union Square East",
            crossStreet: "15th St",
            usesDefiniteArticle: true
        )
    ]
    
    // MARK: - Spatial Proximity Search
    
    /// Finds the nearest verified commercial brand anchor within `maxRadiusMeters` (defaults to 45.0m corner gate).
    public static func nearestAnchor(
        to coordinate: CLLocationCoordinate2D,
        maxRadiusMeters: Double = 45.0
    ) -> SalientCommercialAnchor? {
        var closest: SalientCommercialAnchor?
        var minDistance = maxRadiusMeters
        
        for anchor in anchors {
            let d = distanceMeters(from: coordinate, to: anchor.coordinate)
            if d < minDistance {
                minDistance = d
                closest = anchor
            }
        }
        
        return closest
    }
    
    /// Flat-earth equirectangular distance in meters (sub-microsecond execution for tight bounding radii).
    public static func distanceMeters(from c1: CLLocationCoordinate2D, to c2: CLLocationCoordinate2D) -> Double {
        let latMid = (c1.latitude + c2.latitude) * 0.5 * .pi / 180.0
        let dLat = (c2.latitude - c1.latitude) * 111_132.92
        let dLon = (c2.longitude - c1.longitude) * 111_412.84 * cos(latMid)
        return sqrt(dLat * dLat + dLon * dLon)
    }
    
    // MARK: - Prompt Formatting Helpers
    
    /// Formats a natural English turn prompt anchored at the business.
    /// e.g. "Turn left at the Starbucks on 42nd St", "Turn right at Whole Foods Market onto 6th Ave"
    public static func formatTurnPrompt(
        anchor: SalientCommercialAnchor,
        maneuver: LandmarkManeuver,
        targetStreet: String?
    ) -> String {
        let maneuverText: String
        switch maneuver {
        case .turnLeft: maneuverText = "Turn left"
        case .turnRight: maneuverText = "Turn right"
        case .slightLeft: maneuverText = "Bear left"
        case .slightRight: maneuverText = "Bear right"
        case .depart: maneuverText = "Start walking"
        case .straightPast: maneuverText = "Walk past"
        case .arrive: maneuverText = "Arrive at"
        }
        
        let streetSuffix: String
        if let target = targetStreet, !target.isEmpty {
            streetSuffix = " onto \(target)"
        } else {
            streetSuffix = " on \(anchor.primaryStreet)"
        }
        
        return "\(maneuverText) at \(anchor.articulatedName)\(streetSuffix)"
    }
}
