import SwiftUI

struct TransitRevealSheet: View {
    let stopId: String
    
    enum TransitTabMode: String, CaseIterable, Identifiable {
        case liveArrivals = "Live Arrivals"
        case fullTimetable = "Full Timetable"
        var id: String { rawValue }
    }
    
    struct DirectionalArrivalGroup: Identifiable {
        var id: String { directionName }
        let directionName: String
        let corridorSubtitle: String?
        let iconName: String
        let arrivals: [SpatialDatabaseManager.ArrivalInfo]
    }
    
    @State private var selectedTab: TransitTabMode = .liveArrivals
    @State private var stopDetails: SpatialDatabaseManager.StopDetails?
    @State private var headways: [Double] = []
    @State private var hourlyReliability: [SpatialDatabaseManager.HourlyReliabilityRecord] = []
    @State private var timetableSchedule: [SpatialDatabaseManager.HourScheduleRecord] = []
    @State private var selectedDirection: Int = 0
    @State private var selectedRecord: SpatialDatabaseManager.HourlyReliabilityRecord? = nil
    @State private var liveArrivals: [SpatialDatabaseManager.ArrivalInfo] = []
    @State private var serviceAlerts: [TransitAlert] = []
    @State private var showAlertsExpanded: Bool = false
    @State private var isLiveActive: Bool = false
    @State private var lastUpdated: Date? = nil
    
    init(
        stopId: String,
        initialDetails: SpatialDatabaseManager.StopDetails? = nil,
        initialLiveArrivals: [SpatialDatabaseManager.ArrivalInfo] = [],
        initialAlerts: [TransitAlert] = []
    ) {
        self.stopId = stopId
        self._stopDetails = State(initialValue: initialDetails)
        self._liveArrivals = State(initialValue: initialLiveArrivals)
        self._serviceAlerts = State(initialValue: initialAlerts)
    }
    
    var displayedArrivals: [SpatialDatabaseManager.ArrivalInfo] {
        if !liveArrivals.isEmpty {
            return liveArrivals
        }
        return stopDetails?.arrivals ?? []
    }
    
    var groupedArrivals: [DirectionalArrivalGroup] {
        let all = displayedArrivals
        guard !all.isEmpty else { return [] }
        
        var dict: [String: [SpatialDatabaseManager.ArrivalInfo]] = [:]
        var order: [String] = []
        
        for arr in all {
            let dir = arr.direction ?? "Upcoming Departures"
            if dict[dir] == nil {
                dict[dir] = []
                order.append(dir)
            }
            dict[dir]?.append(arr)
        }
        
        order.sort { d1, d2 in
            let p1 = directionPriority(for: d1)
            let p2 = directionPriority(for: d2)
            if p1 != p2 { return p1 < p2 }
            let min1 = dict[d1]?.first?.minutes ?? 999
            let min2 = dict[d2]?.first?.minutes ?? 999
            return min1 < min2
        }
        
        return order.compactMap { dir in
            guard let items = dict[dir], !items.isEmpty else { return nil }
            let sortedItems = items.sorted { $0.minutes < $1.minutes }
            let icon = directionIcon(for: dir)
            let corridor = corridorNote(for: dir, items: sortedItems)
            return DirectionalArrivalGroup(
                directionName: dir,
                corridorSubtitle: corridor,
                iconName: icon,
                arrivals: sortedItems
            )
        }
    }
    
    private func directionPriority(for dir: String) -> Int {
        let u = dir.uppercased()
        if u.contains("MANHATTAN") || u.contains("UPTOWN") || u.contains("NORTH") || u.contains("INBOUND") || u.contains("EAST") {
            return 0
        }
        if u.contains("BROOKLYN") || u.contains("DOWNTOWN") || u.contains("SOUTH") || u.contains("OUTBOUND") || u.contains("WEST") {
            return 1
        }
        if u.contains("QUEENS") { return 2 }
        if u.contains("BRONX") { return 3 }
        return 4
    }
    
    private func directionIcon(for dir: String) -> String {
        let u = dir.uppercased()
        if u.contains("NORTH") || u.contains("UPTOWN") || u.contains("INBOUND") {
            return "arrow.up.circle.fill"
        }
        if u.contains("SOUTH") || u.contains("DOWNTOWN") || u.contains("OUTBOUND") {
            return "arrow.down.circle.fill"
        }
        if u.contains("EAST") {
            return "arrow.right.circle.fill"
        }
        if u.contains("WEST") {
            return "arrow.left.circle.fill"
        }
        if u.contains("MANHATTAN") {
            return "arrow.up.right.circle.fill"
        }
        if u.contains("BROOKLYN") {
            return "arrow.down.right.circle.fill"
        }
        if u.contains("QUEENS") {
            return "arrow.up.left.circle.fill"
        }
        return "arrow.triangle.swap"
    }
    
    private func corridorNote(for dir: String, items: [SpatialDatabaseManager.ArrivalInfo]) -> String? {
        let dests = Set(items.map { $0.destination })
        if dests.count == 1, let single = dests.first {
            return "to \(single)"
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned Header: Line Badge + Station Name + Tab Picker
            if let details = stopDetails {
                let routeInfo = TransitRouteData.lineInfo(for: details.routeId)
                let isBus = details.routeType == 3
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        if isBus {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(hex: "#00A1DE"))
                                .frame(width: 42, height: 38)
                                .overlay(
                                    Image(systemName: "bus.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        } else {
                            Circle()
                                .fill(routeInfo.color)
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Text(routeInfo.name)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(hex: routeInfo.textColorHex))
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(details.name)
                                .font(.title2)
                                .bold()
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            
                            Text(isBus ? "MTA Bus Stop" : "MTA Subway Station")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 14)
                    
                    // Active Service Alerts Banner
                    if !serviceAlerts.isEmpty {
                        ForEach(serviceAlerts) { alert in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAlertsExpanded.toggle()
                                }
                            } label: {
                                HStack(alignment: .center, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(hex: "#FF9500"))
                                    
                                    Text(alert.headerText)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(showAlertsExpanded ? nil : 1)
                                        .multilineTextAlignment(.leading)
                                    
                                    Spacer()
                                    
                                    Image(systemName: showAlertsExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(hex: "#FF9500").opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Segmented Tab Picker: [ Live Arrivals | Full Timetable ]
                    Picker("Transit Surface", selection: $selectedTab) {
                        ForEach(TransitTabMode.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Divider()
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                
                // Scrollable Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if selectedTab == .liveArrivals {
                            // Real-time Arrivals Organized by Direction
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("UPCOMING DEPARTURES")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    if isLiveActive {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color(hex: "#FFB300"))
                                                .frame(width: 6, height: 6)
                                            Text("LIVE")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundColor(Color(hex: "#FFB300"))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: "#FFB300").opacity(0.12))
                                        .clipShape(Capsule())
                                    }
                                }
                                
                                if groupedArrivals.isEmpty {
                                    Text("No scheduled arrivals in the next 30 minutes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 6)
                                } else {
                                    ForEach(groupedArrivals) { group in
                                        VStack(alignment: .leading, spacing: 6) {
                                            // Direction Section Header
                                            HStack(alignment: .center, spacing: 6) {
                                                Image(systemName: group.iconName)
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(Color(hex: "#FFB300"))
                                                
                                                Text(group.directionName.uppercased())
                                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.primary)
                                                
                                                if let corridor = group.corridorSubtitle {
                                                    Text("• \(corridor)")
                                                        .font(.system(size: 10, weight: .regular))
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                }
                                                
                                                Spacer()
                                                
                                                if let nextMin = group.arrivals.first?.minutes {
                                                    HStack(spacing: 2) {
                                                        Text("Next")
                                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                            .foregroundColor(.secondary)
                                                        Text("\(nextMin)m")
                                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                            .foregroundColor(Color(hex: "#FFB300"))
                                                    }
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color(hex: "#FFB300").opacity(0.1))
                                                    .clipShape(Capsule())
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(Color.primary.opacity(0.04))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            
                                            // Arrival Rows within Direction
                                            VStack(spacing: 2) {
                                                ForEach(group.arrivals) { arrival in
                                                    HStack(alignment: .center, spacing: 10) {
                                                        let arrivalInfo = TransitRouteData.lineInfo(for: arrival.line)
                                                        
                                                        if arrival.line.hasPrefix("M") || arrival.line.hasPrefix("B") || arrival.line.hasPrefix("Q") || arrival.line.hasPrefix("Bx") || arrival.line.hasPrefix("S") {
                                                            Text(arrival.line)
                                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                                .padding(.horizontal, 6)
                                                                .padding(.vertical, 3)
                                                                .background(Color(hex: "#00A1DE").opacity(0.15))
                                                                .foregroundColor(Color(hex: "#00A1DE"))
                                                                .clipShape(Capsule())
                                                        } else {
                                                            Circle()
                                                                .fill(arrivalInfo.color)
                                                                .frame(width: 22, height: 22)
                                                                .overlay(
                                                                    Text(arrivalInfo.name)
                                                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                                                        .foregroundColor(Color(hex: arrivalInfo.textColorHex))
                                                                )
                                                        }
                                                        
                                                        VStack(alignment: .leading, spacing: 1) {
                                                            HStack(spacing: 4) {
                                                                Text(arrival.destination)
                                                                    .font(.subheadline)
                                                                    .fontWeight(.medium)
                                                                    .foregroundColor(.primary)
                                                                    .lineLimit(1)
                                                                
                                                                if arrival.destination.contains("Short Turn") || arrival.destination.contains("Local") {
                                                                    Text("ALERT")
                                                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                                        .padding(.horizontal, 3)
                                                                        .padding(.vertical, 1)
                                                                        .background(Color(hex: "#FF9500"))
                                                                        .foregroundColor(.white)
                                                                        .clipShape(Capsule())
                                                                }
                                                            }
                                                            
                                                            if let dist = arrival.distanceDescription {
                                                                Text(dist)
                                                                    .font(.caption2)
                                                                    .foregroundColor(.secondary)
                                                            }
                                                        }
                                                        
                                                        Spacer()
                                                        
                                                        HStack(spacing: 3) {
                                                            Text("\(arrival.minutes)")
                                                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                                                .foregroundColor(.primary)
                                                            Text("min")
                                                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                                                .foregroundColor(.secondary)
                                                        }
                                                    }
                                                    .padding(.vertical, 3)
                                                    .padding(.horizontal, 4)
                                                }
                                            }
                                        }
                                        .padding(.bottom, 4)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // 24x7 Immediate-Mode Reliability Heatmap Matrix
                            ReliabilityHeatmapCanvas(records: hourlyReliability) { record in
                                self.selectedRecord = record
                            }
                        } else {
                            // Full 24-Hour Departure Timetable Matrix
                            DepartureMatrixView(
                                records: timetableSchedule,
                                routeId: details.routeId,
                                stopId: stopId,
                                liveArrivals: liveArrivals,
                                selectedDirection: $selectedDirection
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .sheet(item: $selectedRecord) { rec in
            TransitMatrixInspectorView(record: rec)
                .presentationDetents([.fraction(0.5), .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: stopId) {
            await startPollingLifecycle()
        }
        .onChange(of: selectedDirection) { _, newDir in
            Task {
                if let details = stopDetails {
                    let timetable = try? await SpatialDatabaseManager.shared.fetchTimetable(for: stopId, routeId: details.routeId, directionId: newDir)
                    if let timetable = timetable {
                        await MainActor.run {
                            self.timetableSchedule = timetable
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    private func startPollingLifecycle() async {
        // 1. Initial base load from local SQLite
        let details = try? await SpatialDatabaseManager.shared.fetchStopDetails(for: stopId)
        let hw = try? await SpatialDatabaseManager.shared.fetchHeadwayData(for: stopId)
        let rel = try? await SpatialDatabaseManager.shared.fetchHourlyReliability(for: stopId, routeId: details?.routeId)
        let timetable = try? await SpatialDatabaseManager.shared.fetchTimetable(for: stopId, routeId: details?.routeId, directionId: selectedDirection)
        
        self.stopDetails = details
        if let hw = hw {
            self.headways = hw
        }
        if let rel = rel {
            self.hourlyReliability = rel
        }
        if let timetable = timetable {
            self.timetableSchedule = timetable
        }
        
        guard let routeId = details?.routeId else { return }
        
        // Load initial service alerts
        let alerts = await TransitRealtimeService.shared.fetchServiceAlerts(for: routeId)
        self.serviceAlerts = alerts
        
        // 2. Sheet-Scoped Polling Loop (15s cadence, cancelled on dismiss)
        while !Task.isCancelled {
            do {
                let live = try await TransitRealtimeService.shared.fetchLiveArrivals(for: stopId, routeId: routeId)
                if !Task.isCancelled {
                    if !live.isEmpty {
                        self.liveArrivals = live
                    }
                    self.isLiveActive = true
                    self.lastUpdated = Date()
                }
            } catch {
                if !Task.isCancelled {
                    self.isLiveActive = false
                }
            }
            
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } catch {
                break
            }
        }
    }
}

#Preview {
    TransitRevealSheet(stopId: "stop_columbus")
}

