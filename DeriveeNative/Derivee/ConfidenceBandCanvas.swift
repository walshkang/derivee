import SwiftUI

/// 120Hz Immediate-Mode Confidence Band Canvas rendering statistical percentile wait times ($P_{10}$, $P_{50}$, $P_{90}$)
/// with statistical variance disutility coloring and interactive tap-to-inspect scrubbing.
///
/// Backed by Metal hardware rasterization via `Canvas(rendersAsynchronously: true)` and `.drawingGroup()`.
public struct ConfidenceBandCanvas: View {
    public enum Style {
        case expanded // Full inspector mode with gridlines, axes, and readout capsule
        case compact  // Minimal spark-band for route cards and inline summaries
    }
    
    public let slice: ConfidenceBandSlice
    public let style: Style
    public let maxY: Float
    public let onSelectSlot: ((_ slotIndex: Int, _ minuteOfDay: Int, _ p10: Float, _ p50: Float, _ p90: Float) -> Void)?
    
    @State private var internalSelectedSlot: Int? = nil
    @State private var isDragging: Bool = false
    
    private let yAxisWidth: CGFloat = 34.0
    private let xAxisHeight: CGFloat = 16.0
    
    public init(
        slice: ConfidenceBandSlice,
        style: Style = .expanded,
        maxY: Float? = nil,
        initialSelectedSlot: Int? = nil,
        onSelectSlot: ((_ slotIndex: Int, _ minuteOfDay: Int, _ p10: Float, _ p50: Float, _ p90: Float) -> Void)? = nil
    ) {
        self.slice = slice
        self.style = style
        self.maxY = max(2.0, maxY ?? slice.maxBound * 1.15)
        self._internalSelectedSlot = State(initialValue: initialSelectedSlot)
        self.onSelectSlot = onSelectSlot
    }
    
    public var body: some View {
        switch style {
        case .expanded:
            expandedView
        case .compact:
            compactView
        }
    }
    
    // MARK: - Expanded Presentation View
    
    private var expandedView: some View {
        VStack(spacing: 8) {
            // 1. Detail Readout Bar
            detailReadoutBar
            
            // 2. Immediate-Mode Canvas Viewport
            GeometryReader { geo in
                let size = geo.size
                let plotWidth = max(1.0, size.width - yAxisWidth)
                let plotHeight = max(1.0, size.height - xAxisHeight)
                
                Canvas(rendersAsynchronously: true) { context, canvasSize in
                    guard slice.slotCount >= 2 else { return }
                    
                    // 1. Draw Background Grid & Axis Markings
                    drawGridAndAxes(context: context, plotWidth: plotWidth, plotHeight: plotHeight)
                    
                    // 2. Draw Variance Ribbon ($P_{10} \dots P_{90}$) and Median Curve ($P_{50}$)
                    drawConfidenceGeometry(context: context, plotWidth: plotWidth, plotHeight: plotHeight, originX: yAxisWidth)
                    
                    // 3. Draw Active Inspection Cursor if selected
                    if let selSlot = internalSelectedSlot, selSlot < slice.slotCount {
                        drawInspectionCursor(context: context, slot: selSlot, plotWidth: plotWidth, plotHeight: plotHeight, originX: yAxisWidth)
                    }
                }
                .drawingGroup()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleScrubTouch(at: value.location, plotWidth: plotWidth, plotHeight: plotHeight)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(height: 140)
            
            // 3. Legend Bar
            legendBar
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    // MARK: - Compact Spark-Band View
    
    private var compactView: some View {
        GeometryReader { geo in
            let size = geo.size
            let plotWidth = max(1.0, size.width)
            let plotHeight = max(1.0, size.height)
            
            Canvas(rendersAsynchronously: true) { context, _ in
                guard slice.slotCount >= 2 else { return }
                drawConfidenceGeometry(context: context, plotWidth: plotWidth, plotHeight: plotHeight, originX: 0.0, isCompact: true)
            }
            .drawingGroup()
        }
        .frame(height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    
    // MARK: - Detail Readout Bar
    
    @ViewBuilder
    private var detailReadoutBar: some View {
        if let slot = internalSelectedSlot, slot < slice.slotCount {
            let q = slice.quantiles(slot: slot)
            let variance = q.p90 - q.p10
            let minOfDay = slice.minuteForSlot(slot)
            let h24 = minOfDay / 60
            let m = minOfDay % 60
            let tier = slice.riskTier(slot: slot)
            
            HStack(spacing: 8) {
                // Clock Time Tag
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#FFB300"))
                    Text(String(format: "%02d:%02d", h24, m))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                
                // Risk Badge
                Text(tier.title)
                    .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(tier.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(tier.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                
                Spacer()
                
                // Metrics
                HStack(spacing: 6) {
                    Text(String(format: "Median: %.1fm", q.p50))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    Text(String(format: "[%.1f–%.1fm, ±%.1fm]", q.p10, q.p90, variance / 2.0))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        } else {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#FFB300"))
                    Text("P10 / P50 / P90 CONFIDENCE BAND")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("SCRUB TO INSPECT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Legend Bar
    
    private var legendBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: "#10B981"))
                    .frame(width: 6, height: 6)
                Text("Reliable (<2.5m)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: "#FFB300"))
                    .frame(width: 6, height: 6)
                Text("Moderate (2.5–6m)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: "#EF4444"))
                    .frame(width: 6, height: 6)
                Text("High Risk (>6m)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Canvas Rendering Passes
    
    private func drawGridAndAxes(context: GraphicsContext, plotWidth: CGFloat, plotHeight: CGFloat) {
        // Y-axis ticks at 0, 50%, 100% of maxY
        let ySteps = 3
        for step in 0...ySteps {
            let frac = CGFloat(step) / CGFloat(ySteps)
            let yVal = Float(1.0 - frac) * maxY
            let yPos = frac * plotHeight
            
            // Gridline
            var gridPath = Path()
            gridPath.move(to: CGPoint(x: yAxisWidth, y: yPos))
            gridPath.addLine(to: CGPoint(x: yAxisWidth + plotWidth, y: yPos))
            context.stroke(gridPath, with: .color(Color.primary.opacity(0.06)), lineWidth: 0.8)
            
            // Y-axis label
            let labelText = String(format: "%.0fm", yVal)
            let resolved = context.resolve(
                Text(labelText)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
            )
            context.draw(resolved, at: CGPoint(x: yAxisWidth - 4, y: yPos), anchor: .trailing)
        }
        
        // X-axis time marks (divide into 4 divisions)
        let xDivs = min(4, max(2, slice.slotCount / 15))
        for div in 0...xDivs {
            let frac = CGFloat(div) / CGFloat(xDivs)
            let slot = min(slice.slotCount - 1, Int(round(Double(frac) * Double(slice.slotCount - 1))))
            let minOfDay = slice.minuteForSlot(slot)
            let xPos = yAxisWidth + frac * plotWidth
            
            let timeText = String(format: "%02d:%02d", minOfDay / 60, minOfDay % 60)
            let resolved = context.resolve(
                Text(timeText)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
            )
            context.draw(resolved, at: CGPoint(x: xPos, y: plotHeight + 3), anchor: .top)
        }
    }
    
    private func drawConfidenceGeometry(
        context: GraphicsContext,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        originX: CGFloat,
        isCompact: Bool = false
    ) {
        let n = slice.slotCount
        guard n >= 2 else { return }
        
        let dx = plotWidth / CGFloat(n - 1)
        let scaleY = CGFloat(maxY)
        
        // Draw segmented column ribbons with continuous variance disutility tinting
        for i in 0..<(n - 1) {
            let x0 = originX + CGFloat(i) * dx
            let x1 = originX + CGFloat(i + 1) * dx
            
            let q0 = slice.quantiles(slot: i)
            let q1 = slice.quantiles(slot: i + 1)
            
            let y0_p90 = plotHeight * (1.0 - CGFloat(q0.p90) / scaleY)
            let y0_p10 = plotHeight * (1.0 - CGFloat(q0.p10) / scaleY)
            
            let y1_p90 = plotHeight * (1.0 - CGFloat(q1.p90) / scaleY)
            let y1_p10 = plotHeight * (1.0 - CGFloat(q1.p10) / scaleY)
            
            // Variance disutility color
            let avgVar = (q0.p90 - q0.p10 + q1.p90 - q1.p10) * 0.5
            let col = Self.colorForVariance(avgVar)
            
            var bandQuad = Path()
            bandQuad.move(to: CGPoint(x: x0, y: y0_p90))
            bandQuad.addLine(to: CGPoint(x: x1, y: y1_p90))
            bandQuad.addLine(to: CGPoint(x: x1, y: y1_p10))
            bandQuad.addLine(to: CGPoint(x: x0, y: y0_p10))
            bandQuad.closeSubpath()
            
            context.fill(bandQuad, with: .color(col.opacity(isCompact ? 0.35 : 0.28)))
        }
        
        // Draw P90 upper boundary stroke
        var p90Path = Path()
        for i in 0..<n {
            let x = originX + CGFloat(i) * dx
            let q = slice.quantiles(slot: i)
            let y = plotHeight * (1.0 - CGFloat(q.p90) / scaleY)
            if i == 0 {
                p90Path.move(to: CGPoint(x: x, y: y))
            } else {
                p90Path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(p90Path, with: .color(Color.primary.opacity(0.2)), lineWidth: 0.9)
        
        // Draw P10 lower boundary stroke
        var p10Path = Path()
        for i in 0..<n {
            let x = originX + CGFloat(i) * dx
            let q = slice.quantiles(slot: i)
            let y = plotHeight * (1.0 - CGFloat(q.p10) / scaleY)
            if i == 0 {
                p10Path.move(to: CGPoint(x: x, y: y))
            } else {
                p10Path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(p10Path, with: .color(Color.primary.opacity(0.2)), lineWidth: 0.9)
        
        // Draw P50 Median Line
        var p50Path = Path()
        for i in 0..<n {
            let x = originX + CGFloat(i) * dx
            let q = slice.quantiles(slot: i)
            let y = plotHeight * (1.0 - CGFloat(q.p50) / scaleY)
            if i == 0 {
                p50Path.move(to: CGPoint(x: x, y: y))
            } else {
                p50Path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        let medianColor = isCompact ? Color(hex: "#0F172A") : Color(hex: "#FFB300")
        context.stroke(p50Path, with: .color(medianColor), lineWidth: isCompact ? 1.5 : 2.0)
    }
    
    private func drawInspectionCursor(
        context: GraphicsContext,
        slot: Int,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        originX: CGFloat
    ) {
        let n = slice.slotCount
        guard n >= 2, slot < n else { return }
        
        let dx = plotWidth / CGFloat(n - 1)
        let scaleY = CGFloat(maxY)
        let x = originX + CGFloat(slot) * dx
        
        // Hairline cursor
        var cursorPath = Path()
        cursorPath.move(to: CGPoint(x: x, y: 0))
        cursorPath.addLine(to: CGPoint(x: x, y: plotHeight))
        context.stroke(cursorPath, with: .color(Color.primary.opacity(0.4)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
        
        // Quantile Nodes
        let q = slice.quantiles(slot: slot)
        let y_p90 = plotHeight * (1.0 - CGFloat(q.p90) / scaleY)
        let y_p50 = plotHeight * (1.0 - CGFloat(q.p50) / scaleY)
        let y_p10 = plotHeight * (1.0 - CGFloat(q.p10) / scaleY)
        
        let dotPathP90 = Path(ellipseIn: CGRect(x: x - 2.5, y: y_p90 - 2.5, width: 5, height: 5))
        let dotPathP50 = Path(ellipseIn: CGRect(x: x - 3.5, y: y_p50 - 3.5, width: 7, height: 7))
        let dotPathP10 = Path(ellipseIn: CGRect(x: x - 2.5, y: y_p10 - 2.5, width: 5, height: 5))
        
        context.fill(dotPathP90, with: .color(Color(hex: "#EF4444")))
        context.fill(dotPathP50, with: .color(Color(hex: "#FFB300")))
        context.fill(dotPathP10, with: .color(Color(hex: "#10B981")))
        
        context.stroke(dotPathP50, with: .color(.white), lineWidth: 1.5)
    }
    
    // MARK: - Touch Handling
    
    private func handleScrubTouch(at point: CGPoint, plotWidth: CGFloat, plotHeight: CGFloat) {
        let localX = point.x - yAxisWidth
        guard localX >= 0, localX <= plotWidth else { return }
        
        let progress = min(1.0, max(0.0, localX / plotWidth))
        let slot = min(slice.slotCount - 1, max(0, Int(round(Double(progress) * Double(slice.slotCount - 1)))))
        
        if internalSelectedSlot != slot {
            internalSelectedSlot = slot
            let q = slice.quantiles(slot: slot)
            let minOfDay = slice.minuteForSlot(slot)
            onSelectSlot?(slot, minOfDay, q.p10, q.p50, q.p90)
            
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }
    
    // MARK: - Procedural Color Helper
    
    public static func colorForVariance(_ variance: Float) -> Color {
        if variance < 2.5 {
            // Low variance: Emerald Green
            return Color(hex: "#10B981")
        } else if variance <= 6.0 {
            // Moderate variance: Electric Amber
            return Color(hex: "#FFB300")
        } else {
            // High variance: Coral Red
            return Color(hex: "#EF4444")
        }
    }
}
