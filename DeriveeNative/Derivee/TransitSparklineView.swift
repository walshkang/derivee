import SwiftUI

struct TransitSparklineView: View {
    let headways: [Double]
    let title: String
    let tintColor: Color
    
    init(headways: [Double] = [4.5, 5.0, 4.2, 6.1, 4.8, 5.5, 4.3], title: String = "7-Day Headway Reliability (min)", tintColor: Color = Color(hex: "#FFB300")) {
        self.headways = headways.isEmpty ? [5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0] : headways
        self.title = title
        self.tintColor = tintColor
    }
    
    private var minVal: Double {
        (headways.min() ?? 0) * 0.9
    }
    
    private var maxVal: Double {
        max((headways.max() ?? 10) * 1.1, minVal + 1.0)
    }
    
    private var avgHeadway: Double {
        headways.reduce(0, +) / Double(headways.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "Avg: %.1f m", avgHeadway))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(tintColor)
            }
            
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let points = computePoints(width: width, height: height)
                
                ZStack {
                    // Subtle background grid line
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height / 2))
                        path.addLine(to: CGPoint(x: width, y: height / 2))
                    }
                    .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    
                    // Area Gradient Fill
                    Path { path in
                        guard !points.isEmpty else { return }
                        path.move(to: CGPoint(x: points[0].x, y: height))
                        path.addLine(to: points[0])
                        for i in 1..<points.count {
                            let p1 = points[i - 1]
                            let p2 = points[i]
                            let midX = (p1.x + p2.x) / 2
                            path.addCurve(to: p2, control1: CGPoint(x: midX, y: p1.y), control2: CGPoint(x: midX, y: p2.y))
                        }
                        path.addLine(to: CGPoint(x: points.last!.x, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [tintColor.opacity(0.35), tintColor.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Smooth Curve Line
                    Path { path in
                        guard !points.isEmpty else { return }
                        path.move(to: points[0])
                        for i in 1..<points.count {
                            let p1 = points[i - 1]
                            let p2 = points[i]
                            let midX = (p1.x + p2.x) / 2
                            path.addCurve(to: p2, control1: CGPoint(x: midX, y: p1.y), control2: CGPoint(x: midX, y: p2.y))
                        }
                    }
                    .stroke(tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    
                    // Latest Data Point Dot
                    if let lastPoint = points.last {
                        Circle()
                            .fill(tintColor)
                            .frame(width: 6, height: 6)
                            .position(lastPoint)
                            .shadow(color: tintColor.opacity(0.8), radius: 4)
                    }
                }
            }
            .frame(height: 48)
            
            HStack {
                Text("7 Days Ago")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Today")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private func computePoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard headways.count > 1 else { return [] }
        let stepX = width / CGFloat(headways.count - 1)
        let rangeY = maxVal - minVal
        
        return headways.enumerated().map { idx, val in
            let x = CGFloat(idx) * stepX
            let normalizedY = CGFloat((val - minVal) / rangeY)
            let y = height - (normalizedY * (height - 8)) - 4
            return CGPoint(x: x, y: y)
        }
    }
}

#Preview {
    TransitSparklineView(headways: [4.5, 5.2, 4.0, 6.5, 4.8, 5.1, 4.2])
        .padding()
}
