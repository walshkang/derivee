import XCTest
import CoreLocation
import UIKit
import MapLibre
@testable import Derivee

final class TransitCartographyTests: XCTestCase {
    
    func testBundledSubwayGeoJSONLoading() {
        let shapeCollection = TransitCartographyLoader.loadTransitLinesShapeSync()
        XCTAssertGreaterThan(shapeCollection.shapes.count, 0, "Bundled transit lines should contain features.")
        XCTAssertEqual(shapeCollection.shapes.count, 11, "NYC dataset should contain 11 polyline trunk features.")
        
        for shape in shapeCollection.shapes {
            guard let feature = shape as? MLNFeature else {
                XCTFail("Shape must conform to MLNFeature.")
                continue
            }
            XCTAssertNotNil(feature.attributes["color_hex"], "Feature must have color_hex attribute.")
            XCTAssertNotNil(feature.attributes["color"] as? UIColor, "Feature must have color UIColor attribute.")
            XCTAssertNotNil(feature.attributes["casing_color_hex"], "Feature must have casing_color_hex attribute.")
            
            let pointCount: UInt
            if let poly = shape as? MLNPolylineFeature {
                pointCount = poly.pointCount
            } else if let multiPoly = shape as? MLNMultiPolylineFeature {
                pointCount = UInt(multiPoly.polylines.reduce(0) { $0 + Int($1.pointCount) })
            } else {
                pointCount = 0
            }
            XCTAssertGreaterThan(pointCount, 1, "Feature must contain at least 2 points.")
        }
    }
    
    func testAsyncTransitLinesLoading() async {
        let shapeCollection = await TransitCartographyLoader.loadTransitLinesShape()
        XCTAssertGreaterThan(shapeCollection.shapes.count, 0, "Async transit lines loader should return features.")
    }
    
    func testSyntheticMultiModalGeoJSONParsing() {
        let geoJSONString = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": {
                "route_id": "Red",
                "route_short_name": "RL",
                "route_name": "Red Line",
                "color_hex": "#DA291C",
                "casing_color_hex": "#FFFFFF",
                "modal_class": 0,
                "route_type": 1
              },
              "geometry": {
                "type": "LineString",
                "coordinates": [
                  [-71.0589, 42.3601],
                  [-71.0570, 42.3550],
                  [-71.0600, 42.3500]
                ]
              }
            },
            {
              "type": "Feature",
              "properties": {
                "route_id": "Green-B",
                "route_short_name": "B",
                "route_name": "Green Line B",
                "color_hex": "#00843D",
                "casing_color_hex": "#222433",
                "modal_class": 1,
                "route_type": 0
              },
              "geometry": {
                "type": "MultiLineString",
                "coordinates": [
                  [
                    [-71.1000, 42.3500],
                    [-71.0900, 42.3510]
                  ],
                  [
                    [-71.0900, 42.3510],
                    [-71.0800, 42.3520]
                  ]
                ]
              }
            },
            {
              "type": "Feature",
              "properties": {
                "route_id": "F4",
                "route_short_name": "F4",
                "route_name": "Charlestown Ferry",
                "color_hex": "#00A3E0",
                "modal_class": 3,
                "route_type": 4
              },
              "geometry": {
                "type": "LineString",
                "coordinates": [
                  [-71.0500, 42.3700],
                  [-71.0450, 42.3600]
                ]
              }
            }
          ]
        }
        """
        
        let data = Data(geoJSONString.utf8)
        let shapeCollection = TransitCartographyLoader.parseGeoJSONData(data)
        
        XCTAssertEqual(shapeCollection.shapes.count, 3, "Parsed shape collection must contain 3 features.")
        
        // 1. Red Line (Heavy Rail Subway)
        guard let redFeature = shapeCollection.shapes[0] as? MLNFeature else {
            XCTFail("Feature 0 must conform to MLNFeature")
            return
        }
        XCTAssertEqual(redFeature.attributes["route_id"] as? String, "Red")
        XCTAssertEqual(redFeature.attributes["color_hex"] as? String, "#DA291C")
        XCTAssertNotNil(redFeature.attributes["color"] as? UIColor)
        XCTAssertEqual(redFeature.attributes["casing_color_hex"] as? String, "#FFFFFF")
        XCTAssertEqual(redFeature.attributes["modal_class"] as? Int, 0)
        
        // 2. Green Line B (Light Rail LRT MultiLineString)
        guard let greenFeature = shapeCollection.shapes[1] as? MLNFeature else {
            XCTFail("Feature 1 must conform to MLNFeature")
            return
        }
        XCTAssertEqual(greenFeature.attributes["route_id"] as? String, "Green-B")
        XCTAssertEqual(greenFeature.attributes["color_hex"] as? String, "#00843D")
        XCTAssertEqual(greenFeature.attributes["casing_color_hex"] as? String, "#222433")
        XCTAssertEqual(greenFeature.attributes["modal_class"] as? Int, 1)
        
        // 3. Ferry F4 (Maritime Ferry - default casing applied)
        guard let ferryFeature = shapeCollection.shapes[2] as? MLNFeature else {
            XCTFail("Feature 2 must conform to MLNFeature")
            return
        }
        XCTAssertEqual(ferryFeature.attributes["route_id"] as? String, "F4")
        XCTAssertEqual(ferryFeature.attributes["color_hex"] as? String, "#00A3E0")
        XCTAssertEqual(ferryFeature.attributes["casing_color_hex"] as? String, "#FFFFFF")
        XCTAssertEqual(ferryFeature.attributes["modal_class"] as? Int, 3)
    }
    
    func testCorruptAndEmptyDataHandling() {
        let corruptData = Data("Not Valid GeoJSON {}}".utf8)
        let corruptShape = TransitCartographyLoader.parseGeoJSONData(corruptData)
        XCTAssertEqual(corruptShape.shapes.count, 0, "Corrupt data must return empty shape collection.")
        
        let emptyData = Data()
        let emptyShape = TransitCartographyLoader.parseGeoJSONData(emptyData)
        XCTAssertEqual(emptyShape.shapes.count, 0, "Empty data must return empty shape collection.")
    }
    
    func testSubwayLineColorExpressionEvaluation() {
        let expr = MapView.Coordinator.subwayLineColorExpression()
        XCTAssertNotNil(expr, "Subway line color expression must be valid.")
    }
}
