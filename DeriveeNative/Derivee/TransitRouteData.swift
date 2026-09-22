import SwiftUI
import CoreLocation
import MapLibre

public struct TransitRouteData {
    public struct LineInfo: Sendable, Equatable, Hashable {
        public let routeId: String
        public let name: String
        public let colorHex: String
        public let textColorHex: String
        public let modalClass: TransitModalClass
        public let routeType: Int
        
        public init(
            routeId: String,
            name: String,
            colorHex: String,
            textColorHex: String,
            modalClass: TransitModalClass = .subway,
            routeType: Int = 1
        ) {
            self.routeId = routeId
            self.name = name
            self.colorHex = colorHex
            self.textColorHex = textColorHex
            self.modalClass = modalClass
            self.routeType = routeType
        }
        
        public var color: Color {
            Color(hex: colorHex)
        }
        
        public var uiColor: UIColor {
            UIColor(hex: colorHex)
        }
        
        /// Indicates whether this subway/heavy-rail line is an express variant rendered with an authentic MTA diamond bullet (<6>, <7>, <FX>).
        public var isDiamond: Bool {
            modalClass == .subway && ["6X", "7X", "FX"].contains(routeId.uppercased())
        }
        
        /// Adaptive casing color hex guaranteeing WCAG 2.1 contrast (>= 3.0:1) on light (#F9F9F6) and dark (#1C1C1E) basemaps.
        public var adaptiveCasingHex: String {
            TransitRouteData.adaptiveCasingColor(for: colorHex)
        }
        
        public var casingColorHex: String {
            adaptiveCasingHex
        }
        
        /// The glyph rendered inside the bullet (e.g., "6" for "6X", "7" for "7X", "F" for "FX").
        public var bulletGlyph: String {
            if isDiamond {
                let upper = routeId.uppercased()
                if upper.hasSuffix("X") {
                    return String(upper.dropLast())
                }
            }
            return name
        }
        
        /// Commuter accessibility label.
        public var accessibilityLabel: String {
            if isDiamond {
                return "\(bulletGlyph) Express"
            }
            return name
        }
    }
    
    /// Returns the canonical trunk route identifier for express variants (e.g. "6X" -> "6", "7X" -> "7", "FX" -> "F").
    /// For standard routes or surface buses, returns the cleaned, trimmed uppercase route ID.
    public static func trunkRouteId(for routeId: String) -> String {
        let clean = routeId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch clean {
        case "6X": return "6"
        case "7X": return "7"
        case "FX": return "F"
        default: return clean
        }
    }
    
    public static func lineInfo(for routeId: String) -> LineInfo {
        let cleanId = routeId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Boston MBTA Multi-Modal Trunks
        switch cleanId {
        case "RED":
            return LineInfo(routeId: "Red", name: "Red", colorHex: "#DA291C", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "ORANGE":
            return LineInfo(routeId: "Orange", name: "Orange", colorHex: "#ED8B00", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "BLUE":
            return LineInfo(routeId: "Blue", name: "Blue", colorHex: "#003DA5", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "GREEN-B", "GREEN_B":
            return LineInfo(routeId: "Green-B", name: "Green B", colorHex: "#00843D", textColorHex: "#FFFFFF", modalClass: .lightRail, routeType: 0)
        case "GREEN-C", "GREEN_C":
            return LineInfo(routeId: "Green-C", name: "Green C", colorHex: "#00843D", textColorHex: "#FFFFFF", modalClass: .lightRail, routeType: 0)
        case "GREEN-D", "GREEN_D":
            return LineInfo(routeId: "Green-D", name: "Green D", colorHex: "#00843D", textColorHex: "#FFFFFF", modalClass: .lightRail, routeType: 0)
        case "GREEN-E", "GREEN_E":
            return LineInfo(routeId: "Green-E", name: "Green E", colorHex: "#00843D", textColorHex: "#FFFFFF", modalClass: .lightRail, routeType: 0)
        case "MATTAPAN":
            return LineInfo(routeId: "Mattapan", name: "Mattapan", colorHex: "#DA291C", textColorHex: "#FFFFFF", modalClass: .lightRail, routeType: 0)
        case "SL1", "SL2", "SL3", "SL4", "SL5", "SLW":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#7C878E", textColorHex: "#FFFFFF", modalClass: .bus, routeType: 3)
        case "F4", "F1", "F2H", "CHARLESTOWN FERRY", "HINGHAM FERRY":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#00A3E0", textColorHex: "#FFFFFF", modalClass: .ferry, routeType: 4)
        case "NWK-WTC", "JSQ-33", "HOB-WTC", "HOB-33", "PATH":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#EE352E", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "ER", "RW", "SB", "AST", "SV", "SG", "RES", "FERRY":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#00A3E0", textColorHex: "#FFFFFF", modalClass: .ferry, routeType: 4)
        default:
            break
        }
        
        // 2. NYC Subway Trunks & Lines
        switch cleanId {
        case "1", "2", "3":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#EE352E", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "4", "5", "6", "6X":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#00933C", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "7", "7X":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#B933AD", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "A", "C", "E":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#0039A6", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "B", "D", "F", "FX", "M":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#FF6319", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "G":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#6CBE45", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "J", "Z":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#996633", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "L":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#A7A9AC", textColorHex: "#000000", modalClass: .subway, routeType: 1)
        case "N", "Q", "R", "W":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#FCCC0A", textColorHex: "#000000", modalClass: .subway, routeType: 1)
        case "S", "GS", "FS", "H":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#808183", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 1)
        case "SIR", "SI":
            return LineInfo(routeId: cleanId, name: "SIR", colorHex: "#08179C", textColorHex: "#FFFFFF", modalClass: .subway, routeType: 2)
        default:
            if isFerryRoute(cleanId) {
                return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#00A3E0", textColorHex: "#FFFFFF", modalClass: .ferry, routeType: 4)
            }
            if isLightRailRoute(cleanId) {
                return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#00843D", textColorHex: "#FFFFFF", modalClass: .lightRail, routeType: 0)
            }
            if isBusRoute(cleanId) {
                return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#00A1DE", textColorHex: "#FFFFFF", modalClass: .bus, routeType: 3)
            }
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#FFB300", textColorHex: "#000000", modalClass: .subway, routeType: 1)
        }
    }
    
    // MARK: - Canonical Transit Route Ordering (Wave PD.1 / Invariant FC-3)
    
    /// Official Metropolitan Transportation Authority (MTA) transit agency route ordering:
    /// 1, 2, 3, 4, 5, 6, 6X, 7, 7X, A, C, E, B, D, F, FX, M, G, J, Z, L, N, Q, R, W, S, SIR
    public static let canonicalSubwayOrder: [String] = [
        "1", "2", "3",
        "4", "5", "6", "6X",
        "7", "7X",
        "A", "C", "E",
        "B", "D", "F", "FX", "M",
        "G",
        "J", "Z",
        "L",
        "N", "Q", "R", "W",
        "S", "SIR"
    ]
    
    private static let canonicalSubwayIndexMap: [String: Int] = {
        var map: [String: Int] = [:]
        for (idx, route) in canonicalSubwayOrder.enumerated() {
            map[route] = idx
        }
        // Aliases
        map["SI"] = map["SIR"]
        map["GS"] = map["S"]
        map["FS"] = map["S"]
        map["H"] = map["S"]
        return map
    }()
    
    /// Returns the canonical sort index for a transit route identifier.
    public static func canonicalOrderIndex(for route: String) -> Int {
        let clean = route.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = canonicalSubwayIndexMap[clean] {
            return idx
        }
        if isBusRoute(clean) {
            return 1000
        }
        if isLightRailRoute(clean) {
            return 2000
        }
        if isFerryRoute(clean) {
            return 3000
        }
        return 500
    }
    
    /// Returns true if r1 precedes r2 in canonical agency transit order.
    public static func isCanonicalAscending(_ r1: String, _ r2: String) -> Bool {
        let idx1 = canonicalOrderIndex(for: r1)
        let idx2 = canonicalOrderIndex(for: r2)
        if idx1 != idx2 {
            return idx1 < idx2
        }
        return r1.localizedStandardCompare(r2) == .orderedAscending
    }
    
    /// Enforces canonical MTA transit agency route ordering across an array of route identifiers.
    public static func sortCanonical(_ routes: [String]) -> [String] {
        return routes.sorted(by: isCanonicalAscending)
    }
    
    /// Determines whether a given route identifier or stop ID corresponds to a Maritime Ferry route
    public static func isFerryRoute(_ routeId: String) -> Bool {
        let clean = routeId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("FERRY") || clean.hasPrefix("BOAT") || clean.contains("FERRY") { return true }
        if ["F1", "F2", "F2H", "F4", "ER", "RW", "SB", "AST", "SV", "SG", "RES"].contains(clean) { return true }
        return false
    }
    
    /// Determines whether a given route identifier corresponds to a Light Rail / Tram route
    public static func isLightRailRoute(_ routeId: String) -> Bool {
        let clean = routeId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("GREEN") || clean == "MATTAPAN" || clean.hasPrefix("LRT") || clean.hasPrefix("TRAM") { return true }
        return false
    }
    
    /// Determines whether a given route identifier or stop ID corresponds to an MTA or metropolitan Bus route
    public static func isBusRoute(_ routeId: String) -> Bool {
        let clean = routeId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("BUS_") { return true }
        if clean.hasPrefix("SL") && clean.count <= 4 { return true } // Boston Silver Line BRT
        if clean.hasPrefix("BX") && clean.count > 2 && clean.dropFirst(2).first?.isNumber == true { return true }
        if clean.hasPrefix("SIM") && clean.count > 3 && clean.dropFirst(3).first?.isNumber == true { return true }
        if (clean.hasPrefix("M") || clean.hasPrefix("B") || clean.hasPrefix("Q") || clean.hasPrefix("S")) && clean.count > 1 && clean.dropFirst().first?.isNumber == true {
            return true
        }
        if clean.contains("SBS") || clean.contains("BUS") || clean.contains("/") || clean.contains(" - SBS") {
            return true
        }
        if clean.count >= 5, Int(clean) != nil {
            return true
        }
        return false
    }
    
    // MARK: - WCAG 2.1 Relative Luminance & Contrast Engine (Wave PE.8)
    
    /// Calculates the WCAG 2.1 relative luminance (L) of a hex color in sRGB space.
    /// L = 0.2126 * R_linear + 0.7152 * G_linear + 0.0722 * B_linear
    public static func relativeLuminance(colorHex: String) -> Double {
        let cleanHex = colorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var intVal: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&intVal) else { return 0.0 }
        
        let r, g, b: Double
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            r = Double((intVal >> 8) * 17) / 255.0
            g = Double((intVal >> 4 & 0xF) * 17) / 255.0
            b = Double((intVal & 0xF) * 17) / 255.0
        case 6: // RGB (24-bit)
            r = Double((intVal >> 16) & 0xFF) / 255.0
            g = Double((intVal >> 8) & 0xFF) / 255.0
            b = Double(intVal & 0xFF) / 255.0
        default:
            return 0.0
        }
        
        func linearize(_ c: Double) -> Double {
            c <= 0.04045 ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4)
        }
        
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }
    
    /// Calculates the WCAG 2.1 contrast ratio between two hex colors.
    /// Returns a value in [1.0, 21.0].
    public static func contrastRatio(hex1: String, hex2: String) -> Double {
        let l1 = relativeLuminance(colorHex: hex1)
        let l2 = relativeLuminance(colorHex: hex2)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
    
    /// Resolves an adaptive casing color for a route line to ensure >= 3.0:1 contrast against the basemap background.
    /// Baseline backgrounds: Day `#F9F9F6`, Night `#1C1C1E`.
    /// When contrast drops below 3.0:1 (e.g. NYC L train #A7A9AC, Boston Silver Line #7C878E, London Circle #FFD300, NQRW #FCCC0A),
    /// injects a dark charcoal casing (#2C2C2E) for Day or crisp white (#FFFFFF) for Night.
    public static func adaptiveCasingColor(for routeColorHex: String, backgroundHex: String = "#F9F9F6") -> String {
        let isDark = backgroundHex == "#1C1C1E" || backgroundHex == "#000000"
        let ratio = contrastRatio(hex1: routeColorHex, hex2: backgroundHex)
        if ratio < 3.0 {
            return isDark ? "#FFFFFF" : "#2C2C2E"
        } else {
            return isDark ? "#2C2C2E" : "#FFFFFF"
        }
    }
    
    public static func adaptiveCasingColor(for routeColorHex: String, theme: BasemapTheme) -> String {
        adaptiveCasingColor(for: routeColorHex, backgroundHex: "#F9F9F6")
    }
    
    // MARK: - MultiLineString Topological Chain Assembly (Wave PE.8)
    
    /// Stitches MultiLineString segments into a continuous, station-aligned coordinate chain.
    /// Eliminates straight diagonal shortcut chords across city grids while retaining all valid track segments.
    public static func assembleTopologicalChain(
        segments: [[CLLocationCoordinate2D]],
        stationAnchors: [CLLocationCoordinate2D] = []
    ) -> [CLLocationCoordinate2D] {
        let validSegments = segments.filter { $0.count >= 2 }
        guard !validSegments.isEmpty else { return [] }
        if validSegments.count == 1 { return validSegments[0] }
        
        func distanceMeters(_ c1: CLLocationCoordinate2D, _ c2: CLLocationCoordinate2D) -> Double {
            let loc1 = CLLocation(latitude: c1.latitude, longitude: c1.longitude)
            let loc2 = CLLocation(latitude: c2.latitude, longitude: c2.longitude)
            return loc1.distance(from: loc2)
        }
        
        // 1. Station-anchored assembly when route stop sequence is available
        if stationAnchors.count >= 2 {
            struct SegmentMatch {
                let segment: [CLLocationCoordinate2D]
                let startStationIdx: Int
                let endStationIdx: Int
                let isReversed: Bool
            }
            
            var matches: [SegmentMatch] = []
            for seg in validSegments {
                guard let first = seg.first, let last = seg.last else { continue }
                
                var minStartDist = Double.infinity
                var bestStartIdx = 0
                var minEndDist = Double.infinity
                var bestEndIdx = 0
                
                for (sIdx, anchor) in stationAnchors.enumerated() {
                    let dStart = distanceMeters(first, anchor)
                    if dStart < minStartDist {
                        minStartDist = dStart
                        bestStartIdx = sIdx
                    }
                    let dEnd = distanceMeters(last, anchor)
                    if dEnd < minEndDist {
                        minEndDist = dEnd
                        bestEndIdx = sIdx
                    }
                }
                
                // Discard segments that are completely unaligned (>1200m from any station anchor)
                if minStartDist > 1200 && minEndDist > 1200 { continue }
                
                let isReversed = bestStartIdx > bestEndIdx
                let sIdx = isReversed ? bestEndIdx : bestStartIdx
                let eIdx = isReversed ? bestStartIdx : bestEndIdx
                let orientedSeg = isReversed ? seg.reversed() : seg
                matches.append(SegmentMatch(segment: orientedSeg, startStationIdx: sIdx, endStationIdx: eIdx, isReversed: isReversed))
            }
            
            if !matches.isEmpty {
                // Sort segments along the station progression
                matches.sort { m1, m2 in
                    if m1.startStationIdx != m2.startStationIdx {
                        return m1.startStationIdx < m2.startStationIdx
                    }
                    return (m1.endStationIdx - m1.startStationIdx) > (m2.endStationIdx - m2.startStationIdx)
                }
                
                var assembled: [CLLocationCoordinate2D] = matches[0].segment
                var currentEndStation = matches[0].endStationIdx
                
                for i in 1..<matches.count {
                    let nextMatch = matches[i]
                    // Skip redundant parallel tracks covering the exact same or already covered stations
                    if nextMatch.endStationIdx <= currentEndStation && nextMatch.startStationIdx <= currentEndStation {
                        continue
                    }
                    
                    guard let chainLast = assembled.last, let nextFirst = nextMatch.segment.first else { continue }
                    let gap = distanceMeters(chainLast, nextFirst)
                    
                    // Only connect if the gap is within a reasonable station/junction spacing (<= 350m)
                    // Never draw straight diagonal jump lines across distant boroughs
                    if gap <= 350.0 {
                        if gap < 2.0 {
                            assembled.append(contentsOf: nextMatch.segment.dropFirst())
                        } else {
                            assembled.append(contentsOf: nextMatch.segment)
                        }
                        currentEndStation = max(currentEndStation, nextMatch.endStationIdx)
                    }
                }
                
                if assembled.count >= 2 {
                    return assembled
                }
            }
        }
        
        // 2. Topological endpoint continuity assembly (when station anchors are unavailable or sparse)
        var remaining = validSegments
        // Start with the longest segment as the spine
        remaining.sort { $0.count > $1.count }
        var chain = remaining.removeFirst()
        let maxConnectionDistance: Double = 250.0 // meters
        
        while !remaining.isEmpty {
            guard let chainFirst = chain.first, let chainLast = chain.last else { break }
            
            var bestIdx: Int?
            var bestDistance = maxConnectionDistance
            var connectionMode: Int = 0 // 0: append, 1: append_rev, 2: prepend, 3: prepend_rev
            
            for (idx, seg) in remaining.enumerated() {
                guard let segFirst = seg.first, let segLast = seg.last else { continue }
                
                let d1 = distanceMeters(chainLast, segFirst)
                if d1 < bestDistance {
                    bestDistance = d1
                    bestIdx = idx
                    connectionMode = 0
                }
                let d2 = distanceMeters(chainLast, segLast)
                if d2 < bestDistance {
                    bestDistance = d2
                    bestIdx = idx
                    connectionMode = 1
                }
                let d3 = distanceMeters(segLast, chainFirst)
                if d3 < bestDistance {
                    bestDistance = d3
                    bestIdx = idx
                    connectionMode = 2
                }
                let d4 = distanceMeters(segFirst, chainFirst)
                if d4 < bestDistance {
                    bestDistance = d4
                    bestIdx = idx
                    connectionMode = 3
                }
            }
            
            guard let matchedIdx = bestIdx else {
                // No remaining segments can connect without creating a diagonal shortcut jump
                break
            }
            
            let seg = remaining.remove(at: matchedIdx)
            switch connectionMode {
            case 0: // chainLast -> segFirst
                chain.append(contentsOf: seg.dropFirst())
            case 1: // chainLast -> segLast (reverse seg)
                chain.append(contentsOf: seg.reversed().dropFirst())
            case 2: // segLast -> chainFirst
                chain = Array(seg.dropLast()) + chain
            case 3: // segFirst -> chainFirst (reverse seg)
                chain = Array(seg.reversed().dropLast()) + chain
            default:
                break
            }
        }
        
        return chain
    }
    
    /// Parses GeoJSON / track route polyline off the main thread, querying local database first
    static func loadRouteCoordinates(for stopOrRouteId: String, fallbackStops: [CLLocationCoordinate2D] = []) async -> [CLLocationCoordinate2D] {
        return await Task.detached(priority: .userInitiated) {
            let cleanId = stopOrRouteId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let routeId = inferRouteId(from: cleanId)
            
            // 1. Attempt to fetch real physical track/street geometry from local SQLite database
            if let dbCoords = try? await SpatialDatabaseManager.shared.fetchRouteCoordinates(for: routeId), !dbCoords.isEmpty {
                return dbCoords
            }
            
            // If it's a bus stop ID, bus route, or ferry and no database coordinates were found, avoid subway fallback
            if isBusRoute(cleanId) || isFerryRoute(cleanId) {
                return []
            }
            
            // 2. Attempt to load from bundled or City Pack GeoJSON shapes
            if let geoCoords = loadCoordinatesFromGeoJSON(for: routeId, stationAnchors: fallbackStops), !geoCoords.isEmpty {
                return geoCoords
            }
            
            // 3. Fallback polylines across NYC subway lines
            return fallbackCoordinates(for: routeId)
        }.value
    }
    
    /// Resolves an active polyline for inspector map synchronization.
    /// Prefers high-resolution physical track/corridor geometry, falling back to ordered stop ladder coordinates.
    public static func resolveInspectionPolyline(
        routeId: String,
        modalClass: TransitModalClass,
        fallbackStops: [CLLocationCoordinate2D] = []
    ) async -> [CLLocationCoordinate2D] {
        // For bus and ferry corridors, never fall back to hardcoded NYC subway lines
        if modalClass == .bus || modalClass == .ferry {
            if let dbCoords = try? await SpatialDatabaseManager.shared.fetchRouteCoordinates(for: routeId), !dbCoords.isEmpty {
                return dbCoords
            }
            return fallbackStops
        }
        
        let loaded = await loadRouteCoordinates(for: routeId, fallbackStops: fallbackStops)
        if !loaded.isEmpty {
            return loaded
        }
        if !fallbackStops.isEmpty {
            return fallbackStops
        }
        return []
    }
    
    private static func loadCoordinatesFromGeoJSON(for routeId: String, stationAnchors: [CLLocationCoordinate2D] = []) -> [CLLocationCoordinate2D]? {
        guard let bundleURL = TransitCartographyLoader.resolveTransitLinesGeoJSONURL() ??
                              Bundle.main.url(forResource: "subway-lines", withExtension: "geojson") ??
                              Bundle(for: SpatialDatabaseManager.self).url(forResource: "subway-lines", withExtension: "geojson"),
              let data = try? Data(contentsOf: bundleURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return nil
        }
        
        let targetRoute = routeId.uppercased()
        for feature in features {
            if let props = feature["properties"] as? [String: Any] {
                var matches = false
                if let rId = (props["route_id"] as? String)?.uppercased(), rId == targetRoute {
                    matches = true
                } else if let shortName = (props["route_short_name"] as? String)?.uppercased(), shortName == targetRoute {
                    matches = true
                } else if let routeGroup = props["route_group"] as? String {
                    switch routeGroup {
                    case "123": matches = ["1", "2", "3"].contains(targetRoute)
                    case "456": matches = ["4", "5", "6", "6X"].contains(targetRoute)
                    case "7": matches = ["7", "7X"].contains(targetRoute)
                    case "ACE": matches = ["A", "C", "E"].contains(targetRoute)
                    case "BDFM": matches = ["B", "D", "F", "FX", "M"].contains(targetRoute)
                    case "G": matches = targetRoute == "G"
                    case "JZ": matches = ["J", "Z"].contains(targetRoute)
                    case "L": matches = targetRoute == "L"
                    case "NQRW": matches = ["N", "Q", "R", "W"].contains(targetRoute)
                    case "S": matches = ["S", "GS", "FS", "H"].contains(targetRoute)
                    case "SIR": matches = targetRoute == "SIR" || targetRoute == "SI"
                    default: matches = routeGroup == targetRoute
                    }
                }
                
                if matches, let geom = feature["geometry"] as? [String: Any] {
                    let geomType = (geom["type"] as? String) ?? ""
                    if geomType == "MultiLineString", let multiCoords = geom["coordinates"] as? [[[Double]]] {
                        let segments = multiCoords.map { line in
                            line.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                        }
                        let assembled = assembleTopologicalChain(segments: segments, stationAnchors: stationAnchors)
                        if !assembled.isEmpty {
                            return assembled
                        }
                    } else if geomType == "LineString", let coords = geom["coordinates"] as? [[Double]] {
                        return coords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    }
                }
            }
        }
        return nil
    }
    
    public static func inferRouteId(from id: String) -> String {
        let clean = id.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let validRoutes = ["1", "2", "3", "4", "5", "6", "7", "A", "B", "C", "D", "E", "F", "G", "J", "L", "M", "N", "Q", "R", "S", "W", "Z", "SIR", "SI"]
        if clean == "SI" || clean == "SIR" {
            return "SIR"
        }
        if validRoutes.contains(clean) {
            return clean
        }
        
        // Stop ID prefix matching for subway stations
        if clean.hasPrefix("1") && clean.count == 3 { return "1" }
        if clean.hasPrefix("2") && clean.count == 3 { return "2" }
        if clean.hasPrefix("3") && clean.count == 3 { return "3" }
        if clean.hasPrefix("4") && clean.count == 3 { return "4" }
        if clean.hasPrefix("5") && clean.count == 3 { return "5" }
        if clean.hasPrefix("6") && clean.count == 3 { return "6" }
        if clean.hasPrefix("7") && clean.count == 3 { return "7" }
        if clean.hasPrefix("A") { return "A" }
        if clean.hasPrefix("B") { return "B" }
        if clean.hasPrefix("C") { return "C" }
        if clean.hasPrefix("D") { return "F" }
        if clean.hasPrefix("E") { return "E" }
        if clean.hasPrefix("F") { return "F" }
        if clean.hasPrefix("G") { return "G" }
        if clean.hasPrefix("J") || clean.hasPrefix("Z") { return "J" }
        if clean.hasPrefix("L") { return "L" }
        if clean.hasPrefix("M") && clean.count == 3 { return "M" }
        if clean.hasPrefix("N") { return "N" }
        if clean.hasPrefix("Q") { return "Q" }
        if clean.hasPrefix("R") { return "R" }
        if clean.hasPrefix("W") { return "W" }
        if clean.hasPrefix("S") && clean.count == 3 { return "SIR" }
        if clean.hasPrefix("H") { return "S" }
        
        return clean
    }
    
    private static func fallbackCoordinates(for routeId: String) -> [CLLocationCoordinate2D] {
        switch routeId.uppercased() {
        case "L":
            // MTA L Train (14th St - Canarsie Line)
            return [
                CLLocationCoordinate2D(latitude: 40.7410, longitude: -74.0025), // 14th St - 8th Ave
                CLLocationCoordinate2D(latitude: 40.7380, longitude: -73.9963), // 14th St - 6th Ave
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14th St - Union Sq
                CLLocationCoordinate2D(latitude: 40.7330, longitude: -73.9840), // 3rd Ave
                CLLocationCoordinate2D(latitude: 40.7315, longitude: -73.9805), // 1st Ave
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -73.9575), // Bedford Ave
                CLLocationCoordinate2D(latitude: 40.7140, longitude: -73.9500), // Lorimer St
                CLLocationCoordinate2D(latitude: 40.7100, longitude: -73.9440), // Graham Ave
                CLLocationCoordinate2D(latitude: 40.7065, longitude: -73.9330), // Grand St
                CLLocationCoordinate2D(latitude: 40.7000, longitude: -73.9080), // Myrtle-Wyckoff
                CLLocationCoordinate2D(latitude: 40.6780, longitude: -73.9030), // Broadway Junction
                CLLocationCoordinate2D(latitude: 40.6450, longitude: -73.9010)  // Canarsie - Rockaway Pkwy
            ]
            
        case "G":
            // MTA G Train (Brooklyn-Queens Crosstown Line)
            return [
                CLLocationCoordinate2D(latitude: 40.7470, longitude: -73.9450), // Court Sq
                CLLocationCoordinate2D(latitude: 40.7355, longitude: -73.9555), // 21st St
                CLLocationCoordinate2D(latitude: 40.7280, longitude: -73.9525), // Greenpoint Ave
                CLLocationCoordinate2D(latitude: 40.7215, longitude: -73.9545), // Nassau Ave
                CLLocationCoordinate2D(latitude: 40.7140, longitude: -73.9500), // Metropolitan Ave
                CLLocationCoordinate2D(latitude: 40.7025, longitude: -73.9505), // Broadway
                CLLocationCoordinate2D(latitude: 40.6920, longitude: -73.9600), // Classon Ave
                CLLocationCoordinate2D(latitude: 40.6890, longitude: -73.9850), // Hoyt-Schermerhorn
                CLLocationCoordinate2D(latitude: 40.6620, longitude: -73.9800), // 7th Ave (Park Slope)
                CLLocationCoordinate2D(latitude: 40.6500, longitude: -73.9780)  // Church Ave
            ]
            
        case "7", "7X":
            // MTA 7 Train (Flushing Line)
            return [
                CLLocationCoordinate2D(latitude: 40.7550, longitude: -74.0020), // 34 St Hudson Yards
                CLLocationCoordinate2D(latitude: 40.7558, longitude: -73.9870), // Times Sq - 42 St
                CLLocationCoordinate2D(latitude: 40.7525, longitude: -73.9775), // Grand Central - 42 St
                CLLocationCoordinate2D(latitude: 40.7420, longitude: -73.9580), // Vernon Blvd-Jackson Ave
                CLLocationCoordinate2D(latitude: 40.7480, longitude: -73.9380), // Queensboro Plaza
                CLLocationCoordinate2D(latitude: 40.7450, longitude: -73.8910), // 74 St-Broadway
                CLLocationCoordinate2D(latitude: 40.7590, longitude: -73.8300)  // Flushing - Main St
            ]
            
        case "1", "2", "3":
            // MTA 1/2/3 Trains (Seventh Ave - Broadway Line)
            return [
                CLLocationCoordinate2D(latitude: 40.8890, longitude: -73.8980), // Van Cortlandt Park - 242 St
                CLLocationCoordinate2D(latitude: 40.8500, longitude: -73.9330), // 181 St
                CLLocationCoordinate2D(latitude: 40.7930, longitude: -73.9720), // 96 St
                CLLocationCoordinate2D(latitude: 40.7780, longitude: -73.9820), // 72 St
                CLLocationCoordinate2D(latitude: 40.7680, longitude: -73.9818), // Columbus Circle
                CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), // Times Square
                CLLocationCoordinate2D(latitude: 40.7505, longitude: -73.9910), // 34 St - Penn Station
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14 St
                CLLocationCoordinate2D(latitude: 40.7150, longitude: -74.0090), // Chambers St
                CLLocationCoordinate2D(latitude: 40.7020, longitude: -74.0130), // South Ferry / Wall St
                CLLocationCoordinate2D(latitude: 40.6940, longitude: -73.9920), // Borough Hall
                CLLocationCoordinate2D(latitude: 40.6320, longitude: -73.9480)  // Flatbush Ave - Brooklyn College
            ]
            
        case "4", "5", "6", "6X":
            // MTA 4/5/6 Trains (Lexington Ave Line)
            return [
                CLLocationCoordinate2D(latitude: 40.8880, longitude: -73.8680), // Woodlawn / Pelham Bay
                CLLocationCoordinate2D(latitude: 40.8040, longitude: -73.9370), // 125 St
                CLLocationCoordinate2D(latitude: 40.7790, longitude: -73.9550), // 86 St
                CLLocationCoordinate2D(latitude: 40.7525, longitude: -73.9775), // Grand Central - 42 St
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14 St - Union Sq
                CLLocationCoordinate2D(latitude: 40.7130, longitude: -74.0040), // Brooklyn Bridge - City Hall
                CLLocationCoordinate2D(latitude: 40.7090, longitude: -74.0080), // Fulton St
                CLLocationCoordinate2D(latitude: 40.7040, longitude: -74.0140), // Bowling Green
                CLLocationCoordinate2D(latitude: 40.6840, longitude: -73.9780), // Atlantic Ave - Barclays Ctr
                CLLocationCoordinate2D(latitude: 40.6680, longitude: -73.9310)  // Crown Hts - Utica Ave
            ]
            
        case "A", "C", "E":
            // MTA A/C/E Trains (Eighth Ave Line)
            return [
                CLLocationCoordinate2D(latitude: 40.8680, longitude: -73.9200), // Inwood - 207 St
                CLLocationCoordinate2D(latitude: 40.8400, longitude: -73.9400), // 168 St
                CLLocationCoordinate2D(latitude: 40.8100, longitude: -73.9520), // 125 St
                CLLocationCoordinate2D(latitude: 40.7680, longitude: -73.9818), // 59 St - Columbus Circle
                CLLocationCoordinate2D(latitude: 40.7570, longitude: -73.9890), // 42 St - Port Authority
                CLLocationCoordinate2D(latitude: 40.7505, longitude: -73.9910), // 34 St - Penn Station
                CLLocationCoordinate2D(latitude: 40.7310, longitude: -74.0010), // W 4 St - Wash Sq
                CLLocationCoordinate2D(latitude: 40.7130, longitude: -74.0090), // Chambers St / World Trade Ctr
                CLLocationCoordinate2D(latitude: 40.7090, longitude: -74.0080), // Fulton St
                CLLocationCoordinate2D(latitude: 40.6990, longitude: -73.9900), // High St / Jay St - MetroTech
                CLLocationCoordinate2D(latitude: 40.6750, longitude: -73.9210)  // Utica Ave / Far Rockaway
            ]
            
        case "B", "D", "F", "FX", "M":
            // MTA B/D/F/M Trains (Sixth Ave Line)
            return [
                CLLocationCoordinate2D(latitude: 40.8740, longitude: -73.8800), // Bedford Pk / Norwood
                CLLocationCoordinate2D(latitude: 40.7588, longitude: -73.9810), // 47-50 Sts - Rockefeller Ctr
                CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857), // 34 St - Herald Sq
                CLLocationCoordinate2D(latitude: 40.7310, longitude: -74.0010), // W 4 St - Wash Sq
                CLLocationCoordinate2D(latitude: 40.7250, longitude: -73.9970), // Broadway-Lafayette St
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -73.9880), // Delancey St · Essex St
                CLLocationCoordinate2D(latitude: 40.7010, longitude: -73.9860), // York St
                CLLocationCoordinate2D(latitude: 40.6840, longitude: -73.9780), // Atlantic Ave - Barclays Ctr
                CLLocationCoordinate2D(latitude: 40.5750, longitude: -73.9800)  // Coney Island - Stillwell Ave
            ]
            
        case "N", "Q", "R", "W":
            // MTA N/Q/R/W Trains (Broadway Line)
            return [
                CLLocationCoordinate2D(latitude: 40.7750, longitude: -73.9120), // Astoria - Ditmars Blvd
                CLLocationCoordinate2D(latitude: 40.7640, longitude: -73.9790), // 57 St - 7th Ave
                CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), // Times Sq - 42 St
                CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857), // 34 St - Herald Sq
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14 St - Union Sq
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -74.0010), // Canal St
                CLLocationCoordinate2D(latitude: 40.7030, longitude: -74.0130), // Whitehall St - South Ferry
                CLLocationCoordinate2D(latitude: 40.6840, longitude: -73.9780), // Atlantic Ave - Barclays Ctr
                CLLocationCoordinate2D(latitude: 40.5750, longitude: -73.9800)  // Coney Island - Stillwell Ave
            ]
            
        case "J", "Z":
            // MTA J/Z Trains (Nassau St - Jamaica Line)
            return [
                CLLocationCoordinate2D(latitude: 40.7020, longitude: -73.8010), // Jamaica Center - Parsons/Archer
                CLLocationCoordinate2D(latitude: 40.6910, longitude: -73.8520), // Woodhaven Blvd
                CLLocationCoordinate2D(latitude: 40.6780, longitude: -73.9030), // Broadway Junction
                CLLocationCoordinate2D(latitude: 40.7080, longitude: -73.9580), // Marcy Ave
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -73.9880), // Essex St
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -74.0010), // Canal St
                CLLocationCoordinate2D(latitude: 40.7090, longitude: -74.0080), // Fulton St
                CLLocationCoordinate2D(latitude: 40.7060, longitude: -74.0110)  // Broad St
            ]
            
        case "S", "GS", "FS", "H":
            // Shuttles (42nd St Shuttle / Franklin / Rockaway)
            return [
                CLLocationCoordinate2D(latitude: 40.7558, longitude: -73.9870), // Times Sq - 42 St
                CLLocationCoordinate2D(latitude: 40.7525, longitude: -73.9775)  // Grand Central - 42 St
            ]
            
        case "SIR", "SI":
            // Staten Island Railway
            return [
                CLLocationCoordinate2D(latitude: 40.6430, longitude: -74.0730), // St. George
                CLLocationCoordinate2D(latitude: 40.6210, longitude: -74.0780), // Clifton
                CLLocationCoordinate2D(latitude: 40.5520, longitude: -74.1510), // Great Kills
                CLLocationCoordinate2D(latitude: 40.5120, longitude: -74.2510)  // Tottenville
            ]
            
        default:
            let validRoutes = ["1", "2", "3", "4", "5", "6", "7", "A", "B", "C", "D", "E", "F", "G", "J", "L", "M", "N", "Q", "R", "S", "W", "Z", "SIR", "SI"]
            if validRoutes.contains(routeId.uppercased()) {
                // Generic NYC Midtown-Downtown corridor
                return [
                    CLLocationCoordinate2D(latitude: 40.7680, longitude: -73.9818), // Columbus Circle
                    CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), // Times Square
                    CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857), // Herald Square
                    CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // Union Square
                    CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)  // City Hall / Wall St
                ]
            }
            return []
        }
    }
}

extension Color {
    public init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
