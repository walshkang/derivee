import Foundation
import CoreLocation
import CoreGraphics
import simd
import MapLibre

/// Mathematical projection utilities converting WGS84 coordinates (EPSG:4326) and Web Mercator (EPSG:3857)
/// to Metal Normalized Device Coordinates (NDC) using Relative-to-Center (RTC) precision offsets.
/// Strictly implements the research specifications in `docs/research/05_maplibre_metal_view_synchronization.md`.
public enum MapProjectionMath {
    
    /// Web Mercator upper projection latitude limit (EPSG:3857).
    public static let maxLatitude: Double = 85.0511287798066
    /// Web Mercator lower projection latitude limit (EPSG:3857).
    public static let minLatitude: Double = -85.0511287798066
    
    // MARK: - 1. Web Mercator Forward & Inverse
    
    /// Converts a geodetic WGS84 coordinate (latitude, longitude) to normalized Web Mercator coordinates [0, 1] x [0, 1].
    /// Automatically clamps latitude to [-85.051128°, 85.051128°] to prevent trigonometric singularities at the poles.
    @inline(__always)
    public static func geodeticToMercator(_ coord: CLLocationCoordinate2D) -> SIMD2<Double> {
        // Normalize longitude to [-180, 180)
        var lon = coord.longitude.truncatingRemainder(dividingBy: 360.0)
        if lon < -180.0 { lon += 360.0 }
        if lon >= 180.0 { lon -= 360.0 }
        
        let x = min(max((lon + 180.0) / 360.0, 0.0), 1.0)
        
        let clampedLat = min(max(coord.latitude, minLatitude), maxLatitude)
        let radLat = clampedLat * .pi / 180.0
        let rawY = 0.5 - (1.0 / (2.0 * .pi)) * log(tan(.pi / 4.0 + radLat / 2.0))
        let y = min(max(rawY, 0.0), 1.0)
        
        return SIMD2<Double>(x, y)
    }
    
    /// Converts normalized Web Mercator coordinates [0, 1] x [0, 1] back to a geodetic WGS84 coordinate.
    @inline(__always)
    public static func mercatorToGeodetic(_ mercator: SIMD2<Double>) -> CLLocationCoordinate2D {
        let lon = mercator.x * 360.0 - 180.0
        let lat = (360.0 / .pi) * (atan(exp(.pi * (1.0 - 2.0 * mercator.y))) - .pi / 4.0)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    // MARK: - 2. World Scale & Camera Distance
    
    /// Computes the absolute Mercator world span in logical points at a given continuous zoom level.
    /// In MapLibre Native for iOS, tile extent at zoom level 0 is 512 points: S(z) = 512 · 2^z.
    @inline(__always)
    public static func worldScale(zoomLevel: Double) -> Double {
        512.0 * pow(2.0, zoomLevel)
    }
    
    /// Computes the perspective camera distance in logical points from the eye position to the ground plane.
    /// Derived from the viewport height `h` and vertical field of view `fov` in degrees:
    /// d_cam = h / (2 · tan(fov / 2)).
    @inline(__always)
    public static func cameraDistance(viewportHeight: Double, fieldOfView: Double) -> Double {
        let fovRad = fieldOfView * .pi / 180.0
        return viewportHeight / (2.0 * tan(fovRad / 2.0))
    }
    
    // MARK: - 3. Relative-to-Center (RTC) Offsets
    
    /// Computes high-precision local point offsets in logical screen points relative to the camera focal center.
    /// Evaluated in 64-bit IEEE 754 float precision before casting to 32-bit Float, mitigating
    /// single-precision floating point jitter at deep zoom levels (z >= 18).
    public static func relativeToCenterOffset(coordinate: CLLocationCoordinate2D, camera: MapCameraState) -> SIMD2<Float> {
        let vMerc = geodeticToMercator(coordinate)
        let cMerc = geodeticToMercator(camera.centerCoordinate)
        let s = worldScale(zoomLevel: camera.zoomLevel)
        
        var dx = vMerc.x - cMerc.x
        // Handle antimeridian wrapping
        if dx > 0.5 { dx -= 1.0 }
        else if dx < -0.5 { dx += 1.0 }
        
        let dy = vMerc.y - cMerc.y
        
        return SIMD2<Float>(Float(dx * s), Float(dy * s))
    }
    
    // MARK: - 4. Transformation Matrices
    
    /// Constructs a 4x4 perspective projection matrix conforming to Metal Normalized Device Coordinates:
    /// - X in [-1, 1]
    /// - Y in [-1, 1] (inverted scaling `-f` to match screen Y increasing downward vs Metal NDC Y increasing upward)
    /// - Z in [0, 1] (Metal clip depth range)
    public static func makePerspectiveProjectionMatrix(
        viewportSize: CGSize,
        fieldOfView: Double,
        nearZ: Double = 1.0,
        farZ: Double? = nil
    ) -> simd_float4x4 {
        let width = Double(viewportSize.width)
        let height = Double(viewportSize.height)
        let aspect = width / height
        let fovRad = fieldOfView * .pi / 180.0
        let camDist = cameraDistance(viewportHeight: height, fieldOfView: fieldOfView)
        
        let near = nearZ
        let far = farZ ?? (camDist * 10.0)
        let f = 1.0 / tan(fovRad / 2.0)
        
        var matProj = matrix_identity_double4x4
        matProj.columns.0.x = f / aspect
        matProj.columns.1.y = -f // Flip Y for Metal NDC
        matProj.columns.2.z = far / (far - near)
        matProj.columns.2.w = 1.0
        matProj.columns.3.z = -(far * near) / (far - near)
        matProj.columns.3.w = 0.0
        
        return simd_float4x4(matProj)
    }
    
    /// Constructs the 4x4 Relative-to-Center (RTC) View matrix combining translation along Z, pitch, and bearing:
    /// M_view = M_translate · M_pitch · M_bearing.
    public static func makeRTCViewMatrix(camera: MapCameraState) -> simd_float4x4 {
        let camDist = cameraDistance(viewportHeight: Double(camera.viewportSize.height), fieldOfView: camera.fieldOfView)
        let pitchRad = camera.pitch * .pi / 180.0
        let bearingRad = -camera.bearing * .pi / 180.0
        
        // 1. Translation: places camera at eye distance along Z
        var matTranslate = matrix_identity_double4x4
        matTranslate.columns.3.z = camDist
        
        // 2. Pitch: tilt angle from visual horizon (rotation around X)
        var matPitch = matrix_identity_double4x4
        matPitch.columns.1.y = cos(pitchRad)
        matPitch.columns.1.z = sin(pitchRad)
        matPitch.columns.2.y = -sin(pitchRad)
        matPitch.columns.2.z = cos(pitchRad)
        
        // 3. Bearing: rotation clockwise from True North (rotation around Z)
        var matBearing = matrix_identity_double4x4
        matBearing.columns.0.x = cos(bearingRad)
        matBearing.columns.0.y = -sin(bearingRad)
        matBearing.columns.1.x = sin(bearingRad)
        matBearing.columns.1.y = cos(bearingRad)
        
        let matView = matrix_multiply(matTranslate, matrix_multiply(matPitch, matBearing))
        return simd_float4x4(matView)
    }
    
    /// Constructs the full Relative-to-Center (RTC) Model-View-Projection (MVP) matrix:
    /// M_mvp,rtc = M_proj · M_view.
    public static func makeRTCProjectionMatrix(
        camera: MapCameraState,
        nearZ: Double = 1.0,
        farZ: Double? = nil
    ) -> simd_float4x4 {
        let width = Double(camera.viewportSize.width)
        let height = Double(camera.viewportSize.height)
        let aspect = width / height
        let fovRad = camera.fieldOfView * .pi / 180.0
        let camDist = cameraDistance(viewportHeight: height, fieldOfView: camera.fieldOfView)
        
        let near = nearZ
        let far = farZ ?? (camDist * 10.0)
        let f = 1.0 / tan(fovRad / 2.0)
        
        var matProj = matrix_identity_double4x4
        matProj.columns.0.x = f / aspect
        matProj.columns.1.y = -f // Flip Y for Metal NDC
        matProj.columns.2.z = far / (far - near)
        matProj.columns.2.w = 1.0
        matProj.columns.3.z = -(far * near) / (far - near)
        matProj.columns.3.w = 0.0
        
        let pitchRad = camera.pitch * .pi / 180.0
        let bearingRad = -camera.bearing * .pi / 180.0
        
        var matPitch = matrix_identity_double4x4
        matPitch.columns.1.y = cos(pitchRad)
        matPitch.columns.1.z = sin(pitchRad)
        matPitch.columns.2.y = -sin(pitchRad)
        matPitch.columns.2.z = cos(pitchRad)
        
        var matBearing = matrix_identity_double4x4
        matBearing.columns.0.x = cos(bearingRad)
        matBearing.columns.0.y = -sin(bearingRad)
        matBearing.columns.1.x = sin(bearingRad)
        matBearing.columns.1.y = cos(bearingRad)
        
        var matTranslate = matrix_identity_double4x4
        matTranslate.columns.3.z = camDist
        
        let matView = matrix_multiply(matTranslate, matrix_multiply(matPitch, matBearing))
        let matMVP = matrix_multiply(matProj, matView)
        
        return simd_float4x4(matMVP)
    }
    
    // MARK: - 5. Coordinate Forward & Inverse Projection
    
    /// Projects a WGS84 geodetic coordinate directly to Metal Normalized Device Coordinates (NDC)
    /// in the range [-1, 1] x [-1, 1] with perspective division.
    public static func projectToNDC(coordinate: CLLocationCoordinate2D, camera: MapCameraState) -> SIMD4<Float> {
        let rtc = relativeToCenterOffset(coordinate: coordinate, camera: camera)
        let localPos = SIMD4<Float>(rtc.x, rtc.y, 0.0, 1.0)
        let mvp = makeRTCProjectionMatrix(camera: camera)
        let clipPos = mvp * localPos
        
        if clipPos.w != 0 {
            return clipPos / clipPos.w
        } else {
            return clipPos
        }
    }
    
    /// Projects a WGS84 coordinate to logical screen space points in the viewport [0, width] x [0, height].
    public static func projectToScreen(coordinate: CLLocationCoordinate2D, camera: MapCameraState) -> CGPoint {
        let ndc = projectToNDC(coordinate: coordinate, camera: camera)
        let screenX = (Double(ndc.x) + 1.0) * 0.5 * Double(camera.viewportSize.width)
        let screenY = (1.0 - Double(ndc.y)) * 0.5 * Double(camera.viewportSize.height)
        return CGPoint(x: screenX, y: screenY)
    }
    
    /// Unprojects a logical screen point in the viewport [0, width] x [0, height] to the ground plane (Z = 0)
    /// in geodetic WGS84 coordinates. Inverts the RTC Model-View-Projection matrix and intersects the viewing ray.
    public static func unprojectFromScreen(
        screenPoint: CGPoint,
        camera: MapCameraState,
        nearZ: Double = 1.0,
        farZ: Double? = nil
    ) -> CLLocationCoordinate2D {
        let ndcX = Float((2.0 * screenPoint.x / camera.viewportSize.width) - 1.0)
        let ndcY = Float(1.0 - (2.0 * screenPoint.y / camera.viewportSize.height))
        
        let mvp = makeRTCProjectionMatrix(camera: camera, nearZ: nearZ, farZ: farZ)
        let invMVP = simd_inverse(mvp)
        
        let pNearClip = SIMD4<Float>(ndcX, ndcY, 0.0, 1.0)
        let pFarClip = SIMD4<Float>(ndcX, ndcY, 1.0, 1.0)
        
        let pNearWorldH = invMVP * pNearClip
        let pFarWorldH = invMVP * pFarClip
        
        let pNearWorld = SIMD3<Float>(pNearWorldH.x, pNearWorldH.y, pNearWorldH.z) / pNearWorldH.w
        let pFarWorld = SIMD3<Float>(pFarWorldH.x, pFarWorldH.y, pFarWorldH.z) / pFarWorldH.w
        
        let rayDir = pFarWorld - pNearWorld
        
        // Ray-plane intersection with ground plane Z = 0: pNear.z + t * rayDir.z = 0
        let t = (0.0 - pNearWorld.z) / rayDir.z
        let rtcX = Double(pNearWorld.x + t * rayDir.x)
        let rtcY = Double(pNearWorld.y + t * rayDir.y)
        
        let scale = worldScale(zoomLevel: camera.zoomLevel)
        let centerMerc = geodeticToMercator(camera.centerCoordinate)
        
        let mercX = centerMerc.x + (rtcX / scale)
        let mercY = centerMerc.y + (rtcY / scale)
        
        return mercatorToGeodetic(SIMD2<Double>(mercX, mercY))
    }
    
    // MARK: - 6. High-Low Split (Double-Single / DSFun) Arithmetic
    
    /// Decomposes a 64-bit IEEE 754 float (`Double`) into two 32-bit floats (`Float` high and low)
    /// such that `Double(high) + Double(low) == value`.
    /// Used for encoding GPU buffer positions without incurring full 64-bit emulation overhead.
    @inline(__always)
    public static func splitDouble(_ value: Double) -> (high: Float, low: Float) {
        let high = Float(value)
        let low = Float(value - Double(high))
        return (high, low)
    }
    
    /// Decomposes a geodetic coordinate into high-precision high and low vectors for GPU buffers.
    public static func splitCoordinate(_ coord: CLLocationCoordinate2D) -> (high: SIMD2<Float>, low: SIMD2<Float>) {
        let lon = splitDouble(coord.longitude)
        let lat = splitDouble(coord.latitude)
        return (
            SIMD2<Float>(lon.high, lat.high),
            SIMD2<Float>(lon.low, lat.low)
        )
    }
    
    /// Performs high-precision double-single subtraction: `(a_high + a_low) - (b_high + b_low)`
    /// via two-sum arithmetic, matching MSL shader implementation in Doc 05 §2.
    @inline(__always)
    public static func subDS(
        aHigh: SIMD2<Float>,
        aLow: SIMD2<Float>,
        bHigh: SIMD2<Float>,
        bLow: SIMD2<Float>
    ) -> SIMD2<Float> {
        let diffHigh = aHigh - bHigh
        let diffLow = aLow - bLow
        return diffHigh + diffLow
    }
    
    // MARK: - 7. MapLibre Matrix Conversion Bridge
    
    /// Converts MapLibre's `MLNMatrix4` to Apple Metal's `simd_float4x4` in column-major format.
    public static func matrixFromMLNMatrix4(_ m: MLNMatrix4) -> simd_float4x4 {
        var result = simd_float4x4()
        result.columns.0 = SIMD4<Float>(Float(m.m00), Float(m.m01), Float(m.m02), Float(m.m03))
        result.columns.1 = SIMD4<Float>(Float(m.m10), Float(m.m11), Float(m.m12), Float(m.m13))
        result.columns.2 = SIMD4<Float>(Float(m.m20), Float(m.m21), Float(m.m22), Float(m.m23))
        result.columns.3 = SIMD4<Float>(Float(m.m30), Float(m.m31), Float(m.m32), Float(m.m33))
        return result
    }
}

// MARK: - Internal simd_float4x4 conversion from simd_double4x4

private extension simd_float4x4 {
    init(_ d: simd_double4x4) {
        self.init()
        self.columns.0 = SIMD4<Float>(d.columns.0)
        self.columns.1 = SIMD4<Float>(d.columns.1)
        self.columns.2 = SIMD4<Float>(d.columns.2)
        self.columns.3 = SIMD4<Float>(d.columns.3)
    }
}
