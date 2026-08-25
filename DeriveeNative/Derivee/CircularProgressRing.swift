import SwiftUI

public struct CircularProgressRing: View {
    public let progress: Double // 0.0 to 1.0 (or 0 to 100)
    public let lineWidth: CGFloat
    public let ringColor: Color
    public let trackColor: Color
    public let showPercentageText: Bool
    
    public static let electricAmber = Color(red: 1.0, green: 179.0 / 255.0, blue: 0.0) // #FFB300
    
    public init(
        progress: Double,
        lineWidth: CGFloat = 6,
        ringColor: Color = CircularProgressRing.electricAmber,
        trackColor: Color = Color.secondary.opacity(0.15),
        showPercentageText: Bool = false
    ) {
        // Normalize 0-100 or 0.0-1.0
        let normalized = progress > 1.0 ? min(1.0, progress / 100.0) : max(0.0, progress)
        self.progress = normalized
        self.lineWidth = lineWidth
        self.ringColor = ringColor
        self.trackColor = trackColor
        self.showPercentageText = showPercentageText
    }
    
    public var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            
            // Progress Ring
            Circle()
                .trim(from: 0.0, to: CGFloat(min(max(progress, 0.0), 1.0)))
                .stroke(
                    ringColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            
            if showPercentageText {
                Text("\(Int(round(progress * 100)))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        CircularProgressRing(progress: 0.42, showPercentageText: true)
            .frame(width: 44, height: 44)
        CircularProgressRing(progress: 0.85, showPercentageText: false)
            .frame(width: 32, height: 32)
    }
    .padding()
}
