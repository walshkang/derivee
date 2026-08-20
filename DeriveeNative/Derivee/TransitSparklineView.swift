import SwiftUI

struct TransitSparklineView: View {
    let headways: [Double]
    let title: String
    let tintColor: Color
    let referenceDate: Date
    
    init(
        headways: [Double] = [4.5, 5.0, 4.2, 6.1, 4.8, 5.5, 4.3],
        title: String = "7-Day Headway Reliability (min)",
        tintColor: Color = Color(hex: "#FFB300"),
        referenceDate: Date = Date()
    ) {
        self.headways = headways.isEmpty ? [5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0] : headways
        self.title = title
        self.tintColor = tintColor
        self.referenceDate = referenceDate
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
    
    private var dayLabels: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "E M/d"
        
        let count = headways.count
        guard count > 0 else { return [] }
        
        return (0..<count).map { idx in
            let daysAgo = (count - 1) - idx
            if let date = calendar.date(byAdding: .day, value: -daysAgo, to: referenceDate) {
                return formatter.string(from: date)
            }
            return ""
        }
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
                    
                    // Latest Data Point Dot & Today Annotation
                    if let lastPoint = points.last, let lastVal = headways.last {
                        Circle()
                            .fill(tintColor)
                            .frame(width: 6, height: 6)
                            .position(lastPoint)
                            .shadow(color: tintColor.opacity(0.8), radius: 4)
                        
                        Text(String(format: "%.1fm", lastVal))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(tintColor)
                            .position(x: max(lastPoint.x - 18, 18), y: max(lastPoint.y - 10, 8))
                    }
                }
            }
            .frame(height: 48)
            
            HStack {
                if let first = dayLabels.first {
                    Text(first)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if dayLabels.count > 2 {
                    Text(dayLabels[dayLabels.count / 2])
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let last = dayLabels.last {
                    Text("\(last) (Today)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
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
