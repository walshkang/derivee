import SwiftUI

struct DepartureMatrixView: View {
    let records: [SpatialDatabaseManager.HourScheduleRecord]
    let routeId: String
    let stopId: String
    let liveArrivals: [SpatialDatabaseManager.ArrivalInfo]
    
    @Binding var selectedDirection: Int
    @State private var isPulsing: Bool = false
    
    init(
        records: [SpatialDatabaseManager.HourScheduleRecord],
        routeId: String,
        stopId: String,
        liveArrivals: [SpatialDatabaseManager.ArrivalInfo] = [],
        selectedDirection: Binding<Int> = .constant(0)
    ) {
        self.records = records
        self.routeId = routeId
        self.stopId = stopId
        self.liveArrivals = liveArrivals
        self._selectedDirection = selectedDirection
    }
    
    private var isBus: Bool {
        stopId.hasPrefix("BUS_") || routeId.contains("-")
    }
    
    private var directionNames: [String] {
        if isBus {
            return ["Uptown / Inbound", "Downtown / Outbound"]
        }
        switch routeId.uppercased() {
        case "L":
            return ["Manhattan (8th Ave)", "Brooklyn (Canarsie)"]
        case "G":
            return ["Court Sq (Northbound)", "Church Ave (Southbound)"]
        case "7":
            return ["Flushing - Main St", "Hudson Yards"]
        case "A", "C", "E":
            return ["Uptown / 207 St", "Downtown / Brooklyn"]
        case "1", "2", "3":
            return ["Uptown / Bronx", "Downtown / Brooklyn"]
        default:
            return ["Uptown / Northbound", "Downtown / Southbound"]
        }
    }
    
    /// Reconciles static scheduled departures with active GTFS-RT arrivals
    private var reconciledRecords: [SpatialDatabaseManager.HourScheduleRecord] {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())
        let currentMinute = calendar.component(.minute, from: Date())
        
        return records.map { hourRec in
            let updatedDepartures = hourRec.departures.map { dep -> SpatialDatabaseManager.DeparturePillRecord in
                var modPill = dep
                
                // Match live arrival if in the current hour and close minute
                if hourRec.hourOfDay == currentHour {
                    if let matchedArrival = liveArrivals.first(where: { arr in
                        let arrivalMinute = (currentMinute + arr.minutes) % 60
                        return abs(arrivalMinute - dep.minute) <= 3
                    }) {
                        modPill.isLive = true
                        modPill.liveDeltaMinutes = matchedArrival.minutes
                        // If live minutes differ from schedule by >= 3 min, show delay
                        let scheduledDelta = (dep.minute >= currentMinute) ? (dep.minute - currentMinute) : (dep.minute + 60 - currentMinute)
                        if matchedArrival.minutes > scheduledDelta + 2 {
                            modPill.delaySeconds = (matchedArrival.minutes - scheduledDelta) * 60
                        }
                    }
                }
                return modPill
            }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: hourRec.hourOfDay, departures: updatedDepartures)
        }
    }
    
    private var totalDeparturesCount: Int {
        records.reduce(0) { $0 + $1.departures.count }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Direction Selector & Metric Bar
            VStack(spacing: 8) {
                Picker("Direction", selection: $selectedDirection) {
                    Text(directionNames[0]).tag(0)
                    Text(directionNames[1]).tag(1)
                }
                .pickerStyle(.segmented)
                
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Text("24-HOUR TIMETABLE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(totalDeparturesCount) DEPARTURES TODAY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
            }
            
            // Full 24-Hour Scrollable Matrix
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(reconciledRecords) { hourRec in
                            HourRowView(
                                hourRecord: hourRec,
                                routeId: routeId,
                                isPulsing: isPulsing
                            )
                            .id(hourRec.hourOfDay)
                            
                            if hourRec.hourOfDay != 23 {
                                Divider()
                                    .opacity(0.4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 380)
                .onAppear {
                    let currentHour = Calendar.current.component(.hour, from: Date())
                    // Scroll to current hour if within operating window
                    withAnimation {
                        scrollProxy.scrollTo(max(0, currentHour - 1), anchor: .top)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
            
            // Legend Footer
            LegendFooterView(routeId: routeId)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Hour Row View

private struct HourRowView: View {
    let hourRecord: SpatialDatabaseManager.HourScheduleRecord
    let routeId: String
    let isPulsing: Bool
    
    private var isCurrentHour: Bool {
        Calendar.current.component(.hour, from: Date()) == hourRecord.hourOfDay
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Hour Label
            HStack(spacing: 2) {
                Text(String(format: "%02d:00", hourRecord.hourOfDay))
                    .font(.system(size: 13, weight: isCurrentHour ? .heavy : .medium, design: .monospaced))
                    .foregroundColor(isCurrentHour ? Color(hex: "#FFB300") : .secondary)
                
                if isCurrentHour {
                    Circle()
                        .fill(Color(hex: "#FFB300"))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 54, alignment: .leading)
            .padding(.top, 4)
            
            // Dynamic Minute Pills Wrap Layout
            if hourRecord.departures.isEmpty {
                Text("No scheduled service")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 4)
            } else {
                FlowLayoutView(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(hourRecord.departures) { pill in
                        DeparturePillView(
                            pill: pill,
                            routeId: routeId,
                            isPulsing: isPulsing
                        )
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Departure Pill View

private struct DeparturePillView: View {
    let pill: SpatialDatabaseManager.DeparturePillRecord
    let routeId: String
    let isPulsing: Bool
    
    private var routeInfo: TransitRouteData.LineInfo {
        TransitRouteData.lineInfo(for: pill.routeId)
    }
    
    var body: some View {
        HStack(spacing: 3) {
            // Live Pulsing Indicator Dot
            if pill.isLive {
                Circle()
                    .fill(Color(hex: "#FFB300"))
                    .frame(width: 5, height: 5)
                    .opacity(isPulsing ? 1.0 : 0.25)
                    .shadow(color: Color(hex: "#FFB300").opacity(0.8), radius: 2)
            }
            
            // 2-Digit Monospace Minute
            Text(String(format: "%02d", pill.minute))
                .font(.system(size: 12, weight: pill.isExpress ? .heavy : .semibold, design: .monospaced))
                .foregroundColor(pill.isExpress ? Color(hex: routeInfo.textColorHex) : .primary)
            
            // Express Tag
            if pill.isExpress {
                Text("EXP")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: routeInfo.textColorHex).opacity(0.9))
            }
            
            // Live Countdown Overlay
            if let delta = pill.liveDeltaMinutes {
                Text("\(delta)m")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#FFB300"))
            }
        }
        .padding(.horizontal, pill.isExpress ? 7 : 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(pill.isExpress ? routeInfo.color : Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    pill.isFirstDeparture || pill.isLastDeparture
                        ? Color(hex: "#FFB300")
                        : (pill.isLive ? Color(hex: "#FFB300").opacity(0.5) : Color.primary.opacity(0.08)),
                    lineWidth: (pill.isFirstDeparture || pill.isLastDeparture) ? 1.5 : 1
                )
        )
        .overlay(alignment: .topTrailing) {
            // Delay Badge
            if let delay = pill.delaySeconds, delay >= 180 {
                Text("+\(delay / 60)m")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color(hex: "#FF453A"))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .offset(x: 4, y: -6)
            }
        }
    }
}

// MARK: - Legend Footer View

private struct LegendFooterView: View {
    let routeId: String
    
    var body: some View {
        HStack(spacing: 12) {
            // First / Last Marker
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color(hex: "#FFB300"), lineWidth: 1.5)
                    .frame(width: 12, height: 10)
                Text("First / Last")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Express Variant
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(TransitRouteData.lineInfo(for: routeId).color)
                    .frame(width: 12, height: 10)
                Text("Express")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Live GTFS-RT
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: "#FFB300"))
                    .frame(width: 6, height: 6)
                Text("Live Δt")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Delay Badge
            HStack(spacing: 4) {
                Text("+4m")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 3)
                    .background(Color(hex: "#FF453A"))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                Text("Delay ≥3m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.top, 2)
    }
}

// MARK: - Flow Layout Helper

struct FlowLayoutView<Content: View>: View {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayoutImplementation(horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
            content()
        }
    }
}

private struct FlowLayoutImplementation: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    let sampleDepartures = [
        SpatialDatabaseManager.DeparturePillRecord(id: "1", tripId: "T1", routeId: "L", destination: "8th Ave", minute: 4, isExpress: false, isFirstDeparture: true),
        SpatialDatabaseManager.DeparturePillRecord(id: "2", tripId: "T2", routeId: "L", destination: "8th Ave", minute: 12, isExpress: false, liveDeltaMinutes: 3, isLive: true),
        SpatialDatabaseManager.DeparturePillRecord(id: "3", tripId: "T3", routeId: "L", destination: "8th Ave", minute: 19, isExpress: true),
        SpatialDatabaseManager.DeparturePillRecord(id: "4", tripId: "T4", routeId: "L", destination: "8th Ave", minute: 26, isExpress: false, delaySeconds: 240),
        SpatialDatabaseManager.DeparturePillRecord(id: "5", tripId: "T5", routeId: "L", destination: "8th Ave", minute: 34, isExpress: false),
        SpatialDatabaseManager.DeparturePillRecord(id: "6", tripId: "T6", routeId: "L", destination: "8th Ave", minute: 42, isExpress: true),
        SpatialDatabaseManager.DeparturePillRecord(id: "7", tripId: "T7", routeId: "L", destination: "8th Ave", minute: 51, isExpress: false)
    ]
    
    let sampleHours = (0..<24).map { h in
        SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: sampleDepartures)
    }
    
    DepartureMatrixView(
        records: sampleHours,
        routeId: "L",
        stopId: "stop_bedford"
    )
    .padding()
}
