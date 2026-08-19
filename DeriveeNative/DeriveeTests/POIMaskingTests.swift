import XCTest
import CoreLocation
@testable import Derivee

final class POIMaskingTests: XCTestCase {
    
    func testActiveVicinityPhaseResolution() {
        let userLocation = CLLocation(latitude: 40.7128, longitude: -74.0060)
        // POI 50 meters north of user
        let nearCoord = CLLocationCoordinate2D(latitude: 40.7132, longitude: -74.0060)
        let poi = GhostPOI(id: "stop_1", name: "Nearby Stop", coordinate: nearCoord, type: 1, h3Index: "8b2a100d6c91fff")
        
        let phase = POIMaskManager.resolvePhase(
            poi: poi,
            userLocation: userLocation,
            exploredHexes: [],
            discoveredPOIs: []
        )
        
        XCTAssertEqual(phase, 2, "POI within 200m should resolve to Phase 2 (Active)")
    }
    
    func testExploredPOIFadesToArchivePhase() {
        let userLocation = CLLocation(latitude: 40.7128, longitude: -74.0060)
        // POI ~600m away
        let farCoord = CLLocationCoordinate2D(latitude: 40.7180, longitude: -74.0060)
        let hex = "8b2a100d6c91fff"
        let poi = GhostPOI(id: "stop_explored", name: "Explored Stop", coordinate: farCoord, type: 1, h3Index: hex)
        
        // 1. Explored via exploredHexes
        let phaseHex = POIMaskManager.resolvePhase(
            poi: poi,
            userLocation: userLocation,
            exploredHexes: [hex],
            discoveredPOIs: []
        )
        XCTAssertEqual(phaseHex, 3, "Explored POI > 200m should resolve to Phase 3 (Archive)")
        
        // 2. Explored via discoveredPOIs
        let phaseDiscovered = POIMaskManager.resolvePhase(
            poi: poi,
            userLocation: userLocation,
            exploredHexes: [],
            discoveredPOIs: ["stop_explored"]
        )
        XCTAssertEqual(phaseDiscovered, 3, "Discovered POI > 200m should resolve to Phase 3 (Archive)")
    }
    
    func testUnexploredPOIFallsToLurePhase() {
        let userLocation = CLLocation(latitude: 40.7128, longitude: -74.0060)
        // POI ~500m away, unexplored
        let midCoord = CLLocationCoordinate2D(latitude: 40.7170, longitude: -74.0060)
        let poi = GhostPOI(id: "stop_lure", name: "Lure Stop", coordinate: midCoord, type: 1, h3Index: "8b2a100d6c92fff")
        
        let phase = POIMaskManager.resolvePhase(
            poi: poi,
            userLocation: userLocation,
            exploredHexes: [],
            discoveredPOIs: []
        )
        
        XCTAssertEqual(phase, 1, "Unexplored POI between 200m and 1000m should resolve to Phase 1 (Lure)")
    }
    
    func testUnexploredPOIOutsideLureRadiusIsHidden() {
        let userLocation = CLLocation(latitude: 40.7128, longitude: -74.0060)
        // POI ~2.5km away, unexplored
        let distantCoord = CLLocationCoordinate2D(latitude: 40.7350, longitude: -74.0060)
        let poi = GhostPOI(id: "stop_distant", name: "Distant Stop", coordinate: distantCoord, type: 1, h3Index: "8b2a100d6c93fff")
        
        let phase = POIMaskManager.resolvePhase(
            poi: poi,
            userLocation: userLocation,
            exploredHexes: [],
            discoveredPOIs: []
        )
        
        XCTAssertNil(phase, "Unexplored POI beyond 1000m should be hidden (nil phase)")
    }
    
    func testComputeH3IndexDeterminism() {
        let lat = 40.71767
        let lon = -73.95677
        let h3Index = POIMaskManager.computeH3Index(latitude: lat, longitude: lon)
        
        XCTAssertFalse(h3Index.isEmpty, "H3 index should not be empty")
        XCTAssertEqual(h3Index.count, 15, "H3 Res-11 index hex string should be 15 characters")
    }
    
    func testHiddenMarkerStyleSuppressesAllMarkers() {
        let userLocation = CLLocation(latitude: 40.7128, longitude: -74.0060)
        let nearCoord = CLLocationCoordinate2D(latitude: 40.7132, longitude: -74.0060)
        let hex = "8b2a100d6c91fff"
        let poi = GhostPOI(id: "stop_1", name: "Nearby Stop", coordinate: nearCoord, type: 1, h3Index: hex)
        
        let phase = POIMaskManager.resolvePhase(
            poi: poi,
            userLocation: userLocation,
            exploredHexes: [hex],
            discoveredPOIs: ["stop_1"],
            markerStyle: .hidden
        )
        
        XCTAssertNil(phase, "Hidden marker style must return nil to suppress all visual markers on map")
    }
    
    func testAllStationsMarkerStyleWithActiveAndExplored() {
        let userLocation = CLLocation(latitude: 40.7128, longitude: -74.0060)
        let nearCoord = CLLocationCoordinate2D(latitude: 40.7132, longitude: -74.0060)
        let hex = "8b2a100d6c91fff"
        let poiNear = GhostPOI(id: "stop_near", name: "Near Stop", coordinate: nearCoord, type: 1, h3Index: hex)
        
        let phaseNear = POIMaskManager.resolvePhase(
            poi: poiNear,
            userLocation: userLocation,
            exploredHexes: [],
            discoveredPOIs: [],
            markerStyle: .allStations
        )
        XCTAssertEqual(phaseNear, 2, "POI <= 200m in .allStations mode should still resolve to Phase 2 (Active)")
        
        let farCoord = CLLocationCoordinate2D(latitude: 40.7350, longitude: -74.0060)
        let poiExploredFar = GhostPOI(id: "stop_exp_far", name: "Explored Far Stop", coordinate: farCoord, type: 1, h3Index: "8b2a100d6c93fff")
        let phaseExploredFar = POIMaskManager.resolvePhase(
            poi: poiExploredFar,
            userLocation: userLocation,
            exploredHexes: ["8b2a100d6c93fff"],
            discoveredPOIs: [],
            markerStyle: .allStations
        )
        XCTAssertEqual(phaseExploredFar, 3, "Explored POI in .allStations mode should resolve to Phase 3 (Archive)")
    }
    
    func testBaseVectorPOILayersDefinition() {
        XCTAssertEqual(POIMaskManager.baseVectorPOILayerIds.count, 10)
        XCTAssertTrue(POIMaskManager.baseVectorPOILayerIds.contains("Public"))
        XCTAssertTrue(POIMaskManager.baseVectorPOILayerIds.contains("Shopping"))
        XCTAssertTrue(POIMaskManager.baseVectorPOILayerIds.contains("Food"))
        XCTAssertTrue(POIMaskManager.baseVectorPOILayerIds.contains("Park"))
        XCTAssertEqual(POIMaskManager.baseStationLayerId, "Station")
        XCTAssertEqual(POIMaskManager.activeVicinityRadius, 200.0)
        XCTAssertEqual(POIMaskManager.lureMaxRadius, 1000.0)
    }
}
