import XCTest
import CoreLocation
@testable import Derivee

final class MissedConnectionDetectionTests: XCTestCase {
    
    private let detector = MissedConnectionDetector()
    
    // MARK: - Fixtures
    
    private func makeTestItinerary(departureSec: UInt32 = 30000) -> JourneyItinerary {
        let walkLeg = JourneyLeg(
            id: UUID(),
            mode: .walk,
            originName: "Broadway & 8th St",
            destinationName: "Astor Place Station",
            departureTimeSec: departureSec - 600,
            arrivalTimeSec: departureSec - 60,
            durationSec: 540,
            distanceMeters: 400,
            confidenceTier: .verified
        )
        
        let subwayLeg = JourneyLeg(
            id: UUID(),
            mode: .subway,
            originName: "Astor Place",
            destinationName: "14th St - Union Square",
            departureTimeSec: departureSec,
            arrivalTimeSec: departureSec + 180,
            durationSec: 180,
            distanceMeters: 800,
            routeId: "6",
            confidenceTier: .verified
        )
        
        return JourneyItinerary(
            id: UUID(),
            profile: .fastest,
            departureTimeSec: departureSec - 600,
            arrivalTimeSec: departureSec + 180,
            p10ArrivalSec: departureSec + 120,
            p50ArrivalSec: departureSec + 180,
            p90ArrivalSec: departureSec + 240,
            totalCost: 2.90,
            legs: [walkLeg, subwayLeg],
            confidenceTier: .verified
        )
    }
    
    // MARK: - Unit Tests
    
    func testOnTrackWhenUserHasAmpleTime() {
        let depSec: UInt32 = 30000
        let itin = makeTestItinerary(departureSec: depSec)
        
        // Station at Astor Place (40.7300, -73.9910)
        let stationCoord = CLLocationCoordinate2D(latitude: 40.7300, longitude: -73.9910)
        // User 100m away
        let userCoord = CLLocationCoordinate2D(latitude: 40.7308, longitude: -73.9910)
        
        // Current clock: 400s before departure
        let currentClockSec = depSec - 400
        
        let result = detector.evaluateConnection(
            itinerary: itin,
            currentLegIndex: 0,
            userLocation: userCoord,
            userSpeedMps: 1.2,
            currentClockSec: currentClockSec,
            targetStationCoordinate: stationCoord
        )
        
        XCTAssertNil(result, "User with 400s available and only ~130s walk needed should be on track")
    }
    
    func testImminentMissWhenWalkingTimeExceedsAvailableTimeWithSlack() {
        let depSec: UInt32 = 30000
        let itin = makeTestItinerary(departureSec: depSec)
        
        let stationCoord = CLLocationCoordinate2D(latitude: 40.7300, longitude: -73.9910)
        // User ~400m away (lat delta ~0.0036 ≈ 400m)
        let userCoord = CLLocationCoordinate2D(latitude: 40.7336, longitude: -73.9910)
        
        // Walk time needed = (400 / 1.2) + 45s = 333 + 45 = 378s
        // Available time = 120s
        // Deficit = 378 - 120 = 258s (> 30s slack)
        let currentClockSec = depSec - 120
        
        let result = detector.evaluateConnection(
            itinerary: itin,
            currentLegIndex: 0,
            userLocation: userCoord,
            userSpeedMps: 1.2,
            currentClockSec: currentClockSec,
            targetStationCoordinate: stationCoord
        )
        
        XCTAssertNotNil(result, "User 400m away with only 120s until departure must trigger imminent miss")
        XCTAssertEqual(result?.missedLeg.routeId, "6")
        XCTAssertEqual(result?.stationName, "Astor Place")
        
        if case .imminentMiss(let deficit) = result?.status {
            XCTAssertGreaterThan(deficit, 30.0)
        } else {
            XCTFail("Expected imminentMiss status")
        }
    }
    
    func testConfirmedMissWhenDepartureTimePassedAndUserOutsideStation() {
        let depSec: UInt32 = 30000
        let itin = makeTestItinerary(departureSec: depSec)
        
        let stationCoord = CLLocationCoordinate2D(latitude: 40.7300, longitude: -73.9910)
        let userCoord = CLLocationCoordinate2D(latitude: 40.7315, longitude: -73.9910) // ~160m away
        
        // Current clock: 45s after departure
        let currentClockSec = depSec + 45
        
        let result = detector.evaluateConnection(
            itinerary: itin,
            currentLegIndex: 0,
            userLocation: userCoord,
            userSpeedMps: 1.2,
            currentClockSec: currentClockSec,
            targetStationCoordinate: stationCoord
        )
        
        XCTAssertNotNil(result)
        if case .confirmedMiss(let minutesLate) = result?.status {
            XCTAssertEqual(minutesLate, 1)
        } else {
            XCTFail("Expected confirmedMiss status")
        }
    }
    
    func testPlatformArrivalRadiusSuppressesMissAlert() {
        let depSec: UInt32 = 30000
        let itin = makeTestItinerary(departureSec: depSec)
        
        let stationCoord = CLLocationCoordinate2D(latitude: 40.7300, longitude: -73.9910)
        // User 15m away (< 35m arrival radius)
        let userCoord = CLLocationCoordinate2D(latitude: 40.7301, longitude: -73.9910)
        
        // Only 10s until departure
        let currentClockSec = depSec - 10
        
        let result = detector.evaluateConnection(
            itinerary: itin,
            currentLegIndex: 0,
            userLocation: userCoord,
            userSpeedMps: 1.0,
            currentClockSec: currentClockSec,
            targetStationCoordinate: stationCoord
        )
        
        XCTAssertNil(result, "User inside 35m platform radius should not trigger missed connection")
    }
}
