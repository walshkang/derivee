import XCTest
import UIKit
import MapLibre
import CoreLocation
import SwiftProtobuf
@testable import Derivee

final class CorridorPulseMapTests: XCTestCase {
    
    // MARK: - 1. Config & Identifiers Tests
    
    func testConfigIdentifiersConformToSpec() {
        XCTAssertEqual(CorridorPulseMapController.Config.vehicleSourceID, "corridor-vehicles-source")
        XCTAssertEqual(CorridorPulseMapController.Config.bunchingSegmentsSourceID, "corridor-bunching-segments-source")
        XCTAssertEqual(CorridorPulseMapController.Config.bunchingCasingLayerID, "corridor-bunching-casing-layer")
        XCTAssertEqual(CorridorPulseMapController.Config.bunchingLineLayerID, "corridor-bunching-line-layer")
        XCTAssertEqual(CorridorPulseMapController.Config.vehicleTargetHaloLayerID, "vehicle-target-halo-layer")
        XCTAssertEqual(CorridorPulseMapController.Config.vehicleCircleBaseLayerID, "vehicle-circle-base-layer")
        XCTAssertEqual(CorridorPulseMapController.Config.vehicleDirectionArrowLayerID, "vehicle-direction-arrow-layer")
        XCTAssertEqual(CorridorPulseMapController.Config.vehicleLabelLayerID, "vehicle-label-layer")
        XCTAssertEqual(CorridorPulseMapController.Config.bearingArrowImageName, "transit-bearing-arrow")
    }
    
    // MARK: - 2. Bearing Arrow Asset Generation Tests
    
    func testBearingArrowImageDimensionsAndRendering() {
        let arrowImage = CorridorPulseMapController.makeBearingArrowImage()
        
        XCTAssertEqual(arrowImage.size.width, 24.0, accuracy: 0.01)
        XCTAssertEqual(arrowImage.size.height, 24.0, accuracy: 0.01)
        
        // Verify image produces valid CGImage and PNG representation
        guard let cgImg = arrowImage.cgImage else {
            XCTFail("Bearing arrow image must contain a valid CGImage")
            return
        }
        XCTAssertGreaterThan(cgImg.width, 0)
        XCTAssertGreaterThan(cgImg.height, 0)
        
        let pngData = arrowImage.pngData()
        XCTAssertNotNil(pngData)
        XCTAssertGreaterThan(pngData?.count ?? 0, 100, "PNG data should be non-trivial for rendered arrow")
    }
    
    // MARK: - 3. Layer Property Configuration Tests (Doc 19 §6)
    
    func testBunchingSegmentLayersConfiguration() {
        let dummySource = MLNShapeSource(
            identifier: CorridorPulseMapController.Config.bunchingSegmentsSourceID,
            shape: MLNShapeCollectionFeature(shapes: []),
            options: nil
        )
        
        let segmentFilter = NSPredicate(format: "feature_class == 'bunching_segment'")
        
        // Casing Layer
        let casing = MLNLineStyleLayer(
            identifier: CorridorPulseMapController.Config.bunchingCasingLayerID,
            source: dummySource
        )
        casing.predicate = segmentFilter
        casing.lineJoin = NSExpression(forConstantValue: "round")
        casing.lineCap = NSExpression(forConstantValue: "round")
        casing.lineColor = NSExpression(forKeyPath: "casing_color")
        casing.lineOpacity = NSExpression(forConstantValue: 0.85)
        
        XCTAssertEqual(casing.identifier, "corridor-bunching-casing-layer")
        XCTAssertEqual(casing.sourceIdentifier, "corridor-bunching-segments-source")
        XCTAssertEqual(casing.predicate?.predicateFormat, "feature_class == \"bunching_segment\"")
        XCTAssertEqual(casing.lineJoin.constantValue as? String, "round")
        XCTAssertEqual(casing.lineCap.constantValue as? String, "round")
        let casingOpacity = (casing.lineOpacity.constantValue as? NSNumber)?.doubleValue ?? 0
        XCTAssertEqual(casingOpacity, 0.85, accuracy: 0.001)
        
        // Line Layer (Dashed)
        let line = MLNLineStyleLayer(
            identifier: CorridorPulseMapController.Config.bunchingLineLayerID,
            source: dummySource
        )
        line.predicate = segmentFilter
        line.lineJoin = NSExpression(forConstantValue: "round")
        line.lineCap = NSExpression(forConstantValue: "round")
        line.lineColor = NSExpression(forKeyPath: "line_color")
        line.lineDashPattern = NSExpression(forConstantValue: [1.5, 0.75])
        
        XCTAssertEqual(line.identifier, "corridor-bunching-line-layer")
        XCTAssertEqual(line.sourceIdentifier, "corridor-bunching-segments-source")
        XCTAssertNotNil(line.lineDashPattern)
    }
    
    func testVehicleTokenLayersConfiguration() {
        let dummySource = MLNShapeSource(
            identifier: CorridorPulseMapController.Config.vehicleSourceID,
            shape: MLNShapeCollectionFeature(shapes: []),
            options: nil
        )
        
        let vehicleFilter = NSPredicate(format: "feature_class == 'vehicle_marker'")
        
        // 1. Halo Layer
        let halo = MLNCircleStyleLayer(
            identifier: CorridorPulseMapController.Config.vehicleTargetHaloLayerID,
            source: dummySource
        )
        halo.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            vehicleFilter,
            NSPredicate(format: "is_target == YES")
        ])
        halo.circlePitchAlignment = NSExpression(forConstantValue: "map")
        halo.circleColor = NSExpression(forKeyPath: "halo_color")
        halo.circleOpacity = NSExpression(forConstantValue: 0.60)
        
        XCTAssertEqual(halo.identifier, "vehicle-target-halo-layer")
        XCTAssertEqual(halo.circlePitchAlignment.constantValue as? String, "map")
        let haloOpacity = (halo.circleOpacity.constantValue as? NSNumber)?.doubleValue ?? 0
        XCTAssertEqual(haloOpacity, 0.60, accuracy: 0.001)
        
        // 2. Base Circle Layer
        let circle = MLNCircleStyleLayer(
            identifier: CorridorPulseMapController.Config.vehicleCircleBaseLayerID,
            source: dummySource
        )
        circle.predicate = vehicleFilter
        circle.circlePitchAlignment = NSExpression(forConstantValue: "map")
        circle.circleColor = NSExpression(forKeyPath: "status_color")
        circle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        
        XCTAssertEqual(circle.identifier, "vehicle-circle-base-layer")
        XCTAssertEqual(circle.circlePitchAlignment.constantValue as? String, "map")
        let strokeColor = circle.circleStrokeColor.constantValue as? UIColor
        XCTAssertNotNil(strokeColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        strokeColor?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 1.0, accuracy: 0.01)
        XCTAssertEqual(b, 1.0, accuracy: 0.01)
        XCTAssertEqual(a, 1.0, accuracy: 0.01)
        
        // 3. Direction Arrow Layer
        let arrow = MLNSymbolStyleLayer(
            identifier: CorridorPulseMapController.Config.vehicleDirectionArrowLayerID,
            source: dummySource
        )
        arrow.predicate = vehicleFilter
        arrow.iconImageName = NSExpression(forConstantValue: "transit-bearing-arrow")
        arrow.iconRotationAlignment = NSExpression(forConstantValue: "map")
        arrow.iconRotation = NSExpression(forKeyPath: "bearing")
        arrow.iconAllowsOverlap = NSExpression(forConstantValue: true)
        arrow.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        
        XCTAssertEqual(arrow.identifier, "vehicle-direction-arrow-layer")
        XCTAssertEqual(arrow.iconImageName.constantValue as? String, "transit-bearing-arrow")
        XCTAssertEqual(arrow.iconRotationAlignment.constantValue as? String, "map")
        XCTAssertEqual(arrow.iconAllowsOverlap.constantValue as? Bool, true)
        XCTAssertEqual(arrow.iconIgnoresPlacement.constantValue as? Bool, true)
        
        // 4. Vehicle Label Layer
        let label = MLNSymbolStyleLayer(
            identifier: CorridorPulseMapController.Config.vehicleLabelLayerID,
            source: dummySource
        )
        label.predicate = vehicleFilter
        label.minimumZoomLevel = 13.5
        label.text = NSExpression(format: "vehicle_id")
        label.textFontSize = NSExpression(forConstantValue: 11.0)
        label.textColor = NSExpression(forConstantValue: UIColor.black)
        label.textHaloColor = NSExpression(forConstantValue: UIColor.white)
        label.textHaloWidth = NSExpression(forConstantValue: 1.5)
        label.textAllowsOverlap = NSExpression(forConstantValue: false)
        
        XCTAssertEqual(label.identifier, "vehicle-label-layer")
        XCTAssertEqual(label.minimumZoomLevel, 13.5)
        XCTAssertEqual(label.textFontSize.constantValue as? Double, 11.0)
        XCTAssertEqual(label.textAllowsOverlap.constantValue as? Bool, false)
    }
    
    // MARK: - 4. GeoJSON Ingestion Tests (Doc 19 §5)
    
    func testGeoJSONTelemetryParsingFidelity() {
        let geoJsonString = """
        {
          "type": "FeatureCollection",
          "metadata": {
            "route_id": "METRO_101",
            "corridor_status": "Delayed",
            "active_bunching_count": 1
          },
          "features": [
            {
              "type": "Feature",
              "id": "veh_bus_9021",
              "geometry": {
                "type": "Point",
                "coordinates": [-122.419416, 37.774929]
              },
              "properties": {
                "feature_class": "vehicle_marker",
                "vehicle_id": "9021",
                "trip_id": "trip_9920194A",
                "bearing": 45.0,
                "speed_mps": 0.8,
                "delay_sec": 420,
                "is_target": true,
                "is_bunched": true,
                "is_service_gap": false,
                "status_color": "#D32F2F",
                "halo_color": "#FFCDD2"
              }
            },
            {
              "type": "Feature",
              "id": "veh_bus_9022",
              "geometry": {
                "type": "Point",
                "coordinates": [-122.418210, 37.775820]
              },
              "properties": {
                "feature_class": "vehicle_marker",
                "vehicle_id": "9022",
                "trip_id": "trip_9920195A",
                "bearing": 44.5,
                "speed_mps": 11.2,
                "delay_sec": -60,
                "is_target": false,
                "is_bunched": true,
                "is_service_gap": false,
                "status_color": "#D32F2F",
                "halo_color": "#FFCDD2"
              }
            },
            {
              "type": "Feature",
              "id": "segment_bunch_9021_9022",
              "geometry": {
                "type": "LineString",
                "coordinates": [
                  [-122.419416, 37.774929],
                  [-122.418813, 37.775375],
                  [-122.418210, 37.775820]
                ]
              },
              "properties": {
                "feature_class": "bunching_segment",
                "severity": "critical",
                "trailing_vehicle_id": "9021",
                "leading_vehicle_id": "9022",
                "segment_length_m": 159.5,
                "headway_compression_ratio": 0.022,
                "line_color": "#B71C1C",
                "casing_color": "#FFEBEE"
              }
            }
          ]
        }
        """
        
        let data = geoJsonString.data(using: .utf8)!
        let parsed = CorridorPulseMapController.parseCorridorGeoJSON(data: data)
        
        // 2 vehicles in vehicle shape collection
        XCTAssertEqual(parsed.vehiclesShape.shapes.count, 2)
        guard let v1 = parsed.vehiclesShape.shapes.first as? MLNPointFeature else {
            XCTFail("First vehicle must be an MLNPointFeature")
            return
        }
        XCTAssertEqual(v1.coordinate.latitude, 37.774929, accuracy: 0.00001)
        XCTAssertEqual(v1.coordinate.longitude, -122.419416, accuracy: 0.00001)
        XCTAssertEqual(v1.attributes["vehicle_id"] as? String, "9021")
        XCTAssertEqual(v1.attributes["feature_class"] as? String, "vehicle_marker")
        XCTAssertEqual(v1.attributes["is_target"] as? Bool, true)
        XCTAssertEqual(v1.attributes["is_bunched"] as? Bool, true)
        XCTAssertEqual(v1.attributes["bearing"] as? Double, 45.0)
        XCTAssertEqual(v1.attributes["status_color"] as? String, "#D32F2F")
        XCTAssertEqual(v1.attributes["halo_color"] as? String, "#FFCDD2")
        
        // 1 bunching segment in bunching shape collection
        XCTAssertEqual(parsed.bunchingShape.shapes.count, 1)
        guard let seg = parsed.bunchingShape.shapes.first as? MLNPolylineFeature else {
            XCTFail("Bunching segment must be an MLNPolylineFeature")
            return
        }
        XCTAssertEqual(seg.pointCount, 3)
        XCTAssertEqual(seg.attributes["feature_class"] as? String, "bunching_segment")
        XCTAssertEqual(seg.attributes["trailing_vehicle_id"] as? String, "9021")
        XCTAssertEqual(seg.attributes["leading_vehicle_id"] as? String, "9022")
        XCTAssertEqual(seg.attributes["line_color"] as? String, "#B71C1C")
        XCTAssertEqual(seg.attributes["casing_color"] as? String, "#FFEBEE")
    }
    
    // MARK: - 5. Protobuf Ingestion Tests
    
    func testProtobufTelemetryParsingAndFiltering() {
        // Construct synthetic GTFS-RT FeedMessage with 2 vehicles (one on 6 train, one on L train)
        var feed = TransitRealtime_FeedMessage()
        feed.header.gtfsRealtimeVersion = "2.0"
        feed.header.timestamp = 1774958400
        
        // Vehicle 1: 6 Train Downtown
        var e1 = TransitRealtime_FeedEntity()
        e1.id = "ent_1"
        var v1 = TransitRealtime_VehiclePosition()
        v1.vehicle.id = "veh_6_101"
        v1.trip.tripID = "trip_6_morning"
        v1.trip.routeID = "6"
        v1.position.latitude = 40.7527
        v1.position.longitude = -73.9772
        v1.position.bearing = 210.0
        v1.position.speed = 12.5
        e1.vehicle = v1
        feed.entity.append(e1)
        
        // Vehicle 2: L Train Crosstown
        var e2 = TransitRealtime_FeedEntity()
        e2.id = "ent_2"
        var v2 = TransitRealtime_VehiclePosition()
        v2.vehicle.id = "veh_L_202"
        v2.trip.tripID = "trip_L_express"
        v2.trip.routeID = "L"
        v2.position.latitude = 40.7380
        v2.position.longitude = -73.9880
        v2.position.bearing = 95.0
        v2.position.speed = 8.0
        e2.vehicle = v2
        feed.entity.append(e2)
        
        // Test A: Parse all without route filter
        let allVehicles = CorridorPulseMapController.parseProtobufVehicles(feed: feed)
        XCTAssertEqual(allVehicles.shapes.count, 2)
        
        // Test B: Filter by route "6" with target vehicle "veh_6_101"
        let filteredVehicles = CorridorPulseMapController.parseProtobufVehicles(
            feed: feed,
            targetRouteId: "6",
            targetVehicleId: "veh_6_101"
        )
        XCTAssertEqual(filteredVehicles.shapes.count, 1)
        guard let p1 = filteredVehicles.shapes.first as? MLNPointFeature else {
            XCTFail("Filtered vehicle must be an MLNPointFeature")
            return
        }
        XCTAssertEqual(p1.attributes["vehicle_id"] as? String, "veh_6_101")
        XCTAssertEqual(p1.attributes["route_id"] as? String, "6")
        XCTAssertEqual(p1.attributes["is_target"] as? Bool, true)
        XCTAssertEqual(p1.attributes["bearing"] as? Double, 210.0)
        XCTAssertEqual(p1.coordinate.latitude, 40.7527, accuracy: 0.0001)
        XCTAssertEqual(p1.coordinate.longitude, -73.9772, accuracy: 0.0001)
    }
    
    // MARK: - 6. Direct Swift Model Telemetry Tests
    
    @MainActor
    func testDirectTypedTelemetryUpdate() {
        let mapView = MLNMapView(frame: .zero)
        let controller = CorridorPulseMapController(mapView: mapView)
        
        let vehicles = [
            CorridorVehicleTelemetry(
                vehicleId: "v_100",
                tripId: "t_100",
                routeId: "1",
                coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                bearing: 180.0,
                speedMps: 10.0,
                delaySec: 30,
                isTarget: true,
                isBunched: false,
                isServiceGap: false,
                statusColorHex: "#EE352E",
                haloColorHex: "#FFCDD2"
            )
        ]
        
        let bunching = [
            CorridorBunchingSegmentTelemetry(
                trailingVehicleId: "v_100",
                leadingVehicleId: "v_101",
                coordinates: [
                    CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                    CLLocationCoordinate2D(latitude: 40.7140, longitude: -74.0050)
                ],
                lineColorHex: "#B71C1C",
                casingColorHex: "#FFEBEE"
            )
        ]
        
        XCTAssertEqual(vehicles.first?.vehicleId, "v_100")
        XCTAssertEqual(vehicles.first?.isTarget, true)
        XCTAssertEqual(bunching.first?.trailingVehicleId, "v_100")
        XCTAssertEqual(bunching.first?.coordinates.count, 2)
        
        // Calling updateTelemetry directly when style is nil does not crash
        controller.updateTelemetry(vehicles: vehicles, bunchingSegments: bunching)
        controller.clearTelemetry()
    }
}
