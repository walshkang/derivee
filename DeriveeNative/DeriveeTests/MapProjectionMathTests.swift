import XCTest
import CoreLocation
import CoreGraphics
import simd
import MapLibre
@testable import Derivee

final class MapProjectionMathTests: XCTestCase {
    
    // MARK: - 1. Web Mercator Forward & Inverse
    
    func testWebMercatorForwardAndInverse() {
        let testCoordinates: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),                  // Null Island
            CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),          // Times Square, NYC
            CLLocationCoordinate2D(latitude: 42.3554, longitude: -71.0664),          // Boston Common
            CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),           // London
            CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),          // Tokyo
            CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),         // Sydney
            CLLocationCoordinate2D(latitude: -54.8019, longitude: -68.3030)          // Ushuaia (Southern Argentina)
        ]
        
        for coord in testCoordinates {
            let merc = MapProjectionMath.geodeticToMercator(coord)
            XCTAssertGreaterThanOrEqual(merc.x, 0.0, "Mercator X must be >= 0.0")
            XCTAssertLessThanOrEqual(merc.x, 1.0, "Mercator X must be <= 1.0")
            XCTAssertGreaterThanOrEqual(merc.y, 0.0, "Mercator Y must be >= 0.0")
            XCTAssertLessThanOrEqual(merc.y, 1.0, "Mercator Y must be <= 1.0")
            
            let reconstructed = MapProjectionMath.mercatorToGeodetic(merc)
            XCTAssertEqual(reconstructed.latitude, coord.latitude, accuracy: 1e-7, "Latitude roundtrip mismatch for \(coord)")
            XCTAssertEqual(reconstructed.longitude, coord.longitude, accuracy: 1e-7, "Longitude roundtrip mismatch for \(coord)")
        }
    }
    
    func testLatitudeBoundariesAndClamping() {
        // Exact Null Island maps to (0.5, 0.5)
        let nullIsland = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        let nullMerc = MapProjectionMath.geodeticToMercator(nullIsland)
        XCTAssertEqual(nullMerc.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(nullMerc.y, 0.5, accuracy: 1e-9)
        
        // Beyond pole boundaries clamped safely to maxLatitude
        let northOfLimit = CLLocationCoordinate2D(latitude: 89.9, longitude: 0.0)
        let northMerc = MapProjectionMath.geodeticToMercator(northOfLimit)
        XCTAssertGreaterThanOrEqual(northMerc.y, 0.0)
        XCTAssertLessThanOrEqual(northMerc.y, 0.01)
        
        let southOfLimit = CLLocationCoordinate2D(latitude: -89.9, longitude: 0.0)
        let southMerc = MapProjectionMath.geodeticToMercator(southOfLimit)
        XCTAssertLessThanOrEqual(southMerc.y, 1.0)
        XCTAssertGreaterThanOrEqual(southMerc.y, 0.99)
        
        // Antimeridian wrapping (-180 / 180)
        let westBoundary = CLLocationCoordinate2D(latitude: 0.0, longitude: -180.0)
        let eastBoundary = CLLocationCoordinate2D(latitude: 0.0, longitude: 180.0)
        let westMerc = MapProjectionMath.geodeticToMercator(westBoundary)
        let eastMerc = MapProjectionMath.geodeticToMercator(eastBoundary)
        XCTAssertEqual(westMerc.x, 0.0, accuracy: 1e-9)
        XCTAssertEqual(eastMerc.x, 0.0, accuracy: 1e-9, "Longitude 180.0 wraps to normalized 0.0")
    }
    
    // MARK: - 2. World Scale & Camera Distance
    
    func testWorldScaleAndCameraDistance() {
        XCTAssertEqual(MapProjectionMath.worldScale(zoomLevel: 0.0), 512.0, accuracy: 1e-6)
        XCTAssertEqual(MapProjectionMath.worldScale(zoomLevel: 1.0), 1024.0, accuracy: 1e-6)
        XCTAssertEqual(MapProjectionMath.worldScale(zoomLevel: 16.0), 512.0 * 65536.0, accuracy: 1e-3)
        XCTAssertEqual(MapProjectionMath.worldScale(zoomLevel: 20.0), 512.0 * 1048576.0, accuracy: 1e-3)
        
        // For viewport height 800 and vertical FOV 36.87°
        let fov: Double = 36.87
        let height: Double = 800.0
        let distance = MapProjectionMath.cameraDistance(viewportHeight: height, fieldOfView: fov)
        let expectedDist = 800.0 / (2.0 * tan((36.87 * .pi / 180.0) / 2.0))
        XCTAssertEqual(distance, expectedDist, accuracy: 1e-6)
    }
    
    // MARK: - 3. Relative-to-Center (RTC) Precision Mitigation
    
    func testRTCPrecisionJitterMitigationAtDeepZoom() {
        // At zoom 20: S(20) = 536,870,912 points.
        // A 1-meter shift at NYC latitude (40.7580) corresponds to ~0.0038 points.
        let zoom: Double = 20.0
        let center = CLLocationCoordinate2D(latitude: 40.758000, longitude: -73.985500)
        let camera = MapCameraState(
            centerCoordinate: center,
            zoomLevel: zoom,
            bearing: 0.0,
            pitch: 0.0,
            fieldOfView: 36.87,
            viewportSize: CGSize(width: 393, height: 852)
        )
        
        // Target is 1.5 meters away
        let target = CLLocationCoordinate2D(latitude: 40.7580135, longitude: -73.985500)
        
        // 1. Naive float32 calculation (simulating GPU absolute world coordinate truncation)
        let scale = MapProjectionMath.worldScale(zoomLevel: zoom)
        let centerMerc = MapProjectionMath.geodeticToMercator(center)
        let targetMerc = MapProjectionMath.geodeticToMercator(target)
        
        let absCenterPointX32 = Float(centerMerc.x * scale)
        let absCenterPointY32 = Float(centerMerc.y * scale)
        let absTargetPointX32 = Float(targetMerc.x * scale)
        let absTargetPointY32 = Float(targetMerc.y * scale)
        
        let naiveDeltaY = absTargetPointY32 - absCenterPointY32
        
        // 2. High-precision 64-bit RTC offset
        let rtc = MapProjectionMath.relativeToCenterOffset(coordinate: target, camera: camera)
        
        let trueDeltaY = Float((targetMerc.y - centerMerc.y) * scale)
        
        // The RTC offset must match the true 64-bit offset within sub-pixel accuracy (< 0.0001pt)
        XCTAssertEqual(rtc.y, trueDeltaY, accuracy: 1e-4, "RTC offset must maintain sub-millimeter precision")
        XCTAssertEqual(rtc.x, 0.0, accuracy: 1e-4)
        
        // Verify RTC offset is small in magnitude (< viewport dimension)
        XCTAssertLessThan(abs(rtc.y), 100.0, "RTC offset magnitude must remain small and stable")
    }
    
    // MARK: - 4. Center Alignment in NDC & Screen Points
    
    func testCenterCoordinateProjectsToNDCOriginAndScreenCenter() {
        let testCenters: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
            CLLocationCoordinate2D(latitude: 42.3554, longitude: -71.0664),
            CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
            CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        ]
        
        let viewports: [CGSize] = [
            CGSize(width: 393, height: 852), // iPhone 16 / 17
            CGSize(width: 430, height: 932), // iPhone Pro Max
            CGSize(width: 800, height: 600)   // Landscape test
        ]
        
        for center in testCenters {
            for size in viewports {
                let camera = MapCameraState(
                    centerCoordinate: center,
                    zoomLevel: 16.0,
                    bearing: 45.0, // Rotated bearing
                    pitch: 0.0,
                    fieldOfView: 36.87,
                    viewportSize: size
                )
                
                // 1. Center projects to NDC (0, 0)
                let ndc = MapProjectionMath.projectToNDC(coordinate: center, camera: camera)
                XCTAssertEqual(ndc.x, 0.0, accuracy: 1e-4, "NDC X of center coordinate must be exactly 0.0")
                XCTAssertEqual(ndc.y, 0.0, accuracy: 1e-4, "NDC Y of center coordinate must be exactly 0.0")
                
                // 2. Center projects to screen center (width/2, height/2)
                let screen = MapProjectionMath.projectToScreen(coordinate: center, camera: camera)
                XCTAssertEqual(screen.x, size.width / 2.0, accuracy: 1e-3, "Screen X of center must be width / 2")
                XCTAssertEqual(screen.y, size.height / 2.0, accuracy: 1e-3, "Screen Y of center must be height / 2")
            }
        }
    }
    
    // MARK: - 5. Bearing & Rotation
    
    func testBearingRotationTransforms() {
        let center = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        let northPoint = CLLocationCoordinate2D(latitude: 40.7600, longitude: -73.9855) // Point directly North
        let size = CGSize(width: 400, height: 400)
        
        // 1. North-up (bearing = 0°): Point North of center has screen Y < 200 (higher up on screen) and X == 200
        let cameraNorthUp = MapCameraState(
            centerCoordinate: center,
            zoomLevel: 16.0,
            bearing: 0.0,
            pitch: 0.0,
            fieldOfView: 36.87,
            viewportSize: size
        )
        let screenNorthUp = MapProjectionMath.projectToScreen(coordinate: northPoint, camera: cameraNorthUp)
        XCTAssertEqual(screenNorthUp.x, 200.0, accuracy: 1e-2, "North-up X must be centered")
        XCTAssertLessThan(screenNorthUp.y, 200.0, "North-up Y must be above screen center")
        
        // 2. Rotated clockwise 90° (East-up): The North point now appears to the right of the center (X > 200, Y == 200)
        let cameraEastUp = MapCameraState(
            centerCoordinate: center,
            zoomLevel: 16.0,
            bearing: 90.0,
            pitch: 0.0,
            fieldOfView: 36.87,
            viewportSize: size
        )
        let screenEastUp = MapProjectionMath.projectToScreen(coordinate: northPoint, camera: cameraEastUp)
        XCTAssertGreaterThan(screenEastUp.x, 200.0, "When bearing is 90° clockwise, North point must be to the right (X > 200)")
        XCTAssertEqual(screenEastUp.y, 200.0, accuracy: 1e-2, "When bearing is 90° clockwise, North point must have Y centered")
    }
    
    // MARK: - 6. Round-Trip Forward and Inverse Unprojection
    
    func testScreenProjectAndUnprojectRoundTrip() {
        let center = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        let camera = MapCameraState(
            centerCoordinate: center,
            zoomLevel: 16.0,
            bearing: 25.0,
            pitch: 0.0,
            fieldOfView: 36.87,
            viewportSize: CGSize(width: 393, height: 852)
        )
        
        let testPoints: [CLLocationCoordinate2D] = [
            center,
            CLLocationCoordinate2D(latitude: 40.7588, longitude: -73.9848),
            CLLocationCoordinate2D(latitude: 40.7572, longitude: -73.9862),
            CLLocationCoordinate2D(latitude: 40.7575, longitude: -73.9850),
            CLLocationCoordinate2D(latitude: 40.7585, longitude: -73.9860)
        ]
        
        for orig in testPoints {
            let screenPoint = MapProjectionMath.projectToScreen(coordinate: orig, camera: camera)
            XCTAssertGreaterThanOrEqual(screenPoint.x, 0.0)
            XCTAssertLessThanOrEqual(screenPoint.x, 393.0)
            XCTAssertGreaterThanOrEqual(screenPoint.y, 0.0)
            XCTAssertLessThanOrEqual(screenPoint.y, 852.0)
            
            let unprojected = MapProjectionMath.unprojectFromScreen(screenPoint: screenPoint, camera: camera)
            XCTAssertEqual(unprojected.latitude, orig.latitude, accuracy: 1e-6, "Unprojected latitude must match original within sub-meter precision")
            XCTAssertEqual(unprojected.longitude, orig.longitude, accuracy: 1e-6, "Unprojected longitude must match original within sub-meter precision")
        }
    }
    
    // MARK: - 7. Double-Single (DSFun) Split Arithmetic
    
    func testDoubleSingleSplitAndSubDS() {
        let value: Double = -73.98550123456789
        let (high, low) = MapProjectionMath.splitDouble(value)
        let reconstructed = Double(high) + Double(low)
        XCTAssertEqual(reconstructed, value, accuracy: 1e-12, "Double-single decomposition must preserve full 64-bit precision")
        
        let coordA = CLLocationCoordinate2D(latitude: 40.758000, longitude: -73.985500)
        let coordB = CLLocationCoordinate2D(latitude: 40.758010, longitude: -73.985490)
        
        let splitA = MapProjectionMath.splitCoordinate(coordA)
        let splitB = MapProjectionMath.splitCoordinate(coordB)
        
        let diff = MapProjectionMath.subDS(aHigh: splitB.high, aLow: splitB.low, bHigh: splitA.high, bLow: splitA.low)
        
        let expectedLatDiff = Float(coordB.latitude - coordA.latitude)
        let expectedLonDiff = Float(coordB.longitude - coordA.longitude)
        
        XCTAssertEqual(diff.y, expectedLatDiff, accuracy: 1e-9)
        XCTAssertEqual(diff.x, expectedLonDiff, accuracy: 1e-9)
    }
    
    // MARK: - 8. MapLibre Matrix Conversion Bridge
    
    func testMLNMatrix4Conversion() {
        var mln = MLNMatrix4()
        mln.m00 = 1.0; mln.m01 = 2.0; mln.m02 = 3.0; mln.m03 = 4.0
        mln.m10 = 5.0; mln.m11 = 6.0; mln.m12 = 7.0; mln.m13 = 8.0
        mln.m20 = 9.0; mln.m21 = 10.0; mln.m22 = 11.0; mln.m23 = 12.0
        mln.m30 = 13.0; mln.m31 = 14.0; mln.m32 = 15.0; mln.m33 = 16.0
        
        let simd = MapProjectionMath.matrixFromMLNMatrix4(mln)
        
        XCTAssertEqual(simd.columns.0.x, 1.0)
        XCTAssertEqual(simd.columns.0.y, 2.0)
        XCTAssertEqual(simd.columns.0.z, 3.0)
        XCTAssertEqual(simd.columns.0.w, 4.0)
        
        XCTAssertEqual(simd.columns.1.x, 5.0)
        XCTAssertEqual(simd.columns.1.y, 6.0)
        XCTAssertEqual(simd.columns.1.z, 7.0)
        XCTAssertEqual(simd.columns.1.w, 8.0)
        
        XCTAssertEqual(simd.columns.2.x, 9.0)
        XCTAssertEqual(simd.columns.2.y, 10.0)
        XCTAssertEqual(simd.columns.2.z, 11.0)
        XCTAssertEqual(simd.columns.2.w, 12.0)
        
        XCTAssertEqual(simd.columns.3.x, 13.0)
        XCTAssertEqual(simd.columns.3.y, 14.0)
        XCTAssertEqual(simd.columns.3.z, 15.0)
        XCTAssertEqual(simd.columns.3.w, 16.0)
    }
    
    // MARK: - 9. LockFreeCameraBridge Concurrency
    
    func testLockFreeCameraBridgeConcurrency() {
        let bridge = LockFreeCameraBridge()
        let iterations = 2000
        
        let writeGroup = DispatchGroup()
        let baseCoord = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        
        // Spawn 4 writer threads updating camera state
        for threadID in 0..<4 {
            writeGroup.enter()
            DispatchQueue.global().async {
                for i in 0..<iterations {
                    let state = MapCameraState(
                        centerCoordinate: CLLocationCoordinate2D(
                            latitude: baseCoord.latitude + Double(threadID) * 0.001,
                            longitude: baseCoord.longitude + Double(i) * 0.0001
                        ),
                        zoomLevel: 14.0 + Double(i % 5),
                        bearing: Double(i % 360),
                        pitch: 0.0,
                        fieldOfView: 36.87,
                        viewportSize: CGSize(width: 393, height: 852)
                    )
                    bridge.write(state)
                }
                writeGroup.leave()
            }
        }
        
        // Spawn 4 reader threads continuously querying snapshots
        let readGroup = DispatchGroup()
        for _ in 0..<4 {
            readGroup.enter()
            DispatchQueue.global().async {
                for _ in 0..<iterations {
                    _ = bridge.read()
                }
                readGroup.leave()
            }
        }
        
        let waitResultW = writeGroup.wait(timeout: .now() + 5.0)
        let waitResultR = readGroup.wait(timeout: .now() + 5.0)
        
        XCTAssertEqual(waitResultW, .success, "Writers must finish without deadlocking")
        XCTAssertEqual(waitResultR, .success, "Readers must finish without deadlocking")
        XCTAssertNotNil(bridge.latestState, "Bridge must retain latest state")
    }
    
    // MARK: - 10. VSyncCameraSynchronizer Lifecycle
    
    @MainActor
    func testVSyncCameraSynchronizerLifecycle() {
        let bridge = LockFreeCameraBridge()
        let initial = MapCameraState(
            centerCoordinate: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
            zoomLevel: 16.0,
            bearing: 0.0,
            pitch: 0.0,
            fieldOfView: 36.87,
            viewportSize: CGSize(width: 393, height: 852)
        )
        bridge.write(initial)
        
        let sync = VSyncCameraSynchronizer(cameraBridge: bridge)
        XCTAssertFalse(sync.active, "Synchronizer must start in inactive state")
        
        sync.start()
        XCTAssertTrue(sync.active, "Synchronizer must be active after start")
        
        sync.pause()
        XCTAssertFalse(sync.active, "Synchronizer must be inactive after pause")
        
        sync.resume()
        XCTAssertTrue(sync.active, "Synchronizer must be active after resume")
        
        sync.stop()
        XCTAssertFalse(sync.active, "Synchronizer must be inactive after stop")
    }
}
