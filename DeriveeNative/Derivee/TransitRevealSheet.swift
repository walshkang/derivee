import SwiftUI
import CoreLocation

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
    @State private var availableDirections: Set<Int> = [0, 1]
    @State private var selectedDirection: Int = 0
    @State private var selectedDayOffset: Int = 0
    @State private var isHistoricalFallback: Bool = false
    @State private var isObservedReplay: Bool = false
    @State private var isScheduleAvailable: Bool = true
    @State private var selectedRecord: SpatialDatabaseManager.HourlyReliabilityRecord? = nil
    @State private var liveArrivals: [SpatialDatabaseManager.ArrivalInfo] = []
    @State private var serviceAlerts: [TransitAlert] = []
    @State private var showAlertsExpanded: Bool = false
    @State private var isLiveActive: Bool = false
    @State private var lastUpdated: Date? = nil
    @State private var isLivePulsing: Bool = false
    @State private var isRefreshing: Bool = false
    let referenceDate: Date?
    var onFocusMap: ((CLLocationCoordinate2D) -> Void)? = nil
    var onInspectRoute: ((RouteInspectionCommand) -> Void)? = nil
    var onClearRouteInspection: (() -> Void)? = nil
    var onDetentChange: ((PresentationDetent) -> Void)? = nil
    var onVehicleFrame: ((CLLocationCoordinate2D, Double) -> Void)? = nil
    @State private var pollProgress: Double = 0.0
    @State private var pollGeneration: Int = 0
    // Wave PD.2: 3-Detent Persistent Dock Peek Detent (~90pt)
    public static let inspectionPeekDetent: PresentationDetent = .fraction(0.12)
    
    private var externalDetent: Binding<PresentationDetent>?
    @State private var internalDetent: PresentationDetent
    
    internal var selectedDetent: PresentationDetent {
        get { externalDetent?.wrappedValue ?? internalDetent }
        nonmutating set {
            if let ext = externalDetent {
                ext.wrappedValue = newValue
            } else {
                internalDetent = newValue
            }
        }
    }
    
    private var selectedDetentBinding: Binding<PresentationDetent> {
        Binding(
            get: { self.selectedDetent },
            set: { newValue in
                if self.inspectingArrival != nil && newValue != .medium && newValue != .large && newValue != Self.inspectionPeekDetent {
                    self.selectedDetent = Self.inspectionPeekDetent
                } else {
                    self.selectedDetent = newValue
                }
            }
        )
    }
    
    @State private var inspectingArrival: SpatialDatabaseManager.ArrivalInfo? = nil
    @State private var reliabilityTiers: [String: LineReliabilityTier] = [:]
    @State private var availableFloors: [StationFloor] = []
    @State private var selectedFloor: StationFloor? = nil
    var onSelectFloor: ((StationFloor) -> Void)? = nil
    @State internal var selectedBusRouteFilter: String? = nil
    
    var isBusStop: Bool {
        stopDetails?.modalClass == .bus || stopId.hasPrefix("BUS_") || (stopDetails?.routeType == 3)
    }
    
    init(
        stopId: String,
        initialDetails: SpatialDatabaseManager.StopDetails? = nil,
        initialLiveArrivals: [SpatialDatabaseManager.ArrivalInfo] = [],
        initialAlerts: [TransitAlert] = [],
        initialAvailableDirections: Set<Int> = [0, 1],
        initialReliabilityTiers: [String: LineReliabilityTier] = [:],
        initialAvailableFloors: [StationFloor] = [],
        initialSelectedFloor: StationFloor? = nil,
        initialInspectingArrival: SpatialDatabaseManager.ArrivalInfo? = nil,
        initialDetent: PresentationDetent = .medium,
        selectedDetent: Binding<PresentationDetent>? = nil,
        initialBusRouteFilter: String? = nil,
        referenceDate: Date? = nil,
        onFocusMap: ((CLLocationCoordinate2D) -> Void)? = nil,
        onInspectRoute: ((RouteInspectionCommand) -> Void)? = nil,
        onClearRouteInspection: (() -> Void)? = nil,
        onSelectFloor: ((StationFloor) -> Void)? = nil,
        onDetentChange: ((PresentationDetent) -> Void)? = nil,
        onVehicleFrame: ((CLLocationCoordinate2D, Double) -> Void)? = nil
    ) {
        self.stopId = stopId
        self._stopDetails = State(initialValue: initialDetails)
        self._liveArrivals = State(initialValue: initialLiveArrivals)
        self._serviceAlerts = State(initialValue: initialAlerts)
        self._availableDirections = State(initialValue: initialAvailableDirections)
        self._reliabilityTiers = State(initialValue: initialReliabilityTiers)
        self._availableFloors = State(initialValue: initialAvailableFloors)
        self._selectedFloor = State(initialValue: initialSelectedFloor)
        self._inspectingArrival = State(initialValue: initialInspectingArrival)
        self.externalDetent = selectedDetent
        self._internalDetent = State(initialValue: selectedDetent?.wrappedValue ?? initialDetent)
        self._selectedBusRouteFilter = State(initialValue: initialBusRouteFilter)
        self._isLiveActive = State(initialValue: !initialLiveArrivals.isEmpty)
        self.referenceDate = referenceDate
        self.onFocusMap = onFocusMap
        self.onInspectRoute = onInspectRoute
        self.onClearRouteInspection = onClearRouteInspection
        self.onSelectFloor = onSelectFloor
        self.onDetentChange = onDetentChange
        self.onVehicleFrame = onVehicleFrame
    }
    
    var displayedArrivals: [SpatialDatabaseManager.ArrivalInfo] {
        if !liveArrivals.isEmpty {
            return liveArrivals
        }
        return stopDetails?.arrivals ?? []
    }
    
    func filteredBusArrivals(for routeFilter: String?) -> [SpatialDatabaseManager.ArrivalInfo] {
        let all = displayedArrivals
        let filtered: [SpatialDatabaseManager.ArrivalInfo] = {
            if let filter = routeFilter, filter != "ALL" {
                return all.filter { $0.line.uppercased() == filter.uppercased() }
            }
            return all
        }()
        return filtered.sorted {
            if $0.minutes != $1.minutes {
                return $0.minutes < $1.minutes
            }
            return $0.arrivalDate < $1.arrivalDate
        }
    }
    
    var unifiedBusArrivals: [SpatialDatabaseManager.ArrivalInfo] {
        filteredBusArrivals(for: selectedBusRouteFilter)
    }
    
    var groupedArrivals: [DirectionalArrivalGroup] {
        // When viewing a bus stop, eliminate subway-style bi-directional grouping
        guard !isBusStop else { return [] }
        let all = displayedArrivals
        guard !all.isEmpty else { return [] }
        
        var vectorDict: [SpatialDatabaseManager.TransitCorridorVector: [SpatialDatabaseManager.ArrivalInfo]] = [:]
        var vectorOrder: [SpatialDatabaseManager.TransitCorridorVector] = []
        
        for arr in all {
            let vector = arr.resolvedCorridorVector
            if vectorDict[vector] == nil {
                vectorDict[vector] = []
                vectorOrder.append(vector)
            }
            vectorDict[vector]?.append(arr)
        }
        
        vectorOrder.sort { v1, v2 in
            let p1 = v1.priority
            let p2 = v2.priority
            if p1 != p2 { return p1 < p2 }
            let min1 = vectorDict[v1]?.first?.minutes ?? 999
            let min2 = vectorDict[v2]?.first?.minutes ?? 999
            return min1 < min2
        }
        
        return vectorOrder.compactMap { vector in
            guard let items = vectorDict[vector], !items.isEmpty else { return nil }
            let sortedItems = items.sorted { $0.minutes < $1.minutes }
            let header = Self.resolveClusterHeader(for: vector, arrivals: sortedItems)
            let icon = vector.iconName
            let corridor = corridorNote(for: header, items: sortedItems)
            return DirectionalArrivalGroup(
                directionName: header,
                corridorSubtitle: corridor,
                iconName: icon,
                arrivals: sortedItems
            )
        }
    }
    
    internal static func resolveClusterHeader(
        for vector: SpatialDatabaseManager.TransitCorridorVector,
        arrivals: [SpatialDatabaseManager.ArrivalInfo]
    ) -> String {
        guard !arrivals.isEmpty else { return vector.rawValue }
        
        let directions = Set(arrivals.compactMap { $0.direction })
        
        // If single unique direction string across all arrivals in this vector cluster, preserve it
        if directions.count == 1, let single = directions.first {
            return single
        }
        
        // Multi-line / complex station clustering logic
        switch vector {
        case .northbound:
            let upperDirs = directions.map { $0.uppercased() }
            let hasQueens = upperDirs.contains(where: { $0.contains("QUEENS") })
            let hasBronx = upperDirs.contains(where: { $0.contains("BRONX") })
            let hasUptown = upperDirs.contains(where: { $0.contains("UPTOWN") })
            
            if hasQueens && hasBronx {
                return "Uptown & Queens / The Bronx"
            }
            if hasBronx {
                return "Uptown & Bronx"
            }
            if hasQueens {
                return hasUptown ? "Uptown & Queens" : "Queens-bound"
            }
            if hasUptown {
                return "Uptown & Northbound"
            }
            return "Northbound"
            
        case .southbound:
            let upperDirs = directions.map { $0.uppercased() }
            let hasBrooklyn = upperDirs.contains(where: { $0.contains("BROOKLYN") })
            let hasLowerManhattan = upperDirs.contains(where: { $0.contains("LOWER MANHATTAN") || $0.contains("WHITEHALL") || $0.contains("SOUTH FERRY") })
            let hasDowntown = upperDirs.contains(where: { $0.contains("DOWNTOWN") })
            
            if hasBrooklyn && hasLowerManhattan {
                return "Downtown & Brooklyn / Lower Manhattan"
            }
            if hasLowerManhattan {
                return "Downtown & Lower Manhattan"
            }
            if hasBrooklyn {
                return "Downtown & Brooklyn"
            }
            if hasDowntown {
                return "Downtown & Southbound"
            }
            return "Southbound"
            
        case .inbound:
            let lines = Set(arrivals.map { $0.line.uppercased() })
            if lines == ["SIR"] || lines == ["SI"] {
                return "Inbound (St George)"
            }
            return "Inbound"
            
        case .outbound:
            let lines = Set(arrivals.map { $0.line.uppercased() })
            if lines == ["SIR"] || lines == ["SI"] {
                return "Outbound (Tottenville)"
            }
            return "Outbound"
            
        case .eastbound:
            let lines = Set(arrivals.map { $0.line.uppercased() })
            if lines.contains("L") {
                return "Brooklyn-bound"
            }
            if lines.contains("7") || lines.contains("7X") {
                return "Queens-bound"
            }
            return "Eastbound"
            
        case .westbound:
            let lines = Set(arrivals.map { $0.line.uppercased() })
            if lines.contains("L") || lines.contains("7") || lines.contains("7X") {
                return "Manhattan-bound"
            }
            return "Westbound"
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
    
    internal static func computeCorridorNote(for dir: String, items: [SpatialDatabaseManager.ArrivalInfo]) -> String? {
        let dests = Set(items.map { $0.destination.trimmingCharacters(in: .whitespacesAndNewlines) })
        if dests.count == 1, let single = dests.first {
            let cleanDir = dir.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let cleanSingle = single.lowercased()
            // Suppress if direction header already contains the destination (e.g. "TO ST GEORGE FERRY")
            if cleanDir.contains(cleanSingle) || cleanDir == "to \(cleanSingle)" {
                return nil
            }
            // Suppress when the section note duplicates the arrival row destination verbatim
            return nil
        }
        return nil
    }
    
    private func corridorNote(for dir: String, items: [SpatialDatabaseManager.ArrivalInfo]) -> String? {
        Self.computeCorridorNote(for: dir, items: items)
    }
    
    private func stationSubtitle(for details: SpatialDatabaseManager.StopDetails) -> String {
        let modes = Set(details.routeIds.map { TransitRouteData.lineInfo(for: $0).modalClass })
        if modes.contains(.subway) && modes.contains(.lightRail) {
            return "Subway & Light Rail Station"
        }
        if modes.contains(.ferry) {
            return "Maritime Ferry Terminal"
        }
        if modes.contains(.lightRail) {
            return "Light Rail Station"
        }
        if details.routeType == 3 || (modes.contains(.bus) && modes.count == 1) {
            return "MTA Bus Stop"
        }
        if modes.contains(.subway) || details.routeType == 1 {
            return "MTA Subway Station"
        }
        return "Transit Station"
    }
    
    var body: some View {
        Group {
            if let arr = inspectingArrival {
                ZStack(alignment: .top) {
                    inspectorView(for: arr)
                        .opacity(selectedDetent == Self.inspectionPeekDetent ? 0 : 1)
                        .allowsHitTesting(selectedDetent != Self.inspectionPeekDetent)
                        .accessibilityHidden(selectedDetent == Self.inspectionPeekDetent)
                    
                    if selectedDetent == Self.inspectionPeekDetent {
                        compactInspectionDockPill(for: arr)
                            .transition(.opacity)
                            .zIndex(1)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing)
                ))
            } else {
                stationOverview
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .animation(.snappy(duration: 0.28, extraBounce: 0.0), value: inspectingArrival?.id)
        .presentationDetents(
            inspectingArrival != nil ? [Self.inspectionPeekDetent, .medium, .large] : [.medium, .large],
            selection: selectedDetentBinding
        )
        .presentationBackgroundInteraction(
            inspectingArrival != nil ? .enabled(upThrough: Self.inspectionPeekDetent) : .disabled
        )
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .transitSheetGlassBackground()
        .sheet(item: $selectedRecord) { rec in
            TransitMatrixInspectorView(record: rec)
                .presentationDetents([.fraction(0.5), .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .transitSheetGlassBackground()
        }
        .onAppear {
            onDetentChange?(selectedDetent)
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isLivePulsing = true
            }
        }
        .onChange(of: selectedDetent) { _, newDetent in
            if inspectingArrival != nil && newDetent != .medium && newDetent != .large && newDetent != Self.inspectionPeekDetent {
                selectedDetent = Self.inspectionPeekDetent
            }
            onDetentChange?(selectedDetent)
        }
        .task(id: stopId) {
            await startPollingLifecycle()
        }
        .onChange(of: stopId) { _, _ in
            inspectingArrival = nil
            selectedDetent = .medium
            onClearRouteInspection?()
        }
        .onChange(of: inspectingArrival?.id) { _, newId in
            if newId == nil && selectedDetent == Self.inspectionPeekDetent {
                selectedDetent = .medium
            }
        }
        .onChange(of: selectedDirection) { _, newDir in
            Task {
                await reloadTimetable(direction: newDir, dayOffset: selectedDayOffset)
            }
        }
        .onChange(of: selectedDayOffset) { _, newOffset in
            Task {
                await reloadTimetable(direction: selectedDirection, dayOffset: newOffset)
            }
        }
    }
    
    // MARK: - Station Overview
    
    @ViewBuilder
    private var stationOverview: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned Header: Line Badge + Station Name + Tab Picker
            if let details = stopDetails {
                let routeInfo = TransitRouteData.lineInfo(for: details.routeId)
                let isBus = details.routeType == 3
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        if details.routeIds.count > 1 {
                            if details.modalClass == .bus {
                                HStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(hex: "#00A1DE"))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: "bus.fill")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                    
                                    ForEach(details.routeIds, id: \.self) { rId in
                                        TransitRouteBadge(routeId: rId, size: .regular)
                                    }
                                }
                            } else {
                                HStack(spacing: 4) {
                                    ForEach(details.routeIds, id: \.self) { rId in
                                        let lineInfo = TransitRouteData.lineInfo(for: rId)
                                        TransitRouteBadge(routeId: rId, lineInfo: lineInfo, size: details.routeIds.count > 4 ? .compact : .regular)
                                    }
                                }
                            }
                        } else {
                            TransitRouteBadge(routeId: details.routeId, lineInfo: routeInfo, size: .large)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(details.name)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            
                            Text(stationSubtitle(for: details))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                    
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
                                .padding(.vertical, 4)
                                .background(Color(hex: "#FF9500").opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Wave Q.4: Interactive 2D Multi-Level Floorplan Stepper Pill
                    if availableFloors.count > 1 {
                        StationFloorStepperPill(
                            floors: availableFloors,
                            selectedFloor: $selectedFloor,
                            onFloorChanged: { floor in
                                onSelectFloor?(floor)
                            }
                        )
                    }
                    
                    // Segmented Tab Picker: [ Live Arrivals | Full Timetable ]
                    Picker("Transit Surface", selection: $selectedTab) {
                        ForEach(TransitTabMode.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Divider()
                }
                .padding(.horizontal, 20)
                
                // Scrollable Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        if selectedTab == .liveArrivals {
                            // Real-time Arrivals Organized by Direction (Subway) or Unified Chronological Stream (Bus)
                            LiveArrivalsCarousel(
                                groupedArrivals: groupedArrivals,
                                busArrivals: unifiedBusArrivals,
                                isBus: isBusStop,
                                routeIds: details.routeIds,
                                selectedRouteFilter: $selectedBusRouteFilter,
                                totalBusArrivalsCount: displayedArrivals.count,
                                isLiveActive: isLiveActive,
                                isLivePulsing: isLivePulsing,
                                isRefreshing: isRefreshing,
                                pollProgress: pollProgress,
                                reliabilityResolver: { arrival in reliabilityTier(for: arrival) },
                                onRefresh: { triggerManualRefresh() },
                                onInspectArrival: { arrival in
                                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                                        inspectingArrival = arrival
                                        selectedDetent = .medium
                                    }
                                }
                            )
                            
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
                                routeIds: details.routeIds,
                                stopId: stopId,
                                liveArrivals: liveArrivals,
                                availableDirections: availableDirections,
                                selectedDirection: $selectedDirection,
                                selectedDayOffset: $selectedDayOffset,
                                isHistoricalFallback: isHistoricalFallback,
                                isObservedReplay: isObservedReplay,
                                scheduleValidity: CameraBounds.activeConfig.transit?.scheduleValidity,
                                referenceDate: referenceDate,
                                isScheduleAvailable: isScheduleAvailable,
                                onInspectDeparture: { arrival in
                                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                                        inspectingArrival = arrival
                                        selectedDetent = .medium
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                TransitSheetSkeletonView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: stopDetails != nil)
    }
    
    // MARK: - Inspector View Router
    
    @ViewBuilder
    private func inspectorView(for arr: SpatialDatabaseManager.ArrivalInfo) -> some View {
        let lineInfo = TransitRouteData.lineInfo(for: arr.line)
        let modalClass = (stopDetails?.modalClass == .bus || stopDetails?.modalClass == .ferry)
            ? stopDetails!.modalClass
            : lineInfo.modalClass
        let followOn = resolveFollowOnArrival(for: arr)
        
        if modalClass == .subway || modalClass == .lightRail {
            GuidewayRunInspector(
                arrival: arr,
                currentStopId: stopId,
                currentStopName: stopDetails?.name ?? "Current Station",
                currentStopCoordinate: stopDetails?.coordinate,
                followOnArrival: followOn,
                onBack: {
                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                        inspectingArrival = nil
                        selectedDetent = .medium
                        onClearRouteInspection?()
                    }
                },
                onFocusMap: { coord in
                    onFocusMap?(coord)
                },
                onInspectRoute: onInspectRoute,
                onClearRouteInspection: onClearRouteInspection,
                onVehicleFrame: onVehicleFrame
            )
        } else {
            SurfaceRunInspector(
                arrival: arr,
                currentStopId: stopId,
                currentStopName: stopDetails?.name ?? "Current Stop",
                currentStopCoordinate: stopDetails?.coordinate,
                modalClass: modalClass,
                followOnArrival: followOn,
                onBack: {
                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                        inspectingArrival = nil
                        selectedDetent = .medium
                        onClearRouteInspection?()
                    }
                },
                onFocusMap: { coord in
                    onFocusMap?(coord)
                },
                onInspectRoute: onInspectRoute,
                onClearRouteInspection: onClearRouteInspection
            )
        }
    }
    
    // MARK: - Wave PD.2 / Pre-T.5: Compact Interactive Inspection Dock Pill
    
    internal static func cleanInspectionDestination(destination: String, line: String) -> String {
        let dest = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "\(line) to "
        if dest.lowercased().hasPrefix(prefix.lowercased()) {
            return String(dest.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if dest.lowercased().hasPrefix("to ") {
            return String(dest.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return dest
    }
    
    @ViewBuilder
    internal func compactInspectionDockPill(for arr: SpatialDatabaseManager.ArrivalInfo) -> some View {
        let cleanDestination = Self.cleanInspectionDestination(destination: arr.destination, line: arr.line)
        
        HStack(alignment: .center, spacing: 10) {
            // [Route Badge]
            TransitRouteBadge(routeId: arr.line, size: .compact)
            
            // [Destination] • [ETA]
            HStack(spacing: 5) {
                Text(cleanDestination)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Text("•")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.secondary)
                
                Text(arr.minutes == 0 ? "Boarding" : "\(arr.minutes) min")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Color(hex: "#FFB300"))
            }
            .lineLimit(1)
            
            Spacer(minLength: 4)
            
            // [^ Tap to Expand]
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    selectedDetent = .medium
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                    Text("Tap to Expand")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(hex: "#FFB300").opacity(0.15))
                .foregroundColor(Color(hex: "#D97706"))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Tapping (X) exits inspection back to station departures
            Button {
                withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                    inspectingArrival = nil
                    selectedDetent = .medium
                    onClearRouteInspection?()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedDetent = .medium
            }
        }
    }
    
    internal func resolveFollowOnArrival(for arr: SpatialDatabaseManager.ArrivalInfo) -> SpatialDatabaseManager.ArrivalInfo? {
        Self.resolveFollowOnArrival(for: arr, from: displayedArrivals)
    }
    
    static func resolveFollowOnArrival(
        for arr: SpatialDatabaseManager.ArrivalInfo,
        from candidates: [SpatialDatabaseManager.ArrivalInfo]
    ) -> SpatialDatabaseManager.ArrivalInfo? {
        candidates
            .filter { $0.line == arr.line && $0.direction == arr.direction && $0.id != arr.id && $0.minutes >= arr.minutes }
            .sorted { $0.minutes < $1.minutes }
            .first
    }
    
    @MainActor
    private func reloadTimetable(direction: Int, dayOffset: Int) async {
        guard let details = stopDetails else { return }
        if let result = try? await SpatialDatabaseManager.shared.fetchTimetableResult(
            for: stopId,
            routeId: details.routeId,
            routeIds: details.routeIds,
            directionId: direction,
            dayOffset: dayOffset,
            referenceDate: referenceDate ?? Date()
        ) {
            self.timetableSchedule = result.records
            self.isHistoricalFallback = result.isHistoricalFallback
            self.isObservedReplay = result.isObservedReplay
            self.isScheduleAvailable = result.isScheduleAvailable
        }
    }
    
    @MainActor
    private func triggerManualRefresh() {
        guard !isRefreshing, let details = stopDetails else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pollGeneration += 1
        let currentGen = pollGeneration
        self.pollProgress = 0.0
        Task {
            await performLiveFetch(routeIds: details.routeIds)
            await runPollingLoop(routeIds: details.routeIds, currentGen: currentGen)
        }
    }
    
    @MainActor
    private func performLiveFetch(routeIds: [String]) async {
        isRefreshing = true
        do {
            let live = try await TransitRealtimeService.shared.fetchLiveArrivals(for: stopId, routeIds: routeIds)
            if !Task.isCancelled {
                if !live.isEmpty {
                    self.liveArrivals = live
                    await updateReliabilityTiers(for: live)
                }
                self.isLiveActive = true
                self.lastUpdated = Date()
            }
        } catch {
            if !Task.isCancelled {
                self.isLiveActive = false
            }
        }
        self.isRefreshing = false
    }
    
    @MainActor
    private func runPollingLoop(routeIds: [String], currentGen: Int) async {
        while !Task.isCancelled && pollGeneration == currentGen {
            let pollDuration: Double = 15.0
            let stepInterval: Double = 0.25
            let totalSteps = Int(pollDuration / stepInterval)
            
            for step in 0..<totalSteps {
                if Task.isCancelled || pollGeneration != currentGen { return }
                self.pollProgress = Double(step) / Double(totalSteps)
                try? await Task.sleep(nanoseconds: UInt64(stepInterval * 1_000_000_000))
            }
            
            if Task.isCancelled || pollGeneration != currentGen { return }
            self.pollProgress = 1.0
            await performLiveFetch(routeIds: routeIds)
            self.pollProgress = 0.0
        }
    }
    
    @MainActor
    private func startPollingLifecycle() async {
        // 1. Initial base load from local SQLite
        let details: SpatialDatabaseManager.StopDetails?
        if let existing = self.stopDetails {
            details = existing
        } else {
            details = try? await SpatialDatabaseManager.shared.fetchStopDetails(for: stopId)
        }
        let hw = try? await SpatialDatabaseManager.shared.fetchHeadwayData(for: stopId)
        let rel = try? await SpatialDatabaseManager.shared.fetchHourlyReliability(for: stopId, routeId: details?.routeId, routeIds: details?.routeIds ?? [])
        let availDirs = (try? await SpatialDatabaseManager.shared.fetchAvailableDirections(for: stopId, stopName: details?.name, routeId: details?.routeId, routeIds: details?.routeIds ?? [])) ?? [0, 1]
        
        let initialDir: Int
        if !availDirs.contains(selectedDirection), let firstAvail = availDirs.sorted().first {
            initialDir = firstAvail
            self.selectedDirection = firstAvail
        } else {
            initialDir = selectedDirection
        }
        
        let timetableResult = try? await SpatialDatabaseManager.shared.fetchTimetableResult(for: stopId, routeId: details?.routeId, routeIds: details?.routeIds ?? [], directionId: initialDir, dayOffset: selectedDayOffset, referenceDate: referenceDate ?? Date())
        
        self.stopDetails = details
        self.availableDirections = availDirs
        if let hw = hw {
            self.headways = hw
        }
        if let rel = rel {
            self.hourlyReliability = rel
        }
        if let result = timetableResult {
            self.timetableSchedule = result.records
            self.isHistoricalFallback = result.isHistoricalFallback
            self.isObservedReplay = result.isObservedReplay
            self.isScheduleAvailable = result.isScheduleAvailable
        }
        
        guard let details = details else { return }
        
        // Wave Q.4: Resolve station complex & available 2D floorplans
        if availableFloors.isEmpty {
            if let cid = await StationFloorplanStore.shared.resolveComplexId(for: stopId) {
                let floors = StationFloorplanStore.shared.floors(for: cid)
                if !floors.isEmpty {
                    self.availableFloors = floors
                    if self.selectedFloor == nil {
                        let def = StationFloorplanStore.shared.defaultFloor(for: cid)
                        self.selectedFloor = def
                        if let def = def {
                            self.onSelectFloor?(def)
                        }
                    }
                }
            }
        }
        
        // Load initial service alerts across all serving lines
        let alerts = await TransitRealtimeService.shared.fetchServiceAlerts(for: details.routeIds)
        self.serviceAlerts = alerts
        
        // 2. Fetch initial reliability tiers for displayed arrivals
        await updateReliabilityTiers(for: displayedArrivals)
        
        // 3. Fetch initial live arrivals & start generational polling loop
        pollGeneration += 1
        let currentGen = pollGeneration
        await performLiveFetch(routeIds: details.routeIds)
        await runPollingLoop(routeIds: details.routeIds, currentGen: currentGen)
    }
    
    // MARK: - Reliability Tier Resolution
    
    internal func reliabilityTier(for arrival: SpatialDatabaseManager.ArrivalInfo) -> LineReliabilityTier? {
        let slot = TripSlotProfileRecord.slotIndex(for: arrival.arrivalDate)
        let day = TripSlotProfileRecord.dayType(for: arrival.arrivalDate)
        let key = "\(arrival.line)_\(arrival.directionId)_\(slot)_\(day)"
        if let direct = reliabilityTiers[key] {
            return direct
        }
        let routeKey = "\(arrival.line)_\(arrival.directionId)"
        if let routeDirect = reliabilityTiers[routeKey] {
            return routeDirect
        }
        
        // Instantaneous fallback: check hourlyReliability loaded for this sheet
        let hour = Calendar.current.component(.hour, from: arrival.arrivalDate)
        if let match = hourlyReliability.first(where: { $0.routeId == arrival.line && $0.directionId == arrival.directionId && $0.hourOfDay == hour }) {
            return LineReliabilityTier(score: match.onTimePct)
        }
        
        return nil
    }
    
    @MainActor
    private func updateReliabilityTiers(for arrivals: [SpatialDatabaseManager.ArrivalInfo]) async {
        guard !arrivals.isEmpty else { return }
        
        var neededKeys: Set<String> = []
        var candidates: [SpatialDatabaseManager.ArrivalInfo] = []
        
        for arr in arrivals {
            let slot = TripSlotProfileRecord.slotIndex(for: arr.arrivalDate)
            let day = TripSlotProfileRecord.dayType(for: arr.arrivalDate)
            let key = "\(arr.line)_\(arr.directionId)_\(slot)_\(day)"
            if reliabilityTiers[key] == nil && !neededKeys.contains(key) {
                neededKeys.insert(key)
                candidates.append(arr)
            }
        }
        
        guard !candidates.isEmpty else { return }
        
        for candidate in candidates {
            let slot = TripSlotProfileRecord.slotIndex(for: candidate.arrivalDate)
            let day = TripSlotProfileRecord.dayType(for: candidate.arrivalDate)
            let key = "\(candidate.line)_\(candidate.directionId)_\(slot)_\(day)"
            let routeKey = "\(candidate.line)_\(candidate.directionId)"
            
            if let tier = await SpatialDatabaseManager.shared.fetchReliabilityTier(
                routeId: candidate.line,
                directionId: candidate.directionId,
                stopId: stopId,
                date: candidate.arrivalDate
            ) {
                self.reliabilityTiers[key] = tier
                self.reliabilityTiers[routeKey] = tier
            }
        }
    }
}

// MARK: - Subcomponents

private struct LiveStatusBadge: View {
    let isLive: Bool
    let isPulsing: Bool
    
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                if isLive {
                    // Outer expanding radar ping
                    Circle()
                        .fill(Color(hex: "#FFB300"))
                        .frame(width: 6, height: 6)
                        .scaleEffect(isPulsing ? 1.8 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.6)
                    
                    // Core breathing amber dot
                    Circle()
                        .fill(Color(hex: "#FFB300"))
                        .frame(width: 6, height: 6)
                        .opacity(isPulsing ? 1.0 : 0.35)
                        .shadow(color: Color(hex: "#FFB300").opacity(0.8), radius: isPulsing ? 2.5 : 0.5)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(width: 8, height: 8)
            
            Text(isLive ? "LIVE" : "SCHEDULED")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(isLive ? Color(hex: "#FFB300") : .secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(isLive ? Color(hex: "#FFB300").opacity(0.12) : Color.primary.opacity(0.04))
        .clipShape(Capsule())
    }
}

private struct CircularRefreshButton: View {
    let isRefreshing: Bool
    let progress: Double
    let onRefresh: () -> Void
    
    var body: some View {
        Button(action: onRefresh) {
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                
                // Animated Progress Ring (15s countdown arc)
                Circle()
                    .trim(from: 0.0, to: isRefreshing ? 0.25 : max(0.02, min(1.0, progress)))
                    .stroke(
                        Color(hex: "#FFB300").opacity(isRefreshing ? 0.8 : 0.5),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(-90))
                
                // Refresh Arrow Icon
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(isRefreshing ? Color(hex: "#FFB300") : .secondary)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing ? .linear(duration: 0.75).repeatForever(autoreverses: false) : .default,
                        value: isRefreshing
                    )
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .accessibilityLabel("Refresh live arrivals")
    }
}

private struct TransitSheetSkeletonView: View {
    @State private var isPulsing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Skeleton
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color(UIColor.secondarySystemFill))
                    .frame(width: 38, height: 38)
                
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(UIColor.secondarySystemFill))
                        .frame(width: 180, height: 18)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(width: 100, height: 12)
                }
                
                Spacer()
            }
            .padding(.top, 16)
            
            // Tab Picker Skeleton
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.secondarySystemFill))
                .frame(height: 32)
            
            Divider()
                .padding(.top, 2)
            
            // Section Title Skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(UIColor.tertiarySystemFill))
                .frame(width: 130, height: 11)
                .padding(.top, 4)
            
            // Row Skeletons
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(UIColor.secondarySystemFill))
                        .frame(width: 24, height: 24)
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(UIColor.secondarySystemFill))
                        .frame(width: 150, height: 16)
                    
                    Spacer()
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(width: 40, height: 16)
                }
                .padding(.vertical, 6)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .opacity(isPulsing ? 0.4 : 0.85)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Live Arrivals Carousel

struct LiveArrivalsCarousel: View {
    let groupedArrivals: [TransitRevealSheet.DirectionalArrivalGroup]
    var busArrivals: [SpatialDatabaseManager.ArrivalInfo] = []
    var isBus: Bool = false
    var routeIds: [String] = []
    @Binding var selectedRouteFilter: String?
    var totalBusArrivalsCount: Int = 0
    let isLiveActive: Bool
    let isLivePulsing: Bool
    let isRefreshing: Bool
    let pollProgress: Double
    var reliabilityResolver: ((SpatialDatabaseManager.ArrivalInfo) -> LineReliabilityTier?)? = nil
    let onRefresh: () -> Void
    let onInspectArrival: (SpatialDatabaseManager.ArrivalInfo) -> Void
    
    init(
        groupedArrivals: [TransitRevealSheet.DirectionalArrivalGroup],
        busArrivals: [SpatialDatabaseManager.ArrivalInfo] = [],
        isBus: Bool = false,
        routeIds: [String] = [],
        selectedRouteFilter: Binding<String?> = .constant(nil),
        totalBusArrivalsCount: Int = 0,
        isLiveActive: Bool,
        isLivePulsing: Bool,
        isRefreshing: Bool,
        pollProgress: Double,
        reliabilityResolver: ((SpatialDatabaseManager.ArrivalInfo) -> LineReliabilityTier?)? = nil,
        onRefresh: @escaping () -> Void,
        onInspectArrival: @escaping (SpatialDatabaseManager.ArrivalInfo) -> Void
    ) {
        self.groupedArrivals = groupedArrivals
        self.busArrivals = busArrivals
        self.isBus = isBus
        self.routeIds = routeIds
        self._selectedRouteFilter = selectedRouteFilter
        self.totalBusArrivalsCount = totalBusArrivalsCount
        self.isLiveActive = isLiveActive
        self.isLivePulsing = isLivePulsing
        self.isRefreshing = isRefreshing
        self.pollProgress = pollProgress
        self.reliabilityResolver = reliabilityResolver
        self.onRefresh = onRefresh
        self.onInspectArrival = onInspectArrival
    }
    
    @ViewBuilder
    private func arrivalRow(for arrival: SpatialDatabaseManager.ArrivalInfo) -> some View {
        Button {
            onInspectArrival(arrival)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                let arrivalInfo = TransitRouteData.lineInfo(for: arrival.line)
                TransitRouteBadge(routeId: arrival.line, lineInfo: arrivalInfo, size: .compact)
                
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
                    
                    HStack(alignment: .center, spacing: 6) {
                        let displayDist: String? = {
                            if arrival.minutes == 0 {
                                // Invariant FC-3: Suppress redundant "Boarding" text when BOARDING capsule is rendered
                                if let trk = arrival.formattedTrack {
                                    return trk
                                }
                                if let dist = arrival.distanceDescription, !dist.localizedCaseInsensitiveContains("boarding") {
                                    return dist
                                }
                                return nil
                            } else {
                                if let dist = arrival.distanceDescription, !dist.isEmpty {
                                    if let trk = arrival.formattedTrack {
                                        return "\(dist) • \(trk)"
                                    }
                                    return dist
                                } else if let trk = arrival.formattedTrack {
                                    return trk
                                }
                                return nil
                            }
                        }()
                        
                        // Terminal qualifier disambiguation (PE.7 §3):
                        // Display branch terminals (e.g. W to Whitehall St, Green Line C to Gov Center) in row subtitle
                        if let qualifier = arrival.terminalQualifier, !qualifier.isEmpty, qualifier != arrival.destination {
                            Text(qualifier)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(Color(hex: "#FFB300"))
                                .lineLimit(1)
                            
                            if displayDist != nil {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let distText = displayDist {
                            Text(distText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        if let tier = reliabilityResolver?(arrival) {
                            RouteReliabilityBadge(tier: tier)
                        }
                    }
                }
                
                Spacer()
                
                if arrival.isHoldingStation {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#D97706"))
                        Text("HELD")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#D97706"))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#FFB300").opacity(0.18))
                    .clipShape(Capsule())
                } else if arrival.minutes == 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: "#FFB300"))
                            .frame(width: 5, height: 5)
                            .opacity(isLivePulsing ? 1.0 : 0.35)
                            .shadow(color: Color(hex: "#FFB300").opacity(0.8), radius: 2)
                        Text("BOARDING")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#FFB300"))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#FFB300").opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 3) {
                        Text("\(arrival.minutes)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                        Text("min")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2.5)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("UPCOMING DEPARTURES")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                LiveStatusBadge(isLive: isLiveActive, isPulsing: isLivePulsing)
                
                CircularRefreshButton(
                    isRefreshing: isRefreshing,
                    progress: pollProgress
                ) {
                    onRefresh()
                }
            }
            
            if isBus {
                // Wave PE.4: Multi-Route Bus Hub Filter Chips
                if routeIds.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.prepare()
                                generator.impactOccurred()
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedRouteFilter = nil
                                }
                            } label: {
                                let isAllSelected = (selectedRouteFilter == nil || selectedRouteFilter == "ALL")
                                Text("All (\(totalBusArrivalsCount))")
                                    .font(.system(size: 11, weight: isAllSelected ? .bold : .medium, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(isAllSelected ? Color(hex: "#FFB300").opacity(0.2) : Color.primary.opacity(0.05))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(isAllSelected ? Color(hex: "#FFB300") : Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                                    .foregroundColor(isAllSelected ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                            
                            ForEach(routeIds, id: \.self) { rId in
                                let rInfo = TransitRouteData.lineInfo(for: rId)
                                let isSelected = (selectedRouteFilter?.uppercased() == rId.uppercased())
                                Button {
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.prepare()
                                    generator.impactOccurred()
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedRouteFilter = rId
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        TransitRouteBadge(routeId: rId, lineInfo: rInfo, size: .filter, isSelected: isSelected)
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
                
                // Unified Chronological Stream (Strictly sorted by ETA, displaying terminal branch variants/short-turns)
                if busArrivals.isEmpty {
                    Text("No scheduled arrivals in the next 30 minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 2) {
                        ForEach(busArrivals) { arrival in
                            arrivalRow(for: arrival)
                        }
                    }
                }
            } else {
                // Fixed Guideway / Subway Directional Partitioning
                if groupedArrivals.isEmpty {
                    Text("No scheduled arrivals in the next 30 minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(groupedArrivals) { group in
                        VStack(alignment: .leading, spacing: 4) {
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
                            .padding(.vertical, 3.5)
                        .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            
                            // Arrival Rows within Direction
                            VStack(spacing: 2) {
                                ForEach(group.arrivals) { arrival in
                                    arrivalRow(for: arrival)
                                }
                            }
                        }
                        .padding(.bottom, 3)
                    }
                }
            }
        }
    }
}

#Preview {
    TransitRevealSheet(stopId: "stop_columbus")
}

