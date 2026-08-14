import Foundation
import GRDB
import CoreLocation
import H3

final class SpatialDatabaseManager: @unchecked Sendable {
    static let shared = SpatialDatabaseManager()
    
    let dbWriter: any DatabaseWriter
    
    var configuredQoS: DispatchQoS {
        dbWriter.configuration.qos
    }
    
#if DEBUG
    static func makeForTesting(inMemory: Bool = true, customTransitURL: URL? = nil) -> SpatialDatabaseManager {
        SpatialDatabaseManager(inMemory: inMemory, customTransitURL: customTransitURL)
    }
#endif

    private init(inMemory: Bool = false, customTransitURL: URL? = nil) {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let databaseURL = appSupportURL.appendingPathComponent("derivee_spatial.sqlite")
            let transitDBURL = customTransitURL ?? appSupportURL.appendingPathComponent("derivee_transit.sqlite")
            let neighborhoodDBURL = appSupportURL.appendingPathComponent("derivee_neighborhood.sqlite")
            
            if customTransitURL == nil {
                Self.copyBundleDatabaseIfNeeded(bundleResourceNames: ["transit_delta", "derivee_transit"], targetURL: transitDBURL, fileManager: fileManager)
            }
            
            Self.copyBundleDatabaseIfNeeded(bundleResourceNames: ["neighborhood"], targetURL: neighborhoodDBURL, fileManager: fileManager)

            
            var configuration = Configuration()
            configuration.qos = .userInitiated
            // Setting pragmas as specified in the blueprint
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA synchronous = NORMAL;")
                try db.execute(sql: "PRAGMA busy_timeout = 5000;")
                
                if fileManager.fileExists(atPath: transitDBURL.path) {
                    do {
                        try db.execute(sql: "ATTACH DATABASE '\(transitDBURL.path)' AS transit")
                        print("Successfully attached transit database")
                    } catch {
                        print("⚠️ Failed to attach transit DB: \(error)")
                    }
                } else {
                    print("⚠️ No transit DB file to attach at \(transitDBURL)")
                }
                
                if fileManager.fileExists(atPath: neighborhoodDBURL.path) {
                    do {
                        try db.execute(sql: "ATTACH DATABASE '\(neighborhoodDBURL.path)' AS neighborhood")
                        print("Successfully attached neighborhood database")
                    } catch {
                        print("⚠️ Failed to attach neighborhood DB: \(error)")
                    }
                } else {
                    print("⚠️ No neighborhood DB file to attach at \(neighborhoodDBURL)")
                }
            }
            
            if inMemory {
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("derivee_test_\(UUID().uuidString).sqlite")
                dbWriter = try DatabasePool(path: tempURL.path, configuration: configuration)
            } else {
                dbWriter = try DatabasePool(path: databaseURL.path, configuration: configuration)
            }
            try migrator.migrate(dbWriter)
            print("🏦 [SpatialDatabaseManager] init complete for pool: \(ObjectIdentifier(dbWriter as AnyObject))")
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
    
    private static func copyBundleDatabaseIfNeeded(bundleResourceNames: [String], targetURL: URL, fileManager: FileManager) {
        var sourceURL: URL? = nil
        for name in bundleResourceNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "sqlite") {
                sourceURL = url
                break
            }
        }
        
        guard let bundleURL = sourceURL else {
            print("⚠️ Could not find \(bundleResourceNames.joined(separator: "/")).sqlite in main bundle")
            return
        }
        
        var shouldCopy = false
        if !fileManager.fileExists(atPath: targetURL.path) {
            shouldCopy = true
        } else {
            // 1. Compare modification dates between bundle asset and cached local file
            do {
                let bundleAttrs = try fileManager.attributesOfItem(atPath: bundleURL.path)
                let targetAttrs = try fileManager.attributesOfItem(atPath: targetURL.path)
                if let bundleDate = bundleAttrs[.modificationDate] as? Date,
                   let targetDate = targetAttrs[.modificationDate] as? Date,
                   bundleDate > targetDate {
                    print("Bundle \(bundleURL.lastPathComponent) is newer than local copy (\(bundleDate) > \(targetDate)). Updating...")
                    shouldCopy = true
                }
            } catch {
                shouldCopy = true
            }
            
            // 2. Schema integrity check for neighborhood database specifically
            if !shouldCopy && bundleResourceNames.contains("neighborhood") {
                do {
                    let dbQueue = try DatabaseQueue(path: targetURL.path)
                    let hasCentroid = try dbQueue.read { db in
                        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(neighborhood_stats)")
                        return rows.contains { ($0["name"] as? String) == "centroid_lat" }
                    }
                    if !hasCentroid {
                        print("Local neighborhood DB is missing centroid_lat column. Re-copying from bundle...")
                        shouldCopy = true
                    }
                } catch {
                    print("Failed to inspect local neighborhood DB schema: \(error). Re-copying...")
                    shouldCopy = true
                }
            }
        }
        
        if shouldCopy {
            do {
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.copyItem(at: bundleURL, to: targetURL)
                print("Successfully copied \(bundleURL.lastPathComponent) to \(targetURL)")
            } catch {
                print("⚠️ Failed to copy \(bundleURL.lastPathComponent): \(error)")
            }
        }
    }

    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            try db.create(table: "explored_hexes") { t in
                t.column("h3_index", .text).primaryKey()
            }
        }
        
        migrator.registerMigration("v2") { db in
            try db.create(table: "meta", options: .withoutRowID) { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }
        }
        
        migrator.registerMigration("v3") { db in
            try db.create(table: "discovered_pois", options: .withoutRowID) { t in
                t.column("poi_id", .text).primaryKey()
            }
        }
        
        migrator.registerMigration("v4") { db in
            // Rebuild explored_hexes to remove WITHOUT ROWID (fixes GRDB tracking bug)
            try db.create(table: "explored_hexes_new") { t in
                t.column("h3_index", .text).primaryKey()
            }
            try db.execute(sql: "INSERT INTO explored_hexes_new SELECT * FROM explored_hexes")
            try db.drop(table: "explored_hexes")
            try db.rename(table: "explored_hexes_new", to: "explored_hexes")
        }
        
        return migrator
    }
    
    // Asynchronous write
    @discardableResult
    func insertDiscoveredHex(h3Index: String) async throws -> Bool {
        return try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO explored_hexes (h3_index)
                VALUES (?)
            """, arguments: [h3Index])
            return db.changesCount > 0
        }
    }
    
    func isHydrationComplete() async throws -> Bool {
        return try await dbWriter.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM meta WHERE key = 'hydration_complete' AND value = '1'") ?? 0
            return count > 0
        }
    }
    
    func setHydrationComplete() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('hydration_complete', '1')")
        }
    }
    
    func clearLocalCache() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM meta WHERE key = 'hydration_complete'")
        }
    }
    
    func resetExplorationData() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM explored_hexes")
            try db.execute(sql: "DELETE FROM discovered_pois")
        }
    }
    
    func insertHexesBatch(h3Indices: [String]) async throws {
        try await dbWriter.write { db in
            for index in h3Indices {
                try db.execute(sql: "INSERT OR IGNORE INTO explored_hexes (h3_index) VALUES (?)", arguments: [index])
            }
        }
    }
    
    func loadDiscoveredPOIs() async throws -> Set<String> {
        return try await dbWriter.read { db in
            let rows = try String.fetchAll(db, sql: "SELECT poi_id FROM discovered_pois")
            return Set(rows)
        }
    }
    
    func insertDiscoveredPOI(_ id: String) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO discovered_pois (poi_id) VALUES (?)", arguments: [id])
        }
    }
    
    struct NeighborhoodProgress: Identifiable {
        let id: String
        let name: String
        let clearedHexes: Int
        let totalHexes: Int
        let centroidLat: Double
        let centroidLng: Double
        
        var percentage: Double {
            guard totalHexes > 0 else { return 0 }
            return (Double(clearedHexes) / Double(totalHexes)) * 100.0
        }
    }
    
    func fetchNeighborhoodProgression() async throws -> [NeighborhoodProgress] {
        return try await dbWriter.read { db in
            let statsRows = try Row.fetchAll(db, sql: "SELECT id, name, total_hexes, centroid_lat, centroid_lng FROM neighborhood.neighborhood_stats")
            let clearedRows = try Row.fetchAll(db, sql: """
            SELECT nh.neighborhood_id, COUNT(eh.h3_index) as cleared_hexes
            FROM explored_hexes eh
            CROSS JOIN neighborhood.neighborhood_hexes nh ON eh.h3_index = nh.h3_index
            GROUP BY nh.neighborhood_id
            """)
            
            var clearedMap: [String: Int] = [:]
            for row in clearedRows {
                let nid: String = row["neighborhood_id"]
                let count: Int = row["cleared_hexes"]
                clearedMap[nid] = count
            }
            
            let list = statsRows.map { row -> NeighborhoodProgress in
                let nid: String = row["id"]
                let total: Int = row["total_hexes"]
                let name: String = row["name"]
                let lat: Double = row["centroid_lat"]
                let lng: Double = row["centroid_lng"]
                let cleared = clearedMap[nid] ?? 0
                return NeighborhoodProgress(
                    id: nid,
                    name: name,
                    clearedHexes: cleared,
                    totalHexes: max(1, total),
                    centroidLat: lat,
                    centroidLng: lng
                )
            }
            
            return list.sorted {
                let p1 = Double($0.clearedHexes) / Double($0.totalHexes)
                let p2 = Double($1.clearedHexes) / Double($1.totalHexes)
                if p1 != p2 { return p1 > p2 }
                return $0.name < $1.name
            }
        }
    }
    
    func fetchNeighborhoodName(for h3Index: String) async throws -> String? {
        return try await dbWriter.read { db in
            let sql = """
            SELECT ns.name
            FROM neighborhood.neighborhood_hexes nh
            JOIN neighborhood.neighborhood_stats ns ON nh.neighborhood_id = ns.id
            WHERE nh.h3_index = ?
            """
            return try String.fetchOne(db, sql: sql, arguments: [h3Index])
        }
    }
    
    func fetchExplorationJournalData() async throws -> ExplorationJournalData {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchExplorationJournalData executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        return try await dbWriter.read { db in
            // 1. Fetch all explored hexes and discovered POIs
            let exploredHexes = Set(try String.fetchAll(db, sql: "SELECT h3_index FROM explored_hexes"))
            let discoveredPOIs = Set(try String.fetchAll(db, sql: "SELECT poi_id FROM discovered_pois"))
            
            // 2. Fetch neighborhood stats and cleared counts via fast indexed join
            let statsRows = try Row.fetchAll(db, sql: "SELECT id, name, total_hexes FROM neighborhood.neighborhood_stats")
            let clearedRows = try Row.fetchAll(db, sql: """
            SELECT nh.neighborhood_id, COUNT(eh.h3_index) as cleared_hexes
            FROM explored_hexes eh
            CROSS JOIN neighborhood.neighborhood_hexes nh ON eh.h3_index = nh.h3_index
            GROUP BY nh.neighborhood_id
            """)
            
            var clearedMap: [String: Int] = [:]
            for row in clearedRows {
                let nid: String = row["neighborhood_id"]
                let count: Int = row["cleared_hexes"]
                clearedMap[nid] = count
            }
            
            var boroughClearedMap: [String: Int] = ["MN": 0, "BK": 0, "QN": 0, "BX": 0, "SI": 0]
            var boroughTotalMap: [String: Int] = ["MN": 0, "BK": 0, "QN": 0, "BX": 0, "SI": 0]
            var boroughNbhdCountMap: [String: Int] = ["MN": 0, "BK": 0, "QN": 0, "BX": 0, "SI": 0]
            var boroughExploredNbhdCountMap: [String: Int] = ["MN": 0, "BK": 0, "QN": 0, "BX": 0, "SI": 0]
            
            var totalCityHexes = 0
            var totalExploredNbhdsCount = 0
            var totalNbhdsCount = 0
            
            for row in statsRows {
                let id: String = row["id"]
                let total: Int = row["total_hexes"]
                let bCode = String(id.prefix(2)).uppercased()
                let cleared = clearedMap[id] ?? 0
                
                boroughTotalMap[bCode, default: 0] += total
                boroughClearedMap[bCode, default: 0] += cleared
                boroughNbhdCountMap[bCode, default: 0] += 1
                totalNbhdsCount += 1
                
                if cleared > 0 {
                    boroughExploredNbhdCountMap[bCode, default: 0] += 1
                    totalExploredNbhdsCount += 1
                }
                
                totalCityHexes += total
            }
            
            if totalCityHexes == 0 {
                totalCityHexes = 362118 // Fallback total NYC walkable landmass hex count
            }
            
            let boroughNames: [(code: String, name: String)] = [
                ("MN", "Manhattan"),
                ("BK", "Brooklyn"),
                ("QN", "Queens"),
                ("BX", "Bronx"),
                ("SI", "Staten Island")
            ]
            
            let boroughProgressList: [BoroughProgress] = boroughNames.map { item in
                BoroughProgress(
                    id: item.code,
                    name: item.name,
                    clearedHexes: boroughClearedMap[item.code] ?? 0,
                    totalHexes: max(1, boroughTotalMap[item.code] ?? 1),
                    neighborhoodCount: boroughNbhdCountMap[item.code] ?? 0,
                    exploredNeighborhoodCount: boroughExploredNbhdCountMap[item.code] ?? 0
                )
            }
            
            let totalClearedHexes = exploredHexes.count
            let overallCityPercentage = totalCityHexes > 0 ? min(100.0, (Double(totalClearedHexes) / Double(totalCityHexes)) * 100.0) : 0.0
            
            // 3. Transit Hubs milestone computation
            var totalTransitStations = 496
            var unlockedTransitStations = 0
            
            do {
                let stopsSQL = "SELECT stop_id, stop_lat, stop_lon FROM transit.stops WHERE location_type = 1"
                let stopRows = try Row.fetchAll(db, sql: stopsSQL)
                if !stopRows.isEmpty {
                    totalTransitStations = stopRows.count
                    
                    // Precompute coordinates of explored hexes for ultra-fast spatial bounding-box filtering
                    var exploredCoords: [(lat: Double, lon: Double)] = []
                    for hStr in exploredHexes {
                        if let cell = UInt64(hStr, radix: 16), let coord = try? H3.cellToLatLng(cell: cell) {
                            exploredCoords.append((lat: coord.latitude, lon: coord.longitude))
                        }
                    }
                    
                    for stopRow in stopRows {
                        let stopId: String = stopRow["stop_id"]
                        let lat: Double = stopRow["stop_lat"]
                        let lon: Double = stopRow["stop_lon"]
                        if discoveredPOIs.contains(stopId) {
                            unlockedTransitStations += 1
                        } else if !exploredCoords.isEmpty {
                            // Fast bounding-box pre-filter (~50m delta) to avoid hundreds of expensive H3 conversions
                            let isNearExploredHex = exploredCoords.contains { abs(lat - $0.lat) < 0.0006 && abs(lon - $0.lon) < 0.0006 }
                            if isNearExploredHex {
                                let h3 = POIMaskManager.computeH3Index(latitude: lat, longitude: lon)
                                if exploredHexes.contains(h3) {
                                    unlockedTransitStations += 1
                                }
                            }
                        }
                    }
                }
            } catch {
                unlockedTransitStations = discoveredPOIs.count
            }
            
            let transitTiers: [MilestoneTier] = [
                MilestoneTier(category: .transitHubs, tierNumber: 1, title: "First Connection", requirementDescription: "Discover your first rail or subway station", targetCount: 1, badgeIconName: "tram.fill", isUnlocked: unlockedTransitStations >= 1),
                MilestoneTier(category: .transitHubs, tierNumber: 2, title: "Commuter", requirementDescription: "Connect 10 transit stations to the explored grid", targetCount: 10, badgeIconName: "figure.walk.arrival", isUnlocked: unlockedTransitStations >= 10),
                MilestoneTier(category: .transitHubs, tierNumber: 3, title: "Metro Explorer", requirementDescription: "Unlock 50 stations across multiple lines", targetCount: 50, badgeIconName: "map.fill", isUnlocked: unlockedTransitStations >= 50),
                MilestoneTier(category: .transitHubs, tierNumber: 4, title: "Transit Navigator", requirementDescription: "Discover 100 stations across the rail network", targetCount: 100, badgeIconName: "arrow.triangle.swap", isUnlocked: unlockedTransitStations >= 100),
                MilestoneTier(category: .transitHubs, tierNumber: 5, title: "Subway Maestro", requirementDescription: "Unlock 250 stations across New York City", targetCount: 250, badgeIconName: "star.fill", isUnlocked: unlockedTransitStations >= 250)
            ]
            
            let transitProgress = MilestoneProgress(
                category: .transitHubs,
                currentCount: unlockedTransitStations,
                totalCount: totalTransitStations,
                tiers: transitTiers
            )
            
            // 4. Neighborhood Voyager milestone computation
            let totalBoroughsVisited = boroughProgressList.filter { $0.exploredNeighborhoodCount > 0 }.count
            let voyagerTiers: [MilestoneTier] = [
                MilestoneTier(category: .neighborhoodVoyager, tierNumber: 1, title: "Local Drifter", requirementDescription: "Explore your very first neighborhood", targetCount: 1, badgeIconName: "location.fill", isUnlocked: totalExploredNbhdsCount >= 1),
                MilestoneTier(category: .neighborhoodVoyager, tierNumber: 2, title: "Borough Stepper", requirementDescription: "Explore neighborhoods in at least 3 boroughs", targetCount: 3, badgeIconName: "signpost.right.and.left.fill", isUnlocked: totalBoroughsVisited >= 3),
                MilestoneTier(category: .neighborhoodVoyager, tierNumber: 3, title: "Urban Cartographer", requirementDescription: "Map out 10 unique neighborhoods", targetCount: 10, badgeIconName: "square.grid.3x3.fill", isUnlocked: totalExploredNbhdsCount >= 10),
                MilestoneTier(category: .neighborhoodVoyager, tierNumber: 4, title: "Borough Master", requirementDescription: "Explore 25 neighborhoods across the city", targetCount: 25, badgeIconName: "globe.americas.fill", isUnlocked: totalExploredNbhdsCount >= 25),
                MilestoneTier(category: .neighborhoodVoyager, tierNumber: 5, title: "Metropolis Legend", requirementDescription: "Discover 50+ neighborhoods across all 5 boroughs", targetCount: 50, badgeIconName: "crown.fill", isUnlocked: totalExploredNbhdsCount >= 50 && totalBoroughsVisited == 5)
            ]
            
            let voyagerProgress = MilestoneProgress(
                category: .neighborhoodVoyager,
                currentCount: totalExploredNbhdsCount,
                totalCount: max(1, totalNbhdsCount),
                tiers: voyagerTiers
            )
            
            // 5. Historic Landmarks milestone computation
            let landmarkCatalog = HistoricLandmarkCatalog.landmarks
            var landmarksList: [LandmarkDiscovery] = []
            var unlockedLandmarksCount = 0
            
            for item in landmarkCatalog {
                let h3 = item.h3Index
                let isDiscovered = exploredHexes.contains(h3) || discoveredPOIs.contains(item.id)
                if isDiscovered {
                    unlockedLandmarksCount += 1
                }
                landmarksList.append(LandmarkDiscovery(
                    id: item.id,
                    name: item.name,
                    borough: item.borough,
                    category: item.category,
                    landmarkDescription: item.description,
                    h3Index: h3,
                    coordinate: item.coordinate,
                    isDiscovered: isDiscovered
                ))
            }
            
            let landmarkTiers: [MilestoneTier] = [
                MilestoneTier(category: .historicLandmarks, tierNumber: 1, title: "Sightseer", requirementDescription: "Discover your first historic NYC landmark", targetCount: 1, badgeIconName: "camera.fill", isUnlocked: unlockedLandmarksCount >= 1),
                MilestoneTier(category: .historicLandmarks, tierNumber: 2, title: "Cultural Wanderer", requirementDescription: "Uncover 3 architectural or cultural anchors", targetCount: 3, badgeIconName: "paintpalette.fill", isUnlocked: unlockedLandmarksCount >= 3),
                MilestoneTier(category: .historicLandmarks, tierNumber: 3, title: "Urban Historian", requirementDescription: "Map out 7 iconic city monuments", targetCount: 7, badgeIconName: "books.vertical.fill", isUnlocked: unlockedLandmarksCount >= 7),
                MilestoneTier(category: .historicLandmarks, tierNumber: 4, title: "Master Archivist", requirementDescription: "Discover 12 historic landmarks across the boroughs", targetCount: 12, badgeIconName: "scroll.fill", isUnlocked: unlockedLandmarksCount >= 12),
                MilestoneTier(category: .historicLandmarks, tierNumber: 5, title: "Living Monument", requirementDescription: "Discover all 20 curated landmarks in the city", targetCount: 20, badgeIconName: "sparkles", isUnlocked: unlockedLandmarksCount >= 20)
            ]
            
            let landmarkProgress = MilestoneProgress(
                category: .historicLandmarks,
                currentCount: unlockedLandmarksCount,
                totalCount: landmarkCatalog.count,
                tiers: landmarkTiers
            )
            
            return ExplorationJournalData(
                totalClearedHexes: totalClearedHexes,
                totalCityHexes: totalCityHexes,
                cityPercentage: overallCityPercentage,
                milestoneCards: [transitProgress, voyagerProgress, landmarkProgress],
                boroughProgress: boroughProgressList,
                landmarks: landmarksList
            )
        }
    }
    
    struct StopDetails {
        let stopId: String
        let name: String
        let routeId: String
        let routeType: Int
        let arrivals: [ArrivalInfo]
    }
    
    struct ArrivalInfo: Identifiable {
        let id = UUID()
        let line: String
        let destination: String
        let minutes: Int
    }
    
    func fetchStopDetails(for stopId: String) async throws -> StopDetails {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchStopDetails for \(stopId) executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        return try await dbWriter.read { db in
            do {
                if let row = try Row.fetchOne(db, sql: "SELECT stop_name FROM transit.stops WHERE stop_id = ?", arguments: [stopId]) {
                    let name: String = row["stop_name"]
                    let routeType = 1
                    let routeId = self.inferRouteId(from: stopId, name: name)
                    
                    let arrivals = self.generateArrivals(for: routeId)
                    return StopDetails(stopId: stopId, name: name, routeId: routeId, routeType: routeType, arrivals: arrivals)
                }
            } catch let error as DatabaseError {
                print("⚠️ Transit DB table missing or unattached: \(error.message). Using fallback.")
            } catch {
                throw error
            }
            
            return StopDetails(
                stopId: stopId,
                name: "Transit Station (\(stopId))",
                routeId: "L",
                routeType: 1,
                arrivals: [
                    ArrivalInfo(line: "L", destination: "Manhattan - 8th Ave", minutes: 3),
                    ArrivalInfo(line: "L", destination: "Brooklyn - Rockaway Pkwy", minutes: 7)
                ]
            )
        }
    }
    
    func fetchHeadwayData(for stopId: String) async throws -> [Double] {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchHeadwayData for \(stopId) executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        return try await dbWriter.read { db in
            do {
                // Attempt query against transit delta historical headway table if available
                let sql = "SELECT headway_min FROM transit.headway_history WHERE stop_id = ? ORDER BY day_offset ASC LIMIT 7"
                let rows = try Double.fetchAll(db, sql: sql, arguments: [stopId])
                if !rows.isEmpty {
                    return rows
                }
            } catch let error as DatabaseError {
                print("⚠️ Transit headway query failed: \(error.message). Returning fallback headways.")
            } catch {
                throw error
            }
            // Fallback realistic headway variation series
            return self.generateFallbackHeadways(for: stopId)
        }
    }
    
    func fetchRouteCoordinates(for routeId: String) async throws -> [CLLocationCoordinate2D]? {
        return try await dbWriter.read { db in
            do {
                let sql = "SELECT lat, lon FROM transit.route_shapes WHERE route_id = ? ORDER BY sequence ASC"
                let rows = try Row.fetchAll(db, sql: sql, arguments: [routeId])
                if !rows.isEmpty {
                    let coords = rows.compactMap { row -> CLLocationCoordinate2D? in
                        let lat: Double? = row["lat"]
                        let lon: Double? = row["lon"]
                        guard let validLat = lat, let validLon = lon else { return nil }
                        return CLLocationCoordinate2D(latitude: validLat, longitude: validLon)
                    }
                    if !coords.isEmpty {
                        return coords
                    }
                }
            } catch {
                // Table does not exist in SQLite schema; fallback to static route geometries
            }
            return nil
        }
    }
    
    private func inferRouteId(from stopId: String, name: String) -> String {
        let upper = (stopId + " " + name).uppercased()
        if upper.contains("L") { return "L" }
        if upper.contains("G") { return "G" }
        if upper.contains("7") { return "7" }
        if upper.contains("A") || upper.contains("C") || upper.contains("E") { return "A" }
        if upper.contains("1") || upper.contains("2") || upper.contains("3") { return "1" }
        if upper.contains("4") || upper.contains("5") || upper.contains("6") { return "4" }
        if upper.contains("N") || upper.contains("Q") || upper.contains("R") { return "N" }
        return "L"
    }
    
    private func generateArrivals(for routeId: String) -> [ArrivalInfo] {
        switch routeId.uppercased() {
        case "G":
            return [
                ArrivalInfo(line: "G", destination: "Court Sq", minutes: 4),
                ArrivalInfo(line: "G", destination: "Church Ave", minutes: 9),
                ArrivalInfo(line: "G", destination: "Court Sq", minutes: 14)
            ]
        case "A", "C", "E":
            return [
                ArrivalInfo(line: "A", destination: "Uptown / 207 St", minutes: 2),
                ArrivalInfo(line: "C", destination: "Downtown / Brooklyn", minutes: 5),
                ArrivalInfo(line: "E", destination: "World Trade Center", minutes: 11)
            ]
        case "1", "2", "3":
            return [
                ArrivalInfo(line: "1", destination: "Van Cortlandt Park", minutes: 3),
                ArrivalInfo(line: "2", destination: "Flatbush Ave", minutes: 6),
                ArrivalInfo(line: "3", destination: "Harlem - 148 St", minutes: 12)
            ]
        default:
            return [
                ArrivalInfo(line: routeId, destination: "Manhattan - 8th Ave", minutes: 3),
                ArrivalInfo(line: routeId, destination: "Brooklyn - Rockaway Pkwy", minutes: 8),
                ArrivalInfo(line: routeId, destination: "Manhattan - 8th Ave", minutes: 15)
            ]
        }
    }
    
    private func generateFallbackHeadways(for stopId: String) -> [Double] {
        let hash = abs(stopId.hashValue)
        let base = 4.0 + Double(hash % 3)
        return [
            base + 0.3,
            base - 0.5,
            base + 1.2,
            base - 0.2,
            base + 0.8,
            base + 0.1,
            base - 0.4
        ]
    }
}

