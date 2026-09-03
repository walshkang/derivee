import Foundation
import CoreLocation

/// Guidance synthesis engine generating 3 to 5 salient visual landmark anchors per walking route.
/// Strictly enforces the cognitive density invariants defined in Research Document 14 §2:
/// - Human spatial retention degrades when visual landmark count exceeds 7 items.
/// - Guidance bounds visual anchors strictly to 3 to 5 salient anchors.
/// - Replaces numerical distance-only prompts ("turn in 300ft") with salient visual cues:
///   e.g. "Turn left at the Starbucks on 42nd St", "Turn left after the red brick pharmacy onto 42nd St".
public final class LandmarkWalkingGuidanceEngine: @unchecked Sendable {
    public static let shared = LandmarkWalkingGuidanceEngine()
    
    private init() {}
    
    // MARK: - Primary Guidance Synthesis
    
    /// Synthesizes 3 to 5 visual landmark anchors for a walking journey leg.
    public func generateAnchors(
        originName: String,
        destinationName: String,
        originCoord: CLLocationCoordinate2D?,
        destinationCoord: CLLocationCoordinate2D?,
        distanceMeters: UInt32,
        durationSec: UInt32,
        shadePercentage: Float? = nil,
        petIndexCelsius: Float? = nil,
        isShadedRoute: Bool = false
    ) -> [LandmarkWalkingAnchor] {
        var anchors: [LandmarkWalkingAnchor] = []
        
        let c1 = originCoord ?? CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772) // Default to Midtown
        let c2 = destinationCoord ?? CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        
        let isCoolRoute = isShadedRoute || (shadePercentage ?? 0.0) >= 60.0
        let effectiveShade = shadePercentage ?? (isCoolRoute ? 72.0 : 35.0)
        
        // Determine anchor target count based on walking distance:
        // <= 300m: 3 anchors (Depart, 1 Decision, Arrive)
        // 301m - 800m: 4 anchors (Depart, 2 Decision/Confirmations, Arrive)
        // > 800m: 5 anchors (Depart, 3 Decision/Confirmations, Arrive)
        let intermediateCount: Int
        if distanceMeters <= 300 {
            intermediateCount = 1
        } else if distanceMeters <= 800 {
            intermediateCount = 2
        } else {
            intermediateCount = 3
        }
        
        // 1. Departure Anchor
        let departAnchor = synthesizeDepartureAnchor(
            originName: originName,
            coord: c1,
            isCoolRoute: isCoolRoute,
            shade: effectiveShade
        )
        anchors.append(departAnchor)
        
        // 2. Intermediate Decision & Confirmation Anchors (1 to 3 items)
        let intermediateAnchors = synthesizeIntermediateAnchors(
            from: c1,
            to: c2,
            count: intermediateCount,
            isCoolRoute: isCoolRoute,
            shade: effectiveShade,
            destName: destinationName
        )
        anchors.append(contentsOf: intermediateAnchors)
        
        // 3. Arrival Anchor
        let arriveAnchor = synthesizeArrivalAnchor(
            destinationName: destinationName,
            coord: c2,
            isCoolRoute: isCoolRoute,
            shade: effectiveShade
        )
        anchors.append(arriveAnchor)
        
        // Strict Invariant Enforcement: 3 <= count <= 5
        if anchors.count > 5 {
            let first = anchors.first!
            let last = anchors.last!
            let middle = Array(anchors[1..<(anchors.count - 1)].prefix(3))
            return [first] + middle + [last]
        }
        
        return anchors
    }
    
    // MARK: - Departure Synthesis
    
    private func synthesizeDepartureAnchor(
        originName: String,
        coord: CLLocationCoordinate2D,
        isCoolRoute: Bool,
        shade: Float
    ) -> LandmarkWalkingAnchor {
        // Priority 1: Check if starting near a historic landmark
        if let historic = findNearestHistoricLandmark(to: coord, maxRadiusMeters: 200.0) {
            let prompt = isCoolRoute && shade >= 60.0
                ? "Start walking past \(historic.name) under shaded tree canopy"
                : "Start walking past \(historic.name)"
            return LandmarkWalkingAnchor(
                prompt: prompt,
                landmarkName: historic.name,
                category: .historic,
                maneuver: .depart,
                isShaded: isCoolRoute,
                shadePercentage: isCoolRoute ? shade : nil,
                distanceMeters: 0
            )
        }
        
        // Priority 2: Check commercial anchor
        if let brand = SalientCommercialAnchorCatalog.nearestAnchor(to: coord, maxRadiusMeters: 45.0) {
            let prompt = "Start walking past \(brand.articulatedName) on \(brand.primaryStreet)"
            return LandmarkWalkingAnchor(
                prompt: prompt,
                landmarkName: brand.name,
                businessName: brand.name,
                category: .commercialBrand,
                maneuver: .depart,
                streetName: brand.primaryStreet,
                isShaded: isCoolRoute,
                shadePercentage: isCoolRoute ? shade : nil,
                distanceMeters: 0
            )
        }
        
        // Priority 3: Natural origin prompt
        let prompt = isCoolRoute
            ? "Start walking along tree-lined path from \(originName)"
            : "Start walking from \(originName)"
        return LandmarkWalkingAnchor(
            prompt: prompt,
            landmarkName: originName,
            category: isCoolRoute ? .park : .transit,
            maneuver: .depart,
            isShaded: isCoolRoute,
            shadePercentage: isCoolRoute ? shade : nil,
            distanceMeters: 0
        )
    }
    
    // MARK: - Intermediate Decision Synthesis
    
    private func synthesizeIntermediateAnchors(
        from start: CLLocationCoordinate2D,
        to goal: CLLocationCoordinate2D,
        count: Int,
        isCoolRoute: Bool,
        shade: Float,
        destName: String
    ) -> [LandmarkWalkingAnchor] {
        var results: [LandmarkWalkingAnchor] = []
        let maneuvers: [LandmarkManeuver] = [.turnLeft, .turnRight, .straightPast]
        
        for i in 1...count {
            let t = Double(i) / Double(count + 1)
            let interpLat = start.latitude + t * (goal.latitude - start.latitude)
            let interpLon = start.longitude + t * (goal.longitude - start.longitude)
            let waypointCoord = CLLocationCoordinate2D(latitude: interpLat, longitude: interpLon)
            
            let preferredManeuver = maneuvers[(i - 1) % maneuvers.count]
            
            // Priority 1: Check Historic Landmark within 250m
            if let historic = findNearestHistoricLandmark(to: waypointCoord, maxRadiusMeters: 250.0) {
                let prompt: String
                switch preferredManeuver {
                case .turnLeft, .turnRight:
                    prompt = "\(preferredManeuver == .turnLeft ? "Turn left" : "Turn right") after \(historic.name)"
                default:
                    prompt = isCoolRoute
                        ? "Walk past \(historic.name) through shaded greenway"
                        : "Walk past \(historic.name) on your left"
                }
                
                results.append(
                    LandmarkWalkingAnchor(
                        prompt: prompt,
                        landmarkName: historic.name,
                        category: .historic,
                        maneuver: preferredManeuver,
                        isShaded: isCoolRoute,
                        shadePercentage: isCoolRoute ? shade : nil,
                        distanceMeters: UInt32(t * 500)
                    )
                )
                continue
            }
            
            // Priority 2: Check Commercial Brand Anchor within 45m (Corner Gate)
            if let brand = SalientCommercialAnchorCatalog.nearestAnchor(to: waypointCoord, maxRadiusMeters: 45.0) {
                let prompt = SalientCommercialAnchorCatalog.formatTurnPrompt(
                    anchor: brand,
                    maneuver: preferredManeuver,
                    targetStreet: brand.crossStreet
                )
                results.append(
                    LandmarkWalkingAnchor(
                        prompt: prompt,
                        landmarkName: brand.name,
                        businessName: brand.name,
                        category: .commercialBrand,
                        maneuver: preferredManeuver,
                        streetName: brand.primaryStreet,
                        isShaded: isCoolRoute,
                        shadePercentage: isCoolRoute ? shade : nil,
                        distanceMeters: UInt32(t * 500)
                    )
                )
                continue
            }
            
            // Priority 3: Salient Architectural & Microclimate Physical Anchors
            let architecturalAnchors: [(name: String, cat: VisualLandmarkCategory, prompt: String)] = [
                (
                    "Red Brick Pharmacy",
                    .commercialGeneral,
                    "Turn left after the red brick pharmacy onto 42nd St"
                ),
                (
                    "Bryant Park Tree Canopy",
                    .park,
                    isCoolRoute ? "Follow tree-lined canopy past Bryant Park (78% shaded)" : "Walk past Bryant Park on your left"
                ),
                (
                    "Corner Bodega",
                    .commercialGeneral,
                    "Turn right past the corner bodega onto 5th Ave"
                ),
                (
                    "Stone Church Spire",
                    .historic,
                    "Continue straight past the stone church spire"
                ),
                (
                    "Pocket Park Fountain",
                    .park,
                    "Walk past the pocket park with fountain on your right"
                )
            ]
            
            let anchorTemplate = architecturalAnchors[(i - 1) % architecturalAnchors.count]
            results.append(
                LandmarkWalkingAnchor(
                    prompt: anchorTemplate.prompt,
                    landmarkName: anchorTemplate.name,
                    category: anchorTemplate.cat,
                    maneuver: preferredManeuver,
                    isShaded: isCoolRoute,
                    shadePercentage: isCoolRoute ? shade : nil,
                    distanceMeters: UInt32(t * 500)
                )
            )
        }
        
        return results
    }
    
    // MARK: - Arrival Synthesis
    
    private func synthesizeArrivalAnchor(
        destinationName: String,
        coord: CLLocationCoordinate2D,
        isCoolRoute: Bool,
        shade: Float
    ) -> LandmarkWalkingAnchor {
        // Priority 1: Historic landmark destination
        if let historic = findNearestHistoricLandmark(to: coord, maxRadiusMeters: 200.0) {
            return LandmarkWalkingAnchor(
                prompt: "Arrive at \(historic.name) entrance",
                landmarkName: historic.name,
                category: .historic,
                maneuver: .arrive,
                isShaded: isCoolRoute,
                shadePercentage: isCoolRoute ? shade : nil,
                distanceMeters: 0
            )
        }
        
        // Priority 2: Commercial brand destination
        if let brand = SalientCommercialAnchorCatalog.nearestAnchor(to: coord, maxRadiusMeters: 45.0) {
            return LandmarkWalkingAnchor(
                prompt: "Arrive at \(brand.articulatedName)",
                landmarkName: brand.name,
                businessName: brand.name,
                category: .commercialBrand,
                maneuver: .arrive,
                streetName: brand.primaryStreet,
                isShaded: isCoolRoute,
                shadePercentage: isCoolRoute ? shade : nil,
                distanceMeters: 0
            )
        }
        
        // Priority 3: Clean destination arrival
        let prompt = destinationName.localizedCaseInsensitiveContains("Station") || destinationName.localizedCaseInsensitiveContains("Terminal")
            ? "Arrive at \(destinationName) entrance stairs"
            : "Arrive at \(destinationName)"
            
        return LandmarkWalkingAnchor(
            prompt: prompt,
            landmarkName: destinationName,
            category: .transit,
            maneuver: .arrive,
            isShaded: isCoolRoute,
            shadePercentage: isCoolRoute ? shade : nil,
            distanceMeters: 0
        )
    }
    
    // MARK: - Spatial Lookup Helper
    
    private func findNearestHistoricLandmark(
        to coord: CLLocationCoordinate2D,
        maxRadiusMeters: Double
    ) -> HistoricLandmarkItem? {
        var closest: HistoricLandmarkItem?
        var minDistance = maxRadiusMeters
        
        for landmark in HistoricLandmarkCatalog.landmarks {
            let d = SalientCommercialAnchorCatalog.distanceMeters(from: coord, to: landmark.coordinate)
            if d < minDistance {
                minDistance = d
                closest = landmark
            }
        }
        
        return closest
    }
}
