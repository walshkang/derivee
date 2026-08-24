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
            highAccuracyThreshold: 12.0,
            dwellDuration: 3.0,
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
    
    func testHighAccuracySingleFixInstantAcceptance() {
        // Fix 1: High accuracy (hAcc = 8m <= 12m) -> Instant unlock at t=0
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 8.0,
            verticalAccuracy: 5.0,
            timestamp: fixedNow
        )
        let result1 = filter.process(location: fix1, now: fixedNow)
        XCTAssertEqual(result1, .accepted(location: fix1, isFirstAcceptedFix: true, stepDistance: 0))
    }
    
    func testIntermediateAccuracyRequiresDwell() {
        // Fix 1: Intermediate accuracy (12m < hAcc = 18m <= 25m) -> Requires stationary dwell
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 18.0,
            verticalAccuracy: 5.0,
            timestamp: fixedNow
        )
        let result1 = filter.process(location: fix1, now: fixedNow)
        XCTAssertEqual(result1, .requiresDwell(location: fix1, dwellDuration: 3.0))
    }
    
    func testContinuousFixResolvesDwellEarly() {
        // Fix 1: Intermediate accuracy -> Starts dwell
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 18.0,
            verticalAccuracy: 5.0,
            timestamp: fixedNow
        )
        let result1 = filter.process(location: fix1, now: fixedNow)
        XCTAssertEqual(result1, .requiresDwell(location: fix1, dwellDuration: 3.0))
        
        // Fix 2: 1 second later, 2m away -> Completes warmup and accepts immediately
        let fix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.712818, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 8.0,
            verticalAccuracy: 5.0,
            timestamp: fixedNow.addingTimeInterval(1.0)
        )
        let result2 = filter.process(location: fix2, now: fixedNow.addingTimeInterval(1.0))
        XCTAssertEqual(result2, .accepted(location: fix2, isFirstAcceptedFix: true, stepDistance: fix2.distance(from: fix1)))
    }
    
    func testCommitDwellTransitionsFilterState() {
        // Fix 1: Intermediate accuracy -> Starts dwell
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 18.0,
            verticalAccuracy: 5.0,
            timestamp: fixedNow
        )
        _ = filter.process(location: fix1, now: fixedNow)
        
        // Dwell timer expires and commits
        filter.commitDwell()
        
        // Fix 2: 4 seconds later (after dwell), 2m away -> Continuous tracking (not first accepted)
        let fix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.712818, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 8.0,
            verticalAccuracy: 5.0,
            timestamp: fixedNow.addingTimeInterval(4.0)
        )
        let result2 = filter.process(location: fix2, now: fixedNow.addingTimeInterval(4.0))
        XCTAssertEqual(result2, .accepted(location: fix2, isFirstAcceptedFix: false, stepDistance: fix2.distance(from: fix1)))
    }
    
    func testUrbanCanyonMultipathBounceIsRejected() {
        // Fix 1: Instant high-accuracy lock
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0, horizontalAccuracy: 8.0, verticalAccuracy: 5.0, timestamp: fixedNow
        )
        _ = filter.process(location: fix1, now: fixedNow)
        
        // Fix 2: Jumps 200m away in 1 second (speed = 200 m/s > 12 m/s) -> Multipath bounce
        let fix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7146, longitude: -74.0060),
            altitude: 0, horizontalAccuracy: 10.0, verticalAccuracy: 5.0, timestamp: fixedNow.addingTimeInterval(1.0)
        )
        let result2 = filter.process(location: fix2, now: fixedNow.addingTimeInterval(1.0))
        if case .discardedExcessiveSpeed(let speed) = result2 {
            XCTAssertGreaterThan(speed, 12.0)
        } else {
            XCTFail("Expected .discardedExcessiveSpeed, got \(result2)")
        }
    }
    
    func testSubwayEmergenceHighAccuracyInstantAcceptance() {
        // Seed initial fix in Brooklyn
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7033, longitude: -73.9890),
            altitude: 0, horizontalAccuracy: 8.0, verticalAccuracy: 5.0, timestamp: fixedNow
        )
        _ = filter.process(location: fix1, now: fixedNow)
        
        // Fix 2: 45 seconds later in Central Park with high accuracy (hAcc = 10m <= 12m)
        let centralParkTime = fixedNow.addingTimeInterval(45.0)
        let fix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7829, longitude: -73.9654),
            altitude: 0,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 5.0,
            course: -1,
            speed: -1,
            timestamp: centralParkTime
        )
        let result2 = filter.process(location: fix2, now: centralParkTime)
        XCTAssertEqual(result2, .accepted(location: fix2, isFirstAcceptedFix: false, stepDistance: 0))
    }
    
    func testSubwayEmergenceIntermediateAccuracyRequiresDwell() {
        // Seed initial fix in Brooklyn
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7033, longitude: -73.9890),
            altitude: 0, horizontalAccuracy: 8.0, verticalAccuracy: 5.0, timestamp: fixedNow
        )
        _ = filter.process(location: fix1, now: fixedNow)
        
        // Fix 2: 45 seconds later in Central Park with intermediate accuracy (hAcc = 18m > 12m)
        let centralParkTime = fixedNow.addingTimeInterval(45.0)
        let fix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7829, longitude: -73.9654),
            altitude: 0,
            horizontalAccuracy: 18.0,
            verticalAccuracy: 5.0,
            course: -1,
            speed: -1,
            timestamp: centralParkTime
        )
        let result2 = filter.process(location: fix2, now: centralParkTime)
        XCTAssertEqual(result2, .requiresDwell(location: fix2, dwellDuration: 3.0))
    }
    
    func testResetPutsFilterBackToColdStart() {
        let fix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0, horizontalAccuracy: 8.0, verticalAccuracy: 5.0, timestamp: fixedNow
        )
        _ = filter.process(location: fix1, now: fixedNow)
        
        // Resetting filter
        filter.reset()
        
        // Next intermediate fix should be treated as cold start dwell
        let fix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.712818, longitude: -74.0060),
            altitude: 0, horizontalAccuracy: 18.0, verticalAccuracy: 5.0, timestamp: fixedNow.addingTimeInterval(5.0)
        )
        let result = filter.process(location: fix2, now: fixedNow.addingTimeInterval(5.0))
        XCTAssertEqual(result, .requiresDwell(location: fix2, dwellDuration: 3.0))
    }
}
