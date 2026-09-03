import XCTest
import CoreLocation
@testable import Derivee

final class LandmarkWalkingGuidanceTests: XCTestCase {
    
    // MARK: - Invariant 1: 3 to 5 Salient Visual Landmarks
    
    func testCognitiveDensityInvariantThreeToFiveAnchors() {
        let engine = LandmarkWalkingGuidanceEngine.shared
        
        let grandCentral = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        let timesSquare = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        
        // 1. Short walk (150m) -> Exactly 3 anchors (Depart, 1 Decision, Arrive)
        let shortAnchors = engine.generateAnchors(
            originName: "Subway Entrance",
            destinationName: "Corner Cafe",
            originCoord: grandCentral,
            destinationCoord: CLLocationCoordinate2D(latitude: 40.7535, longitude: -73.9780),
            distanceMeters: 150,
            durationSec: 120
        )
        XCTAssertEqual(shortAnchors.count, 3, "Short walk must produce exactly 3 landmark anchors")
        XCTAssertEqual(shortAnchors.first?.maneuver, .depart)
        XCTAssertEqual(shortAnchors.last?.maneuver, .arrive)
        
        // 2. Medium walk (500m) -> Exactly 4 anchors (Depart, 2 Decision, Arrive)
        let mediumAnchors = engine.generateAnchors(
            originName: "Grand Central",
            destinationName: "Bryant Park",
            originCoord: grandCentral,
            destinationCoord: CLLocationCoordinate2D(latitude: 40.7536, longitude: -73.9832),
            distanceMeters: 500,
            durationSec: 400
        )
        XCTAssertEqual(mediumAnchors.count, 4, "Medium walk must produce exactly 4 landmark anchors")
        
        // 3. Long walk (1,400m) -> Exactly 5 anchors (strictly capped at 5)
        let longAnchors = engine.generateAnchors(
            originName: "Grand Central Terminal",
            destinationName: "Times Square - 42 St",
            originCoord: grandCentral,
            destinationCoord: timesSquare,
            distanceMeters: 1400,
            durationSec: 1100
        )
        XCTAssertEqual(longAnchors.count, 5, "Long walk must cap anchors strictly at 5 per Research Doc 14")
        
        // Invariant check: Anchors must never be fewer than 3 or exceed 5
        for dist in stride(from: 50, through: 3000, by: 250) {
            let res = engine.generateAnchors(
                originName: "Origin",
                destinationName: "Destination",
                originCoord: grandCentral,
                destinationCoord: timesSquare,
                distanceMeters: UInt32(dist),
                durationSec: UInt32(Double(dist) / 1.3)
            )
            XCTAssertGreaterThanOrEqual(res.count, 3, "Guidance anchor count must be >= 3")
            XCTAssertLessThanOrEqual(res.count, 5, "Guidance anchor count must be <= 5")
        }
    }
    
    // MARK: - Invariant 2: Business Name Synthesis & Natural Grammar
    
    func testBusinessNameSynthesisAndPrepositionGrammar() {
        let sbux42nd = SalientCommercialAnchor(
            id: "test_sbux",
            name: "Starbucks",
            brandType: .coffee,
            coordinate: CLLocationCoordinate2D(latitude: 40.7538, longitude: -73.9806),
            primaryStreet: "42nd St",
            crossStreet: "5th Ave",
            usesDefiniteArticle: true
        )
        
        let wholeFoods = SalientCommercialAnchor(
            id: "test_wf",
            name: "Whole Foods Market",
            brandType: .grocery,
            coordinate: CLLocationCoordinate2D(latitude: 40.7539, longitude: -73.9842),
            primaryStreet: "42nd St",
            crossStreet: "6th Ave",
            usesDefiniteArticle: false
        )
        
        // Definite article formatting ("the Starbucks")
        let turnLeftSbux = SalientCommercialAnchorCatalog.formatTurnPrompt(
            anchor: sbux42nd,
            maneuver: .turnLeft,
            targetStreet: nil
        )
        XCTAssertEqual(turnLeftSbux, "Turn left at the Starbucks on 42nd St")
        
        let turnRightTarget = SalientCommercialAnchorCatalog.formatTurnPrompt(
            anchor: sbux42nd,
            maneuver: .turnRight,
            targetStreet: "5th Ave"
        )
        XCTAssertEqual(turnRightTarget, "Turn right at the Starbucks onto 5th Ave")
        
        // Proper noun without article ("Whole Foods Market")
        let turnWf = SalientCommercialAnchorCatalog.formatTurnPrompt(
            anchor: wholeFoods,
            maneuver: .turnLeft,
            targetStreet: "6th Ave"
        )
        XCTAssertEqual(turnWf, "Turn left at Whole Foods Market onto 6th Ave")
    }
    
    // MARK: - Invariant 3: Decision-Point Proximity Gate (<= 45m)
    
    func testCommercialProximityGate() {
        // Location directly at 42nd & 5th (within 20m of Starbucks)
        let cornerPoint = CLLocationCoordinate2D(latitude: 40.7537, longitude: -73.9805)
        let matchedAnchor = SalientCommercialAnchorCatalog.nearestAnchor(to: cornerPoint, maxRadiusMeters: 45.0)
        XCTAssertNotNil(matchedAnchor)
        XCTAssertEqual(matchedAnchor?.name, "Starbucks")
        
        // Location 150m down the block (should be rejected by 45m corner gate)
        let midBlockPoint = CLLocationCoordinate2D(latitude: 40.7548, longitude: -73.9790)
        let rejectedAnchor = SalientCommercialAnchorCatalog.nearestAnchor(to: midBlockPoint, maxRadiusMeters: 45.0)
        XCTAssertNil(rejectedAnchor, "Commercial anchors must be rejected if > 45m from decision point")
    }
    
    // MARK: - Invariant 4: Historic & Cultural Landmarks
    
    func testHistoricLandmarkProximityMatching() {
        let engine = LandmarkWalkingGuidanceEngine.shared
        let grandCentralCoord = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        
        let anchors = engine.generateAnchors(
            originName: "Grand Central Station",
            destinationName: "Office",
            originCoord: grandCentralCoord,
            destinationCoord: CLLocationCoordinate2D(latitude: 40.7560, longitude: -73.9772),
            distanceMeters: 400,
            durationSec: 320
        )
        
        let depart = anchors.first
        XCTAssertNotNil(depart)
        XCTAssertTrue(
            depart?.prompt.contains("Grand Central Terminal") == true,
            "Departure should anchor to Grand Central Terminal"
        )
        XCTAssertEqual(depart?.category, .historic)
    }
    
    // MARK: - Invariant 5: Microclimate Shaded Routes (PET & Canopy)
    
    func testShadedCoolRouteThermalComfortIntegration() {
        let engine = LandmarkWalkingGuidanceEngine.shared
        let origin = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        let dest = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        
        let shadedAnchors = engine.generateAnchors(
            originName: "Grand Central",
            destinationName: "Times Square",
            originCoord: origin,
            destinationCoord: dest,
            distanceMeters: 850,
            durationSec: 680,
            shadePercentage: 78.0,
            petIndexCelsius: 23.5,
            isShadedRoute: true
        )
        
        XCTAssertEqual(shadedAnchors.count, 5)
        
        for anchor in shadedAnchors {
            XCTAssertTrue(anchor.isShaded, "All anchors in a shaded route must be tagged as isShaded")
            XCTAssertEqual(anchor.shadePercentage, 78.0)
        }
        
        // Verify primary anchor has visual shade descriptor or cue
        let hasCanopyPrompt = shadedAnchors.contains {
            $0.prompt.localizedCaseInsensitiveContains("shaded") ||
            $0.prompt.localizedCaseInsensitiveContains("canopy") ||
            $0.prompt.localizedCaseInsensitiveContains("tree")
        }
        XCTAssertTrue(hasCanopyPrompt, "Shaded route guidance should include tree canopy or shaded phrasing")
    }
    
    // MARK: - Invariant 6: JourneyLeg Integration & Convenience Accessors
    
    func testJourneyLegIntegration() {
        let anchor1 = LandmarkWalkingAnchor(
            prompt: "Turn left at the Starbucks on 42nd St",
            landmarkName: "Starbucks",
            businessName: "Starbucks",
            category: .commercialBrand,
            maneuver: .turnLeft,
            streetName: "42nd St"
        )
        let anchor2 = LandmarkWalkingAnchor(
            prompt: "Arrive at Bryant Park entrance",
            landmarkName: "Bryant Park",
            category: .park,
            maneuver: .arrive
        )
        
        let leg = JourneyLeg(
            mode: .walk,
            originName: "5th Ave",
            destinationName: "Bryant Park",
            departureTimeSec: 1000,
            arrivalTimeSec: 1300,
            distanceMeters: 400,
            landmarkAnchors: [anchor1, anchor2]
        )
        
        XCTAssertEqual(leg.landmarkAnchors.count, 2)
        XCTAssertEqual(leg.primaryLandmarkAnchor?.prompt, "Turn left at the Starbucks on 42nd St")
        XCTAssertEqual(leg.landmarkCue, "Turn left at the Starbucks on 42nd St")
        XCTAssertEqual(leg.primaryLandmarkAnchor?.category, .commercialBrand)
    }
}
