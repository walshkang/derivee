import SwiftUI

struct DepartureMatrixView: View {
    let records: [SpatialDatabaseManager.HourScheduleRecord]
    let routeId: String
    let routeIds: [String]
    let stopId: String
    let liveArrivals: [SpatialDatabaseManager.ArrivalInfo]
    let availableDirections: Set<Int>
    let referenceDate: Date?
    
    @Binding var selectedDirection: Int
    @State private var selectedRouteFilter: String = "ALL"
    @State private var isPulsing: Bool = false
    
    init(
        records: [SpatialDatabaseManager.HourScheduleRecord],
        routeId: String,
        routeIds: [String] = [],
        stopId: String,
        liveArrivals: [SpatialDatabaseManager.ArrivalInfo] = [],
        availableDirections: Set<Int> = [0, 1],
        selectedDirection: Binding<Int> = .constant(0),
        referenceDate: Date? = nil
    ) {
        self.records = records
        self.routeId = routeId
        self.routeIds = routeIds.isEmpty ? [routeId] : routeIds
        self.stopId = stopId
        self.liveArrivals = liveArrivals
        let effectiveDirs = availableDirections.isEmpty ? Set([0, 1]) : availableDirections
        self.availableDirections = effectiveDirs
        self.referenceDate = referenceDate
        self._selectedDirection = selectedDirection
        
        if !effectiveDirs.contains(selectedDirection.wrappedValue), let firstAvailable = effectiveDirs.sorted().first {
            DispatchQueue.main.async {
                selectedDirection.wrappedValue = firstAvailable
            }
        }
    }
    
    private var isBus: Bool {
        stopId.hasPrefix("BUS_") || TransitRouteData.isBusRoute(routeId)
    }
    
    private var baseDirectionNames: [String] {
        if isBus {
            return ["Northbound / Inbound", "Southbound / Outbound"]
        }
        switch routeId.uppercased() {
        case "L":
            return ["Manhattan (8th Ave)", "Brooklyn (Canarsie)"]
        case "G":
            return ["Queens (Court Sq)", "Brooklyn (Church Ave)"]
        case "7", "7X":
            return ["Queens (Flushing)", "Manhattan (Hudson Yards)"]
        case "1", "2", "3":
            return ["Uptown & Bronx", "Downtown & Brooklyn"]
        case "4", "5", "6", "6X":
            return ["Uptown & Bronx", "Downtown & Brooklyn"]
        case "A", "C", "E":
            return ["Uptown & Queens / Bronx", "Downtown & Brooklyn"]
        case "B", "D", "F", "FX", "M":
            return ["Uptown & Queens / Bronx", "Downtown & Brooklyn"]
        case "N", "Q", "R", "W":
            return ["Uptown & Queens", "Downtown & Brooklyn"]
        case "J", "Z":
            return ["Queens (Jamaica)", "Manhattan (Broad St)"]
        case "SIR":
            return ["Inbound (St. George)", "Outbound (Tottenville)"]
        default:
            return ["Uptown / Northbound", "Downtown / Southbound"]
        }
    }
    
    private func directionLabel(for dir: Int) -> String {
        let baseName = (dir >= 0 && dir < baseDirectionNames.count) ? baseDirectionNames[dir] : "Direction \(dir)"
        if !availableDirections.contains(dir) {
            return "\(baseName) (No Service)"
        }
        return baseName
    }
    
    private func autoSelectValidDirectionIfNeeded() {
        if !availableDirections.contains(selectedDirection), let firstAvailable = availableDirections.sorted().first {
            selectedDirection = firstAvailable
        }
    }
    
    private var filteredRecords: [SpatialDatabaseManager.HourScheduleRecord] {
        if selectedRouteFilter == "ALL" {
            return records
        }
        return records.map { hourRec in
            let filteredDeps = hourRec.departures.filter { dep in
                dep.routeId.uppercased() == selectedRouteFilter.uppercased()
            }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: hourRec.hourOfDay, departures: filteredDeps)
        }
    }
    
    // MARK: - Circular Math Helpers
    
    private func signedMinuteDiff(from tSched: Int, to tEst: Int) -> Int {
        var diff = (tEst - tSched) % 1440
        if diff > 720 {
            diff -= 1440
        } else if diff < -720 {
            diff += 1440
        }
        return diff
    }
    
    private func circularMinuteDiff(_ t1: Int, _ t2: Int) -> Int {
        return abs(signedMinuteDiff(from: t1, to: t2))
    }
    
    /// Reconciles static scheduled departures with active GTFS-RT arrivals at a given reference timestamp
    func reconciledRecords(at currentDate: Date) -> [SpatialDatabaseManager.HourScheduleRecord] {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: currentDate)
        let currentMinute = calendar.component(.minute, from: currentDate)
        let nowMinutes = currentHour * 60 + currentMinute
        
        let filteredLiveArrivals = (selectedRouteFilter == "ALL")
            ? liveArrivals
            : liveArrivals.filter { $0.line.uppercased() == selectedRouteFilter.uppercased() }
        
        var matchedArrivalIds = Set<UUID>()
        var pillMatchMap: [String: SpatialDatabaseManager.ArrivalInfo] = [:]
        
        // Flatten all scheduled pills for matching
        let allPills = filteredRecords.flatMap { hourRec in
            hourRec.departures.map { (hour: hourRec.hourOfDay, pill: $0) }
        }
        
        // Tier 1: Match by exact Trip ID if available
        for (h, pill) in allPills {
            if !pill.tripId.isEmpty {
                if let match = filteredLiveArrivals.first(where: { arr in
                    !matchedArrivalIds.contains(arr.id) && arr.tripId == pill.tripId
                }) {
                    pillMatchMap[pill.id] = match
                    matchedArrivalIds.insert(match.id)
                }
            }
        }
        
        // Tier 2: Match by route and circular minute proximity / delay window
        for arr in filteredLiveArrivals {
            guard !matchedArrivalIds.contains(arr.id) else { continue }
            let arrHour = calendar.component(.hour, from: arr.arrivalDate)
            let arrMin = calendar.component(.minute, from: arr.arrivalDate)
            let tEst = arrHour * 60 + arrMin
            
            var bestPillId: String? = nil
            var smallestDiff = 9999
            
            for (h, pill) in allPills {
                guard pillMatchMap[pill.id] == nil else { continue }
                let sameRoute = (pill.routeId.uppercased() == arr.line.uppercased())
                guard sameRoute else { continue }
                
                let tSched = h * 60 + pill.minute
                let delay = signedMinuteDiff(from: tSched, to: tEst)
                
                // Allow matches from 5 min early to 25 min delayed, or circular diff within 10 min
                if (delay >= -5 && delay <= 25) || circularMinuteDiff(tSched, tEst) <= 10 {
                    let absDiff = abs(delay)
                    if absDiff < smallestDiff {
                        smallestDiff = absDiff
                        bestPillId = pill.id
                    }
                }
            }
            
            if let bestId = bestPillId {
                pillMatchMap[bestId] = arr
                matchedArrivalIds.insert(arr.id)
            }
        }
        
        // Build updated HourScheduleRecords
        var resultMap: [Int: [SpatialDatabaseManager.DeparturePillRecord]] = [:]
        for h in 0..<24 {
            resultMap[h] = []
        }
        
        for hourRec in filteredRecords {
            let h = hourRec.hourOfDay
            for dep in hourRec.departures {
                var modPill = dep
                let tSched = h * 60 + dep.minute
                
                if let matchedArrival = pillMatchMap[dep.id] {
                    let arrHour = calendar.component(.hour, from: matchedArrival.arrivalDate)
                    let arrMin = calendar.component(.minute, from: matchedArrival.arrivalDate)
                    let tEst = arrHour * 60 + arrMin
                    
                    modPill.isLive = true
                    modPill.liveDeltaMinutes = matchedArrival.minutes
                    modPill.isBoarding = (matchedArrival.minutes == 0)
                    
                    let delayMin = signedMinuteDiff(from: tSched, to: tEst)
                    if delayMin >= 3 {
                        modPill.delaySeconds = delayMin * 60
                    }
                    
                    // Delay-aware liveness: remains active if arrival time is in future or within 30s boarding grace
                    let isExpired = matchedArrival.arrivalDate.timeIntervalSince(currentDate) < -30.0
                    modPill.isPast = isExpired
                } else {
                    // Check if scheduled time passed in current operating day
                    let pastDiff = signedMinuteDiff(from: tSched, to: nowMinutes)
                    modPill.isPast = (pastDiff > 0)
                }
                
                resultMap[h]?.append(modPill)
            }
        }
        
        // Tier 3: Inject unmatched ad-hoc GTFS-RT arrivals into target hour row
        for arr in filteredLiveArrivals {
            guard !matchedArrivalIds.contains(arr.id) else { continue }
            let arrHour = calendar.component(.hour, from: arr.arrivalDate)
            let arrMin = calendar.component(.minute, from: arr.arrivalDate)
            
            let adHocPill = SpatialDatabaseManager.DeparturePillRecord(
                id: "adhoc_\(arr.id.uuidString)",
                tripId: arr.tripId ?? "adhoc_\(arr.line)_\(arrHour)_\(arrMin)",
                routeId: arr.line,
                destination: arr.destination,
                minute: arrMin,
                isExpress: false,
                isFirstDeparture: false,
                isLastDeparture: false,
                liveDeltaMinutes: arr.minutes,
                delaySeconds: nil,
                isLive: true,
                isPast: false,
                isUnscheduled: true,
                isBoarding: (arr.minutes == 0)
            )
            
            resultMap[arrHour % 24]?.append(adHocPill)
        }
        
        // Return sorted 24-hour records
        return (0..<24).map { h in
            let sortedDeps = (resultMap[h] ?? []).sorted { p1, p2 in
                if p1.minute != p2.minute {
                    return p1.minute < p2.minute
                }
                return p1.id < p2.id
            }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: sortedDeps)
        }
    }
    
    private var totalDeparturesCount: Int {
        filteredRecords.reduce(0) { $0 + $1.departures.count }
    }
    
    var body: some View {
        if let fixedDate = referenceDate {
            matrixContent(for: fixedDate)
        } else {
            TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                matrixContent(for: timeline.date)
            }
        }
    }
    
    @ViewBuilder
    private func matrixContent(for currentDate: Date) -> some View {
        let reconciled = reconciledRecords(at: currentDate)
        let currentHour = Calendar.current.component(.hour, from: currentDate)
        
        VStack(alignment: .leading, spacing: 14) {
            // Direction Selector, Route Filter & Metric Bar
            VStack(spacing: 8) {
                // Direction Selector Segmented Control
                HStack(spacing: 0) {
                    ForEach([0, 1], id: \.self) { dir in
                        let isAvailable = availableDirections.contains(dir)
                        let isSelected = selectedDirection == dir
                        let label = directionLabel(for: dir)
                        
                        Button {
                            if isAvailable {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedDirection = dir
                                }
                            }
                        } label: {
                            Text(label)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(isSelected ? Color(uiColor: .systemBackground) : Color.clear)
                                        .shadow(color: isSelected ? Color.black.opacity(0.12) : Color.clear, radius: 2, y: 1)
                                )
                                .foregroundColor(isSelected ? .primary : (isAvailable ? .secondary : .secondary.opacity(0.6)))
                                .opacity(isAvailable ? 1.0 : 0.35)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isAvailable)
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .secondarySystemFill))
                )
                
                // Horizontal Route Filter Strip (for co-located / multi-route lines)
                if routeIds.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedRouteFilter = "ALL"
                                }
                            } label: {
                                Text("All Routes")
                                    .font(.system(size: 11, weight: selectedRouteFilter == "ALL" ? .bold : .medium, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(selectedRouteFilter == "ALL" ? Color(hex: "#FFB300").opacity(0.18) : Color.primary.opacity(0.05))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(selectedRouteFilter == "ALL" ? Color(hex: "#FFB300") : Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                                    .foregroundColor(selectedRouteFilter == "ALL" ? Color(hex: "#FFB300") : .secondary)
                            }
                            .buttonStyle(.plain)
                            
                            ForEach(routeIds, id: \.self) { rId in
                                let rInfo = TransitRouteData.lineInfo(for: rId)
                                let isSelected = selectedRouteFilter.uppercased() == rId.uppercased()
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedRouteFilter = rId
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(rInfo.color)
                                            .frame(width: 14, height: 14)
                                            .overlay(
                                                Text(rInfo.name)
                                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                                    .foregroundColor(Color(hex: rInfo.textColorHex))
                                            )
                                        
                                        Text(rInfo.name)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? rInfo.color.opacity(0.18) : Color.primary.opacity(0.05))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? rInfo.color : Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                
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
                        ForEach(reconciled) { hourRec in
                            HourRowView(
                                hourRecord: hourRec,
                                routeId: routeId,
                                isPulsing: isPulsing,
                                currentHour: currentHour
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
            autoSelectValidDirectionIfNeeded()
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onChange(of: availableDirections) { _, _ in
            autoSelectValidDirectionIfNeeded()
        }
    }
}

// MARK: - Hour Row View

private struct HourRowView: View {
    let hourRecord: SpatialDatabaseManager.HourScheduleRecord
    let routeId: String
    let isPulsing: Bool
    let currentHour: Int
    
    private var isCurrentHour: Bool {
        currentHour == hourRecord.hourOfDay
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
                .foregroundColor(pill.isPast ? .secondary : (pill.isExpress ? Color(hex: routeInfo.textColorHex) : .primary))
            
            // Express Tag
            if pill.isExpress {
                Text("EXP")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: routeInfo.textColorHex).opacity(pill.isPast ? 0.5 : 0.9))
            }
            
            // Live Countdown Overlay
            if let delta = pill.liveDeltaMinutes {
                Text(delta == 0 ? "0m" : "\(delta)m")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#FFB300"))
            }
        }
        .padding(.horizontal, pill.isExpress ? 7 : 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(pill.isExpress ? (pill.isPast ? routeInfo.color.opacity(0.4) : routeInfo.color) : Color.primary.opacity(pill.isPast ? 0.03 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    pill.isFirstDeparture || pill.isLastDeparture
                        ? Color(hex: "#FFB300").opacity(pill.isPast ? 0.35 : 1.0)
                        : (pill.isLive ? Color(hex: "#FFB300").opacity(pill.isPast ? 0.3 : 0.6) : (pill.isUnscheduled ? Color(hex: "#FFB300").opacity(0.4) : Color.primary.opacity(pill.isPast ? 0.04 : 0.08))),
                    lineWidth: (pill.isFirstDeparture || pill.isLastDeparture) ? 1.5 : 1
                )
        )
        .opacity(pill.isPast ? 0.35 : 1.0)
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
