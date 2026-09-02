import Foundation
import GRDB

/// Dedicated, high-performance async GRDB engine for service disruptions,
/// 15-minute origin dispatch slot profiles, and 168-hour rolling window reliability aggregations.
public final class TransitDatabaseEngine: Sendable {
    public static let shared = TransitDatabaseEngine()
    
    private let dbWriter: (any DatabaseWriter)?
    private let isAttachedMode: Bool
    
    // MARK: - Initializers
    
    /// Initializes TransitDatabaseEngine using an existing GRDB DatabaseWriter (defaults to SpatialDatabaseManager.shared.dbWriter in app context).
    public init(dbWriter: (any DatabaseWriter)? = nil, isAttachedMode: Bool = true) {
        self.dbWriter = dbWriter
        self.isAttachedMode = isAttachedMode
    }
    
    /// Factory for creating an isolated in-memory or file-backed testing instance.
    public static func makeForTesting(inMemory: Bool = true) -> TransitDatabaseEngine {
        var config = Configuration()
        config.qos = .userInitiated
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous = NORMAL;")
            try db.execute(sql: "PRAGMA busy_timeout = 3000;")
        }
        
        do {
            let queue: DatabaseQueue
            if inMemory {
                queue = try DatabaseQueue(configuration: config)
            } else {
                let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let dbURL = tempDir.appendingPathComponent("transit_engine_test_\(UUID().uuidString).sqlite")
                queue = try DatabaseQueue(path: dbURL.path, configuration: config)
            }
            
            try queue.write { db in
                try Self.createTables(in: db)
            }
            
            return TransitDatabaseEngine(dbWriter: queue, isAttachedMode: false)
        } catch {
            fatalError("Failed to initialize test TransitDatabaseEngine: \(error)")
        }
    }
    
    private var activeWriter: any DatabaseWriter {
        if let writer = dbWriter {
            return writer
        }
        return SpatialDatabaseManager.shared.dbWriter
    }
    
    private var schemaPrefix: String {
        isAttachedMode ? "transit." : ""
    }
    
    // MARK: - Table DDL Setup
    
    /// Creates the standard schema for service_disruptions, trip_slot_profiles, and stop_reliability_hourly.
    public static func createTables(in db: Database, schemaPrefix: String = "") throws {
        let p = schemaPrefix.isEmpty ? "" : "\(schemaPrefix)."
        
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS \(p)service_disruptions (
                id TEXT PRIMARY KEY NOT NULL,
                route_id TEXT NOT NULL,
                stop_id TEXT,
                direction_id INTEGER,
                start_epoch INTEGER NOT NULL,
                end_epoch INTEGER NOT NULL,
                disruption_type TEXT NOT NULL,
                summary_text TEXT
            );
            CREATE INDEX IF NOT EXISTS \(p)idx_disruptions_time ON service_disruptions(start_epoch, end_epoch);
            CREATE INDEX IF NOT EXISTS \(p)idx_disruptions_route ON service_disruptions(route_id, direction_id);

            CREATE TABLE IF NOT EXISTS \(p)trip_slot_profiles (
                route_id TEXT NOT NULL,
                direction_id INTEGER NOT NULL,
                origin_slot_index INTEGER NOT NULL,
                stop_id TEXT NOT NULL,
                day_type INTEGER NOT NULL,
                median_duration_sec INTEGER NOT NULL,
                p90_duration_sec INTEGER NOT NULL,
                regularity_pct REAL NOT NULL,
                sample_count INTEGER NOT NULL,
                PRIMARY KEY (route_id, direction_id, origin_slot_index, stop_id, day_type)
            ) WITHOUT ROWID;

            CREATE TABLE IF NOT EXISTS \(p)stop_reliability_hourly (
                stop_id TEXT NOT NULL,
                route_id TEXT NOT NULL,
                direction_id INTEGER NOT NULL,
                hour_of_day INTEGER NOT NULL,
                day_type INTEGER NOT NULL,
                sample_count INTEGER NOT NULL,
                scheduled_count INTEGER NOT NULL,
                sum_actual_headway REAL NOT NULL,
                sum_sq_act_headway REAL NOT NULL,
                sum_sched_headway REAL NOT NULL,
                sum_sq_sch_headway REAL NOT NULL,
                on_time_count INTEGER NOT NULL,
                early_count INTEGER NOT NULL,
                late_count INTEGER NOT NULL,
                p10_delta_q16 INTEGER NOT NULL,
                p50_delta_q16 INTEGER NOT NULL,
                p90_delta_q16 INTEGER NOT NULL,
                p10_headway_q16 INTEGER NOT NULL,
                p50_headway_q16 INTEGER NOT NULL,
                p90_headway_q16 INTEGER NOT NULL,
                PRIMARY KEY (stop_id, route_id, direction_id, hour_of_day, day_type)
            ) WITHOUT ROWID;
        """)
    }

    // MARK: - Service Disruptions Queries
    
    /// Fetches all active service disruptions at a given epoch timestamp.
    public func fetchActiveDisruptions(at epoch: Int64) async throws -> [ServiceDisruptionRecord] {
        let prefix = schemaPrefix
        return try await activeWriter.read { db in
            guard try self.tableExists(named: "service_disruptions", in: db) else {
                return []
            }
            
            let sql = """
                SELECT id, route_id, stop_id, direction_id, start_epoch, end_epoch, disruption_type, summary_text
                FROM \(prefix)service_disruptions
                WHERE start_epoch <= ? AND end_epoch >= ?
                ORDER BY start_epoch ASC
            """
            
            let rows = try Row.fetchAll(db, sql: sql, arguments: [epoch, epoch])
            return rows.map { row in
                let rawId: String = row[0] is String ? row[0] : String(describing: row[0])
                return ServiceDisruptionRecord(
                    id: rawId,
                    routeId: row[1],
                    stopId: row[2],
                    directionId: row[3],
                    startEpoch: row[4],
                    endEpoch: row[5],
                    disruptionType: DisruptionType(rawValueOrUnknown: row[6]),
                    summaryText: row[7]
                )
            }
        }
    }
    
    /// Fetches disruptions matching a route (and optional direction and epoch).
    public func fetchDisruptions(for routeId: String, directionId: Int? = nil, at epoch: Int64? = nil) async throws -> [ServiceDisruptionRecord] {
        let prefix = schemaPrefix
        return try await activeWriter.read { db in
            guard try self.tableExists(named: "service_disruptions", in: db) else {
                return []
            }
            
            var sql = """
                SELECT id, route_id, stop_id, direction_id, start_epoch, end_epoch, disruption_type, summary_text
                FROM \(prefix)service_disruptions
                WHERE route_id = ?
            """
            var args: [DatabaseValueConvertible] = [routeId]
            
            if let dir = directionId {
                sql += " AND (direction_id IS NULL OR direction_id = ?)"
                args.append(dir)
            }
            if let t = epoch {
                sql += " AND start_epoch <= ? AND end_epoch >= ?"
                args.append(t)
                args.append(t)
            }
            sql += " ORDER BY start_epoch ASC"
            
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map { row in
                let rawId: String = row[0] is String ? row[0] : String(describing: row[0])
                return ServiceDisruptionRecord(
                    id: rawId,
                    routeId: row[1],
                    stopId: row[2],
                    directionId: row[3],
                    startEpoch: row[4],
                    endEpoch: row[5],
                    disruptionType: DisruptionType(rawValueOrUnknown: row[6]),
                    summaryText: row[7]
                )
            }
        }
    }
    
    /// Fetches disruptions matching a stop (and optional epoch).
    public func fetchDisruptions(for stopId: String, at epoch: Int64? = nil) async throws -> [ServiceDisruptionRecord] {
        let prefix = schemaPrefix
        return try await activeWriter.read { db in
            guard try self.tableExists(named: "service_disruptions", in: db) else {
                return []
            }
            
            var sql = """
                SELECT id, route_id, stop_id, direction_id, start_epoch, end_epoch, disruption_type, summary_text
                FROM \(prefix)service_disruptions
                WHERE stop_id = ?
            """
            var args: [DatabaseValueConvertible] = [stopId]
            
            if let t = epoch {
                sql += " AND start_epoch <= ? AND end_epoch >= ?"
                args.append(t)
                args.append(t)
            }
            sql += " ORDER BY start_epoch ASC"
            
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map { row in
                let rawId: String = row[0] is String ? row[0] : String(describing: row[0])
                return ServiceDisruptionRecord(
                    id: rawId,
                    routeId: row[1],
                    stopId: row[2],
                    directionId: row[3],
                    startEpoch: row[4],
                    endEpoch: row[5],
                    disruptionType: DisruptionType(rawValueOrUnknown: row[6]),
                    summaryText: row[7]
                )
            }
        }
    }
    
    /// Fetches an in-memory disruption bitmask for all active disruptions at a given epoch.
    public func fetchDisruptionBitmask(at epoch: Int64) async throws -> TransitDisruptionBitmask {
        let active = try await fetchActiveDisruptions(at: epoch)
        return TransitDisruptionBitmask(disruptions: active)
    }
    
    /// Inserts or replaces a list of service disruptions.
    public func insertServiceDisruptions(_ records: [ServiceDisruptionRecord]) async throws {
        guard !records.isEmpty else { return }
        let prefix = schemaPrefix
        try await activeWriter.write { db in
            let sql = """
                INSERT INTO \(prefix)service_disruptions (
                    id, route_id, stop_id, direction_id, start_epoch, end_epoch, disruption_type, summary_text
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    route_id = excluded.route_id,
                    stop_id = excluded.stop_id,
                    direction_id = excluded.direction_id,
                    start_epoch = excluded.start_epoch,
                    end_epoch = excluded.end_epoch,
                    disruption_type = excluded.disruption_type,
                    summary_text = excluded.summary_text;
            """
            let stmt = try db.makeStatement(sql: sql)
            for r in records {
                try stmt.execute(arguments: [
                    r.id,
                    r.routeId,
                    r.stopId,
                    r.directionId,
                    r.startEpoch,
                    r.endEpoch,
                    r.disruptionType.rawValue,
                    r.summaryText
                ])
            }
        }
    }
    
    // MARK: - 15-Minute Origin Dispatch Slot Profiler Queries
    
    /// Fetches a specific origin slot profile for a route, direction, stop, slot index, and day type.
    public func fetchTripSlotProfile(
        routeId: String,
        directionId: Int,
        stopId: String,
        slotIndex: Int,
        dayType: Int
    ) async throws -> TripSlotProfileRecord? {
        let prefix = schemaPrefix
        let clampedSlot = min(max(0, slotIndex), 95)
        let clampedDay = min(max(0, dayType), 2)
        
        return try await activeWriter.read { db in
            guard try self.tableExists(named: "trip_slot_profiles", in: db) else {
                return nil
            }
            
            let sql = """
                SELECT route_id, direction_id, origin_slot_index, stop_id, day_type,
                       median_duration_sec, p90_duration_sec, regularity_pct, sample_count
                FROM \(prefix)trip_slot_profiles
                WHERE route_id = ? AND direction_id = ? AND origin_slot_index = ? AND stop_id = ? AND day_type = ?
                LIMIT 1
            """
            
            guard let row = try Row.fetchOne(db, sql: sql, arguments: [routeId, directionId, clampedSlot, stopId, clampedDay]) else {
                return nil
            }
            
            return TripSlotProfileRecord(
                routeId: row[0],
                directionId: row[1],
                originSlotIndex: row[2],
                stopId: row[3],
                dayType: row[4],
                medianDurationSec: row[5],
                p90DurationSec: row[6],
                regularityPct: row[7],
                sampleCount: row[8]
            )
        }
    }
    
    /// Fetches slot profiles for all stops along a route and direction for a given origin slot.
    public func fetchTripSlotProfiles(
        routeId: String,
        directionId: Int,
        slotIndex: Int,
        dayType: Int
    ) async throws -> [TripSlotProfileRecord] {
        let prefix = schemaPrefix
        let clampedSlot = min(max(0, slotIndex), 95)
        let clampedDay = min(max(0, dayType), 2)
        
        return try await activeWriter.read { db in
            guard try self.tableExists(named: "trip_slot_profiles", in: db) else {
                return []
            }
            
            let sql = """
                SELECT route_id, direction_id, origin_slot_index, stop_id, day_type,
                       median_duration_sec, p90_duration_sec, regularity_pct, sample_count
                FROM \(prefix)trip_slot_profiles
                WHERE route_id = ? AND direction_id = ? AND origin_slot_index = ? AND day_type = ?
                ORDER BY median_duration_sec ASC
            """
            
            let rows = try Row.fetchAll(db, sql: sql, arguments: [routeId, directionId, clampedSlot, clampedDay])
            return rows.map { row in
                TripSlotProfileRecord(
                    routeId: row[0],
                    directionId: row[1],
                    originSlotIndex: row[2],
                    stopId: row[3],
                    dayType: row[4],
                    medianDurationSec: row[5],
                    p90DurationSec: row[6],
                    regularityPct: row[7],
                    sampleCount: row[8]
                )
            }
        }
    }
    
    /// Fetches all slot profiles associated with a given stop across the day.
    public func fetchSlotProfilesForStop(
        stopId: String,
        routeId: String? = nil,
        dayType: Int? = nil
    ) async throws -> [TripSlotProfileRecord] {
        let prefix = schemaPrefix
        return try await activeWriter.read { db in
            guard try self.tableExists(named: "trip_slot_profiles", in: db) else {
                return []
            }
            
            var sql = """
                SELECT route_id, direction_id, origin_slot_index, stop_id, day_type,
                       median_duration_sec, p90_duration_sec, regularity_pct, sample_count
                FROM \(prefix)trip_slot_profiles
                WHERE stop_id = ?
            """
            var args: [DatabaseValueConvertible] = [stopId]
            
            if let rId = routeId {
                sql += " AND route_id = ?"
                args.append(rId)
            }
            if let dt = dayType {
                sql += " AND day_type = ?"
                args.append(dt)
            }
            sql += " ORDER BY origin_slot_index ASC"
            
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map { row in
                TripSlotProfileRecord(
                    routeId: row[0],
                    directionId: row[1],
                    originSlotIndex: row[2],
                    stopId: row[3],
                    dayType: row[4],
                    medianDurationSec: row[5],
                    p90DurationSec: row[6],
                    regularityPct: row[7],
                    sampleCount: row[8]
                )
            }
        }
    }
    
    /// Inserts or replaces a collection of trip slot profiles.
    public func insertTripSlotProfiles(_ records: [TripSlotProfileRecord]) async throws {
        guard !records.isEmpty else { return }
        let prefix = schemaPrefix
        try await activeWriter.write { db in
            let sql = """
                INSERT INTO \(prefix)trip_slot_profiles (
                    route_id, direction_id, origin_slot_index, stop_id, day_type,
                    median_duration_sec, p90_duration_sec, regularity_pct, sample_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(route_id, direction_id, origin_slot_index, stop_id, day_type) DO UPDATE SET
                    median_duration_sec = excluded.median_duration_sec,
                    p90_duration_sec = excluded.p90_duration_sec,
                    regularity_pct = excluded.regularity_pct,
                    sample_count = excluded.sample_count;
            """
            let stmt = try db.makeStatement(sql: sql)
            for r in records {
                try stmt.execute(arguments: [
                    r.routeId,
                    r.directionId,
                    r.originSlotIndex,
                    r.stopId,
                    r.dayType,
                    r.medianDurationSec,
                    r.p90DurationSec,
                    r.regularityPct,
                    r.sampleCount
                ])
            }
        }
    }

    // MARK: - Historical Reliability & 168-Hour Window Aggregations

    /// Fetches hourly reliability records with pre-squared moment sums for a stop.
    public func fetchHourlyReliability(
        stopId: String,
        routeId: String? = nil,
        directionId: Int? = nil,
        dayType: Int? = nil
    ) async throws -> [HourlyReliabilityRecord] {
        let prefix = schemaPrefix
        return try await activeWriter.read { db in
            guard try self.tableExists(named: "stop_reliability_hourly", in: db) else {
                return []
            }
            
            // Check table schema for modern moment columns vs legacy schema
            let columns = try Row.fetchAll(db, sql: "PRAGMA \(prefix)table_info(stop_reliability_hourly)")
            let columnNames = Set(columns.compactMap { $0["name"] as? String })
            let isModernSchema = columnNames.contains("sum_actual_headway")
            
            if isModernSchema {
                var sql = """
                    SELECT stop_id, route_id, direction_id, hour_of_day, day_type,
                           sample_count, scheduled_count,
                           sum_actual_headway, sum_sq_act_headway,
                           sum_sched_headway, sum_sq_sch_headway,
                           on_time_count, early_count, late_count,
                           p10_delta_q16, p50_delta_q16, p90_delta_q16,
                           p10_headway_q16, p50_headway_q16, p90_headway_q16
                    FROM \(prefix)stop_reliability_hourly
                    WHERE stop_id = ?
                """
                var args: [DatabaseValueConvertible] = [stopId]
                
                if let rId = routeId, !rId.isEmpty {
                    sql += " AND route_id = ?"
                    args.append(rId)
                }
                if let dir = directionId {
                    sql += " AND direction_id = ?"
                    args.append(dir)
                }
                if let dt = dayType {
                    sql += " AND day_type = ?"
                    args.append(dt)
                }
                sql += " ORDER BY day_type ASC, hour_of_day ASC"
                
                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    HourlyReliabilityRecord(
                        stopId: row[0],
                        routeId: row[1],
                        directionId: row[2],
                        hourOfDay: row[3],
                        dayType: row[4],
                        sampleCount: row[5],
                        scheduledCount: row[6],
                        sumActualHeadway: row[7],
                        sumSqActualHeadway: row[8],
                        sumSchedHeadway: row[9],
                        sumSqSchedHeadway: row[10],
                        onTimeCount: row[11],
                        earlyCount: row[12],
                        lateCount: row[13],
                        p10DeltaQ16: row[14],
                        p50DeltaQ16: row[15],
                        p90DeltaQ16: row[16],
                        p10HeadwayQ16: row[17],
                        p50HeadwayQ16: row[18],
                        p90HeadwayQ16: row[19]
                    )
                }
            } else {
                // Graceful fallback for legacy table schema
                var sql = """
                    SELECT route_id, stop_id, direction_id, hour_of_day, day_of_week,
                           median_delay_sec, p90_delay_sec, median_headway_sec, headway_stddev_sec,
                           ewt_seconds, on_time_pct, sample_count
                    FROM \(prefix)stop_reliability_hourly
                    WHERE stop_id = ?
                """
                var args: [DatabaseValueConvertible] = [stopId]
                if let rId = routeId, !rId.isEmpty {
                    sql += " AND route_id = ?"
                    args.append(rId)
                }
                if let dir = directionId {
                    sql += " AND direction_id = ?"
                    args.append(dir)
                }
                sql += " ORDER BY day_of_week ASC, hour_of_day ASC"
                
                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    let rId: String = row[0]
                    let sId: String = row[1]
                    let dir: Int = row[2] ?? 0
                    let hour: Int = row[3]
                    let dow: Int = row[4]
                    let medDelay: Double = row[5]
                    let p90Delay: Double = row[6]
                    let medHeadway: Double = row[7] ?? 300.0
                    let stdDev: Double = row[8] ?? 60.0
                    let ewtSec: Double = row[9] ?? 60.0
                    let onTimePct: Double = row[10]
                    let count: Int = row[11]
                    
                    let actH = medHeadway * Double(count)
                    let actHSq = (pow(medHeadway, 2) + pow(stdDev, 2)) * Double(count)
                    let schH = medHeadway * Double(count)
                    let schHSq = pow(medHeadway, 2) * Double(count)
                    let onTimeCnt = Int(round((onTimePct / 100.0) * Double(count)))
                    let lateCnt = count - onTimeCnt
                    
                    return HourlyReliabilityRecord(
                        stopId: sId,
                        routeId: rId,
                        directionId: dir,
                        hourOfDay: hour,
                        dayType: dow % 3,
                        sampleCount: count,
                        scheduledCount: count,
                        sumActualHeadway: actH,
                        sumSqActualHeadway: actHSq,
                        sumSchedHeadway: schH,
                        sumSqSchedHeadway: schHSq,
                        onTimeCount: onTimeCnt,
                        earlyCount: 0,
                        lateCount: lateCnt,
                        p10DeltaQ16: Int32(ReliabilityQuantizer.quantize(medDelay * 0.4)),
                        p50DeltaQ16: Int32(ReliabilityQuantizer.quantize(medDelay)),
                        p90DeltaQ16: Int32(ReliabilityQuantizer.quantize(p90Delay)),
                        p10HeadwayQ16: Int32(ReliabilityQuantizer.quantize(medHeadway * 0.5)),
                        p50HeadwayQ16: Int32(ReliabilityQuantizer.quantize(medHeadway)),
                        p90HeadwayQ16: Int32(ReliabilityQuantizer.quantize(medHeadway + stdDev * 1.645))
                    )
                }
            }
        }
    }
    
    /// Fetches the full 168-hour reliability matrix (or 72 entries across 3 day-types) for a stop.
    public func fetch168HourReliabilityMatrix(
        stopId: String,
        routeId: String? = nil,
        directionId: Int? = nil
    ) async throws -> [HourlyReliabilityRecord] {
        return try await fetchHourlyReliability(stopId: stopId, routeId: routeId, directionId: directionId, dayType: nil)
    }
    
    /// Aggregates multiple hourly records in O(1) time using pre-squared algebraic moments.
    public func aggregateReliability(records: [HourlyReliabilityRecord]) -> ReliabilityAggregationSummary {
        return ReliabilityAggregationSummary(records: records)
    }
    
    /// Evaluates aggregated reliability metrics over an arbitrary hour range and day type set in O(1).
    public func aggregateReliability(
        stopId: String,
        routeId: String? = nil,
        directionId: Int? = nil,
        startHour: Int,
        endHour: Int,
        dayTypes: [Int] = [0, 1, 2]
    ) async throws -> ReliabilityAggregationSummary {
        let allRecords = try await fetchHourlyReliability(stopId: stopId, routeId: routeId, directionId: directionId)
        let filtered = allRecords.filter { r in
            let matchesHour: Bool
            if startHour <= endHour {
                matchesHour = r.hourOfDay >= startHour && r.hourOfDay <= endHour
            } else {
                matchesHour = r.hourOfDay >= startHour || r.hourOfDay <= endHour
            }
            return matchesHour && dayTypes.contains(r.dayType)
        }
        return aggregateReliability(records: filtered)
    }
    
    /// Populates a 4,320-element Float CanvasReliabilityBufferContainer directly for 120Hz rendering.
    public func populateReliabilityBuffer(
        stopId: String,
        routeId: String? = nil,
        container: CanvasReliabilityBufferContainer
    ) async throws {
        let records = try await fetchHourlyReliability(stopId: stopId, routeId: routeId)
        container.populate(from: records)
    }
    
    /// Inserts or replaces a batch of hourly reliability records.
    public func insertHourlyReliability(_ records: [HourlyReliabilityRecord]) async throws {
        guard !records.isEmpty else { return }
        let prefix = schemaPrefix
        try await activeWriter.write { db in
            let sql = """
                INSERT INTO \(prefix)stop_reliability_hourly (
                    stop_id, route_id, direction_id, hour_of_day, day_type,
                    sample_count, scheduled_count,
                    sum_actual_headway, sum_sq_act_headway,
                    sum_sched_headway, sum_sq_sch_headway,
                    on_time_count, early_count, late_count,
                    p10_delta_q16, p50_delta_q16, p90_delta_q16,
                    p10_headway_q16, p50_headway_q16, p90_headway_q16
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(stop_id, route_id, direction_id, hour_of_day, day_type) DO UPDATE SET
                    sample_count = excluded.sample_count,
                    scheduled_count = excluded.scheduled_count,
                    sum_actual_headway = excluded.sum_actual_headway,
                    sum_sq_act_headway = excluded.sum_sq_act_headway,
                    sum_sched_headway = excluded.sum_sched_headway,
                    sum_sq_sch_headway = excluded.sum_sq_sch_headway,
                    on_time_count = excluded.on_time_count,
                    early_count = excluded.early_count,
                    late_count = excluded.late_count,
                    p10_delta_q16 = excluded.p10_delta_q16,
                    p50_delta_q16 = excluded.p50_delta_q16,
                    p90_delta_q16 = excluded.p90_delta_q16,
                    p10_headway_q16 = excluded.p10_headway_q16,
                    p50_headway_q16 = excluded.p50_headway_q16,
                    p90_headway_q16 = excluded.p90_headway_q16;
            """
            let stmt = try db.makeStatement(sql: sql)
            for r in records {
                try stmt.execute(arguments: [
                    r.stopId,
                    r.routeId,
                    r.directionId,
                    r.hourOfDay,
                    r.dayType,
                    r.sampleCount,
                    r.scheduledCount,
                    r.sumActualHeadway,
                    r.sumSqActualHeadway,
                    r.sumSchedHeadway,
                    r.sumSqSchedHeadway,
                    r.onTimeCount,
                    r.earlyCount,
                    r.lateCount,
                    r.p10DeltaQ16,
                    r.p50DeltaQ16,
                    r.p90DeltaQ16,
                    r.p10HeadwayQ16,
                    r.p50HeadwayQ16,
                    r.p90HeadwayQ16
                ])
            }
        }
    }
    
    // MARK: - Internal Helpers
    
    private func tableExists(named tableName: String, in db: Database) throws -> Bool {
        let prefix = schemaPrefix
        let pragma = prefix.isEmpty ? "PRAGMA table_info(\(tableName))" : "PRAGMA \(prefix)table_info(\(tableName))"
        let cols = try Row.fetchAll(db, sql: pragma)
        return !cols.isEmpty
    }
}
