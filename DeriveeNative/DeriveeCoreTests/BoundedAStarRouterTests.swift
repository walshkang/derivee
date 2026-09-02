import XCTest
import CxxStdlib
@testable import DeriveeCore

final class BoundedAStarRouterTests: XCTestCase {

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

        var data = Data(count: totalSize)
        data.withUnsafeMutableBytes { rawBuf in
            let ptr = rawBuf.baseAddress!
            ptr.storeBytes(of: observer.format.MAGIC_WALK_GRAPH, toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: UInt32(1), toByteOffset: 4, as: UInt32.self)
            ptr.storeBytes(of: observer.format.ENDIAN_MARKER, toByteOffset: 8, as: UInt32.self)
            ptr.storeBytes(of: UInt32(232), toByteOffset: 12, as: UInt32.self)
            ptr.storeBytes(of: UInt64(totalSize), toByteOffset: 16, as: UInt64.self)
            ptr.storeBytes(of: UInt64(0), toByteOffset: 24, as: UInt64.self)
            ptr.storeBytes(of: UInt32(2), toByteOffset: 32, as: UInt32.self)
            ptr.storeBytes(of: UInt32(0), toByteOffset: 36, as: UInt32.self)

            func writeTOC(index: Int, offset: Int, size: Int, count: Int) {
                let tocBase = 40 + index * 24
                ptr.storeBytes(of: UInt64(offset), toByteOffset: tocBase, as: UInt64.self)
                ptr.storeBytes(of: UInt64(size), toByteOffset: tocBase + 8, as: UInt64.self)
                ptr.storeBytes(of: UInt64(count), toByteOffset: tocBase + 16, as: UInt64.self)
            }

            writeTOC(index: 0, offset: offS0, size: lenS0, count: nodes.count)
            writeTOC(index: 1, offset: offS1, size: lenS1, count: edges.count)

            for (i, n) in nodes.enumerated() {
                ptr.storeBytes(of: n, toByteOffset: offS0 + i * MemoryLayout<observer.format.WalkNode>.size, as: observer.format.WalkNode.self)
            }
            for (i, e) in edges.enumerated() {
                ptr.storeBytes(of: e, toByteOffset: offS1 + i * MemoryLayout<observer.format.WalkEdge>.size, as: observer.format.WalkEdge.self)
            }
        }
        return data
    }

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

    func testWalkGraphBinaryHeaderValidation() {
        var store = WalkGraphStore()
        XCTAssertFalse(store.is_loaded())

        // 1. Valid binary
        let n0 = makeNode(lat: 40.7300, lon: -73.9900)
        let validData = buildSyntheticWalkGraph(nodes: [n0], edges: [])

        let loaded = validData.withUnsafeBytes { raw in
            store.load_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        XCTAssertTrue(loaded)
        XCTAssertTrue(store.is_loaded())
        XCTAssertEqual(store.node_count(), 1)
        XCTAssertEqual(store.edge_count(), 0)

        // 2. Corrupt magic
        var corruptData = validData
        corruptData.withUnsafeMutableBytes { raw in
            raw.baseAddress?.storeBytes(of: UInt32(0xDEADBEEF), toByteOffset: 0, as: UInt32.self)
        }
        var corruptStore = WalkGraphStore()
        let corruptLoaded = corruptData.withUnsafeBytes { raw in
            corruptStore.load_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        XCTAssertFalse(corruptLoaded)
        XCTAssertFalse(corruptStore.is_loaded())

        // 3. Truncated data
        var truncatedStore = WalkGraphStore()
        let truncatedLoaded = validData.prefix(100).withUnsafeBytes { raw in
            truncatedStore.load_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        XCTAssertFalse(truncatedLoaded)
    }

    func testSpatialGridNearestNode() {
        var grid = WalkSpatialGrid()
        XCTAssertFalse(grid.is_built())

        let nodes = [
            makeNode(lat: 40.7300, lon: -73.9920), // Node 0
            makeNode(lat: 40.7350, lon: -73.9910)  // Node 1
        ]

        nodes.withUnsafeBufferPointer { buf in
            grid.build(buf.baseAddress, buf.count)
        }
        XCTAssertTrue(grid.is_built())

        // Query near Node 0: (40.7302, -73.9919) ~25m away
        var distCM: UInt32 = 0
        let nearest = grid.find_nearest_node(
            Int32(40.7302 * 1e7),
            Int32(-73.9919 * 1e7),
            500.0,
            &distCM
        )
        XCTAssertEqual(nearest, 0)
        XCTAssertGreaterThan(distCM, 1000) // >10m
        XCTAssertLessThan(distCM, 4000)    // <40m
    }

    func testBoundedOneToManyDijkstraSearch() {
        var router = BoundedAStarRouter()

        // Synthetic graph:
        // Node 0 (origin entry): (40.7300, -73.9900)
        // Node 1: (40.7320, -73.9900), edge 0 -> 1 (222m = 22200cm)
        // Node 2: (40.7350, -73.9900), edge 1 -> 2 (333m = 33300cm) -> total from 0 = 555m
        // Node 3: (40.7420, -73.9900), edge 2 -> 3 (778m = 77800cm) -> total from 0 = 1333m
        let nodes = [
            makeNode(lat: 40.7300, lon: -73.9900, firstEdge: 0, edgeCount: 1),
            makeNode(lat: 40.7320, lon: -73.9900, firstEdge: 1, edgeCount: 1),
            makeNode(lat: 40.7350, lon: -73.9900, firstEdge: 2, edgeCount: 1),
            makeNode(lat: 40.7420, lon: -73.9900, firstEdge: 3, edgeCount: 0)
        ]
        let edges = [
            makeEdge(target: 1, distCM: 22200, weightMS: 17000), // 0 -> 1
            makeEdge(target: 2, distCM: 33300, weightMS: 25600), // 1 -> 2
            makeEdge(target: 3, distCM: 60000, weightMS: 46000)  // 2 -> 3
        ]

        let walkData = buildSyntheticWalkGraph(nodes: nodes, edges: edges)
        let loaded = walkData.withUnsafeBytes { raw in
            router.load_walk_graph_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        XCTAssertTrue(loaded)
        XCTAssertEqual(router.walk_nodes_count(), 4)

        // Stops located exactly at Node 1 (Stop 0), Node 2 (Stop 1), Node 3 (Stop 2)
        let stops = [
            Stop(40.7320, -73.9900, 0, 0, 1, 0), // Stop 0 @ Node 1 (~222m)
            Stop(40.7350, -73.9900, 1, 0, 1, 0), // Stop 1 @ Node 2 (~555m)
            Stop(40.7420, -73.9900, 2, 0, 1, 0)  // Stop 2 @ Node 3 (~1333m)
        ]
        stops.withUnsafeBufferPointer { buf in
            router.bind_stops(buf.baseAddress, buf.count)
        }

        // Bounded search from Node 0 vicinity with radius 800m
        let reachable = router.find_reachable_stops(40.7300, -73.9900, 800.0, 0, 10)

        // Must find Stop 0 (~222m) and Stop 1 (~555m)
        // Must NOT find Stop 2 (~1333m > 800m bounded cutoff)
        XCTAssertEqual(reachable.size(), 2)
        XCTAssertEqual(reachable[0].stop_id, 0)
        XCTAssertEqual(reachable[1].stop_id, 1)
        XCTAssertGreaterThan(reachable[0].distance_meters, 200.0)
        XCTAssertLessThan(reachable[0].distance_meters, 250.0)
        XCTAssertGreaterThan(reachable[1].distance_meters, 500.0)
        XCTAssertLessThan(reachable[1].distance_meters, 600.0)
    }

    func testWheelchairAccessibilityPruning() {
        var router = BoundedAStarRouter()

        // Graph with two routes to Node 2:
        // Node 0 -> Node 1 (has steps): edge dist = 100m, Node 1 has WALK_FLAG_IS_STEPS
        // Node 1 -> Node 2: edge dist = 50m (total 150m via steps)
        // Node 0 -> Node 3 (ramp/wheelchair): edge dist = 150m, Node 3 accessible
        // Node 3 -> Node 2: edge dist = 100m (total 250m via ramp)
        let nodes = [
            makeNode(lat: 40.7300, lon: -73.9900, firstEdge: 0, edgeCount: 2),
            makeNode(lat: 40.7308, lon: -73.9900, firstEdge: 2, edgeCount: 1, flags: UInt16(WALK_FLAG_IS_STEPS)),
            makeNode(lat: 40.7315, lon: -73.9900, firstEdge: 3, edgeCount: 0),
            makeNode(lat: 40.7300, lon: -73.9880, firstEdge: 3, edgeCount: 1, flags: UInt16(WALK_FLAG_WHEELCHAIR_ACCESSIBLE))
        ]
        let edges = [
            makeEdge(target: 1, distCM: 10000, weightMS: 7700),  // 0 -> 1 (steps)
            makeEdge(target: 3, distCM: 15000, weightMS: 11500), // 0 -> 3 (ramp)
            makeEdge(target: 2, distCM: 5000, weightMS: 3800),   // 1 -> 2
            makeEdge(target: 2, distCM: 10000, weightMS: 7700)   // 3 -> 2
        ]

        let walkData = buildSyntheticWalkGraph(nodes: nodes, edges: edges)
        walkData.withUnsafeBytes { raw in
            router.load_walk_graph_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        let stops = [Stop(40.7315, -73.9900, 0, 0, 1, 0)] // Stop 0 @ Node 2
        stops.withUnsafeBufferPointer { buf in
            router.bind_stops(buf.baseAddress, buf.count)
        }

        // 1. Standard search (flags = 0): picks shortest ~150m path via steps
        let standard = router.find_reachable_stops(40.7300, -73.9900, 800.0, 0, 10)
        XCTAssertEqual(standard.size(), 1)
        XCTAssertEqual(standard[0].distance_meters, 150.0, accuracy: 1.0)

        // 2. Wheelchair search: prunes steps path, chooses ~250m ramp path
        let wheelchair = router.find_reachable_stops(40.7300, -73.9900, 800.0, UInt16(ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE), 10)
        XCTAssertEqual(wheelchair.size(), 1)
        XCTAssertEqual(wheelchair[0].distance_meters, 250.0, accuracy: 1.0)
    }

    func testPointToPointDirectWalkAStar() {
        var router = BoundedAStarRouter()

        let nodes = [
            makeNode(lat: 40.7300, lon: -73.9900, firstEdge: 0, edgeCount: 1),
            makeNode(lat: 40.7330, lon: -73.9900, firstEdge: 1, edgeCount: 0)
        ]
        let edges = [
            makeEdge(target: 1, distCM: 35000, weightMS: 27000) // 350m to Node 1
        ]

        let walkData = buildSyntheticWalkGraph(nodes: nodes, edges: edges)
        walkData.withUnsafeBytes { raw in
            router.load_walk_graph_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        // Direct walk from (40.7300, -73.9900) to (40.7330, -73.9900)
        let res = router.compute_direct_walk(40.7300, -73.9900, 40.7330, -73.9900, 2000.0, 0)
        XCTAssertTrue(res.path_found)
        XCTAssertGreaterThan(res.distance_meters, 340.0)
        XCTAssertLessThan(res.distance_meters, 360.0)
        XCTAssertGreaterThan(res.walk_duration_sec, 25)
    }

    func testExecutionTimeBudgetBenchmark() {
        var router = BoundedAStarRouter()

        // Build a 15x15 grid of nodes (225 nodes, ~400 edges)
        var nodes: [observer.format.WalkNode] = []
        var edges: [observer.format.WalkEdge] = []

        let gridW = 15
        let gridH = 15
        for y in 0..<gridH {
            for x in 0..<gridW {
                let firstEdge = UInt32(edges.count)
                var count: UInt16 = 0

                // Right edge
                if x + 1 < gridW {
                    let target = UInt32(y * gridW + (x + 1))
                    edges.append(makeEdge(target: target, distCM: 5500, weightMS: 4200)) // 55m
                    count += 1
                }
                // Up edge
                if y + 1 < gridH {
                    let target = UInt32((y + 1) * gridW + x)
                    edges.append(makeEdge(target: target, distCM: 5500, weightMS: 4200)) // 55m
                    count += 1
                }

                let lat = 40.7300 + Double(y) * 0.0005
                let lon = -73.9900 + Double(x) * 0.0005
                nodes.append(makeNode(lat: lat, lon: lon, firstEdge: firstEdge, edgeCount: count))
            }
        }

        let walkData = buildSyntheticWalkGraph(nodes: nodes, edges: edges)
        walkData.withUnsafeBytes { raw in
            router.load_walk_graph_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        // Add 20 stops scattered across grid
        var stops: [Stop] = []
        for i in 0..<20 {
            let nodeIdx = (i * 11) % nodes.count
            let n = nodes[nodeIdx]
            let lat = Float(Double(n.lat_quantized) * 1e-7)
            let lon = Float(Double(n.lon_quantized) * 1e-7)
            stops.append(Stop(lat, lon, UInt32(i), 0, 1, 0))
        }
        stops.withUnsafeBufferPointer { buf in
            router.bind_stops(buf.baseAddress, buf.count)
        }

        // Run 100 consecutive searches and measure execution time
        let start = CACurrentMediaTime()
        let iterations = 100
        for _ in 0..<iterations {
            let results = router.find_reachable_stops(40.7330, -73.9870, 800.0, 0, 16)
            _ = results.size()
        }
        let elapsedSec = CACurrentMediaTime() - start
        let avgMs = (elapsedSec / Double(iterations)) * 1000.0

        // Target: <3ms execution budget
        XCTAssertLessThan(avgMs, 3.0, "Average search time (\(avgMs) ms) must be strictly under 3ms budget")
    }
}
