import Foundation

/// Mathematical resolver for circular time calculations and midnight wrap-around resolution.
///
/// Implements non-negative Euclidean modulo arithmetic and circular signed delay projections
/// across 1,440-minute and 86,400-second periodic intervals without 24-hour phantom delay artifacts.
public struct GTFSMidnightResolver: Sendable {
    
    public static let secondsPerDay: Int64 = 86_400
    public static let minutesPerDay: Int = 1_440
    public static let halfDayMinutes: Int = 720
    public static let halfDaySeconds: Int64 = 43_200
    
    // MARK: - Euclidean Modulo
    
    /// Computes non-negative Euclidean modulo: `(a % n + n) % n`.
    ///
    /// Unlike standard truncated integer division (`%`), Euclidean modulo guarantees that the result
    /// is strictly in the range `[0, |n| - 1]` for all non-zero divisors, including negative dividends.
    ///
    /// - Parameters:
    ///   - a: The dividend (can be positive, negative, or zero).
    ///   - n: The divisor (modulus).
    /// - Returns: The non-negative remainder in `[0, |n| - 1]`, or `0` if `n == 0`.
    @inlinable
    public static func euclideanModulo<T: BinaryInteger>(_ a: T, _ n: T) -> T {
        guard n != 0 else { return 0 }
        let r = a % n
        if r < 0 {
            return n > 0 ? r + n : r - n
        }
        return r
    }
    
    // MARK: - Signed Circular Delay
    
    /// Computes the signed circular delay between a real-time (live) arrival minute and a scheduled minute
    /// constrained to the `[-720, +720]` minute domain on a 1,440-minute clock face.
    ///
    /// Eliminates 24-hour wrap-around inversion at midnight boundaries:
    /// - Scheduled `23:58` (1438m), Live `00:03` (3m) -> `+5m` delay (late)
    /// - Scheduled `00:03` (3m), Live `23:58` (1438m) -> `-5m` delay (early)
    ///
    /// - Parameters:
    ///   - liveMinutes: Live estimated minute of day `[0, 1439]`.
    ///   - scheduledMinutes: Scheduled timetable minute of day `[0, 1439]`.
    /// - Returns: Signed delay in minutes `[-720, +720]`.
    @inlinable
    public static func calculateSignedCircularDelayMinutes(liveMinutes: Int, scheduledMinutes: Int) -> Int {
        let diff = euclideanModulo(liveMinutes - scheduledMinutes + halfDayMinutes, minutesPerDay) - halfDayMinutes
        return diff
    }
    
    /// Convenience alias for `calculateSignedCircularDelayMinutes`.
    @inlinable
    public static func calculateSignedCircularDelay(live: Int, sched: Int) -> Int {
        return calculateSignedCircularDelayMinutes(liveMinutes: live, scheduledMinutes: sched)
    }
    
    /// Computes full-resolution signed circular delay between real-time seconds and scheduled seconds
    /// constrained to the `[-43200, +43200]` second domain on an 86,400-second day face.
    ///
    /// - Parameters:
    ///   - liveSeconds: Live estimated second of day `[0, 86399]` (or epoch timestamps).
    ///   - scheduledSeconds: Scheduled second of day `[0, 86399]` (or epoch timestamps).
    /// - Returns: Signed delay in seconds `[-43200, +43200]`.
    @inlinable
    public static func calculateSignedCircularDelaySeconds(liveSeconds: Int64, scheduledSeconds: Int64) -> Int64 {
        let diff = euclideanModulo(liveSeconds - scheduledSeconds + halfDaySeconds, secondsPerDay) - halfDaySeconds
        return diff
    }
    
    // MARK: - Wait Time & Monotonic Epoch Normalization
    
    /// Computes the forward wait duration across midnight transitions within a 24-hour window.
    ///
    /// - Parameters:
    ///   - arrivalSeconds: Time when user/passenger arrives at the platform (seconds of day).
    ///   - departureSeconds: Time when transit vehicle departs the platform (seconds of day).
    /// - Returns: Positive wait duration in seconds `[0, 86400)`.
    @inlinable
    public static func calculateWaitTime(arrivalSeconds: UInt32, departureSeconds: UInt32) -> UInt32 {
        if departureSeconds >= arrivalSeconds {
            return departureSeconds - arrivalSeconds
        }
        return (departureSeconds + UInt32(secondsPerDay)) - arrivalSeconds
    }
    
    /// Normalizes real-time departure seconds relative to absolute service epoch with underflow protection.
    ///
    /// - Parameters:
    ///   - rawSecondsFromEpoch: Scheduled departure time in seconds from epoch.
    ///   - gtfsRtDelaySeconds: Real-time delay offset in seconds (positive for late, negative for early).
    /// - Returns: Adjusted epoch seconds, clamped to `0` if negative.
    @inlinable
    public static func normalizeScheduleTime(rawSecondsFromEpoch: Int32, gtfsRtDelaySeconds: Int32) -> UInt32 {
        let adjusted = rawSecondsFromEpoch + gtfsRtDelaySeconds
        return adjusted < 0 ? 0 : UInt32(adjusted)
    }
    
    // MARK: - Epoch & GTFS Time Conversions
    
    /// Converts a Unix epoch timestamp to the minute-of-day in the specified timezone `[0, 1439]`.
    public static func epochToMinuteOfDay(_ epoch: Int64, timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        return hour * 60 + minute
    }
    
    /// Converts a Unix epoch timestamp to the second-of-day in the specified timezone `[0, 86399]`.
    public static func epochToSecondOfDay(_ epoch: Int64, timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0
        return hour * 3600 + minute * 60 + second
    }
    
    /// Parses a GTFS timetable time string (`HH:MM:SS` or `H:MM:SS`) into total seconds.
    ///
    /// Supports extended GTFS service hours crossing midnight (e.g. `25:30:00` -> `91800` seconds).
    ///
    /// - Parameter timeString: The GTFS formatted time string.
    /// - Returns: Total seconds from midnight of service date, or `nil` if invalid format.
    public static func parseGTFSTimeToSeconds(_ timeString: String) -> Int? {
        let parts = timeString.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        
        guard let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return nil }
        
        let seconds: Int
        if parts.count == 3 {
            guard let s = Int(parts[2]) else { return nil }
            seconds = s
        } else {
            seconds = 0
        }
        
        guard hours >= 0, minutes >= 0, minutes < 60, seconds >= 0, seconds < 60 else {
            return nil
        }
        
        return hours * 3600 + minutes * 60 + seconds
    }
    
    /// Formats total seconds from service day start into a standard GTFS `HH:MM:SS` string.
    public static func formatSecondsToGTFSTime(_ seconds: Int) -> String {
        let positiveSec = max(0, seconds)
        let h = positiveSec / 3600
        let m = (positiveSec % 3600) / 60
        let s = positiveSec % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
