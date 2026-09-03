import XCTest
import CxxStdlib
@testable import DeriveeCore

final class MicroClimateEvaluatorTests: XCTestCase {

    private func align64(_ offset: Int) -> Int {
        let rem = offset % 64
        return rem == 0 ? offset : offset + (64 - rem)
    }

    private func makeNode(
        lat: Double,
        lon: Double,
        firstEdge: UInt32 = 0,
        edgeCount: UInt16 = 0,
        flags: UInt16 = UInt16(WALK_FLAG_WALKABLE)
    ) -> observer.format.WalkNode {
        var n = observer.format.WalkNode()
        n.lat_quantized = Int32(lat * 1e7)
        n.lon_quantized = Int32(lon * 1e7)
        n.first_edge_idx = firstEdge
        n.edge_count = edgeCount
        n.access_flags = flags
        return n
    }

    private func makeEdge(target: UInt32, distCM: UInt16, weightMS: UInt16) -> observer.format.WalkEdge {
        var e = observer.format.WalkEdge()
        e.target_node_idx = target
        e.distance_cm = distCM
        e.weight_ms = weightMS
        return e
    }

    private func buildSyntheticWalkGraph(
        nodes: [observer.format.WalkNode],
        edges: [observer.format.WalkEdge]
    ) -> Data {
        let headerSize = 232
        let lenS0 = nodes.count * MemoryLayout<observer.format.WalkNode>.size
        let lenS1 = edges.count * MemoryLayout<observer.format.WalkEdge>.size

        let offS0 = align64(headerSize)
        let offS1 = align64(offS0 + lenS0)
        let totalSize = align64(offS1 + lenS1)

        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: totalSize, alignment: 64)
        rawPtr.initializeMemory(as: UInt8.self, repeating: 0, count: totalSize)
        rawPtr.storeBytes(of: observer.format.MAGIC_WALK_GRAPH, toByteOffset: 0, as: UInt32.self)
        rawPtr.storeBytes(of: UInt32(1), toByteOffset: 4, as: UInt32.self)
        rawPtr.storeBytes(of: observer.format.ENDIAN_MARKER, toByteOffset: 8, as: UInt32.self)
        rawPtr.storeBytes(of: UInt32(232), toByteOffset: 12, as: UInt32.self)
        rawPtr.storeBytes(of: UInt64(totalSize), toByteOffset: 16, as: UInt64.self)
        rawPtr.storeBytes(of: UInt64(0), toByteOffset: 24, as: UInt64.self)
        rawPtr.storeBytes(of: UInt32(2), toByteOffset: 32, as: UInt32.self)
        rawPtr.storeBytes(of: UInt32(0), toByteOffset: 36, as: UInt32.self)

        func writeTOC(index: Int, offset: Int, size: Int, count: Int) {
            let tocBase = 40 + index * 24
            rawPtr.storeBytes(of: UInt64(offset), toByteOffset: tocBase, as: UInt64.self)
            rawPtr.storeBytes(of: UInt64(size), toByteOffset: tocBase + 8, as: UInt64.self)
            rawPtr.storeBytes(of: UInt64(count), toByteOffset: tocBase + 16, as: UInt64.self)
        }

        writeTOC(index: 0, offset: offS0, size: lenS0, count: nodes.count)
        writeTOC(index: 1, offset: offS1, size: lenS1, count: edges.count)

        for (i, n) in nodes.enumerated() {
            rawPtr.storeBytes(of: n, toByteOffset: offS0 + i * MemoryLayout<observer.format.WalkNode>.size, as: observer.format.WalkNode.self)
        }
        for (i, e) in edges.enumerated() {
            rawPtr.storeBytes(of: e, toByteOffset: offS1 + i * MemoryLayout<observer.format.WalkEdge>.size, as: observer.format.WalkEdge.self)
        }

        return Data(bytesNoCopy: rawPtr, count: totalSize, deallocator: .custom({ ptr, _ in
            ptr.deallocate()
        }))
    }

    // MARK: - Unit Tests

    func testSolarPositionCalculation() {
        // NYC: 40.7128° N, -74.0060° W
        // Summer Solstice: June 21, 2025 ~17:00 UTC (13:00 EDT - solar noon vicinity)
        // Epoch for 2025-06-21 17:00:00 UTC = 1750525200
        let summerNoon = derivee.climate.MicroClimateEnergyEvaluator.calculate_solar_position(
            40.7128, -74.0060, 1750525200
        )
        XCTAssertTrue(summerNoon.is_daylight)
        // High solar altitude in summer noon (> 65 degrees = ~1.13 radians)
        XCTAssertGreaterThan(summerNoon.altitude_rad, 1.10)
        XCTAssertLessThan(summerNoon.altitude_rad, 1.35)
        // Azimuth near South (~180 degrees = ~3.14 radians)
        XCTAssertGreaterThan(summerNoon.azimuth_rad, 2.7)
        XCTAssertLessThan(summerNoon.azimuth_rad, 3.6)

        // Night time in NYC: June 21, 2025 04:00 UTC (00:00 EDT midnight)
        let summerMidnight = derivee.climate.MicroClimateEnergyEvaluator.calculate_solar_position(
            40.7128, -74.0060, 1750478400
        )
        XCTAssertFalse(summerMidnight.is_daylight)
        XCTAssertLessThan(summerMidnight.altitude_rad, 0.0)

        // Winter Solstice: Dec 21, 2025 ~17:00 UTC (12:00 EST noon)
        // Epoch for 2025-12-21 17:00:00 UTC = 1766336400
        let winterNoon = derivee.climate.MicroClimateEnergyEvaluator.calculate_solar_position(
            40.7128, -74.0060, 1766336400
        )
        XCTAssertTrue(winterNoon.is_daylight)
        // Lower solar altitude in winter noon (~26 degrees = ~0.45 radians)
        XCTAssertGreaterThan(winterNoon.altitude_rad, 0.35)
        XCTAssertLessThan(winterNoon.altitude_rad, 0.55)
    }

    func testBuildingShadowGeometry() {
        // High sun (altitude = 1.2 rad ~ 69°), azimuth = South (pi rad)
        let sun = derivee.climate.SolarPosition(1.2, Float.pi, Float.pi * 0.5 - 1.2, true)

        // East-West street: latitude 40.7300, lon from -73.9900 to -73.9800
        // Sun is nearly perpendicular to street (cross-canyon sin ~ 1.0)
        let shadowMidrise = derivee.climate.MicroClimateEnergyEvaluator.calculate_building_shadow(
            40.7300, -73.9900, 40.7300, -73.9800, sun, derivee.climate.MicroClimateEnergyEvaluator.canyon_aspect_mid_rise()
        )
        // Midrise canyon aspect ratio 1.2 / tan(69°) ~ 1.2 / 2.6 ~ 0.46
        XCTAssertGreaterThan(shadowMidrise, 0.35)
        XCTAssertLessThan(shadowMidrise, 0.55)

        // Highrise canyon aspect ratio 2.5 / tan(69°) ~ 2.5 / 2.6 ~ 0.96
        let shadowHighrise = derivee.climate.MicroClimateEnergyEvaluator.calculate_building_shadow(
            40.7300, -73.9900, 40.7300, -73.9800, sun, derivee.climate.MicroClimateEnergyEvaluator.canyon_aspect_high_rise()
        )
        XCTAssertGreaterThan(shadowHighrise, 0.85)

        // Lowrise aspect ratio 0.4 / tan(69°) ~ 0.4 / 2.6 ~ 0.15
        let shadowLowrise = derivee.climate.MicroClimateEnergyEvaluator.calculate_building_shadow(
            40.7300, -73.9900, 40.7300, -73.9800, sun, derivee.climate.MicroClimateEnergyEvaluator.canyon_aspect_low_rise()
        )
        XCTAssertLessThan(shadowLowrise, 0.25)
    }

    func testTreeCanopyAndCombinedShade() {
        let sun = derivee.climate.SolarPosition(1.2, Float.pi, Float.pi * 0.5 - 1.2, true)

        // Node with WALK_FLAG_TREE_CANOPY_HIGH (bit 5)
        let highCanopyFlags = UInt16(WALK_FLAG_TREE_CANOPY_HIGH)
        let shadeHigh = derivee.climate.MicroClimateEnergyEvaluator.calculate_edge_shade_factor(
            40.7300, -73.9900, 40.7310, -73.9900, sun, highCanopyFlags
        )
        // Must be at least 75% shade due to dense tree canopy
        XCTAssertGreaterThanOrEqual(shadeHigh, 0.75)

        // Node with standard flags (no canopy, lowrise)
        let baselineShade = derivee.climate.MicroClimateEnergyEvaluator.calculate_edge_shade_factor(
            40.7300, -73.9900, 40.7310, -73.9900, sun, UInt16(WALK_FLAG_WALKABLE)
        )
        XCTAssertLessThan(baselineShade, shadeHigh)
    }

    func testPETEstimation() {
        // Air temp 32°C, 60% RH, 1.0 m/s wind, high sun (altitude 1.2 rad)
        let petSun = derivee.climate.MicroClimateEnergyEvaluator.estimate_pet_celsius(
            32.0, 0.60, 1.0, 0.0, 1.2
        )
        let petShade = derivee.climate.MicroClimateEnergyEvaluator.estimate_pet_celsius(
            32.0, 0.60, 1.0, 1.0, 1.2
        )

        // In open sun, PET should be elevated (> 38°C)
        XCTAssertGreaterThan(petSun, 38.0)
        // In full shade, PET should be significantly cooler (< 41°C)
        XCTAssertLessThan(petShade, 41.0)
        // Heat relief delta must be at least 5°C
        XCTAssertGreaterThan(petSun - petShade, 5.0)
    }

    func testThermalWeightMultipliers() {
        // 1. Neutral mode: always 1.0
        var neutralConfig = derivee.climate.MicroClimateConfig()
        neutralConfig.mode = derivee.climate.ThermalComfortMode.Neutral
        XCTAssertEqual(derivee.climate.MicroClimateEnergyEvaluator.calculate_edge_weight_multiplier(0.0, neutralConfig), 1.0)
        XCTAssertEqual(derivee.climate.MicroClimateEnergyEvaluator.calculate_edge_weight_multiplier(1.0, neutralConfig), 1.0)

        // 2. Summer Shaded mode: penalizes open sun (0.0 shade -> 1.75, 1.0 shade -> 1.0)
        var summerConfig = derivee.climate.MicroClimateConfig()
        summerConfig.mode = derivee.climate.ThermalComfortMode.SummerShaded
        let summerSun = derivee.climate.MicroClimateEnergyEvaluator.calculate_edge_weight_multiplier(0.0, summerConfig)
        let summerShade = derivee.climate.MicroClimateEnergyEvaluator.calculate_edge_weight_multiplier(1.0, summerConfig)
        XCTAssertEqual(summerShade, 1.0, accuracy: 0.01)
        XCTAssertEqual(summerSun, 1.75, accuracy: 0.01)

        // 3. Winter Sunlit mode: penalizes shadow (1.0 shade -> 1.60, 0.0 shade -> 1.0)
        var winterConfig = derivee.climate.MicroClimateConfig()
        winterConfig.mode = derivee.climate.ThermalComfortMode.WinterSunlit
        let winterSun = derivee.climate.MicroClimateEnergyEvaluator.calculate_edge_weight_multiplier(0.0, winterConfig)
        let winterShade = derivee.climate.MicroClimateEnergyEvaluator.calculate_edge_weight_multiplier(1.0, winterConfig)
        XCTAssertEqual(winterSun, 1.0, accuracy: 0.01)
        XCTAssertEqual(winterShade, 1.60, accuracy: 0.01)
    }

    func testPathDivergenceInAStar() {
        var router = BoundedAStarRouter()

        // Synthetic graph with 2 alternative paths from Node 0 to Node 3:
        // Path A (Sunny Avenue): Node 0 -> Node 1 -> Node 3
        //   - Node 0 -> Node 1: 100m, flags = 0 (open sun)
        //   - Node 1 -> Node 3: 100m, flags = 0 (open sun)
        //   - Total actual distance: 200m
        //
        // Path B (Shaded Greenway): Node 0 -> Node 2 -> Node 3
        //   - Node 0 -> Node 2: 110m, flags = WALK_FLAG_TREE_CANOPY_HIGH (dense shade)
        //   - Node 2 -> Node 3: 110m, flags = WALK_FLAG_TREE_CANOPY_HIGH (dense shade)
        //   - Total actual distance: 220m (+10% detour)
        let nodes = [
            makeNode(lat: 40.7300, lon: -73.9900, firstEdge: 0, edgeCount: 2),                                      // Node 0
            makeNode(lat: 40.7309, lon: -73.9900, firstEdge: 2, edgeCount: 1),                                      // Node 1 (Sunny)
            makeNode(lat: 40.7305, lon: -73.9888, firstEdge: 3, edgeCount: 1, flags: UInt16(WALK_FLAG_TREE_CANOPY_HIGH)), // Node 2 (Shaded)
            makeNode(lat: 40.7318, lon: -73.9900, firstEdge: 4, edgeCount: 0)                                       // Node 3 (Destination)
        ]
        let edges = [
            makeEdge(target: 1, distCM: 10000, weightMS: 7700),  // 0 -> 1 (100m sunny)
            makeEdge(target: 2, distCM: 11000, weightMS: 8460),  // 0 -> 2 (110m shaded)
            makeEdge(target: 3, distCM: 10000, weightMS: 7700),  // 1 -> 3 (100m sunny)
            makeEdge(target: 3, distCM: 11000, weightMS: 8460)   // 2 -> 3 (110m shaded)
        ]

        let walkData = buildSyntheticWalkGraph(nodes: nodes, edges: edges)
        walkData.withUnsafeBytes { raw in
            router.load_walk_graph_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        // 1. Standard / Neutral Routing (Distance Optimal):
        // Path A is 200m < Path B (220m). Router MUST pick Path A (200m).
        var neutralConfig = derivee.climate.MicroClimateConfig()
        neutralConfig.mode = derivee.climate.ThermalComfortMode.Neutral
        let neutralResult = router.compute_direct_walk(40.7300, -73.9900, 40.7318, -73.9900, 2000.0, 0, neutralConfig)
        XCTAssertTrue(neutralResult.path_found)
        XCTAssertEqual(neutralResult.distance_meters, 200.0, accuracy: 2.0)

        // 2. Summer Shaded Routing:
        // Path A (sunny): 200m * 1.75 = 350m weighted cost.
        // Path B (shaded): 220m * ~1.18 = ~260m weighted cost.
        // Router MUST pick Path B (220m) for thermal comfort!
        var summerConfig = derivee.climate.MicroClimateConfig()
        summerConfig.mode = derivee.climate.ThermalComfortMode.SummerShaded
        summerConfig.ambient_temp_c = 31.0
        summerConfig.relative_humidity = 0.60
        summerConfig.has_custom_solar = true
        summerConfig.solar_altitude_rad = 1.15
        summerConfig.solar_azimuth_rad = Float.pi
        let summerResult = router.compute_direct_walk(40.7300, -73.9900, 40.7318, -73.9900, 2000.0, 0, summerConfig)
        XCTAssertTrue(summerResult.path_found)
        XCTAssertEqual(summerResult.distance_meters, 220.0, accuracy: 2.0)
        XCTAssertGreaterThan(summerResult.shade_percentage, 60.0)

        // 3. Winter Sunlit Routing:
        // Path A (sunny): 200m * 1.0 = 200m weighted cost.
        // Path B (shaded): 220m * ~1.45 = ~319m weighted cost.
        // Router MUST pick Path A (200m) to maximize sun warmth!
        var winterConfig = derivee.climate.MicroClimateConfig()
        winterConfig.mode = derivee.climate.ThermalComfortMode.WinterSunlit
        winterConfig.ambient_temp_c = 4.0
        winterConfig.relative_humidity = 0.45
        winterConfig.has_custom_solar = true
        winterConfig.solar_altitude_rad = 0.50
        winterConfig.solar_azimuth_rad = Float.pi
        let winterResult = router.compute_direct_walk(40.7300, -73.9900, 40.7318, -73.9900, 2000.0, 0, winterConfig)
        XCTAssertTrue(winterResult.path_found)
        XCTAssertEqual(winterResult.distance_meters, 200.0, accuracy: 2.0)
        XCTAssertLessThan(winterResult.shade_percentage, 40.0)
    }

    func testMicroclimateExecutionBudgetBenchmark() {
        var router = BoundedAStarRouter()

        // Build a 10x10 grid of nodes (100 nodes, ~180 edges)
        var nodes: [observer.format.WalkNode] = []
        var edges: [observer.format.WalkEdge] = []

        let gridW = 10
        let gridH = 10
        for y in 0..<gridH {
            for x in 0..<gridW {
                let firstEdge = UInt32(edges.count)
                var count: UInt16 = 0

                if x + 1 < gridW {
                    let target = UInt32(y * gridW + (x + 1))
                    edges.append(makeEdge(target: target, distCM: 5000, weightMS: 3800))
                    count += 1
                }
                if y + 1 < gridH {
                    let target = UInt32((y + 1) * gridW + x)
                    edges.append(makeEdge(target: target, distCM: 5000, weightMS: 3800))
                    count += 1
                }

                let lat = 40.7300 + Double(y) * 0.0005
                let lon = -73.9900 + Double(x) * 0.0005
                let flags: UInt16 = (x % 2 == 0) ? UInt16(WALK_FLAG_TREE_CANOPY_HIGH) : UInt16(WALK_FLAG_WALKABLE)
                nodes.append(makeNode(lat: lat, lon: lon, firstEdge: firstEdge, edgeCount: count, flags: flags))
            }
        }

        let walkData = buildSyntheticWalkGraph(nodes: nodes, edges: edges)
        walkData.withUnsafeBytes { raw in
            router.load_walk_graph_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        var summerConfig = derivee.climate.MicroClimateConfig()
        summerConfig.mode = derivee.climate.ThermalComfortMode.SummerShaded
        summerConfig.ambient_temp_c = 31.0
        let iterations = 100
        let start = CACurrentMediaTime()
        for _ in 0..<iterations {
            _ = router.compute_direct_walk(40.7300, -73.9900, 40.7340, -73.9860, 2000.0, 0, summerConfig)
        }
        let elapsed = CACurrentMediaTime() - start
        let avgMs = (elapsed / Double(iterations)) * 1000.0

        // Target: strictly under 3.0ms budget
        XCTAssertLessThan(avgMs, 3.0, "Microclimate direct walk A* (\(avgMs) ms) must execute under 3.0ms budget")
    }
}
