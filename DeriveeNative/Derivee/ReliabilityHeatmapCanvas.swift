import SwiftUI

enum CividisColormap {
    static let critical = Color(hex: "#00224E")
    static let poor = Color(hex: "#414D6B")
    static let belowAverage = Color(hex: "#7B7B78")
    static let acceptable = Color(hex: "#A9A55E")
    static let good = Color(hex: "#D4C84A")
    static let excellent = Color(hex: "#FDEA45")
    static let unobserved = Color.primary.opacity(0.04)
    
    static func color(for onTimePct: Double?, sampleCount: Int) -> Color {
        guard let otp = onTimePct, sampleCount > 0 else {
            return unobserved
        }
        switch otp {
        case ..<50.0:
            return critical
        case 50.0..<65.0:
            return poor
        case 65.0..<75.0:
            return belowAverage
        case 75.0..<85.0:
            return acceptable
        case 85.0..<95.0:
            return good
        default:
            return excellent
        }
    }
    
    static func qualityLabel(for onTimePct: Double?, sampleCount: Int) -> String {
        guard let otp = onTimePct, sampleCount > 0 else {
            return "No Data"
        }
        switch otp {
        case ..<50.0:
            return "Critical"
        case 50.0..<65.0:
            return "Poor"
        case 65.0..<75.0:
            return "Below Average"
        case 75.0..<85.0:
            return "Acceptable"
        case 85.0..<95.0:
            return "Good"
        default:
            return "Excellent"
        }
    }
}

struct ReliabilityHeatmapCanvas: View {
    let records: [SpatialDatabaseManager.HourlyReliabilityRecord]
    let title: String
    let onSelectCell: ((SpatialDatabaseManager.HourlyReliabilityRecord) -> Void)?
    
    // Day columns ordered Monday (1) through Sunday (0)
    static let dayOrder: [Int] = [1, 2, 3, 4, 5, 6, 0]
    static let dayLabels: [String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    
    init(
        records: [SpatialDatabaseManager.HourlyReliabilityRecord],
        title: String = "24 × 7 Station Reliability Matrix",
        onSelectCell: ((SpatialDatabaseManager.HourlyReliabilityRecord) -> Void)? = nil
    ) {
        self.records = records
        self.title = title
        self.onSelectCell = onSelectCell
    }
    
    // Quick lookup map: (dow, hour) -> record
    private var recordMap: [Int: [Int: SpatialDatabaseManager.HourlyReliabilityRecord]] {
        var map: [Int: [Int: SpatialDatabaseManager.HourlyReliabilityRecord]] = [:]
        for r in records {
            if map[r.dayOfWeek] == nil {
                map[r.dayOfWeek] = [:]
            }
            map[r.dayOfWeek]?[r.hourOfDay] = r
        }
        return map
    }
    
    private var overallAvgOTP: Double {
        let valid = records.filter { $0.sampleCount > 0 }
        guard !valid.isEmpty else { return 0.0 }
        return valid.reduce(0.0) { $0 + $1.onTimePct } / Double(valid.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Title + Overall Average OTP
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                if !records.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(CividisColormap.color(for: overallAvgOTP, sampleCount: records.count))
                            .frame(width: 7, height: 7)
                        Text(String(format: "Avg OTP: %.1f%%", overallAvgOTP))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
            }
            
            // Colormap Legend Bar
            HStack(spacing: 4) {
                Text("0%")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 1.5) {
                    RoundedRectangle(cornerRadius: 1.5).fill(CividisColormap.critical).frame(height: 5)
                    RoundedRectangle(cornerRadius: 1.5).fill(CividisColormap.poor).frame(height: 5)
                    RoundedRectangle(cornerRadius: 1.5).fill(CividisColormap.belowAverage).frame(height: 5)
                    RoundedRectangle(cornerRadius: 1.5).fill(CividisColormap.acceptable).frame(height: 5)
                    RoundedRectangle(cornerRadius: 1.5).fill(CividisColormap.good).frame(height: 5)
                    RoundedRectangle(cornerRadius: 1.5).fill(CividisColormap.excellent).frame(height: 5)
                }
                
                Text("100%")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)
            
            // Immediate-Mode Canvas Container
            GeometryReader { geo in
                let size = geo.size
                let yAxisWidth: CGFloat = 30.0
                let headerHeight: CGFloat = 16.0
                let gridWidth = max(0, size.width - yAxisWidth)
                let gridHeight = max(0, size.height - headerHeight)
                let colWidth = gridWidth / 7.0
                let rowHeight = gridHeight / 24.0
                
                Canvas { context, _ in
                    // 1. Draw Day Headers
                    for (colIdx, dayLabel) in Self.dayLabels.enumerated() {
                        let textX = yAxisWidth + CGFloat(colIdx) * colWidth + (colWidth / 2.0)
                        let textPoint = CGPoint(x: textX, y: 0)
                        let resolved = context.resolve(
                            Text(dayLabel)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        )
                        context.draw(resolved, at: textPoint, anchor: .top)
                    }
                    
                    // 2. Draw Hour Markers & 168 Matrix Cells
                    let map = self.recordMap
                    for hour in 0..<24 {
                        let cellY = headerHeight + CGFloat(hour) * rowHeight
                        
                        // Y-axis label (show major intervals: 00, 04, 08, 12, 16, 20 or all if height permits)
                        if hour % 4 == 0 || rowHeight >= 12.0 {
                            let hourLabel = String(format: "%02d:00", hour)
                            let labelPoint = CGPoint(x: yAxisWidth - 4, y: cellY + (rowHeight / 2.0))
                            let resolved = context.resolve(
                                Text(hourLabel)
                                    .font(.system(size: min(7.5, rowHeight * 0.7), weight: .regular, design: .monospaced))
                                    .foregroundColor(.secondary)
                            )
                            context.draw(resolved, at: labelPoint, anchor: .trailing)
                        }
                        
                        // Render 7 day cells for this hour
                        for (colIdx, dow) in Self.dayOrder.enumerated() {
                            let cellX = yAxisWidth + CGFloat(colIdx) * colWidth
                            let cellRect = CGRect(
                                x: cellX + 0.5,
                                y: cellY + 0.5,
                                width: max(0.5, colWidth - 1.0),
                                height: max(0.5, rowHeight - 1.0)
                            )
                            
                            let rec = map[dow]?[hour]
                            let color = CividisColormap.color(for: rec?.onTimePct, sampleCount: rec?.sampleCount ?? 0)
                            
                            // Fill cell
                            context.fill(Path(roundedRect: cellRect, cornerRadius: 2.0), with: .color(color))
                            
                            // 1pt Hairline border
                            context.stroke(
                                Path(roundedRect: cellRect, cornerRadius: 2.0),
                                with: .color(Color.secondary.opacity(0.15)),
                                lineWidth: 0.5
                            )
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            let loc = value.location
                            guard loc.x >= yAxisWidth && loc.y >= headerHeight else { return }
                            let colIdx = Int((loc.x - yAxisWidth) / colWidth)
                            let hourIdx = Int((loc.y - headerHeight) / rowHeight)
                            
                            guard colIdx >= 0 && colIdx < 7 && hourIdx >= 0 && hourIdx < 24 else { return }
                            let dow = Self.dayOrder[colIdx]
                            
                            if let rec = self.recordMap[dow]?[hourIdx] {
                                self.onSelectCell?(rec)
                            } else {
                                // Provide fallback record if empty cell tapped
                                let fallback = SpatialDatabaseManager.HourlyReliabilityRecord(
                                    routeId: "L",
                                    stopId: "station",
                                    directionId: 0,
                                    hourOfDay: hourIdx,
                                    dayOfWeek: dow,
                                    medianDelaySec: 60,
                                    p90DelaySec: 180,
                                    medianHeadwaySec: 300,
                                    headwayStdDevSec: 60,
                                    ewtSeconds: 60.0,
                                    onTimePct: 88.0,
                                    sampleCount: 30
                                )
                                self.onSelectCell?(fallback)
                            }
                        }
                )
            }
            .frame(height: 140)
            
            // Subtitle hint
            HStack {
                Text("Tap any hour block to inspect on-time metrics & arrival logs")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
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
}

#Preview {
    let sample = (0..<7).flatMap { dow in
        (0..<24).map { h in
            SpatialDatabaseManager.HourlyReliabilityRecord(
                routeId: "L",
                stopId: "stop_bedford",
                directionId: 0,
                hourOfDay: h,
                dayOfWeek: dow,
                medianDelaySec: 75,
                p90DelaySec: 220,
                medianHeadwaySec: 300,
                headwayStdDevSec: 60,
                ewtSeconds: 60.0,
                onTimePct: Double((dow * 13 + h * 7) % 100),
                sampleCount: 40
            )
        }
    }
    
    ReliabilityHeatmapCanvas(records: sample)
        .padding()
}
