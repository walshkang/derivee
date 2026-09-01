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
    static let fullDayNames: [Int: String] = [
        1: "Monday", 2: "Tuesday", 3: "Wednesday", 4: "Thursday", 5: "Friday", 6: "Saturday", 0: "Sunday"
    ]
    static let shortDayNames: [Int: String] = [
        1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 0: "Sun"
    ]
    
    @State private var selectedDay: Int
    @State private var selectedHour: Int
    
    init(
        records: [SpatialDatabaseManager.HourlyReliabilityRecord],
        title: String = "24 × 7 Station Reliability Matrix",
        initialDay: Int? = nil,
        initialHour: Int? = nil,
        onSelectCell: ((SpatialDatabaseManager.HourlyReliabilityRecord) -> Void)? = nil
    ) {
        self.records = records
        self.title = title
        self.onSelectCell = onSelectCell
        
        let currentWeekday = Calendar.current.component(.weekday, from: Date())
        let defaultDay = (currentWeekday - 1) % 7
        let defaultHour = Calendar.current.component(.hour, from: Date())
        
        self._selectedDay = State(initialValue: initialDay ?? defaultDay)
        self._selectedHour = State(initialValue: initialHour ?? defaultHour)
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
    
    static func hourRangeString(for hour: Int) -> String {
        String(format: "%02d:00 – %02d:00", hour, (hour + 1) % 24)
    }
    
    func recordFor(dayOfWeek dow: Int, hourOfDay hour: Int) -> SpatialDatabaseManager.HourlyReliabilityRecord {
        if let rec = recordMap[dow]?[hour] {
            return rec
        }
        let rId = records.first?.routeId ?? "L"
        let sId = records.first?.stopId ?? "station"
        let dir = records.first?.directionId ?? 0
        return SpatialDatabaseManager.HourlyReliabilityRecord(
            routeId: rId,
            stopId: sId,
            directionId: dir,
            hourOfDay: hour,
            dayOfWeek: dow,
            medianDelaySec: 60,
            p90DelaySec: 180,
            medianHeadwaySec: 300,
            headwayStdDevSec: 60,
            ewtSeconds: 60.0,
            onTimePct: 0.0,
            sampleCount: 0
        )
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
                    
                    // 3. Draw Crosshair Guide Lines & Highlighted Active Cell
                    if let colIdx = Self.dayOrder.firstIndex(of: selectedDay), selectedHour >= 0, selectedHour < 24 {
                        let activeCellX = yAxisWidth + CGFloat(colIdx) * colWidth
                        let activeCellY = headerHeight + CGFloat(selectedHour) * rowHeight
                        let activeRect = CGRect(
                            x: activeCellX + 0.5,
                            y: activeCellY + 0.5,
                            width: max(0.5, colWidth - 1.0),
                            height: max(0.5, rowHeight - 1.0)
                        )
                        
                        // Vertical Column Crosshair Guide
                        var vGuide = Path()
                        vGuide.move(to: CGPoint(x: activeCellX + colWidth / 2.0, y: headerHeight))
                        vGuide.addLine(to: CGPoint(x: activeCellX + colWidth / 2.0, y: headerHeight + gridHeight))
                        context.stroke(vGuide, with: .color(Color(hex: "#FFB300").opacity(0.3)), lineWidth: 1.0)
                        
                        // Horizontal Row Crosshair Guide
                        var hGuide = Path()
                        hGuide.move(to: CGPoint(x: yAxisWidth, y: activeCellY + rowHeight / 2.0))
                        hGuide.addLine(to: CGPoint(x: yAxisWidth + gridWidth, y: activeCellY + rowHeight / 2.0))
                        context.stroke(hGuide, with: .color(Color(hex: "#FFB300").opacity(0.3)), lineWidth: 1.0)
                        
                        // Highlight Active Cell Outline
                        let highlightBorder = Path(roundedRect: activeRect.insetBy(dx: -0.5, dy: -0.5), cornerRadius: 2.0)
                        context.stroke(
                            highlightBorder,
                            with: .color(Color(hex: "#FFB300")),
                            lineWidth: 1.5
                        )
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
                            
                            self.selectedDay = dow
                            self.selectedHour = hourIdx
                            
                            let rec = self.recordFor(dayOfWeek: dow, hourOfDay: hourIdx)
                            self.onSelectCell?(rec)
                        }
                )
            }
            .frame(height: 140)
            
            // Dual-Input Inspector Controls: Day & Hour Menus + Inspect Button
            HStack(spacing: 8) {
                // Day Selector Menu
                Menu {
                    ForEach(Self.dayOrder, id: \.self) { dow in
                        Button {
                            self.selectedDay = dow
                            let rec = self.recordFor(dayOfWeek: dow, hourOfDay: self.selectedHour)
                            self.onSelectCell?(rec)
                        } label: {
                            HStack {
                                Text(Self.fullDayNames[dow] ?? "Day \(dow)")
                                if dow == selectedDay {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(Color(hex: "#FFB300"))
                        Text(Self.shortDayNames[selectedDay] ?? "Day")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: 32)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                
                // Hour Selector Menu
                Menu {
                    ForEach(0..<24, id: \.self) { h in
                        Button {
                            self.selectedHour = h
                            let rec = self.recordFor(dayOfWeek: self.selectedDay, hourOfDay: h)
                            self.onSelectCell?(rec)
                        } label: {
                            HStack {
                                Text(Self.hourRangeString(for: h))
                                if h == selectedHour {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(Color(hex: "#FFB300"))
                        Text(Self.hourRangeString(for: selectedHour))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: 32)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Inspect Button
                Button {
                    let rec = self.recordFor(dayOfWeek: self.selectedDay, hourOfDay: self.selectedHour)
                    self.onSelectCell?(rec)
                } label: {
                    HStack(spacing: 4) {
                        Text("Inspect")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#FFB300"))
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "#FFB300"))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(minHeight: 32)
                    .background(Color(hex: "#FFB300").opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            
            // Subtitle hint
            HStack {
                Text("Select Day & Hour above or tap matrix to inspect metrics")
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
    ReliabilityHeatmapCanvas(
        records: (0..<7).flatMap { dow in
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
        },
        initialDay: 3,
        initialHour: 8
    )
    .padding()
}
