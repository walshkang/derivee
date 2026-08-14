import SwiftUI
import UIKit

// MARK: - Brand Colors

public extension Color {
    static let electricAmber = Color(red: 1.0, green: 179.0 / 255.0, blue: 0.0)
    static let midnightSlate = Color(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 26.0 / 255.0)
    static let oledBlack = Color(red: 9.0 / 255.0, green: 9.0 / 255.0, blue: 13.0 / 255.0)
}

public extension UIColor {
    static let electricAmber = UIColor(red: 1.0, green: 179.0 / 255.0, blue: 0.0, alpha: 1.0)
    static let graphiteFog = UIColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, alpha: 1.0)
    static let mutedSlate = UIColor(red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 147.0 / 255.0, alpha: 1.0)
}

// MARK: - Aperture Stepped 7-Hex Shape

public struct ApertureShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        let rawPoints: [(CGFloat, CGFloat)] = [
            (16.0, 3.0),
            (20.0, 5.5),
            (24.0, 3.0),
            (28.0, 5.5),
            (28.0, 10.5),
            (31.5, 12.5),
            (31.5, 17.5),
            (31.5, 22.5),
            (28.0, 24.5),
            (28.0, 29.5),
            (24.0, 32.0),
            (20.0, 29.5),
            (16.0, 32.0),
            (12.0, 29.5),
            (8.0, 32.0),
            (4.0, 29.5),
            (4.0, 24.5),
            (0.5, 22.5),
            (0.5, 17.5),
            (0.5, 12.5),
            (4.0, 10.5),
            (4.0, 5.5),
            (8.0, 3.0),
            (12.0, 5.5)
        ]
        
        guard let first = rawPoints.first else { return path }
        let startX = rect.minX + (first.0 / 32.0) * w
        let startY = rect.minY + (first.1 / 32.0) * h
        path.move(to: CGPoint(x: startX, y: startY))
        
        for pt in rawPoints.dropFirst() {
            let x = rect.minX + (pt.0 / 32.0) * w
            let y = rect.minY + (pt.1 / 32.0) * h
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Variation A: The Micro-Glyph

public struct ApertureMicroGlyph: View {
    public let size: CGFloat
    public let strokeWidth: CGFloat
    public let nodeColor: Color
    public let strokeColor: Color?
    
    public init(
        size: CGFloat = 24,
        strokeWidth: CGFloat = 1.5,
        nodeColor: Color = .electricAmber,
        strokeColor: Color? = nil
    ) {
        self.size = size
        self.strokeWidth = strokeWidth
        self.nodeColor = nodeColor
        self.strokeColor = strokeColor
    }
    
    public var body: some View {
        ZStack {
            ApertureShape()
                .stroke(strokeColor ?? Color.primary, style: StrokeStyle(lineWidth: strokeWidth, lineJoin: .round))
                .frame(width: size, height: size)
            
            Circle()
                .fill(nodeColor)
                .frame(width: max(3, size * 0.22), height: max(3, size * 0.22))
                .offset(y: size * (1.5 / 32.0))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Variation B: Pulsing Vector Aperture (Screen 0 Onboarding Gate)

public struct AperturePulsingView: View {
    public let size: CGFloat
    public let isHydrating: Bool
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    @State private var rotationAngle: Double = 0
    
    public init(size: CGFloat = 220, isHydrating: Bool = true) {
        self.size = size
        self.isHydrating = isHydrating
    }
    
    public var body: some View {
        ZStack {
            // Background ambient glow
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.electricAmber.opacity(0.3),
                    Color.electricAmber.opacity(0.05),
                    Color.clear
                ]),
                center: .center,
                startRadius: 5,
                endRadius: size * 0.65
            )
            .frame(width: size * 1.4, height: size * 1.4)
            .scaleEffect(pulseScale)
            
            // Outer Hex Rosette Cluster (Background Stencil)
            ForEach(0..<6) { i in
                let angle = Double(i) * 60.0 * .pi / 180.0
                let radius = size * 0.32
                ApertureShape()
                    .stroke(Color(red: 24.0/255.0, green: 24.0/255.0, blue: 34.0/255.0).opacity(0.5), lineWidth: 1.0)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            }
            
            // Main Stepped Aperture
            ApertureShape()
                .fill(Color.midnightSlate)
                .frame(width: size, height: size)
                .overlay(
                    ApertureShape()
                        .stroke(Color.electricAmber.opacity(0.8), style: StrokeStyle(lineWidth: 2.0, lineJoin: .round))
                )
                .shadow(color: Color.electricAmber.opacity(0.3), radius: 12, x: 0, y: 0)
            
            // Inner Subtle Cartography Grid Lines
            Path { path in
                let step = size / 6.0
                for i in 1..<6 {
                    let y = step * CGFloat(i)
                    path.move(to: CGPoint(x: size * 0.15, y: y))
                    path.addLine(to: CGPoint(x: size * 0.85, y: y))
                }
            }
            .stroke(Color(red: 37.0/255.0, green: 37.0/255.0, blue: 56.0/255.0).opacity(0.6), lineWidth: 1.0)
            .frame(width: size, height: size)
            .clipShape(ApertureShape())
            
            // Dashed Radar Aperture Ring
            Circle()
                .stroke(
                    Color.electricAmber.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 6])
                )
                .frame(width: size * 0.32, height: size * 0.32)
                .rotationEffect(.degrees(rotationAngle))
            
            // Electric Amber Central Node + Crisp White Target Ring
            ZStack {
                Circle()
                    .fill(Color.electricAmber)
                    .frame(width: size * 0.12, height: size * 0.12)
                
                Circle()
                    .stroke(Color.white, lineWidth: 2.0)
                    .frame(width: size * 0.12, height: size * 0.12)
            }
            .offset(y: size * (1.5 / 32.0))
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .onAppear {
            if isHydrating {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.15
                    pulseOpacity = 0.9
                }
                withAnimation(.linear(duration: 20.0).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
            }
        }
    }
}

// MARK: - Variation C: Milestone Category Aperture Frame

public struct ApertureMilestoneFrame: View {
    public let category: MilestoneCategory
    public let isUnlocked: Bool
    public let size: CGFloat
    
    public init(category: MilestoneCategory, isUnlocked: Bool = true, size: CGFloat = 44) {
        self.category = category
        self.isUnlocked = isUnlocked
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            // Outer Stepped Aperture Ring
            ApertureShape()
                .stroke(
                    isUnlocked ? Color.electricAmber : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.8, lineJoin: .round)
                )
                .background(
                    ApertureShape()
                        .fill(isUnlocked ? Color.electricAmber.opacity(0.12) : Color.gray.opacity(0.08))
                )
                .frame(width: size, height: size)
            
            // Inner Category Vector Graphic (High Negative Space)
            Group {
                switch category {
                case .transitHubs:
                    // Parallel dual transit rail lines cutting through aperture
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(isUnlocked ? Color.electricAmber : .secondary)
                            .frame(width: size * 0.5, height: 2)
                        Rectangle()
                            .fill(isUnlocked ? Color.electricAmber : .secondary)
                            .frame(width: size * 0.5, height: 2)
                    }
                    .rotationEffect(.degrees(-25))
                    
                case .neighborhoodVoyager:
                    // Hexagonal street grid mesh node
                    ZStack {
                        ApertureShape()
                            .stroke(isUnlocked ? Color.electricAmber.opacity(0.7) : .secondary.opacity(0.5), lineWidth: 1.0)
                            .frame(width: size * 0.45, height: size * 0.45)
                        
                        Circle()
                            .fill(isUnlocked ? Color.electricAmber : .secondary)
                            .frame(width: 4, height: 4)
                    }
                    
                case .historicLandmarks:
                    // Landmark Diamond Anchor
                    ZStack {
                        Rectangle()
                            .fill(isUnlocked ? Color.electricAmber : .secondary)
                            .frame(width: size * 0.28, height: size * 0.28)
                            .rotationEffect(.degrees(45))
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 3, height: 3)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Variation D: System Signature

public struct ApertureSignatureView: View {
    public init() {}
    
    public var body: some View {
        VStack(spacing: 8) {
            ApertureMicroGlyph(size: 20, strokeWidth: 1.2, nodeColor: .secondary, strokeColor: .secondary)
                .opacity(0.8)
            
            VStack(spacing: 2) {
                Text("Dérivée v1.0 (Build 1)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text("Unlearn your commute.")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - 120Hz Native Compass Needle Generator

public enum ApertureCompassNeedle {
    public static func makeNeedleImage(size: CGSize = CGSize(width: 40, height: 40)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgContext = ctx.cgContext
            let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            let halfW: CGFloat = size.width * 0.16
            let needleLength: CGFloat = size.height * 0.42
            
            // 1. Draw North Pointer (Electric Amber #FFB300)
            let northPath = UIBezierPath()
            northPath.move(to: CGPoint(x: center.x, y: center.y - needleLength))
            northPath.addLine(to: CGPoint(x: center.x + halfW, y: center.y))
            northPath.addLine(to: CGPoint(x: center.x, y: center.y - 3))
            northPath.addLine(to: CGPoint(x: center.x - halfW, y: center.y))
            northPath.close()
            
            UIColor.electricAmber.setFill()
            northPath.fill()
            
            // 2. Draw North Center Ridge Highlight
            let northFacet = UIBezierPath()
            northFacet.move(to: CGPoint(x: center.x, y: center.y - needleLength))
            northFacet.addLine(to: CGPoint(x: center.x + halfW, y: center.y))
            northFacet.addLine(to: CGPoint(x: center.x, y: center.y - 3))
            northFacet.close()
            
            UIColor.white.withAlphaComponent(0.3).setFill()
            northFacet.fill()
            
            // 3. Draw South Pointer (Graphite / Muted Slate)
            let southPath = UIBezierPath()
            southPath.move(to: CGPoint(x: center.x, y: center.y + needleLength))
            southPath.addLine(to: CGPoint(x: center.x + halfW, y: center.y))
            southPath.addLine(to: CGPoint(x: center.x, y: center.y + 3))
            southPath.addLine(to: CGPoint(x: center.x - halfW, y: center.y))
            southPath.close()
            
            UIColor.mutedSlate.setFill()
            southPath.fill()
            
            // 4. Draw South Facet Shadow
            let southFacet = UIBezierPath()
            southFacet.move(to: CGPoint(x: center.x, y: center.y + needleLength))
            southFacet.addLine(to: CGPoint(x: center.x - halfW, y: center.y))
            southFacet.addLine(to: CGPoint(x: center.x, y: center.y + 3))
            southFacet.close()
            
            UIColor.black.withAlphaComponent(0.25).setFill()
            southFacet.fill()
            
            // 5. Center Hub
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fillEllipse(in: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
            
            cgContext.setFillColor(UIColor.graphiteFog.cgColor)
            cgContext.fillEllipse(in: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
        }
    }
}
