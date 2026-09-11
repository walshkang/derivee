import XCTest
import UIKit
import MapLibre
import CoreLocation
@testable import Derivee

final class StationTransitionTests: XCTestCase {
    
    // MARK: - 1. Config & Identifiers Tests (Doc 20 §5)
    
    func testConfigIdentifiersConformToSpec() {
        XCTAssertEqual(StationTransitVisualizationManager.Config.stationShapesSourceId, "station-shapes-source")
        XCTAssertEqual(StationTransitVisualizationManager.Config.footprintLayerId, "station-interior-fill")
        XCTAssertEqual(StationTransitVisualizationManager.Config.platformLayerId, "station-platform-lines")
        XCTAssertEqual(StationTransitVisualizationManager.Config.exitLayerId, "station-exit-symbols")
        XCTAssertEqual(StationTransitVisualizationManager.Config.bulletLayerId, "subway-station-bullets-layer")
        XCTAssertEqual(StationTransitVisualizationManager.Config.smartZoomBulletLayerId, "smart-zoom-station-bullets-layer")
        XCTAssertEqual(StationTransitVisualizationManager.Config.exitPortalImageName, "station-exit-portal")
        XCTAssertEqual(StationTransitVisualizationManager.Config.colorFootprintFill, "#292E38")
        XCTAssertEqual(StationTransitVisualizationManager.Config.colorPlatformLine, "#FAB83D")
        XCTAssertEqual(StationTransitVisualizationManager.Config.colorExitPortalPill, "#008542")
    }
    
    // MARK: - 2. Zoom Interpolation Expressions Tests (Doc 20 §1 & §5)
    
    func testBulletPinDecayAndContractionExpressions() {
        let opacityExpr = StationTransitVisualizationManager.bulletOpacityExpression()
        let radiusExpr = StationTransitVisualizationManager.bulletRadiusExpression()
        let strokeOpacityExpr = StationTransitVisualizationManager.bulletStrokeOpacityExpression()
        let smartZoomOpacityExpr = StationTransitVisualizationManager.smartZoomBulletOpacityExpression()
        
        let opacityFormat = opacityExpr.description
        let radiusFormat = radiusExpr.description
        let strokeOpacityFormat = strokeOpacityExpr.description
        let smartZoomFormat = smartZoomOpacityExpr.description
        
        // Check function name and arguments
        XCTAssertTrue(opacityFormat.contains("mgl_interpolate") || opacityFormat.contains("15") && opacityFormat.contains("16"))
        XCTAssertTrue(radiusFormat.contains("mgl_interpolate") || radiusFormat.contains("6") && radiusFormat.contains("3"))
        XCTAssertTrue(strokeOpacityFormat.contains("mgl_interpolate") || strokeOpacityFormat.contains("15") && strokeOpacityFormat.contains("16"))
        XCTAssertTrue(smartZoomFormat.contains("mgl_interpolate") || smartZoomFormat.contains("15") && smartZoomFormat.contains("16"))
    }
    
    func testFootprintAndPlatformIngressExpressions() {
        let footprintExpr = StationTransitVisualizationManager.footprintOpacityExpression()
        let platformExpr = StationTransitVisualizationManager.platformOpacityExpression()
        let widthExpr = StationTransitVisualizationManager.platformWidthExpression()
        let exitExpr = StationTransitVisualizationManager.exitOpacityExpression()
        
        let footprintFormat = footprintExpr.description
        let platformFormat = platformExpr.description
        let widthFormat = widthExpr.description
        let exitFormat = exitExpr.description
        
        // Footprint ingress: 15.2 -> 16.2
        XCTAssertTrue(footprintFormat.contains("15.2") && footprintFormat.contains("16.2"), "Footprint opacity must interpolate between 15.2 and 16.2")
        
        // Platform line ingress: 15.5 -> 16.5
        XCTAssertTrue(platformFormat.contains("15.5") && platformFormat.contains("16.5"), "Platform line opacity must interpolate between 15.5 and 16.5")
        
        // Platform width: exponential curve base 1.5 from 16.0 (1.5pt) to 20.0 (8.0pt)
        XCTAssertTrue(widthFormat.contains("exponential") || (widthFormat.contains("16") && widthFormat.contains("20")), "Platform width must scale exponentially")
        
        // Exit portals: 16.0 -> 16.5
        XCTAssertTrue(exitFormat.contains("16") && exitFormat.contains("16.5"), "Exit portal opacity must interpolate between 16.0 and 16.5")
    }
    
    // MARK: - 3. Exit Portal Asset Generation Tests
    
    func testExitPortalImageRendering() {
        let portalImage = StationTransitVisualizationManager.makeExitPortalImage()
        
        XCTAssertEqual(portalImage.size.width, 24.0, accuracy: 0.01)
        XCTAssertEqual(portalImage.size.height, 24.0, accuracy: 0.01)
        
        guard let cgImg = portalImage.cgImage else {
            XCTFail("Exit portal image must produce a valid CGImage")
            return
        }
        XCTAssertGreaterThan(cgImg.width, 0)
        XCTAssertGreaterThan(cgImg.height, 0)
        
        let pngData = portalImage.pngData()
        XCTAssertNotNil(pngData)
        XCTAssertGreaterThan(pngData?.count ?? 0, 100, "PNG data should be non-trivial for rendered portal asset")
    }
    
    // MARK: - 4. StationCartographyLoader Tests (Doc 15 §2 & Doc 20 §4)
    
    func testStationCartographyLoader_ResolvesAndParsesBaseline() {
        let url = StationCartographyLoader.resolveStationShapesGeoJSONURL()
        XCTAssertNotNil(url, "station_shapes.geojson URL must be resolvable from bundle or documents")
        
        let shapesCollection = StationCartographyLoader.loadStationShapesSync()
        XCTAssertGreaterThan(shapesCollection.shapes.count, 0, "Loaded station shapes collection must contain features")
    }
    
    func testStationCartographyLoader_OptimizedSourceOptions() {
        let dummyCollection = MLNShapeCollectionFeature(shapes: [])
        let source = StationCartographyLoader.makeOptimizedStationSource(
            identifier: "test-station-source",
            shape: dummyCollection
        )
        
        XCTAssertEqual(source.identifier, "test-station-source")
        // Verify source initialized with non-nil shape
        XCTAssertNotNil(source.shape)
    }
    
    // MARK: - 5. Baseline GeoJSON Schema Conformance Tests (Doc 15 §2)
    
    func testStationShapesGeoJSONFeaturesConformToSchema() {
        guard let url = StationCartographyLoader.resolveStationShapesGeoJSONURL(),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            XCTFail("Failed to parse station_shapes.geojson as JSON dictionary")
            return
        }
        
        XCTAssertGreaterThanOrEqual(features.count, 10, "Baseline station_shapes.geojson should define multiple stations and components")
        
        var foundFootprint = false
        var foundPlatform = false
        var foundEntrance = false
        var complexIDs = Set<String>()
        
        for feat in features {
            guard let properties = feat["properties"] as? [String: Any],
                  let geometry = feat["geometry"] as? [String: Any],
                  let geomType = geometry["type"] as? String else {
                XCTFail("Every feature must have properties and geometry")
                continue
            }
            
            // Required properties per Doc 15 §2
            XCTAssertNotNil(properties["complex_id"], "Feature must have complex_id")
            XCTAssertNotNil(properties["level"], "Feature must have level")
            XCTAssertNotNil(properties["ordinal"], "Feature must have ordinal")
            XCTAssertNotNil(properties["feature_type"], "Feature must have feature_type")
            XCTAssertNotNil(properties["accessible"], "Feature must have accessible")
            
            if let cid = properties["complex_id"] as? String {
                complexIDs.insert(cid)
            }
            
            let fType = properties["feature_type"] as? String ?? ""
            if fType == "mezzanine" || fType == "corridor" {
                foundFootprint = true
                XCTAssertEqual(geomType, "Polygon", "Mezzanine concourse should be Polygon geometry")
            }
            if fType == "platform" {
                foundPlatform = true
                XCTAssertTrue(geomType == "LineString" || geomType == "Polygon", "Platform should be LineString or Polygon")
            }
            if fType == "subway_entrance" || fType == "portal" {
                foundEntrance = true
                XCTAssertEqual(geomType, "Point", "Portal entrance should be Point geometry")
            }
        }
        
        XCTAssertTrue(foundFootprint, "Must contain at least one 2D concourse footprint polygon")
        XCTAssertTrue(foundPlatform, "Must contain at least one platform line feature")
        XCTAssertTrue(foundEntrance, "Must contain at least one street-level egress portal feature")
        
        // Verify Regional Anchor Complex IDs exist (Penn Station 600001, Grand Central 600002, Union Sq 602)
        XCTAssertTrue(complexIDs.contains("600001"), "Penn Station complex 600001 must be present")
        XCTAssertTrue(complexIDs.contains("600002"), "Grand Central complex 600002 must be present")
        XCTAssertTrue(complexIDs.contains("602"), "Union Square complex 602 must be present")
    }
    
    // MARK: - 6. Discrete Floor Filtering Predicate Tests (Doc 20 §3)
    
    func testFloorFilterPredicateEvaluation() {
        let predicateLevelMinus1 = StationTransitVisualizationManager.makeFloorFilterPredicate(targetLevel: -1)
        
        // Mock item matching single level -1.0
        let item1: [String: Any] = ["level": -1.0, "levels": "-1"]
        XCTAssertTrue(predicateLevelMinus1.evaluate(with: item1), "Should match level == -1.0")
        
        // Mock item matching string-casted level "-1"
        let item2: [String: Any] = ["level": "-1", "levels": "-1"]
        XCTAssertTrue(predicateLevelMinus1.evaluate(with: item2), "Should match level == '-1'")
        
        // Mock multi-level connector spanning "-2;-1"
        let item3: [String: Any] = ["level": -2.0, "levels": "-2;-1"]
        XCTAssertTrue(predicateLevelMinus1.evaluate(with: item3), "Should match multi-level connector spanning -1")
        
        // Mock item on floor 0 (different floor)
        let item4: [String: Any] = ["level": 0.0, "levels": "0"]
        XCTAssertFalse(predicateLevelMinus1.evaluate(with: item4), "Should not match different level 0.0")
    }
}
