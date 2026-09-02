import XCTest
@testable import Derivee

final class GTFSMidnightResolverTests: XCTestCase {
    
    func testEuclideanModuloBasic() {
        // Standard positive values
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(100, 10), 0)
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(15, 4), 3)
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(7, 12), 7)
        
        // Negative values crossing midnight
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(-5, 1440), 1435)
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(-1, 86400), 86399)
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(-120, 86400), 86280)
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(-86400, 86400), 0)
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(-86401, 86400), 86399)
        
        // Zero dividend
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(0, 1440), 0)
        
        // Zero divisor safety guard
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(42, 0), 0)
        
        // Different binary integer types
        let int32Val: Int32 = -30
        let mod32: Int32 = 1440
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(int32Val, mod32), 1410)
        
        let int64Val: Int64 = -3600
        let mod64: Int64 = 86400
        XCTAssertEqual(GTFSMidnightResolver.euclideanModulo(int64Val, mod64), 82800)
    }
    
    func testSignedCircularDelayMinutesStandard() {
        // On time
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 60, scheduledMinutes: 60), 0)
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelay(live: 120, sched: 120), 0)
        
        // Late (live > scheduled)
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 65, scheduledMinutes: 60), 5)
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 100, scheduledMinutes: 80), 20)
        
        // Early (live < scheduled)
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 55, scheduledMinutes: 60), -5)
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 80, scheduledMinutes: 100), -20)
    }
    
    func testSignedCircularDelayMinutesMidnightBoundary() {
        // Midnight boundary late: scheduled 23:58 (1438m), live 00:03 (3m) -> +5m late
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 3, scheduledMinutes: 1438), 5)
        
        // Midnight boundary early: scheduled 00:03 (3m), live 23:58 (1438m) -> -5m early
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 1438, scheduledMinutes: 3), -5)
        
        // Scheduled 23:45 (1425m), live 00:10 (10m) -> +25m late
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 10, scheduledMinutes: 1425), 25)
        
        // Scheduled 00:10 (10m), live 23:45 (1425m) -> -25m early
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 1425, scheduledMinutes: 10), -25)
        
        // Constraint check within [-720, +720]
        let maxLate = GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 700, scheduledMinutes: 0)
        XCTAssertEqual(maxLate, 700)
        
        let maxEarly = GTFSMidnightResolver.calculateSignedCircularDelayMinutes(liveMinutes: 0, scheduledMinutes: 700)
        XCTAssertEqual(maxEarly, -700)
    }
    
    func testSignedCircularDelaySeconds() {
        // Same minute
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelaySeconds(liveSeconds: 3600, scheduledSeconds: 3600), 0)
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelaySeconds(liveSeconds: 3645, scheduledSeconds: 3600), 45)
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelaySeconds(liveSeconds: 3555, scheduledSeconds: 3600), -45)
        
        // Midnight transition: scheduled 23:59:30 (86370s), live 00:00:30 (30s) -> +60s late
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelaySeconds(liveSeconds: 30, scheduledSeconds: 86370), 60)
        
        // Midnight transition: scheduled 00:00:30 (30s), live 23:59:30 (86370s) -> -60s early
        XCTAssertEqual(GTFSMidnightResolver.calculateSignedCircularDelaySeconds(liveSeconds: 86370, scheduledSeconds: 30), -60)
    }
    
    func testCalculateWaitTime() {
        // Same-day departure
        XCTAssertEqual(GTFSMidnightResolver.calculateWaitTime(arrivalSeconds: 3600, departureSeconds: 4200), 600)
        XCTAssertEqual(GTFSMidnightResolver.calculateWaitTime(arrivalSeconds: 28800, departureSeconds: 28800), 0)
        
        // Midnight crossing: user arrives at 23:55 (86,100s), trip departs at 01:30 (5,400s)
        // Wait: (86400 - 86100) + 5400 = 300 + 5400 = 5,700s (95 minutes)
        XCTAssertEqual(GTFSMidnightResolver.calculateWaitTime(arrivalSeconds: 86100, departureSeconds: 5400), 5700)
    }
    
    func testNormalizeScheduleTime() {
        // Positive delay
        XCTAssertEqual(GTFSMidnightResolver.normalizeScheduleTime(rawSecondsFromEpoch: 3600, gtfsRtDelaySeconds: 300), 3900)
        
        // Negative delay (early vehicle)
        XCTAssertEqual(GTFSMidnightResolver.normalizeScheduleTime(rawSecondsFromEpoch: 3600, gtfsRtDelaySeconds: -600), 3000)
        
        // Underflow protection
        XCTAssertEqual(GTFSMidnightResolver.normalizeScheduleTime(rawSecondsFromEpoch: 100, gtfsRtDelaySeconds: -500), 0)
    }
    
    func testEpochToMinuteAndSecondOfDay() {
        // Fix timezone to UTC for deterministic verification
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            XCTFail("UTC timezone required")
            return
        }
        
        // 2024-01-01 08:30:15 UTC -> 8h * 3600 + 30m * 60 + 15s = 30615s, minute = 8*60+30 = 510
        let epoch: Int64 = 1704097815
        
        let minuteOfDay = GTFSMidnightResolver.epochToMinuteOfDay(epoch, timeZone: utc)
        let secondOfDay = GTFSMidnightResolver.epochToSecondOfDay(epoch, timeZone: utc)
        
        XCTAssertEqual(minuteOfDay, 510)
        XCTAssertEqual(secondOfDay, 30615)
    }
    
    func testParseGTFSTimeToSeconds() {
        // Standard formats
        XCTAssertEqual(GTFSMidnightResolver.parseGTFSTimeToSeconds("00:00:00"), 0)
        XCTAssertEqual(GTFSMidnightResolver.parseGTFSTimeToSeconds("08:30:00"), 30600)
        XCTAssertEqual(GTFSMidnightResolver.parseGTFSTimeToSeconds("9:15:30"), 33330)
        XCTAssertEqual(GTFSMidnightResolver.parseGTFSTimeToSeconds("23:59:59"), 86399)
        
        // Extended GTFS service hours (> 24h)
        XCTAssertEqual(GTFSMidnightResolver.parseGTFSTimeToSeconds("24:00:00"), 86400)
        XCTAssertEqual(GTFSMidnightResolver.parseGTFSTimeToSeconds("25:30:15"), 91815)
        XCTAssertEqual(GTFSMidnightResolver.parseGTFSTimeToSeconds("28:00:00"), 100800)
        
        // Two-component time (HH:MM)
        XCTAssertEqual(GTFSMidnightResolver.parseGTFSTimeToSeconds("14:30"), 52200)
        
        // Invalid strings
        XCTAssertNil(GTFSMidnightResolver.parseGTFSTimeToSeconds(""))
        XCTAssertNil(GTFSMidnightResolver.parseGTFSTimeToSeconds("invalid"))
        XCTAssertNil(GTFSMidnightResolver.parseGTFSTimeToSeconds("12:65:00"))
        XCTAssertNil(GTFSMidnightResolver.parseGTFSTimeToSeconds("12:30:65"))
        XCTAssertNil(GTFSMidnightResolver.parseGTFSTimeToSeconds("12:30:45:67"))
    }
    
    func testFormatSecondsToGTFSTime() {
        XCTAssertEqual(GTFSMidnightResolver.formatSecondsToGTFSTime(0), "00:00:00")
        XCTAssertEqual(GTFSMidnightResolver.formatSecondsToGTFSTime(30600), "08:30:00")
        XCTAssertEqual(GTFSMidnightResolver.formatSecondsToGTFSTime(86399), "23:59:59")
        XCTAssertEqual(GTFSMidnightResolver.formatSecondsToGTFSTime(86400), "24:00:00")
        XCTAssertEqual(GTFSMidnightResolver.formatSecondsToGTFSTime(91815), "25:30:15")
    }
}
