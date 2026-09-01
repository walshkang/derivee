import XCTest
@testable import DeriveeCore

final class TransitTimeTests: XCTestCase {
    
    func testEuclideanModulo() {
        // Standard positive values
        XCTAssertEqual(TransitTime.euclidean_mod(100, 10), 0)
        XCTAssertEqual(TransitTime.euclidean_mod(15, 4), 3)
        
        // Negative values crossing midnight
        XCTAssertEqual(TransitTime.euclidean_mod(-5, 86400), 86395)
        XCTAssertEqual(TransitTime.euclidean_mod(-120, 86400), 86280)
        XCTAssertEqual(TransitTime.euclidean_mod(-86400, 86400), 0)
        XCTAssertEqual(TransitTime.euclidean_mod(-86401, 86400), 86399)
        
        // Zero divisor safety
        XCTAssertEqual(TransitTime.euclidean_mod(42, 0), 0)
    }
    
    func testNormalizeScheduleTime() {
        // Positive delay
        XCTAssertEqual(TransitTime.normalize_schedule_time(3600, 300), 3900)
        
        // Negative delay (early vehicle)
        XCTAssertEqual(TransitTime.normalize_schedule_time(3600, -600), 3000)
        
        // Underflow protection
        XCTAssertEqual(TransitTime.normalize_schedule_time(100, -500), 0)
    }
    
    func testCalculateWaitTime() {
        // Same-day departure
        XCTAssertEqual(TransitTime.calculate_wait_time(3600, 4200), 600)
        XCTAssertEqual(TransitTime.calculate_wait_time(28800, 28800), 0)
        
        // Midnight crossing: user arrives at 23:55 (86,100s), trip departs at 01:30 (5,400s)
        // Expected wait: (86400 - 86100) + 5400 = 300 + 5400 = 5,700s (95 minutes)
        XCTAssertEqual(TransitTime.calculate_wait_time(86100, 5400), 5700)
    }
    
    func testCalculateSignedCircularDelayMinutes() {
        // Exactly on time
        XCTAssertEqual(TransitTime.calculate_signed_circular_delay_minutes(60, 60), 0)
        
        // 5 minutes late (live > scheduled)
        XCTAssertEqual(TransitTime.calculate_signed_circular_delay_minutes(65, 60), 5)
        
        // 5 minutes early (live < scheduled)
        XCTAssertEqual(TransitTime.calculate_signed_circular_delay_minutes(55, 60), -5)
        
        // Midnight boundary late: scheduled 23:58 (1438m), live 00:03 (3m) -> +5m late
        XCTAssertEqual(TransitTime.calculate_signed_circular_delay_minutes(3, 1438), 5)
        
        // Midnight boundary early: scheduled 00:03 (3m), live 23:58 (1438m) -> -5m early
        XCTAssertEqual(TransitTime.calculate_signed_circular_delay_minutes(1438, 3), -5)
    }
}
