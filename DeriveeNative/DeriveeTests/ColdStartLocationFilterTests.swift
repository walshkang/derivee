import XCTest
import CoreLocation
@testable import Derivee

final class ColdStartLocationFilterTests: XCTestCase {
    
    var filter: ColdStartLocationFilter!
    let fixedNow = Date()
    
    override func setUp() {
        super.setUp()
        filter = ColdStartLocationFilter(
            maxStaleness: 5.0,
            targetAccuracy: 25.0,
            requiredWarmupFixes: 2,
            maxPedestrianSpeed: 12.0,
            temporalGapThreshold: 15.0
        )
    }
    
    func testStaleCachedFixIsRejected() {
        // Fix is 30 seconds old (e.g. cached from CoreLocation prior session)
        let staleLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: fixedNow.addingTimeInterval(-30.0)
        )
        
        let result = filter.process(location: staleLocation, now: fixedNow)
        XCTAssertEqual(result, .discardedStale(age: 30.0))
    }
    
    func testInaccurateCellTowerFixIsRejected() {
        // Fix with horizontalAccuracy = 65m (cell tower triangulation)
        let cellTowerLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 65.0,
            verticalAccuracy: 5.0,
            timestamp: fixedNow
        )
        
        let result = filter.process(location: cellTowerLocation, now: fixedNow)
        XCTAssertEqual(result, .discardedUncertain(accuracy: 65.0))
    }
    
    func testNegativeAccuracyIsRejected() {
        // Fix with invalid / negative accuracy
        let invalidLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: -1.0,
            verticalAccuracy: -1.0,
            timestamp: fixedNow
        )
        
        let result = filter.process(location: invalidLocation, now: fixedNow)
        XCTAssertEqual(result, .discardedUncertain(accuracy: -1.0))
    }
    
    func testTwoFixWarmupConvergence() {
        // Fix 1: Fresh & accurate -> Buffers in warmup (1/2)
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 5.0,
            timestamp: fixedNow
        )
        let result1 = filter.process(location: fix1, now: fixedNow)
        XCTAssertEqual(result1, .warmingUp(currentFix: 1, target: 2))
        
        // Fix 2: 1 second later, 2m away -> Completes warmup and is accepted as first fix
        let fix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.712818, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 8.0,
            verticalAccuracy: 5.0,
            timestamp: fixedNow.addingTimeInterval(1.0)
        )
        let result2 = filter.process(location: fix2, now: fixedNow.addingTimeInterval(1.0))
        XCTAssertEqual(result2, .accepted(location: fix2, isFirstAcceptedFix: true, stepDistance: 0))
    }
    
    func testUrbanCanyonMultipathBounceIsRejected() {
        // Complete warmup first
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0, horizontalAccuracy: 10.0, verticalAccuracy: 5.0, timestamp: fixedNow
        )
        _ = filter.process(location: fix1, now: fixedNow)
        
        let fix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.712818, longitude: -74.0060),
            altitude: 0, horizontalAccuracy: 8.0, verticalAccuracy: 5.0, timestamp: fixedNow.addingTimeInterval(1.0)
        )
        _ = filter.process(location: fix2, now: fixedNow.addingTimeInterval(1.0))
        
        // Fix 3: Jumps 200m away in 1 second (speed = 200 m/s > 12 m/s) -> Multipath bounce
        let fix3 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7146, longitude: -74.0060),
            altitude: 0, horizontalAccuracy: 12.0, verticalAccuracy: 5.0, timestamp: fixedNow.addingTimeInterval(2.0)
        )
        let result3 = filter.process(location: fix3, now: fixedNow.addingTimeInterval(2.0))
        if case .discardedExcessiveSpeed(let speed) = result3 {
            XCTAssertGreaterThan(speed, 12.0)
        } else {
            XCTFail("Expected .discardedExcessiveSpeed, got \(result3)")
        }
    }
    
    func testSubwayEmergenceAfterTemporalGapIsAccepted() {
        // Complete warmup in Brooklyn
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7033, longitude: -73.9890),
            altitude: 0, horizontalAccuracy: 10.0, verticalAccuracy: 5.0, timestamp: fixedNow
        )
        _ = filter.process(location: fix1, now: fixedNow)
        
        let fix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.70331, longitude: -73.9890),
            altitude: 0, horizontalAccuracy: 8.0, verticalAccuracy: 5.0, timestamp: fixedNow.addingTimeInterval(1.0)
        )
        _ = filter.process(location: fix2, now: fixedNow.addingTimeInterval(1.0))
        
        // Fix 3: 45 seconds later in Central Park (Manhattan, 9km away)
        let centralParkTime = fixedNow.addingTimeInterval(45.0)
        let fix3 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7829, longitude: -73.9654),
            altitude: 0,
            horizontalAccuracy: 15.0,
            verticalAccuracy: 5.0,
            course: -1,
            speed: -1,
            timestamp: centralParkTime
        )
        let result3 = filter.process(location: fix3, now: centralParkTime)
        XCTAssertEqual(result3, .accepted(location: fix3, isFirstAcceptedFix: false, stepDistance: 0))
    }
    
    func testResetPutsFilterBackToWarmup() {
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0, horizontalAccuracy: 10.0, verticalAccuracy: 5.0, timestamp: fixedNow
        )
        _ = filter.process(location: fix1, now: fixedNow)
        
        let fix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.712818, longitude: -74.0060),
            altitude: 0, horizontalAccuracy: 8.0, verticalAccuracy: 5.0, timestamp: fixedNow.addingTimeInterval(1.0)
        )
        _ = filter.process(location: fix2, now: fixedNow.addingTimeInterval(1.0))
        
        // Resetting filter
        filter.reset()
        
        // Next fix should be treated as warmup 1/2
        let fix3 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.712818, longitude: -74.0060),
            altitude: 0, horizontalAccuracy: 8.0, verticalAccuracy: 5.0, timestamp: fixedNow.addingTimeInterval(5.0)
        )
        let result = filter.process(location: fix3, now: fixedNow.addingTimeInterval(5.0))
        XCTAssertEqual(result, .warmingUp(currentFix: 1, target: 2))
    }
}
