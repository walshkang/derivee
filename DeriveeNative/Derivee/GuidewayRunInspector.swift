import SwiftUI
import CoreLocation

/// Guideway Run Inspector sub-sheet for dedicated right-of-way transit:
/// Heavy Rail (Subway), Light Rail (LRT), and Commuter Rail.
///
/// Follows the first-principles 5-element specification (design.md §10.5):
/// 1. Hero: Identity & Imminence (Route pill, destination, direction, live countdown, stops away, trip ID)
/// 2. Alert: Active Disruption Banner (inline amber warning pill, dismissible)
/// 3. Core: Stop Progression Ladder (continuous vertical route line, completed stops, current station, downstream ETAs)
/// 4. Context: Follow-On Departure (Next departure below ladder)
/// 5. Signal: Crowding Micro-Badge (single glanceable badge, no carriage diagrams)
public struct GuidewayRunInspector: View {
    public let arrival: SpatialDatabaseManager.ArrivalInfo
    public let currentStopId: String
    public let currentStopName: String
    public let currentStopCoordinate: CLLocationCoordinate2D?
    public var followOnArrival: SpatialDatabaseManager.ArrivalInfo? = nil
    public var onFocusMap: ((CLLocationCoordinate2D) -> Void)? = nil
    public var onInspectRoute: ((RouteInspectionCommand) -> Void)? = nil
    public var onClearRouteInspection: (() -> Void)? = nil
    
    @State private var stopLadder: [TrackStop] = []
    @State private var isLoadingLadder: Bool = true
    @State private var isPassedStopsExpanded: Bool = false
    @State private var crowdEstimate: CrowdDensityEstimate = CrowdDensityEstimate(level: .moderate, isLiveSensors: false)
    @State private var activeDisruption: String? = nil
    @State private var isDisruptionDismissed: Bool = false
    @State private var isPulsing: Bool = false
    @State private var selectedStopForFocus: TrackStop? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    public init(
        arrival: SpatialDatabaseManager.ArrivalInfo,
        currentStopId: String,
        currentStopName: String,
        currentStopCoordinate: CLLocationCoordinate2D? = nil,
        followOnArrival: SpatialDatabaseManager.ArrivalInfo? = nil,
        onFocusMap: ((CLLocationCoordinate2D) -> Void)? = nil,
        onInspectRoute: ((RouteInspectionCommand) -> Void)? = nil,
        onClearRouteInspection: (() -> Void)? = nil
    ) {
        self.arrival = arrival
        self.currentStopId = currentStopId
        self.currentStopName = currentStopName
        self.currentStopCoordinate = currentStopCoordinate
        self.followOnArrival = followOnArrival
        self.onFocusMap = onFocusMap
        self.onInspectRoute = onInspectRoute
        self.onClearRouteInspection = onClearRouteInspection
    }
    
    private var lineInfo: TransitRouteData.LineInfo {
        TransitRouteData.lineInfo(for: arrival.line)
    }
    
    private var directionId: Int {
        arrival.resolvedDirectionId
    }
    
    public var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // 1. Hero: Identity & Imminence
                        renderHeroHeader()
                        
                        // 2. Alert: Active Disruption Banner (if present & not dismissed)
                        if let disruption = activeDisruption, !isDisruptionDismissed {
                            renderDisruptionBanner(disruption)
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        // 3. Core: Stop Progression Ladder
                        renderStopProgressionLadder()
                        
                        // 4. Context: Follow-On Departure
                        if let nextArr = followOnArrival {
                            renderFollowOnDeparture(nextArr)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
                .onChange(of: isLoadingLadder) { _, loading in
                    if !loading, let currentStop = stopLadder.first(where: { $0.isCurrent }) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            scrollProxy.scrollTo("ACTIVE_STATION_\(currentStop.id)", anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle("Guideway Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.fraction(0.40), .fraction(0.88)])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .transitSheetGlassBackground()
        .task {
            await loadInspectorData()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onDisappear {
            onClearRouteInspection?()
        }
    }
    
    // MARK: - 1. Hero: Identity & Imminence
    
    @ViewBuilder
    private func renderHeroHeader() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                TransitRouteBadge(routeId: arrival.line, lineInfo: lineInfo, size: .large)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(arrival.destination)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if arrival.minutes == 0 {
                            let trackSuffix = arrival.formattedTrack.map { " (\($0))" } ?? ""
                            Text("• Boarding\(trackSuffix)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "#FFB300"))
                                .lineLimit(1)
                        }
                    }
                    
                    if let dir = arrival.direction {
                        Text(dir.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Arrival Countdown & Imminence Pill
                VStack(alignment: .trailing, spacing: 2) {
                    if arrival.minutes == 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: "#FFB300"))
                                .frame(width: 6, height: 6)
                                .opacity(isPulsing ? 1.0 : 0.3)
                            Text("BOARDING")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "#FFB300"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#FFB300").opacity(0.12))
                        .clipShape(Capsule())
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(arrival.minutes)")
                                .font(.system(size: 26, weight: .black, design: .monospaced))
                                .foregroundColor(.primary)
                            Text("min")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        if let dist = arrival.distanceDescription, !dist.isEmpty, dist.lowercased() != "boarding" {
                            Text(dist)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Commuter Context & Action Bar (Invariants FC-2 & FC-3)
            HStack(spacing: 8) {
                // Vehicle Proximity Pill
                let proximity = arrival.proximityContext(ladder: stopLadder, currentStopName: currentStopName)
                HStack(spacing: 5) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(lineInfo.color)
                    Text(proximity)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                
                // Follow-On Departure Imminence
                if let nextArr = followOnArrival {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                        let followOnText = nextArr.minutes == 0 ? "Next train due now" : "Next train in \(nextArr.minutes)m"
                        Text(followOnText)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
                // Station Hold (if active)
                if arrival.isHoldingStation {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color(hex: "#D97706"))
                        Text("STATION HOLD")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#D97706"))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#FFB300").opacity(0.18))
                    .clipShape(Capsule())
                }
                
                // 5. Signal: Crowding Micro-Badge
                renderCrowdingMicroBadge()
                
                Spacer()
                
                // 1-Tap Map Synchronizer Action
                Button {
                    synchronizeWithMap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Focus on Map")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#FFB300").opacity(0.15))
                    .foregroundColor(Color(hex: "#D97706"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - 2. Alert: Disruption Banner
    
    @ViewBuilder
    private func renderDisruptionBanner(_ disruption: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "#D97706"))
            
            Text(disruption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#92400E"))
                .lineLimit(2)
            
            Spacer()
            
            Button {
                isDisruptionDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "#B45309"))
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(hex: "#FEF3C7"))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: "#F59E0B").opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - 3. Core: Stop Progression Ladder
    
    @ViewBuilder
    private func renderStopProgressionLadder() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STOP PROGRESSION")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(stopLadder.count) STATIONS")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            if isLoadingLadder {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                let passedStops = stopLadder.filter { $0.isPassed }
                let activeAndUpcomingStops = stopLadder.filter { !$0.isPassed }
                let shouldCollapsePassed = passedStops.count >= 3
                
                VStack(spacing: 0) {
                    if shouldCollapsePassed {
                        // Collapsed Accordion Header / Toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isPassedStopsExpanded.toggle()
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 14) {
                                // Continuous Track Stem indicator
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(width: 4, height: 6)
                                    Circle()
                                        .fill(Color.secondary.opacity(0.35))
                                        .frame(width: 8, height: 8)
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.25))
                                        .frame(width: 4, height: 6)
                                }
                                .frame(width: 24)
                                
                                Text("\(passedStops.count) stops passed")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                                
                                Image(systemName: isPassedStopsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        if isPassedStopsExpanded {
                            ForEach(Array(passedStops.enumerated()), id: \.element.id) { index, stop in
                                renderLadderNode(stop: stop, isFirst: index == 0, isLast: false)
                            }
                        }
                    } else {
                        // Fewer than 3 passed stops: render inline
                        ForEach(Array(passedStops.enumerated()), id: \.element.id) { index, stop in
                            renderLadderNode(stop: stop, isFirst: index == 0, isLast: false)
                        }
                    }
                    
                    // Active & Upcoming stops
                    ForEach(Array(activeAndUpcomingStops.enumerated()), id: \.element.id) { index, stop in
                        let isFirstInBlock = passedStops.isEmpty && index == 0
                        let isLastInBlock = index == activeAndUpcomingStops.count - 1
                        renderLadderNode(stop: stop, isFirst: isFirstInBlock, isLast: isLastInBlock)
                            .id(stop.isCurrent ? "ACTIVE_STATION_\(stop.id)" : stop.id)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
            }
        }
    }
    
    @ViewBuilder
    private func renderLadderNode(stop: TrackStop, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Track Stem & Station Bullet
            VStack(spacing: 0) {
                // Upper Stem
                Rectangle()
                    .fill(isFirst ? Color.clear : (stop.isPassed ? Color.secondary.opacity(0.25) : lineInfo.color))
                    .frame(width: 4, height: 18)
                
                // Central Node
                ZStack {
                    if stop.isCurrent {
                        Circle()
                            .stroke(Color(hex: "#FFB300"), lineWidth: 3)
                            .frame(width: 20, height: 20)
                            .scaleEffect(isPulsing ? 1.15 : 0.95)
                            .opacity(isPulsing ? 1.0 : 0.6)
                        
                        Circle()
                            .fill(Color(hex: "#FFB300"))
                            .frame(width: 10, height: 10)
                    } else if stop.isPassed {
                        Circle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 10, height: 10)
                    } else if stop.isTerminus {
                        Circle()
                            .stroke(lineInfo.color, lineWidth: 3)
                            .frame(width: 14, height: 14)
                        Circle()
                            .fill(lineInfo.color)
                            .frame(width: 6, height: 6)
                    } else {
                        Circle()
                            .fill(lineInfo.color)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    }
                }
                .frame(width: 22, height: 22)
                
                // Lower Stem
                Rectangle()
                    .fill(isLast ? Color.clear : (stop.isPassed && !stop.isCurrent ? Color.secondary.opacity(0.25) : lineInfo.color))
                    .frame(width: 4, height: 18)
            }
            .frame(width: 24)
            
            // Stop Information
            Button {
                selectedStopForFocus = stop
                onFocusMap?(stop.coordinate)
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(stop.stopName)
                                .font(.system(size: stop.isCurrent ? 14.5 : 13.5, weight: stop.isCurrent ? .bold : .medium, design: .rounded))
                                .foregroundColor(stop.isPassed ? .secondary : .primary)
                                .lineLimit(1)
                            
                            if stop.isCurrent {
                                Text("YOU ARE HERE")
                                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Color(hex: "#FFB300"))
                                    .foregroundColor(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            } else if isFirst && arrival.isHoldingStation {
                                Text("HELD AT TERMINUS")
                                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Color(hex: "#FFB300").opacity(0.2))
                                    .foregroundColor(Color(hex: "#D97706"))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        
                        // Connecting Lines Badges
                        if !stop.transferRoutes.isEmpty {
                            HStack(spacing: 3) {
                                ForEach(stop.transferRoutes.prefix(5), id: \.self) { rId in
                                    let tInfo = TransitRouteData.lineInfo(for: rId)
                                    Text(rId)
                                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(hex: tInfo.textColorHex))
                                        .frame(width: 14, height: 14)
                                        .background(tInfo.color)
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.top, 1)
                        }
                    }
                    
                    Spacer()
                    
                    // ETA Indicator
                    if let eta = stop.estimatedMinutes {
                        if eta == 0 {
                            Text("Now")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "#FFB300"))
                        } else {
                            Text("+\(eta)m")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(stop.isCurrent ? Color(hex: "#FFB300") : .secondary)
                        }
                    } else if stop.isPassed {
                        Text("Passed")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 46)
    }
    
    // MARK: - 4. Context: Follow-On Departure
    
    @ViewBuilder
    private func renderFollowOnDeparture(_ nextArrival: SpatialDatabaseManager.ArrivalInfo) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            HStack(alignment: .center, spacing: 6) {
                Text("Next")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                
                TransitRouteBadge(routeId: arrival.line, lineInfo: lineInfo, size: .compact)
                
                let minText = nextArrival.minutes == 0 ? "due now" : "in \(nextArrival.minutes) min"
                Text(minText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                let timeStr = DateFormatter.localizedString(from: nextArrival.arrivalDate, dateStyle: .none, timeStyle: .short)
                Text(timeStr)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    // MARK: - 5. Signal: Crowding Micro-Badge
    
    @ViewBuilder
    private func renderCrowdingMicroBadge() -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(crowdEstimate.level.statusColor)
                .frame(width: 6, height: 6)
            Text(crowdEstimate.level.glanceableTitle)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(crowdEstimate.level.statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(crowdEstimate.level.statusColor.opacity(0.12))
        .clipShape(Capsule())
    }
    
    // MARK: - Data & Actions
    
    private func synchronizeWithMap() {
        let coord = stopLadder.first(where: { $0.isCurrent })?.coordinate ??
                    currentStopCoordinate ??
                    stopLadder.first?.coordinate
        if let coord = coord {
            onFocusMap?(coord)
            dismiss()
        } else {
            dismiss()
        }
    }
    
    private func loadInspectorData() async {
        isLoadingLadder = true
        
        // 1. Resolve glanceable occupancy estimate
        crowdEstimate = CrowdDensityEstimate.resolve(
            gtfsOccupancy: nil,
            occupancyPercentage: nil,
            date: arrival.arrivalDate
        )
        
        // 2. Fetch Active Disruptions if available
        let epoch = Int64(arrival.arrivalDate.timeIntervalSince1970)
        var disruptions = (try? await SpatialDatabaseManager.shared.fetchDisruptions(for: arrival.line, directionId: directionId, at: epoch)) ?? []
        if disruptions.isEmpty {
            disruptions = (try? await SpatialDatabaseManager.shared.fetchDisruptions(for: arrival.line, directionId: nil, at: epoch)) ?? []
        }
        if disruptions.isEmpty {
            disruptions = (try? await SpatialDatabaseManager.shared.fetchDisruptions(for: arrival.line, directionId: nil, at: nil)) ?? []
        }
        
        if let first = disruptions.first {
            await MainActor.run {
                self.activeDisruption = first.formattedAlertSummary
            }
        }
        
        // 3. Fetch Stop Ladder & Synchronize Map Polyline (Wave PA.5 & Wave PB.3)
        do {
            let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
                routeId: arrival.line,
                directionId: directionId,
                currentStopId: currentStopId,
                currentArrivalMinutes: arrival.minutes,
                tappedCoordinate: currentStopCoordinate
            )
            
            var stationCoord = ladder.first(where: { $0.isCurrent })?.coordinate ??
                               currentStopCoordinate ??
                               ladder.first?.coordinate
            if stationCoord == nil {
                stationCoord = try? await SpatialDatabaseManager.shared.fetchStopCoordinate(for: currentStopId)
            }
            
            let polyline = await TransitRouteData.resolveInspectionPolyline(
                routeId: arrival.line,
                modalClass: lineInfo.modalClass,
                fallbackStops: ladder.map(\.coordinate)
            )
            
            let vehicleLoc = TransitRealtimeService.shared.resolveVehicleLocation(
                arrival: arrival,
                ladder: ladder
            )
            
            if let validStationCoord = stationCoord {
                let command = RouteInspectionCommand(
                    routeId: arrival.line,
                    lineName: lineInfo.name,
                    agencyColorHex: lineInfo.colorHex,
                    casingColorHex: "#FFFFFF",
                    modalClass: lineInfo.modalClass,
                    coordinates: polyline,
                    stationCoordinate: validStationCoord,
                    shouldFrameCamera: true,
                    vehicleCoordinate: vehicleLoc?.coordinate,
                    vehicleBearing: vehicleLoc?.bearing,
                    vehicleStatus: arrival.distanceDescription
                )
                
                await MainActor.run {
                    self.stopLadder = ladder
                    self.isLoadingLadder = false
                    self.onInspectRoute?(command)
                }
            } else {
                await MainActor.run {
                    self.stopLadder = ladder
                    self.isLoadingLadder = false
                }
            }
        } catch {
            await MainActor.run {
                self.isLoadingLadder = false
            }
        }
    }
}
