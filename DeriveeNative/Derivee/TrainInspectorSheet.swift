import SwiftUI
import CoreLocation

/// Deep Train Inspector sub-sheet presenting the linear Track Thermometer, live vehicle occupancy
/// with diurnal crowd fallback, 15-minute dispatch slot regularity, platform car positioning,
/// and deterministic subterranean exit codes.
struct TrainInspectorSheet: View {
    let arrival: SpatialDatabaseManager.ArrivalInfo
    let currentStopId: String
    let currentStopName: String
    var onFocusMap: ((CLLocationCoordinate2D) -> Void)?
    
    @State private var stopLadder: [TrackStop] = []
    @State private var isLoadingLadder: Bool = true
    @State private var slotProfile: TripSlotProfileRecord? = nil
    @State private var crowdEstimate: CrowdDensityEstimate = CrowdDensityEstimate(level: .moderate, isLiveSensors: false)
    @State private var platformRecommendation: PlatformCarRecommendation = SubterraneanEgressEngine.resolveCarRecommendation(for: "")
    @State private var primaryExit: SubterraneanExitInfo = SubterraneanEgressEngine.resolvePrimaryExit(for: "")
    @State private var isPulsing: Bool = false
    @State private var selectedStopForFocus: TrackStop? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    private var lineInfo: TransitRouteData.LineInfo {
        TransitRouteData.lineInfo(for: arrival.line)
    }
    
    private var directionId: Int {
        let dir = (arrival.direction ?? "").uppercased()
        if dir.contains("DOWNTOWN") || dir.contains("SOUTH") || dir.contains("BROOKLYN") || dir.contains("OUTBOUND") {
            return 1
        }
        return 0
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Train Hero Header
                    renderHeroHeader()
                    
                    Divider()
                    
                    // 2. Platform Car Recommendation & Subterranean Exit Cards
                    renderPlatformAndExitSection()
                    
                    // 3. GTFS-RT Occupancy Status & Crowd Fallback
                    renderOccupancySection()
                    
                    // 4. 15-Minute Slot Regularity Card
                    renderRegularityCard()
                    
                    // 5. Track Thermometer (Linear Stop Progression Ladder)
                    renderTrackThermometerSection()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .background(Color(hex: "#F9F9F6").ignoresSafeArea())
            .navigationTitle("Train Inspector")
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
        .task {
            await loadInspectorData()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
    
    // MARK: - 1. Hero Header
    
    @ViewBuilder
    private func renderHeroHeader() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                TransitRouteBadge(routeId: arrival.line, lineInfo: lineInfo, size: .large)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(arrival.destination)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    
                    if let dir = arrival.direction {
                        Text(dir.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Arrival ETA Pill
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
                    }
                    
                    if let dist = arrival.distanceDescription {
                        Text(dist)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Trip Identifier & Live Status Row
            HStack(spacing: 8) {
                if let tripId = arrival.tripId {
                    HStack(spacing: 4) {
                        Image(systemName: "train.side.front.car")
                            .font(.system(size: 10))
                        Text(tripId.count > 16 ? "TRIP ...\(tripId.suffix(12))" : "TRIP \(tripId)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: "#10B981"))
                        .frame(width: 5, height: 5)
                    Text("REALTIME AVL")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#059669"))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: "#10B981").opacity(0.12))
                .clipShape(Capsule())
                
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
    
    // MARK: - 2. Platform Car Recommendation & Subterranean Exit
    
    @ViewBuilder
    private func renderPlatformAndExitSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PLATFORM EGRESS & SUBTERRANEAN ALIGNMENT")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // Platform Car Recommendation Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: platformRecommendation.position.systemImageName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "#D97706"))
                        Text(platformRecommendation.position.shortBadgeText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#92400E"))
                    }
                    
                    Text(platformRecommendation.specificCars)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#B45309"))
                    
                    Text(platformRecommendation.rationale)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Stylized Train Car Indicator
                    HStack(spacing: 2) {
                        ForEach(0..<8) { carIndex in
                            let isHighlighted: Bool = {
                                switch platformRecommendation.position {
                                case .front: return carIndex < 3
                                case .middle: return carIndex >= 3 && carIndex <= 5
                                case .rear: return carIndex > 5
                                }
                            }()
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isHighlighted ? Color(hex: "#FFB300") : Color.primary.opacity(0.12))
                                .frame(height: 6)
                                .shadow(color: isHighlighted ? Color(hex: "#FFB300").opacity(0.6) : .clear, radius: 2)
                        }
                    }
                    .padding(.top, 2)
                    
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.badge.clock.fill")
                            .font(.system(size: 9))
                        Text("Saves ~\(platformRecommendation.walkSavingsSeconds)s platform walk")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(Color(hex: "#059669"))
                    .padding(.top, 1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#FEF3C7").opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                // Deterministic Subterranean Exit Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "#2563EB"))
                        Text(primaryExit.exitCode)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#1E40AF"))
                    }
                    
                    Text(primaryExit.streetCorner)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(primaryExit.mezzanine)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        if primaryExit.isWheelchairAccessible {
                            HStack(spacing: 2) {
                                Image(systemName: "figure.roll")
                                    .font(.system(size: 9))
                                Text("Elevator ♿️")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#10B981").opacity(0.15))
                            .foregroundColor(Color(hex: "#047857"))
                            .clipShape(Capsule())
                        } else {
                            HStack(spacing: 2) {
                                Image(systemName: "figure.stairs")
                                    .font(.system(size: 9))
                                Text("Stairs Only")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#DBEAFE").opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    
    // MARK: - 3. GTFS-RT Occupancy & Crowd Fallback
    
    @ViewBuilder
    private func renderOccupancySection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CARRIAGE OCCUPANCY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(crowdEstimate.badgeTitle)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(crowdEstimate.isLiveSensors ? Color(hex: "#059669") : Color(hex: "#7C3AED"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((crowdEstimate.isLiveSensors ? Color(hex: "#10B981") : Color(hex: "#8B5CF6")).opacity(0.12))
                    .clipShape(Capsule())
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .fill(crowdEstimate.level.statusColor)
                        .frame(width: 10, height: 10)
                    
                    Text(crowdEstimate.level.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                
                // Multi-Carriage Visual Diagram
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        ForEach(0..<crowdEstimate.carriageLoads.count, id: \.self) { idx in
                            let load = crowdEstimate.carriageLoads[idx]
                            VStack(spacing: 2) {
                                GeometryReader { geo in
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.primary.opacity(0.08))
                                        
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(colorForLoad(load))
                                            .frame(height: geo.size.height * CGFloat(load))
                                    }
                                }
                                .frame(height: 24)
                                
                                Text("C\(idx + 1)")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    HStack {
                        Text("← Front of Train")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Rear of Train →")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
                
                Text(crowdEstimate.detailDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        }
    }
    
    private func colorForLoad(_ load: Double) -> Color {
        if load < 0.40 {
            return Color(hex: "#10B981") // Emerald
        } else if load < 0.70 {
            return Color(hex: "#F59E0B") // Amber
        } else if load < 0.90 {
            return Color(hex: "#EA580C") // Orange
        } else {
            return Color(hex: "#EF4444") // Red
        }
    }
    
    // MARK: - 4. 15-Minute Slot Regularity Card
    
    @ViewBuilder
    private func renderRegularityCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("15-MIN ORIGIN SLOT REGULARITY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let profile = slotProfile {
                    let range = TripSlotProfileRecord.slotRange(slotIndex: profile.originSlotIndex)
                    let startMin = range.startSec / 60
                    let endMin = range.endSec / 60
                    let startH = (startMin / 60) % 24
                    let startM = startMin % 60
                    let endH = (endMin / 60) % 24
                    let endM = endMin % 60
                    Text(String(format: "%02d:%02d–%02d:%02d SLOT", startH, startM, endH, endM))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#D97706"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#FFB300").opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            
            if let profile = slotProfile {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.1f%%", profile.regularityPct))
                            .font(.system(size: 26, weight: .black, design: .monospaced))
                            .foregroundColor(profile.regularityPct >= 85 ? Color(hex: "#10B981") : (profile.regularityPct >= 70 ? Color(hex: "#F59E0B") : Color(hex: "#EF4444")))
                        
                        Text("Dispatch Regularity")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(profile.regularityPct >= 85 ? "High Consistency" : "Moderate Variance")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(profile.regularityPct >= 85 ? Color(hex: "#059669") : Color(hex: "#B45309"))
                    }
                    
                    // Metric Gauges
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MEDIAN RUN")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("\(profile.medianDurationSec / 60)m \(profile.medianDurationSec % 60)s")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("P90 DURATION")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("\(profile.p90DurationSec / 60)m \(profile.p90DurationSec % 60)s")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OBSERVATIONS")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("\(profile.sampleCount) runs")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
            } else {
                HStack {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Baseline schedule active. Historical 15-minute slot calibration syncing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    
    // MARK: - 5. Track Thermometer (Linear Stop Ladder)
    
    @ViewBuilder
    private func renderTrackThermometerSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRACK THERMOMETER")
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
                VStack(spacing: 0) {
                    ForEach(Array(stopLadder.enumerated()), id: \.element.id) { index, stop in
                        renderThermometerNode(stop: stop, isFirst: index == 0, isLast: index == stopLadder.count - 1)
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
    private func renderThermometerNode(stop: TrackStop, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Track Stem & Node
            VStack(spacing: 0) {
                // Upper Stem
                Rectangle()
                    .fill(isFirst ? Color.clear : (stop.isPassed ? Color.secondary.opacity(0.25) : lineInfo.color))
                    .frame(width: 4, height: 18)
                
                // Central Station Bullet Node
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
    
    // MARK: - Actions & Data Loading
    
    private func synchronizeWithMap() {
        let coord = stopLadder.first(where: { $0.isCurrent })?.coordinate ??
                    CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        onFocusMap?(coord)
        dismiss()
    }
    
    private func loadInspectorData() async {
        isLoadingLadder = true
        
        // 1. Resolve Subterranean Exit & Platform Car recommendations
        primaryExit = SubterraneanEgressEngine.resolvePrimaryExit(for: currentStopId, stationName: currentStopName)
        platformRecommendation = SubterraneanEgressEngine.resolveCarRecommendation(for: currentStopId, routeId: arrival.line)
        
        // 2. Resolve Occupancy & Crowd Estimate
        crowdEstimate = CrowdDensityEstimate.resolve(
            gtfsOccupancy: nil,
            occupancyPercentage: nil,
            date: arrival.arrivalDate
        )
        
        // 3. Fetch 15-Minute Slot Profile Record
        let slotIdx = TripSlotProfileRecord.slotIndex(for: arrival.arrivalDate)
        let dayType = TripSlotProfileRecord.dayType(for: arrival.arrivalDate)
        slotProfile = try? await TransitDatabaseEngine.shared.fetchTripSlotProfile(
            routeId: arrival.line,
            directionId: directionId,
            stopId: currentStopId,
            slotIndex: slotIdx,
            dayType: dayType
        )
        
        // 4. Fetch Ordered Track Stop Ladder
        do {
            let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
                routeId: arrival.line,
                directionId: directionId,
                currentStopId: currentStopId,
                currentArrivalMinutes: arrival.minutes
            )
            await MainActor.run {
                self.stopLadder = ladder
                self.isLoadingLadder = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingLadder = false
            }
        }
    }
}
