import SwiftUI

struct DepartureMatrixView: View {
    let records: [SpatialDatabaseManager.HourScheduleRecord]
    let routeId: String
    let routeIds: [String]
    let stopId: String
    let liveArrivals: [SpatialDatabaseManager.ArrivalInfo]
    let availableDirections: Set<Int>
    let referenceDate: Date?
    let isHistoricalFallback: Bool
    let isObservedReplay: Bool
    let scheduleValidity: ScheduleValidity?
    
    @Binding var selectedDirection: Int
    @Binding var selectedDayOffset: Int
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
        selectedDayOffset: Binding<Int> = .constant(0),
        isHistoricalFallback: Bool = false,
        isObservedReplay: Bool = false,
        scheduleValidity: ScheduleValidity? = nil,
        referenceDate: Date? = nil
    ) {
        self.records = records
        self.routeId = routeId
        self.routeIds = routeIds.isEmpty ? [routeId] : routeIds
        self.stopId = stopId
        self.liveArrivals = liveArrivals
        let effectiveDirs = availableDirections.isEmpty ? Set([0, 1]) : availableDirections
        self.availableDirections = effectiveDirs
        self.isHistoricalFallback = isHistoricalFallback
        self.isObservedReplay = isObservedReplay
        self.scheduleValidity = scheduleValidity
        self.referenceDate = referenceDate
        self._selectedDirection = selectedDirection
        self._selectedDayOffset = selectedDayOffset
        
        if !effectiveDirs.contains(selectedDirection.wrappedValue), let firstAvailable = effectiveDirs.sorted().first {
            DispatchQueue.main.async {
                selectedDirection.wrappedValue = firstAvailable
            }
        }
    }
    
    private var isBus: Bool {
        stopId.hasPrefix("BUS_") || TransitRouteData.isBusRoute(routeId)
    }
    
    private var matchToleranceMinutes: Int {
        isBus ? 15 : 10
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
        // If not today (e.g. historical day or future day), return static/observed records directly
        if selectedDayOffset != 0 {
            return filteredRecords
        }
        
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
        for (_, pill) in allPills {
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
                
                // Allow matches from 5 min early to 25 min delayed, or circular diff within mode-adaptive tolerance
                if (delay >= -5 && delay <= 25) || circularMinuteDiff(tSched, tEst) <= matchToleranceMinutes {
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
                    
                    if matchedArrival.scheduleRelationship == .canceled {
                        modPill.scheduleRelationship = .canceled
                        modPill.isPast = false
                    } else {
                        modPill.scheduleRelationship = matchedArrival.scheduleRelationship
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
                    }
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
            
            let isUnscheduled = (arr.scheduleRelationship != .added)
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
                isUnscheduled: isUnscheduled,
                isBoarding: (arr.minutes == 0),
                scheduleRelationship: arr.scheduleRelationship
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
            // Day Scrubber (±7 Day Navigation)
            DayScrubberView(
                selectedDayOffset: $selectedDayOffset,
                referenceDate: referenceDate ?? currentDate
            )
            
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
                                        TransitRouteBadge(routeId: rId, lineInfo: rInfo, size: .filter, isSelected: isSelected)
                                        
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
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                }
                
                // Status Header or Fallback Banner
                if selectedDayOffset < 0 && isHistoricalFallback {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#FFB300"))
                        Text("Scheduled Timetable • Real-time history recording launches in Phase 2")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.04))
                    )
                } else if selectedDayOffset < 0 && isObservedReplay {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: "#34C759"))
                            .frame(width: 6, height: 6)
                        Text("Observed Reality Replay • \(totalDeparturesCount) recorded departures")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "#34C759").opacity(0.12))
                    )
                } else {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(selectedDayOffset == 0 ? "24-HOUR TIMETABLE" : "SCHEDULED TIMETABLE")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(totalDeparturesCount) DEPARTURES")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())
                    }
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
                                currentHour: selectedDayOffset == 0 ? currentHour : -1
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
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 380)
                .onAppear {
                    // Scroll to current hour if today
                    if selectedDayOffset == 0 {
                        withAnimation {
                            scrollProxy.scrollTo(max(0, currentHour - 1), anchor: .top)
                        }
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
            
            // Schedule Validity Footer (for future days)
            if selectedDayOffset > 0, let validity = scheduleValidity {
                let validityText: String = {
                    if let label = validity.seasonLabel, !label.isEmpty {
                        return label
                    } else if let start = validity.startDate, let end = validity.endDate {
                        return "\(start) – \(end)"
                    }
                    return ""
                }()
                if !validityText.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("Valid: \(validityText)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
            }
            
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

// MARK: - Day Scrubber View

private struct DayScrubberView: View {
    @Binding var selectedDayOffset: Int
    let referenceDate: Date
    
    private let calendar = Calendar.current
    
    private func date(for offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: referenceDate) ?? referenceDate
    }
    
    private func dayTitle(for offset: Int) -> String {
        if offset == 0 { return "Today" }
        if offset == -1 { return "Yesterday" }
        if offset == 1 { return "Tomorrow" }
        let d = date(for: offset)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter.string(from: d)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(-7...7, id: \.self) { offset in
                        let isSelected = selectedDayOffset == offset
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedDayOffset = offset
                            }
                        } label: {
                            Text(dayTitle(for: offset))
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color(hex: "#FFB300") : Color.primary.opacity(0.05))
                                )
                                .foregroundColor(isSelected ? .black : (offset == 0 ? Color(hex: "#FFB300") : .secondary))
                                .shadow(color: isSelected ? Color(hex: "#FFB300").opacity(0.3) : Color.clear, radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .id(offset)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onAppear {
                proxy.scrollTo(selectedDayOffset, anchor: .center)
            }
            .onChange(of: selectedDayOffset) { _, newOffset in
                withAnimation {
                    proxy.scrollTo(newOffset, anchor: .center)
                }
            }
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
    
    private var isCanceled: Bool {
        pill.scheduleRelationship == .canceled
    }
    
    private var isAdded: Bool {
        pill.scheduleRelationship == .added
    }
    
    private var isUnscheduled: Bool {
        pill.scheduleRelationship == .unscheduled || pill.isUnscheduled
    }
    
    private var isDuplicated: Bool {
        pill.scheduleRelationship == .duplicated
    }
    
    private var effectiveOpacity: Double {
        if isCanceled {
            return 0.4
        }
        return pill.isPast ? 0.35 : 1.0
    }
    
    private var strokeColor: Color {
        if isCanceled {
            return Color(hex: "#FF453A").opacity(0.4)
        }
        if pill.isHistoricalEvent {
            let delay = pill.historicalDelaySeconds ?? 0
            if delay <= 120 {
                return Color(hex: "#34C759").opacity(0.8)
            } else if delay <= 300 {
                return Color(hex: "#FFB300").opacity(0.8)
            } else {
                return Color(hex: "#FF453A").opacity(0.8)
            }
        }
        if pill.isFirstDeparture || pill.isLastDeparture {
            return Color(hex: "#FFB300").opacity(pill.isPast ? 0.35 : 1.0)
        }
        if pill.isLive || isAdded {
            return Color(hex: "#FFB300").opacity(pill.isPast ? 0.3 : 0.8)
        }
        if isUnscheduled {
            return Color(hex: "#FFB300").opacity(0.5)
        }
        return Color.primary.opacity(pill.isPast ? 0.04 : 0.08)
    }
    
    var body: some View {
        HStack(spacing: 3) {
            // Live Pulsing Indicator Dot
            if pill.isLive || isAdded || isUnscheduled {
                Circle()
                    .fill(isCanceled ? Color(hex: "#FF453A") : Color(hex: "#FFB300"))
                    .frame(width: 5, height: 5)
                    .opacity(isPulsing ? 1.0 : 0.25)
                    .shadow(color: Color(hex: "#FFB300").opacity(0.8), radius: 2)
            }
            
            // Historical Status Dot
            if pill.isHistoricalEvent {
                let delay = pill.historicalDelaySeconds ?? 0
                Circle()
                    .fill(delay <= 120 ? Color(hex: "#34C759") : (delay <= 300 ? Color(hex: "#FFB300") : Color(hex: "#FF453A")))
                    .frame(width: 5, height: 5)
            }
            
            // 2-Digit Monospace Minute
            Text(String(format: "%02d", pill.minute))
                .font(.system(size: 12, weight: isAdded ? .bold : (pill.isExpress ? .heavy : .semibold), design: .monospaced))
                .italic(isUnscheduled)
                .strikethrough(isCanceled, color: Color(hex: "#FF453A"))
                .foregroundColor(
                    isCanceled ? Color(hex: "#FF453A") :
                    (pill.isPast ? .secondary : (pill.isExpress ? Color(hex: routeInfo.textColorHex) : .primary))
                )
            
            // Express Tag
            if pill.isExpress && !isCanceled {
                Text("EXP")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: routeInfo.textColorHex).opacity(pill.isPast ? 0.5 : 0.9))
            }
            
            // Live Countdown Overlay
            if let delta = pill.liveDeltaMinutes, !isCanceled {
                Text(delta == 0 ? "0m" : "\(delta)m")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#FFB300"))
            }
        }
        .padding(.horizontal, pill.isExpress ? 7 : 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isCanceled ? Color(hex: "#FF453A").opacity(0.08) :
                    (pill.isExpress ? (pill.isPast ? routeInfo.color.opacity(0.4) : routeInfo.color) : Color.primary.opacity(pill.isPast ? 0.03 : 0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(strokeColor, lineWidth: (pill.isFirstDeparture || pill.isLastDeparture || pill.isHistoricalEvent) ? 1.5 : 1)
        )
        .opacity(effectiveOpacity)
        .overlay(alignment: .topTrailing) {
            if isCanceled {
                Text("CANCELED")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color(hex: "#FF453A"))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .offset(x: 6, y: -6)
            } else if isAdded {
                Text("ADDED")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color(hex: "#FFB300"))
                    .foregroundColor(.black)
                    .clipShape(Capsule())
                    .offset(x: 4, y: -6)
            } else if isUnscheduled {
                Text("LIVE")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color(hex: "#007AFF"))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .offset(x: 4, y: -6)
            } else if isDuplicated {
                Text("DUPLICATE")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.secondary)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .offset(x: 6, y: -6)
            } else if let delay = pill.delaySeconds, delay >= 180 {
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // First / Last Marker
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(hex: "#FFB300"), lineWidth: 1.5)
                        .frame(width: 12, height: 10)
                    Text("First/Last")
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
                
                // Canceled
                HStack(spacing: 4) {
                    Text("CANCELED")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color(hex: "#FF453A"))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    Text("Canceled")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 2)
        }
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
        SpatialDatabaseManager.DeparturePillRecord(id: "5", tripId: "T5", routeId: "L", destination: "8th Ave", minute: 34, isExpress: false, scheduleRelationship: .canceled),
        SpatialDatabaseManager.DeparturePillRecord(id: "6", tripId: "T6", routeId: "L", destination: "8th Ave", minute: 42, isExpress: true, scheduleRelationship: .added),
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
