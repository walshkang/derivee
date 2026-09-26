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
    public var onBack: (() -> Void)? = nil
    public var onFocusMap: ((CLLocationCoordinate2D) -> Void)? = nil
    public var onInspectRoute: ((RouteInspectionCommand) -> Void)? = nil
    public var onClearRouteInspection: (() -> Void)? = nil
    public var onVehicleFrame: ((CLLocationCoordinate2D, Double) -> Void)? = nil
    
    @State private var stopLadder: [TrackStop] = []
    @State private var isLoadingLadder: Bool = true
    @State private var isPassedStopsExpanded: Bool = false
    @State private var isApproachingStopsExpanded: Bool = false
    @State private var crowdEstimate: CrowdDensityEstimate = CrowdDensityEstimate(level: .moderate, isLiveSensors: false)
    @State private var activeDisruption: String? = nil
    @State private var isDisruptionDismissed: Bool = false
    @State private var isPulsing: Bool = false
    @State private var selectedStopForFocus: TrackStop? = nil
    @State private var resolvedVehicleCoordinate: CLLocationCoordinate2D? = nil
    @State private var trackingSession: LiveVehicleTrackingSession? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    public init(
        arrival: SpatialDatabaseManager.ArrivalInfo,
        currentStopId: String,
        currentStopName: String,
        currentStopCoordinate: CLLocationCoordinate2D? = nil,
        followOnArrival: SpatialDatabaseManager.ArrivalInfo? = nil,
        onBack: (() -> Void)? = nil,
        onFocusMap: ((CLLocationCoordinate2D) -> Void)? = nil,
        onInspectRoute: ((RouteInspectionCommand) -> Void)? = nil,
        onClearRouteInspection: (() -> Void)? = nil,
        onVehicleFrame: ((CLLocationCoordinate2D, Double) -> Void)? = nil
    ) {
        self.arrival = arrival
        self.currentStopId = currentStopId
        self.currentStopName = currentStopName
        self.currentStopCoordinate = currentStopCoordinate
        self.followOnArrival = followOnArrival
        self.onBack = onBack
        self.onFocusMap = onFocusMap
        self.onInspectRoute = onInspectRoute
        self.onClearRouteInspection = onClearRouteInspection
        self.onVehicleFrame = onVehicleFrame
    }
    
    private var lineInfo: TransitRouteData.LineInfo {
        TransitRouteData.lineInfo(for: arrival.line)
    }
    
    private var directionId: Int {
        arrival.directionId
    }
    
    private var inspectionMode: SpatialDatabaseManager.ArrivalInfo.RunInspectionMode {
        arrival.inspectionMode
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned Navigation Header
            HStack(alignment: .center) {
                if let onBack = onBack {
                    Button {
                        trackingSession?.stop()
                        trackingSession = nil
                        onBack()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                            Text(currentStopName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(Color(hex: "#FFB300"))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Train Inspector")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    trackingSession?.stop()
                    trackingSession = nil
                    if let onBack = onBack {
                        onBack()
                    } else {
                        onClearRouteInspection?()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
            
            // Pre-T.7: Dual-Horizon Focus Switcher Capsule
            if let vCoord = resolvedVehicleCoordinate {
                let vehicleStopName = stopLadder.first(where: { $0.isVehicleHere })?.stopName ?? "En Route"
                let stationCoord = stopLadder.first(where: { $0.isCurrent })?.coordinate ?? currentStopCoordinate
                if let stCoord = stationCoord {
                    TransitFocusSwitcherCapsule(
                        stationName: currentStopName,
                        stationCoordinate: stCoord,
                        vehicleStopName: vehicleStopName,
                        vehicleCoordinate: vCoord,
                        etaMinutes: arrival.minutes,
                        onFocus: { coord in
                            onFocusMap?(coord)
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            
            Divider()
            
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
                    .padding(.top, 14)
                    .padding(.bottom, 36)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: isLoadingLadder) { _, loading in
                    if !loading {
                        let vehicleStop = stopLadder.first(where: { $0.isVehicleHere })
                        let currentStop = stopLadder.first(where: { $0.isCurrent })
                        
                        let vehicleIdx = stopLadder.firstIndex(where: { $0.isVehicleHere }) ?? (stopLadder.firstIndex(where: { $0.isCurrent }) ?? 0)
                        let currentIdx = stopLadder.firstIndex(where: { $0.isCurrent }) ?? 0
                        let stopsAway = currentIdx - vehicleIdx
                        
                        let targetId: String? = {
                            if stopsAway > 4, let currentStop = currentStop {
                                return "ACTIVE_STATION_\(currentStop.id)"
                            } else if let vehicleStop = vehicleStop {
                                return "VEHICLE_STOP_\(vehicleStop.id)"
                            } else if let currentStop = currentStop {
                                return "ACTIVE_STATION_\(currentStop.id)"
                            }
                            return nil
                        }()
                        if let id = targetId {
                            let anchor: UnitPoint = (stopsAway > 4) ? .center : .top
                            withAnimation(.easeInOut(duration: 0.35)) {
                                scrollProxy.scrollTo(id, anchor: anchor)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadInspectorData()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onDisappear {
            trackingSession?.stop()
            trackingSession = nil
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
                        
                        if inspectionMode == .liveRun && arrival.minutes == 0 {
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
                
                // Mode-Aware Arrival Countdown & Imminence Pill
                VStack(alignment: .trailing, spacing: 2) {
                    switch inspectionMode {
                    case .historicalReplay:
                        let timeStr = DateFormatter.localizedString(from: arrival.arrivalDate, dateStyle: .none, timeStyle: .short)
                        Text(timeStr)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Text("DEPARTED")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                        
                    case .scheduledRun:
                        let timeStr = DateFormatter.localizedString(from: arrival.arrivalDate, dateStyle: .none, timeStyle: .short)
                        Text(timeStr)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                        HStack(spacing: 4) {
                            Text("SCHEDULED")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                        
                    case .liveRun:
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
            }
            
            // Commuter Context & Action Bar (Invariants FC-2 & FC-3)
            HStack(spacing: 8) {
                switch inspectionMode {
                case .historicalReplay:
                    let outcome = SpatialDatabaseManager.ArrivalInfo.formatHistoricalOutcome(delaySeconds: arrival.historicalDelaySeconds ?? 0)
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(outcome)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    
                case .scheduledRun:
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(activeDisruption != nil ? Color(hex: "#D97706") : lineInfo.color)
                        Text(activeDisruption != nil ? "Delays Reported" : "Timetable Run")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(activeDisruption != nil ? Color(hex: "#D97706") : .primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(activeDisruption != nil ? Color(hex: "#FFB300").opacity(0.15) : Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    
                case .liveRun:
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
                }
                
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
                
                // Station Hold / Origin Dwell (if active)
                if inspectionMode == .liveRun {
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
                    } else if arrival.isDwellingAtOrigin {
                        HStack(spacing: 4) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Color(hex: "#D97706"))
                            Text("AT TERMINUS")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "#D97706"))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#FFB300").opacity(0.14))
                        .clipShape(Capsule())
                    }
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
                let approachingAndUpcomingStops = stopLadder.filter { !$0.isPassed }
                let hasPassedStops = !passedStops.isEmpty
                let hasAccordion = passedStops.count >= 3
                
                let vehicleIdx = stopLadder.firstIndex(where: { $0.isVehicleHere }) ?? (stopLadder.firstIndex(where: { $0.isCurrent }) ?? 0)
                let currentIdx = stopLadder.firstIndex(where: { $0.isCurrent }) ?? 0
                let stopsAway = currentIdx - vehicleIdx
                let hasDistantConsist = stopsAway > 4
                
                VStack(spacing: 0) {
                    if inspectionMode.isHistoricalReplay {
                        // Full chronological journey for Historical Replay
                        ForEach(Array(stopLadder.enumerated()), id: \.element.id) { index, stop in
                            let isLastInBlock = index == stopLadder.count - 1
                            renderLadderNode(stop: stop, isFirst: index == 0, isLast: isLastInBlock)
                                .id(stop.id)
                        }
                    } else {
                        // Preceding Stops Accordion (Invariant FC-1):
                        // Auto-collapse when passed count >= 3, render inline when < 3
                        if hasAccordion {
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
                                            .frame(width: 4)
                                            .frame(minHeight: 8, maxHeight: .infinity)
                                        Circle()
                                            .fill(Color.secondary.opacity(0.35))
                                            .frame(width: 8, height: 8)
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.25))
                                            .frame(width: 4)
                                            .frame(minHeight: 8, maxHeight: .infinity)
                                    }
                                    .frame(width: 24)
                                    
                                    // Wave PE.11 / PD.3: auto-collapse preceding earlier stops into 'X stops passed' accordion
                                    let noun = passedStops.count == 1 ? "earlier stop" : "stops passed"
                                    Text("\(passedStops.count) \(noun)")
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
                                        .id(stop.id)
                                }
                            }
                        } else if hasPassedStops {
                            // Render passed stops inline directly above current station when < 3
                            ForEach(Array(passedStops.enumerated()), id: \.element.id) { index, stop in
                                renderLadderNode(stop: stop, isFirst: index == 0, isLast: false)
                                    .id(stop.id)
                            }
                        }
                        
                        // Approaching & Upcoming Stops anchored to commuter station
                        if hasDistantConsist, let vehicleStop = stopLadder.indices.contains(vehicleIdx) ? stopLadder[vehicleIdx] : nil {
                            let intermediateApproachingStops = stopLadder.enumerated().filter { idx, _ in idx > vehicleIdx && idx < currentIdx }.map(\.element)
                            let activeAndUpcomingStops = stopLadder.enumerated().filter { idx, _ in idx >= currentIdx }.map(\.element)
                            let isFirstInBlock = !hasPassedStops
                            
                            // 1. Live Oncoming Vehicle Stop
                            renderLadderNode(stop: vehicleStop, isFirst: isFirstInBlock, isLast: false)
                                .id("VEHICLE_STOP_\(vehicleStop.id)")
                            
                            // 2. Expandable Accordion for Distant Approaching Stops (Wave PD.7)
                            Button {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    isApproachingStopsExpanded.toggle()
                                }
                            } label: {
                                HStack(alignment: .center, spacing: 14) {
                                    // Continuous Track Stem indicator in route color
                                    VStack(spacing: 0) {
                                        Rectangle()
                                            .fill(lineInfo.color)
                                            .frame(width: 4)
                                            .frame(minHeight: 8, maxHeight: .infinity)
                                        Circle()
                                            .fill(lineInfo.color.opacity(0.6))
                                            .frame(width: 8, height: 8)
                                        Rectangle()
                                            .fill(lineInfo.color)
                                            .frame(width: 4)
                                            .frame(minHeight: 8, maxHeight: .infinity)
                                    }
                                    .frame(width: 24)
                                    
                                    let count = intermediateApproachingStops.count
                                    let noun = count == 1 ? "approaching stop" : "approaching stops"
                                    Text("\(count) \(noun)")
                                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)
                                    
                                    Image(systemName: isApproachingStopsExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            // 3. Intermediate stops when expanded
                            if isApproachingStopsExpanded {
                                ForEach(intermediateApproachingStops) { stop in
                                    renderLadderNode(stop: stop, isFirst: false, isLast: false)
                                        .id(stop.id)
                                }
                            }
                            
                            // 4. Commuter station and upcoming stops
                            ForEach(Array(activeAndUpcomingStops.enumerated()), id: \.element.id) { index, stop in
                                let isLastInBlock = index == activeAndUpcomingStops.count - 1
                                renderLadderNode(stop: stop, isFirst: false, isLast: isLastInBlock)
                                    .id(stop.isCurrent ? "ACTIVE_STATION_\(stop.id)" : stop.id)
                            }
                        } else {
                            // Standard / Close-range Approaching & Upcoming stops (starts at live oncoming train's current stop)
                            ForEach(Array(approachingAndUpcomingStops.enumerated()), id: \.element.id) { index, stop in
                                let isFirstInBlock = !hasPassedStops && index == 0
                                let isLastInBlock = index == approachingAndUpcomingStops.count - 1
                                renderLadderNode(stop: stop, isFirst: isFirstInBlock, isLast: isLastInBlock)
                                    .id(stop.isVehicleHere ? "VEHICLE_STOP_\(stop.id)" : (stop.isCurrent ? "ACTIVE_STATION_\(stop.id)" : stop.id))
                            }
                        }
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
    
    /// Normalizes transfer routes by stripping self-referential routes (route == current line)
    /// and express variants matching the trunk (e.g. 6 on 6X, 7 on 7X, F on FX). (Wave Pre-T.6)
    internal func displayedTransferRoutes(for stop: TrackStop) -> [String] {
        let currentTrunk = TransitRouteData.trunkRouteId(for: arrival.line)
        let lineTrunk = TransitRouteData.trunkRouteId(for: lineInfo.routeId)
        return stop.transferRoutes.filter { rId in
            let transferTrunk = TransitRouteData.trunkRouteId(for: rId)
            return rId != lineInfo.routeId &&
                   rId != arrival.line &&
                   transferTrunk != currentTrunk &&
                   transferTrunk != lineTrunk
        }
    }
    
    @ViewBuilder
    private func renderLadderNode(stop: TrackStop, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Track Stem & Station Bullet (Continuous edge-to-edge solid progression stroke)
            VStack(spacing: 0) {
                // Upper Stem
                Rectangle()
                    .fill(isFirst ? Color.clear : (stop.isPassed ? Color.secondary.opacity(0.25) : lineInfo.color))
                    .frame(width: 4)
                    .frame(minHeight: 18, maxHeight: .infinity)
                
                // Central Node
                ZStack {
                    if stop.isVehicleHere && !stop.isCurrent {
                        Circle()
                            .stroke(lineInfo.color.opacity(0.35), lineWidth: 4)
                            .frame(width: 24, height: 24)
                            .scaleEffect(isPulsing ? 1.25 : 0.95)
                            .opacity(isPulsing ? 1.0 : 0.5)
                        
                        Circle()
                            .fill(lineInfo.color)
                            .frame(width: 14, height: 14)
                        
                        Image(systemName: "tram.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    } else if stop.isCurrent {
                        Circle()
                            .stroke(Color(hex: "#FFB300"), lineWidth: 3)
                            .frame(width: 20, height: 20)
                            .scaleEffect(isPulsing ? 1.15 : 0.95)
                            .opacity(isPulsing ? 1.0 : 0.6)
                        
                        Circle()
                            .fill(Color(hex: "#FFB300"))
                            .frame(width: 10, height: 10)
                        
                        if stop.isVehicleHere {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.black)
                        }
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
                .frame(width: 24, height: 24)
                .background(
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(isFirst ? Color.clear : (stop.isPassed ? Color.secondary.opacity(0.25) : lineInfo.color))
                            .frame(width: 4, height: 12)
                        Rectangle()
                            .fill(isLast ? Color.clear : (stop.isPassed && !stop.isCurrent && !stop.isVehicleHere ? Color.secondary.opacity(0.25) : lineInfo.color))
                            .frame(width: 4, height: 12)
                    }
                    .frame(width: 24, height: 24)
                )
                
                // Lower Stem
                Rectangle()
                    .fill(isLast ? Color.clear : (stop.isPassed && !stop.isCurrent && !stop.isVehicleHere ? Color.secondary.opacity(0.25) : lineInfo.color))
                    .frame(width: 4)
                    .frame(minHeight: 18, maxHeight: .infinity)
            }
            .frame(width: 24)
            
            // Stop Information
            Button {
                selectedStopForFocus = stop
                onFocusMap?(stop.coordinate)
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(stop.stopName)
                                .font(.system(size: (stop.isCurrent || stop.isVehicleHere) ? 14.5 : 13.5,
                                              weight: (stop.isCurrent || stop.isVehicleHere) ? .bold : .medium,
                                              design: .rounded))
                                .foregroundColor(stop.isPassed ? .secondary : .primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if stop.isVehicleHere && !stop.isCurrent {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 4, height: 4)
                                        .opacity(isPulsing ? 1.0 : 0.3)
                                    Text("TRAIN HERE")
                                        .font(.system(size: 8.0, weight: .black, design: .monospaced))
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(lineInfo.color)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            
                            if stop.isCurrent {
                                Text("YOU ARE HERE")
                                    .font(.system(size: 8.0, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 3.5)
                                    .padding(.vertical, 1.5)
                                    .background(Color(hex: "#FFB300"))
                                    .foregroundColor(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            } else if isFirst && arrival.isHoldingStation {
                                Text("HELD AT TERMINUS")
                                    .font(.system(size: 8.0, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 3.5)
                                    .padding(.vertical, 1.5)
                                    .background(Color(hex: "#FFB300").opacity(0.2))
                                    .foregroundColor(Color(hex: "#D97706"))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        
                        // Connecting Lines Badges (Wave PD.9 / Pre-T.6: Transfer Route Disambiguation & Express Variant Normalization)
                        let activeTransfers = displayedTransferRoutes(for: stop)
                        if !activeTransfers.isEmpty {
                            HStack(alignment: .center, spacing: 3.5) {
                                Text("⇄")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.75))
                                    .accessibilityHidden(true)
                                ForEach(activeTransfers.prefix(7), id: \.self) { rId in
                                    TransferRouteBadge(routeId: rId)
                                }
                            }
                            .padding(.top, 1)
                        }
                    }
                    
                    Spacer()
                    
                    // Mode-Aware ETA Indicator
                    if inspectionMode.isHistoricalReplay {
                        Text(stop.isCurrent ? "Departed" : "Passed")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    } else if inspectionMode == .scheduledRun {
                        if let wallTime = stop.scheduledWallTime {
                            Text(wallTime)
                                .font(.system(size: 11, weight: stop.isCurrent ? .bold : .medium, design: .monospaced))
                                .foregroundColor(stop.isCurrent ? Color(hex: "#FFB300") : .secondary)
                        } else if let eta = stop.estimatedMinutes {
                            Text("+\(eta)m")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(stop.isCurrent ? Color(hex: "#FFB300") : .secondary)
                        }
                    } else {
                        // .liveRun
                        if stop.isVehicleHere && !stop.isCurrent {
                            Text("Live")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(lineInfo.color)
                        } else if let eta = stop.estimatedMinutes {
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
        
        // 3. Fetch Stop Ladder & Synchronize Map Polyline (Wave PA.5 & Wave PB.3 & Wave PD.3)
        do {
            let rawLadder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
                routeId: arrival.line,
                directionId: directionId,
                currentStopId: currentStopId,
                currentArrivalMinutes: arrival.minutes,
                tappedCoordinate: currentStopCoordinate,
                referenceDepartureDate: arrival.arrivalDate
            )
            
            let ladder: [TrackStop]
            let vehicleLoc: (coordinate: CLLocationCoordinate2D, bearing: Double?)?
            
            switch inspectionMode {
            case .liveRun:
                ladder = TransitRealtimeService.shared.annotateLadderWithVehicle(
                    ladder: rawLadder,
                    arrival: arrival
                )
                vehicleLoc = TransitRealtimeService.shared.resolveVehicleLocation(
                    arrival: arrival,
                    ladder: ladder
                )
            case .historicalReplay:
                ladder = rawLadder.map { s in
                    TrackStop(
                        id: s.id,
                        stopId: s.stopId,
                        stopName: s.stopName,
                        coordinate: s.coordinate,
                        sequenceIndex: s.sequenceIndex,
                        isPassed: true,
                        isCurrent: s.isCurrent,
                        isTerminus: s.isTerminus,
                        estimatedMinutes: nil,
                        transferRoutes: s.transferRoutes,
                        isVehicleHere: false,
                        scheduledWallTime: s.scheduledWallTime
                    )
                }
                vehicleLoc = nil
            case .scheduledRun:
                ladder = rawLadder.map { s in
                    TrackStop(
                        id: s.id,
                        stopId: s.stopId,
                        stopName: s.stopName,
                        coordinate: s.coordinate,
                        sequenceIndex: s.sequenceIndex,
                        isPassed: false,
                        isCurrent: s.isCurrent,
                        isTerminus: s.isTerminus,
                        estimatedMinutes: s.estimatedMinutes,
                        transferRoutes: s.transferRoutes,
                        isVehicleHere: false,
                        scheduledWallTime: s.scheduledWallTime
                    )
                }
                vehicleLoc = nil
            }
            
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
            
            if let validStationCoord = stationCoord {
                let vehicleIdx = ladder.firstIndex(where: { $0.isVehicleHere })
                let currentIdx = ladder.firstIndex(where: { $0.isCurrent })
                let stopsAway: Int? = {
                    if let v = vehicleIdx, let c = currentIdx {
                        return max(0, c - v)
                    }
                    return nil
                }()
                
                let command = RouteInspectionCommand(
                    routeId: arrival.line,
                    lineName: lineInfo.name,
                    agencyColorHex: lineInfo.colorHex,
                    casingColorHex: lineInfo.casingColorHex,
                    modalClass: lineInfo.modalClass,
                    coordinates: polyline,
                    stationCoordinate: validStationCoord,
                    shouldFrameCamera: true,
                    vehicleCoordinate: (inspectionMode == .liveRun) ? vehicleLoc?.coordinate : nil,
                    vehicleBearing: (inspectionMode == .liveRun) ? vehicleLoc?.bearing : nil,
                    vehicleStatus: (inspectionMode == .liveRun) ? arrival.distanceDescription : (inspectionMode.isHistoricalReplay ? "Historical" : "Scheduled"),
                    stopsAway: stopsAway,
                    minutes: arrival.minutes
                )
                
                await MainActor.run {
                    self.stopLadder = ladder
                    self.resolvedVehicleCoordinate = (inspectionMode == .liveRun) ? vehicleLoc?.coordinate : nil
                    self.isLoadingLadder = false
                    self.onInspectRoute?(command)
                    
                    if inspectionMode == .liveRun && !polyline.isEmpty {
                        let session = LiveVehicleTrackingSession()
                        session.configure(polyline: polyline, arrival: arrival, ladder: ladder)
                        session.onVehicleFrame = self.onVehicleFrame
                        session.start()
                        self.trackingSession = session
                    }
                }
            } else {
                await MainActor.run {
                    self.stopLadder = ladder
                    self.resolvedVehicleCoordinate = (inspectionMode == .liveRun) ? vehicleLoc?.coordinate : nil
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
