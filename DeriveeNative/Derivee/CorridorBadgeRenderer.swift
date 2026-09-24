import Foundation
import UIKit
import MapLibre

/// High-performance in-memory CoreGraphics badge renderer for multi-route transit corridors.
/// Generates crisp @3x Retina horizontal capsule badges for canonical corridors (e.g. "badge_4_5_6", "badge_F_M", "badge_L").
/// Implements Research Doc 22 §5.3, §5.4 and Wave V.4.
public enum CorridorBadgeRenderer: Sendable {
    
    // In-memory cache for rendered UIImage badges
    private static let cache = NSCache<NSString, UIImage>()
    
    /// Canonical badge geometry tokens (Doc 22 §5.1, §5.3)
    public enum Metrics {
        public static let badgeHeight: CGFloat = 18.0
        public static let cornerRadius: CGFloat = 9.0
        public static let bulletDiameter: CGFloat = 14.0
        public static let bulletRadius: CGFloat = 7.0
        public static let bulletSpacing: CGFloat = 2.0
        public static let horizontalPadding: CGFloat = 2.5
        public static let casingBorderWidth: CGFloat = 1.0
    }
    
    /// Parses a composite badge key (e.g. "badge_4_5_6" or "badge_F_M") into its constituent route tokens (e.g. ["4", "5", "6"]).
    public static func parseTokens(from compositeKey: String) -> [String] {
        var key = compositeKey
        if key.hasPrefix("badge_") {
            key = String(key.dropFirst(6))
        }
        guard !key.isEmpty else { return [] }
        return key.components(separatedBy: "_").filter { !$0.isEmpty }
    }
    
    /// Renders or retrieves a cached badge image for a composite key and fallback trunk color.
    @MainActor
    public static func badgeImage(for compositeKey: String, trunkColorHex: String? = nil) -> UIImage {
        let cacheKey = "\(compositeKey)_\(trunkColorHex ?? "")" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        let tokens = parseTokens(from: compositeKey)
        let image = renderBadge(tokens: tokens, fallbackTrunkColor: trunkColorHex)
        cache.setObject(image, forKey: cacheKey)
        return image
    }
    
    /// CoreGraphics @3x Retina capsule renderer.
    @MainActor
    public static func renderBadge(tokens: [String], fallbackTrunkColor: String? = nil) -> UIImage {
        let displayTokens = tokens.isEmpty ? ["•"] : tokens
        let count = CGFloat(displayTokens.count)
        
        let totalWidth = (Metrics.horizontalPadding * 2.0) + (count * Metrics.bulletDiameter) + (max(0, count - 1) * Metrics.bulletSpacing)
        let size = CGSize(width: ceil(totalWidth), height: Metrics.badgeHeight)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3.0 // Native Retina @3x
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            // 1. Draw outer white capsule background with subtle dark casing border
            let capsuleRect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: capsuleRect, cornerRadius: Metrics.cornerRadius)
            
            UIColor.white.setFill()
            path.fill()
            
            UIColor(white: 0.15, alpha: 0.25).setStroke()
            path.lineWidth = Metrics.casingBorderWidth
            path.stroke()
            
            // 2. Draw circular bullets for each route token
            var currentX = Metrics.horizontalPadding
            let bulletY = (Metrics.badgeHeight - Metrics.bulletDiameter) / 2.0
            
            for token in displayTokens {
                let bulletRect = CGRect(x: currentX, y: bulletY, width: Metrics.bulletDiameter, height: Metrics.bulletDiameter)
                let bulletPath = UIBezierPath(ovalIn: bulletRect)
                
                // Color lookup: prioritize fallbackTrunkColor if provided, otherwise lineInfo
                let lineInfo = TransitRouteData.lineInfo(for: token)
                let fillColorHex: String
                if let fallback = fallbackTrunkColor, !fallback.isEmpty {
                    fillColorHex = fallback
                } else {
                    fillColorHex = lineInfo.colorHex
                }
                
                let bulletColor = UIColor(hex: fillColorHex)
                bulletColor.setFill()
                bulletPath.fill()
                
                // Text typography & contrast
                let textColorHex = lineInfo.textColorHex
                let textColor: UIColor
                if !textColorHex.isEmpty && textColorHex != "#FFFFFF" {
                    textColor = UIColor(hex: textColorHex)
                } else {
                    textColor = isLightColor(bulletColor) ? .black : .white
                }
                
                let fontSize: CGFloat = token.count > 2 ? 7.0 : (token.count > 1 ? 8.0 : 9.5)
                let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor
                ]
                
                let attrString = NSAttributedString(string: token, attributes: attributes)
                let textSize = attrString.size()
                let textRect = CGRect(
                    x: bulletRect.midX - (textSize.width / 2.0),
                    y: bulletRect.midY - (textSize.height / 2.0) - 0.2,
                    width: textSize.width,
                    height: textSize.height
                )
                attrString.draw(in: textRect)
                
                currentX += Metrics.bulletDiameter + Metrics.bulletSpacing
            }
        }
    }
    
    /// Scans a ShapeCollectionFeature and registers all composite badge images in the MapLibre style.
    @MainActor
    public static func registerBadges(for shapeCollection: MLNShapeCollectionFeature, in style: MLNStyle) {
        var registeredKeys = Set<String>()
        for shape in shapeCollection.shapes {
            guard let feature = shape as? MLNFeature else { continue }
            let attrs = feature.attributes
            guard let compKey = attrs["composite_key"] as? String,
                  !compKey.isEmpty,
                  !registeredKeys.contains(compKey) else {
                continue
            }
            
            registeredKeys.insert(compKey)
            let trunkHex = (attrs["trunk_color_hex"] as? String) ?? (attrs["trunk_color"] as? String)
            let img = badgeImage(for: compKey, trunkColorHex: trunkHex)
            style.setImage(img, forName: compKey)
        }
    }
    
    private static func isLightColor(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        // ITU-R BT.709 perceived luminance
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return lum > 0.65
    }
}
