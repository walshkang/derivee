import XCTest
import CoreLocation
import SwiftUI
import SnapshotTesting
@testable import Derivee

final class ApertureBrandingTests: XCTestCase {
    
    func testApertureShapeGeometry() {
        let shape = ApertureShape()
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = shape.path(in: rect)
        
        XCTAssertFalse(path.isEmpty, "Aperture path must not be empty")
        let bounds = path.boundingRect
        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.height, 0)
        XCTAssertLessThanOrEqual(bounds.maxX, 101)
        XCTAssertLessThanOrEqual(bounds.maxY, 101)
    }
    
    func testApertureCompassNeedleGeneration() {
        let image = ApertureCompassNeedle.makeNeedleImage(size: CGSize(width: 40, height: 40))
        XCTAssertNotNil(image, "Needle image must be successfully rendered")
        XCTAssertEqual(image.size.width, 40)
        XCTAssertEqual(image.size.height, 40)
        XCTAssertNotNil(image.cgImage)
    }
    
    func testTrackingAttributesContentStateWithDistance() throws {
        let state = TrackingAttributes.ContentState(hexesCleared: 42, activeNeighborhood: "Williamsburg", distanceMeters: 1450.5)
        XCTAssertEqual(state.hexesCleared, 42)
        XCTAssertEqual(state.activeNeighborhood, "Williamsburg")
        XCTAssertEqual(state.distanceMeters, 1450.5)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let decoded = try JSONDecoder().decode(TrackingAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded.hexesCleared, 42)
        XCTAssertEqual(decoded.activeNeighborhood, "Williamsburg")
        XCTAssertEqual(decoded.distanceMeters, 1450.5)
    }
    
    @MainActor
    func testProfileFABSnapshot() {
        let fab = ProfileFAB(action: {})
            .frame(width: 60, height: 60)
            .background(Color.black)
        
        let vc = UIHostingController(rootView: fab)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 60, height: 60))))
    }
    
    @MainActor
    func testApertureMicroGlyphSnapshot() {
        let glyph = ApertureMicroGlyph(size: 32, strokeWidth: 1.8)
            .padding()
            .background(Color.black)
        
        let vc = UIHostingController(rootView: glyph)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 64, height: 64))))
    }
    
    @MainActor
    func testApertureMilestoneFrameSnapshot() {
        let frame = VStack(spacing: 12) {
            ApertureMilestoneFrame(category: .transitHubs, isUnlocked: true, size: 40)
            ApertureMilestoneFrame(category: .neighborhoodVoyager, isUnlocked: true, size: 40)
            ApertureMilestoneFrame(category: .historicLandmarks, isUnlocked: false, size: 40)
        }
        .padding()
        .background(Color.black)
        
        let vc = UIHostingController(rootView: frame)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 80, height: 180))))
    }
    
    @MainActor
    func testApertureSignatureViewSnapshot() {
        let sig = ApertureSignatureView()
            .frame(width: 300, height: 80)
            .background(Color(UIColor.systemGroupedBackground))
        
        let vc = UIHostingController(rootView: sig)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 300, height: 80))))
    }
}
