import XCTest
import CxxStdlib
@testable import DeriveeCore

final class BoundedAStarRouterTests: XCTestCase {

    func testDistanceCalculation() {
        // Known distance between Astor Place (40.7300, -73.9925) and Union Square (40.7359, -73.9911) ~ 660m
        let dist = BoundedAStarRouter.calculate_distance_meters(
            40.7300, -73.9925,
            40.7359, -73.9911
        )
        
        XCTAssertGreaterThan(dist, 600.0)
        XCTAssertLessThan(dist, 750.0)
    }

    func testWalkDurationCalculation() {
        // 520m at standard 1.3 m/s walking speed = 400 seconds
        let duration = BoundedAStarRouter.calculate_walk_duration_sec(520.0, 1.3)
        XCTAssertEqual(duration, 400)
        
        // 0 distance = 0 duration
        XCTAssertEqual(BoundedAStarRouter.calculate_walk_duration_sec(0.0, 1.3), 0)
    }

    func testCandidateStopsSearch() {
        let stops = [
            Stop(40.7300, -73.9925, 0, 0, 1, 0), // Stop 0 (Astor Place)
            Stop(40.7359, -73.9911, 1, 0, 1, 0), // Stop 1 (Union Sq, ~660m)
            Stop(40.7580, -73.9855, 2, 0, 1, 0)  // Stop 2 (Times Sq, ~3.2km)
        ]
        
        stops.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            
            // Query from Astor Place vicinity (40.7302, -73.9920) with 1,000m radius
            let candidates = BoundedAStarRouter.find_candidate_stops(
                base,
                buffer.count,
                40.7302,
                -73.9920,
                1000.0,
                0,
                10
            )
            
            // Should find Stop 0 and Stop 1, but NOT Stop 2 (outside 1,000m)
            XCTAssertEqual(candidates.size(), 2)
            XCTAssertEqual(candidates[0].stop_id, 0) // Closest
            XCTAssertEqual(candidates[1].stop_id, 1) // Second closest
            XCTAssertLessThan(candidates[0].distance_meters, candidates[1].distance_meters)
        }
    }
}
