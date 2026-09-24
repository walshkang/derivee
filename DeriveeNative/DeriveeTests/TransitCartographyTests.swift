import XCTest
import CoreLocation
import UIKit
import MapLibre
@testable import Derivee

final class TransitCartographyTests: XCTestCase {
    
    func testTransitModalClassNormalization() {
        // Standard GTFS route_type codes
        XCTAssertEqual(TransitModalClass.from(routeType: 0), .lightRail, "route_type 0 is Tram/Light Rail")
        XCTAssertEqual(TransitModalClass.from(routeType: 1), .subway, "route_type 1 is Subway")
        XCTAssertEqual(TransitModalClass.from(routeType: 2), .subway, "route_type 2 is Rail (Metro/Subway envelope)")
        XCTAssertEqual(TransitModalClass.from(routeType: 3), .bus, "route_type 3 is Bus")
        XCTAssertEqual(TransitModalClass.from(routeType: 4), .ferry, "route_type 4 is Ferry")
        XCTAssertEqual(TransitModalClass.from(routeType: 5), .bus, "route_type 5 is Cable Tram/Bus")
        XCTAssertEqual(TransitModalClass.from(routeType: 11), .bus, "route_type 11 is Trolleybus")
        
        // Extended GTFS / HVT codes
        // 100-199: Commuter Rail / Railway
        XCTAssertEqual(TransitModalClass.from(routeType: 100), .subway)
        XCTAssertEqual(TransitModalClass.from(routeType: 101), .subway)
        // 400-499: Urban Rail / Underground / Monorail
        XCTAssertEqual(TransitModalClass.from(routeType: 401), .subway, "HVT 401 is Metro")
        XCTAssertEqual(TransitModalClass.from(routeType: 402), .subway, "HVT 402 is Underground")
        XCTAssertEqual(TransitModalClass.from(routeType: 405), .subway, "HVT 405 is Monorail")
        // 700-899: Bus / Express Bus / Trolleybus
        XCTAssertEqual(TransitModalClass.from(routeType: 700), .bus, "HVT 700 is Bus")
        XCTAssertEqual(TransitModalClass.from(routeType: 702), .bus, "HVT 702 is Express Bus")
        XCTAssertEqual(TransitModalClass.from(routeType: 800), .bus, "HVT 800 is Trolleybus")
        // 900-999: Tram / LRT
        XCTAssertEqual(TransitModalClass.from(routeType: 900), .lightRail, "HVT 900 is Tram")
        XCTAssertEqual(TransitModalClass.from(routeType: 901), .lightRail, "HVT 901 is City Tram")
        XCTAssertEqual(TransitModalClass.from(routeType: 904), .lightRail, "HVT 904 is LRT")
        // 1000-1299: Maritime Ferry / Water Transport
        XCTAssertEqual(TransitModalClass.from(routeType: 1000), .ferry, "HVT 1000 is Water Transport")
        XCTAssertEqual(TransitModalClass.from(routeType: 1200), .ferry, "HVT 1200 is Ferry Service")
    }
    
    func testTransitModalStylingMetrics() {
        // Subway metrics (canonical z=14 neighborhood baseline)
        let subway = TransitModalClass.subway
        XCTAssertEqual(subway.cartographyLineWidth, 2.5)
        XCTAssertEqual(subway.cartographyCasingWidth, 4.5)
        XCTAssertNil(subway.cartographyLineDashPattern)
        XCTAssertNil(subway.cartographyCasingDashPattern)
        
        // Light Rail metrics (canonical z=14 baseline: solid line, dashed casing)
        let lrt = TransitModalClass.lightRail
        XCTAssertEqual(lrt.cartographyLineWidth, 2.5)
        XCTAssertEqual(lrt.cartographyCasingWidth, 4.5)
        XCTAssertNil(lrt.cartographyLineDashPattern)
        XCTAssertEqual(lrt.cartographyCasingDashPattern, [3.0, 2.0])
        
        // Ferry metrics (dashed line over water, no casing)
        let ferry = TransitModalClass.ferry
        XCTAssertEqual(ferry.cartographyLineWidth, 2.5)
        XCTAssertEqual(ferry.cartographyCasingWidth, 0.0)
        XCTAssertEqual(ferry.cartographyLineDashPattern, [4.0, 3.0])
        XCTAssertNil(ferry.cartographyCasingDashPattern)
    }
    
    // MARK: - Wave V.1 Tests: Continuous Zoom Interpolation & Solid Opacity (Doc 22 §4.2)
    
    func testTransitModalZoomInterpolatedExpressions() {
        let subway = TransitModalClass.subway
        let lrt = TransitModalClass.lightRail
        let ferry = TransitModalClass.ferry
        let bus = TransitModalClass.bus
        
        // 1. Subway and Light Rail expressions exist and are interpolation functions
        let subwayLineExpr = subway.cartographyLineWidthExpression()
        let subwayCasingExpr = subway.cartographyCasingWidthExpression()
        let lrtLineExpr = lrt.cartographyLineWidthExpression()
        let lrtCasingExpr = lrt.cartographyCasingWidthExpression()
        
        XCTAssertEqual(subwayLineExpr.expressionType, .function)
        XCTAssertEqual(subwayLineExpr.function, "mgl_interpolate:withCurveType:parameters:stops:")
        XCTAssertEqual(subwayCasingExpr.expressionType, .function)
        XCTAssertEqual(subwayCasingExpr.function, "mgl_interpolate:withCurveType:parameters:stops:")
        
        // 2. Exact stops validation for Subway/LRT ribbon widths: z11=1.2, z14=2.5, z17=4.5
        let subLineStops = (subwayLineExpr.arguments?[3] as? NSExpression)?.constantValue as? [NSNumber: NSNumber]
        XCTAssertNotNil(subLineStops)
        if let stops = subLineStops {
            XCTAssertEqual(stops[11.0]?.doubleValue ?? -1, 1.2, accuracy: 0.01, "z=11 ribbon width must be 1.2pt (Doc 22 §4.2)")
            XCTAssertEqual(stops[14.0]?.doubleValue ?? -1, 2.5, accuracy: 0.01, "z=14 ribbon width must be 2.5pt (Doc 22 §4.2)")
            XCTAssertEqual(stops[17.0]?.doubleValue ?? -1, 4.5, accuracy: 0.01, "z=17 ribbon width must be 4.5pt (Doc 22 §4.2)")
        }
        
        // 3. Exact stops validation for Subway/LRT casing widths: z11=2.5, z14=4.5, z17=8.1
        let subCasingStops = (subwayCasingExpr.arguments?[3] as? NSExpression)?.constantValue as? [NSNumber: NSNumber]
        XCTAssertNotNil(subCasingStops)
        if let stops = subCasingStops {
            XCTAssertEqual(stops[11.0]?.doubleValue ?? -1, 2.5, accuracy: 0.01, "z=11 casing width must be 2.5pt (Doc 22 §4.2)")
            XCTAssertEqual(stops[14.0]?.doubleValue ?? -1, 4.5, accuracy: 0.01, "z=14 casing width must be 4.5pt (Doc 22 §4.2)")
            XCTAssertEqual(stops[17.0]?.doubleValue ?? -1, 8.1, accuracy: 0.01, "z=17 casing width must be 8.1pt (Doc 22 §4.2)")
            
            // Casing margin assertions: Margin <= 1.0pt for z <= 14.0 (Wave V.1 Directive 3)
            let margin11 = ((stops[11.0]?.doubleValue ?? 0) - 1.2) / 2.0
            let margin14 = ((stops[14.0]?.doubleValue ?? 0) - 2.5) / 2.0
            let margin17 = ((stops[17.0]?.doubleValue ?? 0) - 4.5) / 2.0
            
            XCTAssertEqual(margin11, 0.65, accuracy: 0.01, "z=11 casing margin must be 0.65pt")
            XCTAssertEqual(margin14, 1.00, accuracy: 0.01, "z=14 casing margin must be 1.0pt")
            XCTAssertEqual(margin17, 1.80, accuracy: 0.01, "z=17 casing margin must be 1.8pt")
            XCTAssertLessThanOrEqual(margin11, 1.0, "Regional casing margin must be <= 1.0pt to prevent avenue choking")
            XCTAssertLessThanOrEqual(margin14, 1.0, "Neighborhood casing margin must be <= 1.0pt")
        }
        
        // 4. Light rail expressions match subway stops and structure
        let lrtLineStops = (lrtLineExpr.arguments?[3] as? NSExpression)?.constantValue as? [NSNumber: NSNumber]
        let lrtCasingStops = (lrtCasingExpr.arguments?[3] as? NSExpression)?.constantValue as? [NSNumber: NSNumber]
        XCTAssertEqual(lrtLineStops, subLineStops)
        XCTAssertEqual(lrtCasingStops, subCasingStops)
        XCTAssertEqual(lrtLineExpr.function, subwayLineExpr.function)
        XCTAssertEqual(lrtCasingExpr.function, subwayCasingExpr.function)
        
        // 5. Ferry and Bus modal expressions
        XCTAssertEqual(ferry.cartographyLineWidthExpression(), NSExpression(forConstantValue: 2.5))
        XCTAssertEqual(ferry.cartographyCasingWidthExpression(), NSExpression(forConstantValue: 0.0))
        XCTAssertEqual(bus.cartographyLineWidthExpression(), NSExpression(forConstantValue: 0.0))
        XCTAssertEqual(bus.cartographyCasingWidthExpression(), NSExpression(forConstantValue: 0.0))
    }
    
    func testTransitLayersSolidOpacity() {
        // Research Doc 22 §4.2 Directive 2: Keep ribbons and casings 100% solid/opaque (1.0),
        // relying entirely on geometric scaling rather than alpha transparency to eliminate
        // muddy color blending and anti-aliasing knots.
        let show = true
        let subwayCasingOpacity = NSExpression(forConstantValue: show ? 1.0 : 0.0)
        let subwayLineOpacity = NSExpression(forConstantValue: show ? 1.0 : 0.0)
        let lrtCasingOpacity = NSExpression(forConstantValue: show ? 1.0 : 0.0)
        let lrtLineOpacity = NSExpression(forConstantValue: show ? 1.0 : 0.0)
        let ferryLineOpacity = NSExpression(forConstantValue: show ? 1.0 : 0.0)
        
        XCTAssertEqual(subwayCasingOpacity.constantValue as? Double, 1.0)
        XCTAssertEqual(subwayLineOpacity.constantValue as? Double, 1.0)
        XCTAssertEqual(lrtCasingOpacity.constantValue as? Double, 1.0)
        XCTAssertEqual(lrtLineOpacity.constantValue as? Double, 1.0)
        XCTAssertEqual(ferryLineOpacity.constantValue as? Double, 1.0)
    }
    
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
            XCTAssertNotNil(feature.attributes["modal_class"], "Feature must have modal_class attribute.")
            
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
            },
            {
              "type": "Feature",
              "properties": {
                "route_id": "Orange",
                "route_short_name": "OL",
                "color_hex": "#ED8B00",
                "route_type": 401
              },
              "geometry": {
                "type": "LineString",
                "coordinates": [
                  [-71.0600, 42.3600],
                  [-71.0700, 42.3500]
                ]
              }
            }
          ]
        }
        """
        
        let data = Data(geoJSONString.utf8)
        let shapeCollection = TransitCartographyLoader.parseGeoJSONData(data)
        
        XCTAssertEqual(shapeCollection.shapes.count, 4, "Parsed shape collection must contain 4 features.")
        
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
        
        // 4. Orange Line (Inferred from HVT 401 Metro without explicit modal_class)
        guard let orangeFeature = shapeCollection.shapes[3] as? MLNFeature else {
            XCTFail("Feature 3 must conform to MLNFeature")
            return
        }
        XCTAssertEqual(orangeFeature.attributes["route_id"] as? String, "Orange")
        XCTAssertEqual(orangeFeature.attributes["color_hex"] as? String, "#ED8B00")
        XCTAssertEqual(orangeFeature.attributes["modal_class"] as? Int, 0, "HVT 401 should infer modal_class 0 (subway)")
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
    
    func testSubwayCasingColorExpressionEvaluation() {
        let expr = MapView.Coordinator.subwayCasingColorExpression()
        XCTAssertNotNil(expr, "Subway casing color expression must be valid.")
        XCTAssertEqual(expr.keyPath, "casing_color")
    }
    
    func testMultiModalRouteDataCatalog() {
        let red = TransitRouteData.lineInfo(for: "Red")
        XCTAssertEqual(red.modalClass, .subway)
        XCTAssertEqual(red.colorHex, "#DA291C")
        
        let greenB = TransitRouteData.lineInfo(for: "Green-B")
        XCTAssertEqual(greenB.modalClass, .lightRail)
        XCTAssertEqual(greenB.colorHex, "#00843D")
        
        let silverLine = TransitRouteData.lineInfo(for: "SL1")
        XCTAssertEqual(silverLine.modalClass, .bus)
        XCTAssertEqual(silverLine.colorHex, "#7C878E")
        
        let ferry = TransitRouteData.lineInfo(for: "F4")
        XCTAssertEqual(ferry.modalClass, .ferry)
        XCTAssertEqual(ferry.colorHex, "#00A3E0")
        
        let path = TransitRouteData.lineInfo(for: "PATH")
        XCTAssertEqual(path.modalClass, .subway)
    }
    
    // MARK: - Wave PE.8 Tests: WCAG Contrast, Topological Chain & Squiggle Elimination
    
    func testWCAG21RelativeLuminanceAndContrastRatio() {
        let whiteL = TransitRouteData.relativeLuminance(colorHex: "#FFFFFF")
        let blackL = TransitRouteData.relativeLuminance(colorHex: "#000000")
        XCTAssertEqual(whiteL, 1.0, accuracy: 0.001)
        XCTAssertEqual(blackL, 0.0, accuracy: 0.001)
        
        let maxContrast = TransitRouteData.contrastRatio(hex1: "#FFFFFF", hex2: "#000000")
        XCTAssertEqual(maxContrast, 21.0, accuracy: 0.01)
        
        // Day basemap (#F9F9F6) contrast tests
        let dayBasemap = "#F9F9F6"
        
        // Low contrast routes (< 3.0:1)
        let lTrainContrast = TransitRouteData.contrastRatio(hex1: "#A7A9AC", hex2: dayBasemap)
        XCTAssertLessThan(lTrainContrast, 3.0, "L Train (#A7A9AC) contrast must be < 3.0:1 on Day basemap")
        
        let circleLineContrast = TransitRouteData.contrastRatio(hex1: "#FFD300", hex2: dayBasemap)
        XCTAssertLessThan(circleLineContrast, 3.0, "Circle Line (#FFD300) contrast must be < 3.0:1 on Day basemap")
        
        let yellowSubwayContrast = TransitRouteData.contrastRatio(hex1: "#FCCC0A", hex2: dayBasemap)
        XCTAssertLessThan(yellowSubwayContrast, 3.0, "Yellow subway (#FCCC0A) contrast must be < 3.0:1 on Day basemap")
        
        // High contrast routes (>= 3.0:1)
        let redLineContrast = TransitRouteData.contrastRatio(hex1: "#DA291C", hex2: dayBasemap)
        XCTAssertGreaterThanOrEqual(redLineContrast, 3.0, "Red Line (#DA291C) contrast must be >= 3.0:1 on Day basemap")
        
        let blueLineContrast = TransitRouteData.contrastRatio(hex1: "#0039A6", hex2: dayBasemap)
        XCTAssertGreaterThanOrEqual(blueLineContrast, 3.0, "Blue Line (#0039A6) contrast must be >= 3.0:1 on Day basemap")
    }
    
    func testAdaptiveCasingColorResolution() {
        // Day theme: low contrast routes get dark charcoal casing #2C2C2E
        XCTAssertEqual(TransitRouteData.adaptiveCasingColor(for: "#A7A9AC", theme: .day), "#2C2C2E")
        XCTAssertEqual(TransitRouteData.adaptiveCasingColor(for: "#FFD300", theme: .day), "#2C2C2E")
        XCTAssertEqual(TransitRouteData.adaptiveCasingColor(for: "#FCCC0A", theme: .day), "#2C2C2E")
        
        // Day theme: high contrast routes retain #FFFFFF casing
        XCTAssertEqual(TransitRouteData.adaptiveCasingColor(for: "#DA291C", theme: .day), "#FFFFFF")
        XCTAssertEqual(TransitRouteData.adaptiveCasingColor(for: "#0039A6", theme: .day), "#FFFFFF")
        
        // Night / dark background: dark routes get white casing
        XCTAssertEqual(TransitRouteData.adaptiveCasingColor(for: "#08179C", backgroundHex: "#1C1C1E"), "#FFFFFF")
        
        // LineInfo properties
        let lLine = TransitRouteData.lineInfo(for: "L")
        XCTAssertEqual(lLine.adaptiveCasingHex, "#2C2C2E")
        XCTAssertEqual(lLine.casingColorHex, "#2C2C2E")
        
        let redLine = TransitRouteData.lineInfo(for: "Red")
        XCTAssertEqual(redLine.adaptiveCasingHex, "#FFFFFF")
    }
    
    func testGeoJSONParsingInjectsAdaptiveCasing() {
        let testGeoJSON = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": {
                "route_id": "L",
                "route_name": "Canarsie Line",
                "color_hex": "#A7A9AC",
                "casing_color_hex": "#FFFFFF",
                "modal_class": 0
              },
              "geometry": {
                "type": "LineString",
                "coordinates": [[-73.90, 40.64], [-74.00, 40.74]]
              }
            }
          ]
        }
        """
        let data = Data(testGeoJSON.utf8)
        let collection = TransitCartographyLoader.parseGeoJSONData(data)
        guard let feature = collection.shapes.first as? MLNFeature else {
            XCTFail("Feature must be present")
            return
        }
        
        // Even though GeoJSON supplied #FFFFFF, dynamic engine replaces it with #2C2C2E due to low contrast
        XCTAssertEqual(feature.attributes["casing_color_hex"] as? String, "#2C2C2E")
        XCTAssertNotNil(feature.attributes["casing_color"] as? UIColor)
    }
    
    func testTopologicalChainAssemblyContinuousStitching() {
        // Two connected segments: Seg1: (0,0) -> (0,1), Seg2: (0,1) -> (0,2)
        let seg1 = [
            CLLocationCoordinate2D(latitude: 40.70, longitude: -74.00),
            CLLocationCoordinate2D(latitude: 40.72, longitude: -74.00)
        ]
        let seg2 = [
            CLLocationCoordinate2D(latitude: 40.72, longitude: -74.00),
            CLLocationCoordinate2D(latitude: 40.74, longitude: -74.00)
        ]
        
        let stitched = TransitRouteData.assembleTopologicalChain(segments: [seg1, seg2])
        XCTAssertEqual(stitched.count, 3, "Connected endpoint should be merged without duplicate joint point")
        XCTAssertEqual(stitched.first?.latitude, 40.70)
        XCTAssertEqual(stitched.last?.latitude, 40.74)
    }
    
    func testTopologicalChainAssemblyStationAnchorAlignment() {
        // Route with 3 stations running South to North
        let stations = [
            CLLocationCoordinate2D(latitude: 40.70, longitude: -74.00), // Station 0
            CLLocationCoordinate2D(latitude: 40.75, longitude: -74.00), // Station 1
            CLLocationCoordinate2D(latitude: 40.80, longitude: -74.00)  // Station 2
        ]
        
        // Segment A runs Station 0 to 1
        let segA = [
            CLLocationCoordinate2D(latitude: 40.70, longitude: -74.00),
            CLLocationCoordinate2D(latitude: 40.75, longitude: -74.00)
        ]
        // Segment B runs Station 2 to 1 (reversed direction)
        let segB = [
            CLLocationCoordinate2D(latitude: 40.80, longitude: -74.00),
            CLLocationCoordinate2D(latitude: 40.75, longitude: -74.00)
        ]
        // Segment C is on a completely distant branch (in Queens, 15km away)
        let segC = [
            CLLocationCoordinate2D(latitude: 40.70, longitude: -73.80),
            CLLocationCoordinate2D(latitude: 40.75, longitude: -73.80)
        ]
        
        let chain = TransitRouteData.assembleTopologicalChain(segments: [segA, segB, segC], stationAnchors: stations)
        XCTAssertEqual(chain.first?.latitude, 40.70)
        XCTAssertEqual(chain.last?.latitude, 40.80)
        
        // Ensure distant branch segC was pruned to eliminate diagonal jump shortcut across borough
        for coord in chain {
            XCTAssertEqual(coord.longitude, -74.00, accuracy: 0.01, "Should not contain distant Queens longitude")
        }
    }
    
    func testFogPolygonMathSquiggleElimination() {
        // 1. Degenerate ring with < 3 distinct vertices
        let twoVertexRing = [
            CLLocationCoordinate2D(latitude: 40.70, longitude: -74.00),
            CLLocationCoordinate2D(latitude: 40.71, longitude: -74.00),
            CLLocationCoordinate2D(latitude: 40.70, longitude: -74.00)
        ]
        XCTAssertEqual(FogPolygonMath.distinctVertexCount(twoVertexRing), 2)
        
        // 2. Microscopic sliver loop (< 10m²)
        let microLoop = [
            CLLocationCoordinate2D(latitude: 40.70000, longitude: -74.00000),
            CLLocationCoordinate2D(latitude: 40.70001, longitude: -74.00000),
            CLLocationCoordinate2D(latitude: 40.70001, longitude: -74.00001),
            CLLocationCoordinate2D(latitude: 40.70000, longitude: -74.00000)
        ]
        let microArea = FogPolygonMath.polygonAreaInSquareMeters(microLoop)
        XCTAssertLessThan(microArea, 10.0, "Micro loop area must be < 10m²")
        
        // 3. Genuine H3 Resolution 9 hex ring (~105,000 m²)
        // ~100m radius polygon around NYC
        let genuineHexRing = [
            CLLocationCoordinate2D(latitude: 40.700, longitude: -74.000),
            CLLocationCoordinate2D(latitude: 40.702, longitude: -74.000),
            CLLocationCoordinate2D(latitude: 40.703, longitude: -74.002),
            CLLocationCoordinate2D(latitude: 40.701, longitude: -74.003),
            CLLocationCoordinate2D(latitude: 40.700, longitude: -74.000)
        ]
        let genuineArea = FogPolygonMath.polygonAreaInSquareMeters(genuineHexRing)
        XCTAssertGreaterThan(genuineArea, 10.0, "Genuine hex ring area must be > 10m²")
    }
    
    // MARK: - Wave V.3 & V.4 Tests: Unified Trench Casing & In-Line Badges
    
    func testTrenchCasingWidthExpression() {
        let expr = TransitModalClass.trenchCasingWidthExpression()
        XCTAssertEqual(expr.expressionType, .function)
        XCTAssertEqual(expr.function, "mgl_interpolate:withCurveType:parameters:stops:")
        
        let stopsDict = (expr.arguments?[3] as? NSExpression)?.constantValue as? NSDictionary
        XCTAssertNotNil(stopsDict)
        if let stops = stopsDict {
            let expr11 = stops[11.0] as? NSExpression
            let expr14 = stops[14.0] as? NSExpression
            let expr17 = stops[17.0] as? NSExpression
            
            XCTAssertEqual(expr11?.keyPath, "casing_width_z11")
            XCTAssertEqual(expr14?.keyPath, "casing_width")
            XCTAssertEqual(expr17?.keyPath, "casing_width_z17")
        }
    }
    
    func testBadgeOpacityExpression() {
        let expr = TransitModalClass.badgeOpacityExpression()
        XCTAssertEqual(expr.expressionType, .function)
        XCTAssertEqual(expr.function, "mgl_interpolate:withCurveType:parameters:stops:")
        
        let stops = (expr.arguments?[3] as? NSExpression)?.constantValue as? [NSNumber: NSNumber]
        XCTAssertNotNil(stops)
        if let stops = stops {
            XCTAssertEqual(stops[13.5]?.doubleValue ?? -1, 0.0, accuracy: 0.01, "Badge opacity must be 0.0 below z=13.5 (INV-BADGE-01)")
            XCTAssertEqual(stops[14.5]?.doubleValue ?? -1, 1.0, accuracy: 0.01, "Badge opacity must reach 1.0 at z=14.5 (INV-BADGE-01)")
        }
    }
    
    @MainActor
    func testCorridorBadgeRendererTokensAndRasterization() {
        // 1. Token parsing
        let tokens3 = CorridorBadgeRenderer.parseTokens(from: "badge_4_5_6")
        XCTAssertEqual(tokens3, ["4", "5", "6"])
        
        let tokens2 = CorridorBadgeRenderer.parseTokens(from: "badge_F_M")
        XCTAssertEqual(tokens2, ["F", "M"])
        
        let tokens1 = CorridorBadgeRenderer.parseTokens(from: "badge_L")
        XCTAssertEqual(tokens1, ["L"])
        
        // 2. Rendering
        let image = CorridorBadgeRenderer.badgeImage(for: "badge_4_5_6", trunkColorHex: "#00933C")
        XCTAssertNotNil(image)
        XCTAssertEqual(image.size.height, 18.0)
        XCTAssertGreaterThan(image.size.width, 40.0)
        XCTAssertEqual(image.scale, 3.0, "Renderer must generate @3x Retina images")
    }
}
