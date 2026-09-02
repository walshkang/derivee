import UIKit

/// High-performance graphics renderer producing discrete, pixel-perfect route bullet clusters.
/// Used by MapLibre's `MLNSymbolStyleLayer` to resolve discrete line badges (`[4][5][6]` vs `[6]`) at $z \ge 14.5$.
public enum StationBulletRenderer: Sendable {
    
    /// Normalizes and cleans a comma-separated or whitespace-separated route string into unique, ordered route identifiers.
    public static func parseAndNormalizeRoutes(_ rawRoutes: String) -> [String] {
        let items = rawRoutes.components(separatedBy: CharacterSet(charactersIn: ",;/| "))
        var seen = Set<String>()
        var result = [String]()
        
        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        
        // Sort routes in natural transit order (numbers first, then letters, then multi-char)
        result.sort { r1, r2 in
            let n1 = Int(r1)
            let n2 = Int(r2)
            if let a = n1, let b = n2 {
                return a < b
            } else if n1 != nil {
                return true
            } else if n2 != nil {
                return false
            }
            return r1 < r2
        }
        
        return result
    }
    
    /// Returns a deterministic icon cache key for a route set (e.g. `bullet_4_5_6`).
    public static func bulletIconIdentifier(for routes: [String]) -> String {
        let safeNames = routes.map { $0.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "") }
        return "bullet_\(safeNames.joined(separator: "_"))"
    }
    
    /// Renders a composite UIImage containing side-by-side circular route discs.
    /// Each disc features the official route color, contrasting bold typography, and a 1.0pt white rim.
    @MainActor
    public static func renderCompositeBulletImage(
        routes: [String],
        discDiameter: CGFloat = 16.0,
        gap: CGFloat = 2.0
    ) -> UIImage {
        let count = max(1, routes.count)
        let totalWidth = CGFloat(count) * discDiameter + CGFloat(count - 1) * gap + 4.0 // 2pt padding on edges
        let totalHeight = discDiameter + 4.0 // 2pt padding on edges
        let size = CGSize(width: totalWidth, height: totalHeight)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            
            var currentX: CGFloat = 2.0
            let startY: CGFloat = 2.0
            
            for route in routes {
                let info = TransitRouteData.lineInfo(for: route)
                let discRect = CGRect(x: currentX, y: startY, width: discDiameter, height: discDiameter)
                
                // Outer subtle drop glow / shadow for dark and light basemaps
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 1.0), blur: 2.0, color: UIColor.black.withAlphaComponent(0.35).cgColor)
                
                // 1. Fill Route Disc
                let path = UIBezierPath(ovalIn: discRect)
                UIColor(hex: info.colorHex).setFill()
                path.fill()
                cg.restoreGState()
                
                // 2. Crisp 1.0pt Inner/Outer Border
                UIColor.white.setStroke()
                path.lineWidth = 1.0
                path.stroke()
                
                // 3. Route Label Typography
                let text = route
                let fontSize: CGFloat = text.count > 2 ? (discDiameter * 0.44) : (discDiameter * 0.58)
                let font = UIFont.systemFont(ofSize: fontSize, weight: .black)
                let textColor = UIColor(hex: info.textColorHex)
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
                
                let textSize = text.size(withAttributes: attrs)
                let textRect = CGRect(
                    x: discRect.minX + (discDiameter - textSize.width) / 2.0,
                    y: discRect.minY + (discDiameter - textSize.height) / 2.0,
                    width: textSize.width,
                    height: textSize.height
                )
                
                text.draw(in: textRect, withAttributes: attrs)
                
                currentX += discDiameter + gap
            }
        }
    }
}
