import SwiftUI

/// 120Hz Immediate-Mode Departure Matrix Canvas rendering a 24-hour by 60-minute (1,440-minute)
/// departure density grid and statistical percentile wait bands ($P_{10}$, $P_{50}$, $P_{90}$).
///
/// Backed by Metal hardware rasterization via `Canvas(rendersAsynchronously: true)` and `.drawingGroup()`.
public struct DepartureMatrixCanvas: View {
    public let buffer: DepartureMatrixBuffer
    public let maxWaitThreshold: Float
    public let onSelectSlot: ((_ hour: Int, _ minute: Int, _ p10: Float, _ p50: Float, _ p90: Float) -> Void)?
    
    @State private var internalSelectedSlot: Int? = nil
    @State private var isDragging: Bool = false
    
    // Pre-allocated static unit square geometry to eliminate heap allocations inside render loop
    private static let unitSquarePath = Path(CGRect(x: 0, y: 0, width: 1.0, height: 1.0))
    
    private let yAxisWidth: CGFloat = 32.0
    private let xAxisHeight: CGFloat = 16.0
    
    public init(
        buffer: DepartureMatrixBuffer,
        maxWaitThreshold: Float = 15.0,
        initialSelectedSlot: Int? = nil,
        onSelectSlot: ((_ hour: Int, _ minute: Int, _ p10: Float, _ p50: Float, _ p90: Float) -> Void)? = nil
    ) {
        self.buffer = buffer
        self.maxWaitThreshold = max(1.0, maxWaitThreshold)
        self._internalSelectedSlot = State(initialValue: initialSelectedSlot)
        self.onSelectSlot = onSelectSlot
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Selected Slot Detail Readout Capsule
            detailReadoutBar
            
            // Immediate-Mode Canvas Viewport
            GeometryReader { geo in
                let size = geo.size
                let gridWidth = max(1.0, size.width - yAxisWidth)
                let gridHeight = max(1.0, size.height - xAxisHeight)
                let cellWidth = gridWidth / 60.0
                let cellHeight = gridHeight / 24.0
                
                Canvas(rendersAsynchronously: true) { context, _ in
                    guard buffer.values.count == DepartureMatrixBuffer.totalElements else { return }
                    
                    // 1. Draw X-axis Minute Labels (00, 15, 30, 45)
                    let minuteMarks = [0, 15, 30, 45]
                    for minMark in minuteMarks {
                        let textX = yAxisWidth + CGFloat(minMark) * cellWidth
                        let textPoint = CGPoint(x: textX, y: 0)
                        let resolved = context.resolve(
                            Text(String(format: "%02d", minMark))
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        )
                        context.draw(resolved, at: textPoint, anchor: .topLeading)
                    }
                    
                    // 2. Draw 24x60 Matrix via Direct Buffer Pointer Traversal
                    buffer.values.withUnsafeBufferPointer { ptr in
                        guard let base = ptr.baseAddress else { return }
                        
                        var currentContext = context
                        let selectedIdx = internalSelectedSlot
                        
                        for h in 0..<24 {
                            let rowY = xAxisHeight + CGFloat(h) * cellHeight
                            
                            // Y-axis label every 4 hours (00, 04, 08, 12, 16, 20)
                            if h % 4 == 0 || cellHeight >= 12.0 {
                                let hourText = String(format: "%02d:00", h)
                                let labelPoint = CGPoint(x: yAxisWidth - 4, y: rowY + (cellHeight / 2.0))
                                let resolved = context.resolve(
                                    Text(hourText)
                                        .font(.system(size: min(7.5, cellHeight * 0.7), weight: .regular, design: .monospaced))
                                        .foregroundColor(.secondary)
                                )
                                context.draw(resolved, at: labelPoint, anchor: .trailing)
                            }
                            
                            for m in 0..<60 {
                                let slotIdx = (h * 60 + m)
                                let baseIdx = slotIdx * 3
                                
                                let p10 = base[baseIdx + DepartureMatrixBuffer.p10Channel]
                                let p50 = base[baseIdx + DepartureMatrixBuffer.p50Channel]
                                let p90 = base[baseIdx + DepartureMatrixBuffer.p90Channel]
                                
                                let colX = yAxisWidth + CGFloat(m) * cellWidth
                                
                                // Procedural Color Calculation:
                                // Variance disutility (P90 - P10) controls red channel intensity;
                                // Median wait (P50) controls brightness/opacity.
                                let variance = max(0.0, p90 - p10)
                                let normVar = min(1.0, Double(variance / maxWaitThreshold))
                                let normWait = min(1.0, Double(p50 / maxWaitThreshold))
                                
                                let cellColor = Self.colorForQuantiles(normWait: normWait, normVar: normVar)
                                
                                // Apply Context Matrix Transform (Zero Heap Allocation)
                                currentContext.transform = CGAffineTransform(
                                    a: cellWidth - 0.5, b: 0,
                                    c: 0, d: cellHeight - 0.5,
                                    tx: colX + 0.25, ty: rowY + 0.25
                                )
                                currentContext.fill(Self.unitSquarePath, with: .color(cellColor))
                                
                                // Active Selected Cell Highlight
                                if selectedIdx == slotIdx {
                                    currentContext.stroke(
                                        Self.unitSquarePath,
                                        with: .color(.white),
                                        lineWidth: 1.5 / max(0.01, min(cellWidth, cellHeight))
                                    )
                                }
                            }
                        }
                    }
                }
                .drawingGroup()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleTouch(at: value.location, in: size)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(height: 220)
            
            // Legend Bar
            legendBar
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    // MARK: - Detail Readout Bar
    
    @ViewBuilder
    private var detailReadoutBar: some View {
        if let slot = internalSelectedSlot {
            let h = slot / 60
            let m = slot % 60
            let q = buffer.quantiles(hour: h, minute: m)
            let variance = q.p90 - q.p10
            
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#FFB300"))
                    Text(String(format: "%02d:%02d", h, m))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text(String(format: "Median Wait: %.1fm", q.p50))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    Text(String(format: "(%.1f–%.1fm, ±%.1f)", q.p10, q.p90, variance))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )
        } else {
            HStack {
                Text("24×60 DEPARTURE WAIT & VARIANCE MATRIX")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("SCRUB TO INSPECT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Legend Bar
    
    private var legendBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#34C759"))
                    .frame(width: 8, height: 8)
                Text("Low Variance (<2m)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#FFB300"))
                    .frame(width: 8, height: 8)
                Text("Moderate (2–6m)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#FF3B30"))
                    .frame(width: 8, height: 8)
                Text("High (>6m)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Touch Interaction
    
    private func handleTouch(at point: CGPoint, in size: CGSize) {
        let gridWidth = max(1.0, size.width - yAxisWidth)
        let gridHeight = max(1.0, size.height - xAxisHeight)
        
        let localX = point.x - yAxisWidth
        let localY = point.y - xAxisHeight
        
        guard localX >= 0, localX < gridWidth, localY >= 0, localY < gridHeight else { return }
        
        let cellWidth = gridWidth / 60.0
        let cellHeight = gridHeight / 24.0
        
        let col = min(59, max(0, Int(localX / cellWidth)))
        let row = min(23, max(0, Int(localY / cellHeight)))
        
        let slot = row * 60 + col
        if internalSelectedSlot != slot {
            internalSelectedSlot = slot
            let q = buffer.quantiles(hour: row, minute: col)
            onSelectSlot?(row, col, q.p10, q.p50, q.p90)
            
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }
    
    // MARK: - Color Interpolation Helper
    
    public static func colorForQuantiles(normWait: Double, normVar: Double) -> Color {
        // Cividis-inspired CVD-safe gradient + variance disutility warning mix
        // Low variance: Emerald (#34C759) to Amber (#FFB300)
        // High variance: Red (#FF3B30)
        
        let r: Double
        let g: Double
        let b: Double
        
        if normVar < 0.35 {
            // Low variance: Green -> Amber
            let t = normVar / 0.35
            r = 0.20 + 0.80 * t
            g = 0.78 + 0.10 * t
            b = 0.35 * (1.0 - t)
        } else if normVar < 0.70 {
            // Moderate variance: Amber -> Coral
            let t = (normVar - 0.35) / 0.35
            r = 1.0
            g = 0.70 * (1.0 - t) + 0.40 * t
            b = 0.05
        } else {
            // High variance: Coral -> Deep Red
            let t = (normVar - 0.70) / 0.30
            r = 1.0 * (1.0 - 0.15 * t)
            g = 0.23 * (1.0 - t)
            b = 0.19 * (1.0 - t)
        }
        
        let opacity = 0.35 + 0.60 * (1.0 - normWait * 0.5)
        return Color(red: r, green: g, blue: b, opacity: opacity)
    }
}
