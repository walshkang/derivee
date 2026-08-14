import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func hexColor(_ hex: String, alpha: CGFloat = 1.0) -> CGColor {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r, g, b: CGFloat
    switch hex.count {
    case 6:
        r = CGFloat((int >> 16) & 0xFF) / 255.0
        g = CGFloat((int >> 8) & 0xFF) / 255.0
        b = CGFloat(int & 0xFF) / 255.0
    default:
        r = 1; g = 1; b = 1
    }
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

func createAperturePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
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

func renderIcon(mode: String, size: CGFloat = 1024) -> CGImage? {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    
    switch mode {
    case "dark":
        // 1. Base dark background
        context.setFillColor(hexColor("#09090D"))
        context.fill(rect)
        
        // 2. Outer background rosette lines
        context.setStrokeColor(hexColor("#181822", alpha: 0.5))
        context.setLineWidth(3.0)
        let rosetteRadius = size * 0.32
        for i in 0..<6 {
            let angle = CGFloat(i) * 60.0 * .pi / 180.0
            let rRect = CGRect(
                x: size * 0.5 + cos(angle) * rosetteRadius - (size * 0.38) * 0.5,
                y: size * 0.5 + sin(angle) * rosetteRadius - (size * 0.38) * 0.5,
                width: size * 0.38,
                height: size * 0.38
            )
            let rPath = createAperturePath(in: rRect)
            context.addPath(rPath)
            context.strokePath()
        }
        
        // 3. Main Aperture fill (Midnight Slate map pattern)
        let apertureRect = CGRect(x: size * 0.15, y: size * 0.15, width: size * 0.7, height: size * 0.7)
        let aperturePath = createAperturePath(in: apertureRect)
        
        context.saveGState()
        context.addPath(aperturePath)
        context.clip()
        
        context.setFillColor(hexColor("#12121A"))
        context.fill(rect)
        
        // Map lines
        context.setStrokeColor(hexColor("#252538"))
        context.setLineWidth(5.0)
        context.move(to: CGPoint(x: 0, y: size * 0.5))
        context.addQuadCurve(to: CGPoint(x: size, y: size * 0.5), control: CGPoint(x: size * 0.5, y: size * 0.4))
        context.strokePath()
        
        context.move(to: CGPoint(x: size * 0.5, y: 0))
        context.addQuadCurve(to: CGPoint(x: size * 0.5, y: size), control: CGPoint(x: size * 0.6, y: size * 0.5))
        context.strokePath()
        
        context.restoreGState()
        
        // 4. Main Aperture Stroke
        context.addPath(aperturePath)
        context.setStrokeColor(hexColor("#FFB300", alpha: 0.8))
        context.setLineWidth(4.0)
        context.strokePath()
        
        // 5. Center Amber Radar / Glow
        let center = CGPoint(x: size * 0.5, y: size * 0.5)
        
        // Amber Radial Glow
        let colors = [hexColor("#FFB300", alpha: 0.35), hexColor("#FFB300", alpha: 0.0)] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size * 0.25, options: [])
        
        // Dashed radar circle
        context.setStrokeColor(hexColor("#FFB300", alpha: 0.8))
        context.setLineWidth(3.0)
        context.setLineDash(phase: 0, lengths: [8, 12])
        context.strokeEllipse(in: CGRect(x: center.x - size * 0.12, y: center.y - size * 0.12, width: size * 0.24, height: size * 0.24))
        
        // Central live amber coordinate node + crisp white ring
        context.setLineDash(phase: 0, lengths: [])
        context.setFillColor(hexColor("#FFB300"))
        context.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
        
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.setLineWidth(6.0)
        context.strokeEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
        
    case "light":
        // 1. Base graphite fog background
        context.setFillColor(hexColor("#1C1C1E"))
        context.fill(rect)
        
        // 2. Outer background rosette lines
        context.setStrokeColor(hexColor("#2C2C2E", alpha: 0.8))
        context.setLineWidth(3.0)
        let rosetteRadius = size * 0.32
        for i in 0..<6 {
            let angle = CGFloat(i) * 60.0 * .pi / 180.0
            let rRect = CGRect(
                x: size * 0.5 + cos(angle) * rosetteRadius - (size * 0.38) * 0.5,
                y: size * 0.5 + sin(angle) * rosetteRadius - (size * 0.38) * 0.5,
                width: size * 0.38,
                height: size * 0.38
            )
            let rPath = createAperturePath(in: rRect)
            context.addPath(rPath)
            context.strokePath()
        }
        
        // 3. Main Aperture fill (Soft Parchment base)
        let apertureRect = CGRect(x: size * 0.15, y: size * 0.15, width: size * 0.7, height: size * 0.7)
        let aperturePath = createAperturePath(in: apertureRect)
        
        context.saveGState()
        context.addPath(aperturePath)
        context.clip()
        
        context.setFillColor(hexColor("#F9F9F6"))
        context.fill(rect)
        
        // Map lines
        context.setStrokeColor(hexColor("#E5E5EA"))
        context.setLineWidth(5.0)
        context.move(to: CGPoint(x: 0, y: size * 0.5))
        context.addQuadCurve(to: CGPoint(x: size, y: size * 0.5), control: CGPoint(x: size * 0.5, y: size * 0.4))
        context.strokePath()
        
        context.move(to: CGPoint(x: size * 0.5, y: 0))
        context.addQuadCurve(to: CGPoint(x: size * 0.5, y: size), control: CGPoint(x: size * 0.6, y: size * 0.5))
        context.strokePath()
        
        context.restoreGState()
        
        // 4. Main Aperture Stroke
        context.addPath(aperturePath)
        context.setStrokeColor(hexColor("#1C1C1E"))
        context.setLineWidth(4.0)
        context.strokePath()
        
        // 5. Center Live Amber Node
        let center = CGPoint(x: size * 0.5, y: size * 0.5)
        
        context.setFillColor(hexColor("#FFB300"))
        context.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
        
        context.setStrokeColor(hexColor("#000000"))
        context.setLineWidth(6.0)
        context.strokeEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
        
    case "tinted":
        // Pure monochrome alpha stencil for iOS 18
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(rect)
        
        let apertureRect = CGRect(x: size * 0.15, y: size * 0.15, width: size * 0.7, height: size * 0.7)
        let aperturePath = createAperturePath(in: apertureRect)
        
        context.addPath(aperturePath)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.setLineWidth(6.0)
        context.strokePath()
        
        let center = CGPoint(x: size * 0.5, y: size * 0.5)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
        
    default:
        break
    }
    
    return context.makeImage()
}

func savePNG(image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "ImageExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "ImageExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image destination"])
    }
}

let appIconDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./Derivee/Assets.xcassets/AppIcon.appiconset")

try FileManager.default.createDirectory(at: appIconDir, withIntermediateDirectories: true)

let variants = ["light": "AppIcon-Light.png", "dark": "AppIcon-Dark.png", "tinted": "AppIcon-Tinted.png"]

for (mode, filename) in variants {
    if let img = renderIcon(mode: mode) {
        let dest = appIconDir.appendingPathComponent(filename)
        try savePNG(image: img, to: dest)
        print("Generated \(dest.path)")
    }
}
