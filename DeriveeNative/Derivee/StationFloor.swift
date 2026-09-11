import Foundation
import CoreLocation

/// Model representing a discrete architectural floor slice of a multi-level transit station complex.
/// Built strictly to Research Doc 15 (§2) and Research Doc 20 (§3) for Wave Q.4 (WQ4-2D-FLOORPLAN-VIEWER).
public struct StationFloor: Identifiable, Hashable, Equatable, Comparable, Sendable {
    public var id: String { "\(complexId)_\(ordinal)" }
    
    /// GTFS complex identifier (e.g., "600001" for Penn Station, "600002" for Grand Central).
    public let complexId: String
    
    /// Normalized floating-point floor index used for discrete client-side filtering (e.g. 0.0, -1.0, -2.0, -1.5).
    public let level: Double
    
    /// Normalized vertical integer sequence relative to ground level (0).
    public let ordinal: Int
    
    /// Human-readable floor label (e.g., "Moynihan Train Hall Concourse", "Platform Level").
    public let name: String
    
    /// Compact short badge identifier for chips and pills (e.g., "0", "-1", "-2", or "G", "B1", "B2").
    public let shortName: String
    
    /// Set of feature types located on this floor (e.g. "mezzanine", "platform", "steps", "subway_entrance").
    public let featureTypes: Set<String>
    
    /// Array of connected levels for multi-level structures on this floor (e.g. [-1.0, -2.0]).
    public let connectedLevels: [Double]
    
    public init(
        complexId: String,
        level: Double,
        ordinal: Int,
        name: String,
        shortName: String? = nil,
        featureTypes: Set<String> = [],
        connectedLevels: [Double] = []
    ) {
        self.complexId = complexId
        self.level = level
        self.ordinal = ordinal
        self.name = name
        self.featureTypes = featureTypes
        self.connectedLevels = connectedLevels
        
        if let explicitShort = shortName, !explicitShort.isEmpty {
            self.shortName = explicitShort
        } else {
            // Standard transit floor notation: 0 -> "0" or "G", -1 -> "-1" or "B1", -2 -> "-2" or "B2"
            if ordinal == 0 {
                self.shortName = "0"
            } else if ordinal < 0 {
                self.shortName = "\(ordinal)"
            } else {
                self.shortName = "+\(ordinal)"
            }
        }
    }
    
    public var isGround: Bool { ordinal == 0 }
    public var isSubterranean: Bool { ordinal < 0 }
    public var isElevated: Bool { ordinal > 0 }
    
    public var hasPlatforms: Bool {
        featureTypes.contains("platform") || featureTypes.contains("station_platform")
    }
    
    public var hasMezzanine: Bool {
        featureTypes.contains("mezzanine") || featureTypes.contains("corridor") || featureTypes.contains("room")
    }
    
    public var hasExits: Bool {
        featureTypes.contains("subway_entrance") || featureTypes.contains("portal")
    }
    
    public var hasVerticalCirculation: Bool {
        featureTypes.contains("steps") || featureTypes.contains("escalator") || featureTypes.contains("elevator")
    }
    
    // Sort descending by ordinal: Ground (0) -> Mezzanine (-1) -> Platform (-2)
    // Matches physical top-down vertical layout for floor steppers
    public static func < (lhs: StationFloor, rhs: StationFloor) -> Bool {
        if lhs.ordinal != rhs.ordinal {
            return lhs.ordinal > rhs.ordinal
        }
        return lhs.level > rhs.level
    }
}

/// Central registry and in-memory cache for station complex 2D multi-level floorplans.
/// Indexes features from `station_shapes.geojson` and provides sub-millisecond floor queries.
public final class StationFloorplanStore: @unchecked Sendable {
    public static let shared = StationFloorplanStore()
    
    private let lock = NSLock()
    private var floorsByComplex: [String: [StationFloor]] = [:]
    private var complexIdByStopId: [String: String] = [:]
    private var isInitialized = false
    
    public init() {
        bootstrap()
    }
    
    /// Bootstraps the store by parsing station shapes from the primary GeoJSON resource.
    public func bootstrap(citySlug: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        floorsByComplex.removeAll()
        
        guard let url = StationCartographyLoader.resolveStationShapesGeoJSONURL(for: citySlug),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            isInitialized = true
            return
        }
        
        // Group features by (complex_id, ordinal)
        struct FloorAccumulator {
            let complexId: String
            let level: Double
            let ordinal: Int
            var names: [String] = []
            var featureTypes: Set<String> = []
            var connectedLevels: Set<Double> = []
        }
        
        var accumulators: [String: FloorAccumulator] = [:]
        
        for feat in features {
            guard let properties = feat["properties"] as? [String: Any],
                  let complexId = properties["complex_id"] as? String,
                  let levelNum = properties["level"] as? NSNumber,
                  let ordinalNum = properties["ordinal"] as? NSNumber else {
                continue
            }
            
            let level = levelNum.doubleValue
            let ordinal = ordinalNum.intValue
            let key = "\(complexId)_\(ordinal)"
            
            let featureType = properties["feature_type"] as? String ?? ""
            let levelName = properties["level_name"] as? String ?? properties["name"] as? String
            
            var acc = accumulators[key] ?? FloorAccumulator(
                complexId: complexId,
                level: level,
                ordinal: ordinal
            )
            
            if let name = levelName, !name.isEmpty, !acc.names.contains(name) {
                acc.names.append(name)
            }
            if !featureType.isEmpty {
                acc.featureTypes.insert(featureType)
            }
            
            // Collect multi-level connector links
            if let connects = properties["connects_levels"] as? [NSNumber] {
                for c in connects {
                    acc.connectedLevels.insert(c.doubleValue)
                }
            } else if let levelsStr = properties["levels"] as? String {
                let tokens = levelsStr.components(separatedBy: ";")
                for t in tokens {
                    if let d = Double(t.trimmingCharacters(in: .whitespaces)) {
                        acc.connectedLevels.insert(d)
                    }
                }
            }
            
            accumulators[key] = acc
        }
        
        // Convert accumulators to StationFloor models grouped by complexId
        for (_, acc) in accumulators {
            let preferredName: String
            if let first = acc.names.first(where: { !$0.isEmpty }) {
                preferredName = first
            } else if acc.ordinal == 0 {
                preferredName = "Street Level"
            } else if acc.ordinal == -1 {
                preferredName = "Mezzanine Concourse"
            } else if acc.ordinal < -1 {
                preferredName = "Platform Level \(abs(acc.ordinal))"
            } else {
                preferredName = "Level \(acc.ordinal)"
            }
            
            let floor = StationFloor(
                complexId: acc.complexId,
                level: acc.level,
                ordinal: acc.ordinal,
                name: preferredName,
                featureTypes: acc.featureTypes,
                connectedLevels: Array(acc.connectedLevels).sorted()
            )
            
            var list = floorsByComplex[acc.complexId] ?? []
            list.append(floor)
            floorsByComplex[acc.complexId] = list
        }
        
        // Sort each complex's floors descending by ordinal (Ground -> Mezzanine -> Platform)
        for (cid, list) in floorsByComplex {
            floorsByComplex[cid] = list.sorted()
        }
        
        isInitialized = true
    }
    
    /// Returns sorted floors for a given complex ID (descending: 0 -> -1 -> -2).
    public func floors(for complexId: String) -> [StationFloor] {
        lock.lock()
        defer { lock.unlock() }
        return floorsByComplex[complexId] ?? []
    }
    
    /// Returns whether the specified complex has multiple vertical storeys available.
    public func hasMultiLevelFloorplan(for complexId: String) -> Bool {
        return floors(for: complexId).count > 1
    }
    
    /// Resolves the default floor for a station complex (defaults to primary mezzanine -1, or ground 0).
    public func defaultFloor(for complexId: String) -> StationFloor? {
        let available = floors(for: complexId)
        guard !available.isEmpty else { return nil }
        // Preference order: Mezzanine (-1), then Ground (0), then deepest platform
        if let mez = available.first(where: { $0.ordinal == -1 }) {
            return mez
        }
        if let gnd = available.first(where: { $0.ordinal == 0 }) {
            return gnd
        }
        return available.first
    }
    
    /// Returns a specific floor by ordinal integer.
    public func floor(for complexId: String, ordinal: Int) -> StationFloor? {
        let available = floors(for: complexId)
        return available.first(where: { $0.ordinal == ordinal })
    }
    
    /// Dynamically resolves the complex ID for a given stopId.
    /// Integrates with `SpatialDatabaseManager` and in-memory caches.
    public func resolveComplexId(for stopId: String) async -> String? {
        lock.lock()
        if let cached = complexIdByStopId[stopId] {
            lock.unlock()
            return cached
        }
        if floorsByComplex[stopId] != nil {
            complexIdByStopId[stopId] = stopId
            lock.unlock()
            return stopId
        }
        lock.unlock()
        
        // 1. Check if SpatialDatabaseManager can resolve parent complex
        if let complex = try? await SpatialDatabaseManager.shared.fetchComplex(forStopId: stopId) {
            let cid = String(complex.id)
            lock.lock()
            complexIdByStopId[stopId] = cid
            lock.unlock()
            return cid
        }
        
        // 2. Fallback heuristic: strip direction suffix (e.g. "602N" -> "602")
        let baseStopId = stopId.trimmingCharacters(in: CharacterSet.letters)
        if !baseStopId.isEmpty && baseStopId != stopId {
            lock.lock()
            if floorsByComplex[baseStopId] != nil {
                complexIdByStopId[stopId] = baseStopId
                lock.unlock()
                return baseStopId
            }
            lock.unlock()
        }
        
        return nil
    }
    
    /// Seeds an in-memory mapping from stop ID to complex ID.
    public func registerStopMapping(stopId: String, complexId: String) {
        lock.lock()
        defer { lock.unlock() }
        complexIdByStopId[stopId] = complexId
    }
}
