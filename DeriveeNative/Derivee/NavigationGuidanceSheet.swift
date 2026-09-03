import SwiftUI

/// Unified 3-tier multimodal navigation bottom sheet (Wave N-D.5).
/// Coordinates active trip guidance across the three standardized ergonomic detents:
/// - 15% (`peek`): Glanceable next upcoming maneuver banner with minimal map occlusion.
/// - 50% (`half`): Step-by-step turn-by-turn guidance and leg timeline with car positioning and exits.
/// - 90% (`expanded`): Full-screen expanded route alternatives and timetable comparison.
/// Preserves the floating hero map canvas via background interaction and anchors
/// primary actions (`Start Journey`, `Reroute`, `Unlock Bike`) in the lower-third thumb zone.
public struct NavigationGuidanceSheet: View {
    public let itinerary: JourneyItinerary
    public var alternatives: [JourneyItinerary]
    public var navigationSession: ActiveWalkingNavigationSession?
    public var cyclingSession: ActiveCyclingNavigationSession?
    public var navigationManager: MultimodalTripNavigationManager?
    
    @Binding public var selectedDetent: PresentationDetent
    @State public var currentLegIndex: Int
    
    public var onSelectAlternative: ((JourneyItinerary) -> Void)?
    public var onFocusLeg: ((JourneyLeg) -> Void)?
    public var onUnlockBike: ((JourneyLeg) -> Void)?
    public var onReroute: (() -> Void)?
    public var onEndJourney: (() -> Void)?
    
    public init(
        itinerary: JourneyItinerary,
        alternatives: [JourneyItinerary] = [],
        selectedDetent: Binding<PresentationDetent>,
        initialLegIndex: Int = 0,
        navigationSession: ActiveWalkingNavigationSession? = nil,
        cyclingSession: ActiveCyclingNavigationSession? = nil,
        navigationManager: MultimodalTripNavigationManager? = nil,
        onSelectAlternative: ((JourneyItinerary) -> Void)? = nil,
        onFocusLeg: ((JourneyLeg) -> Void)? = nil,
        onUnlockBike: ((JourneyLeg) -> Void)? = nil,
        onReroute: (() -> Void)? = nil,
        onEndJourney: (() -> Void)? = nil
    ) {
        self.itinerary = itinerary
        self.alternatives = alternatives
        self._selectedDetent = selectedDetent
        self._currentLegIndex = State(initialValue: initialLegIndex)
        self.navigationSession = navigationSession
        self.cyclingSession = cyclingSession
        self.navigationManager = navigationManager
        self.onSelectAlternative = onSelectAlternative
        self.onFocusLeg = onFocusLeg
        self.onUnlockBike = onUnlockBike
        self.onReroute = onReroute
        self.onEndJourney = onEndJourney
    }
    
    public var body: some View {
        Group {
            if isPeekDetent {
                peekContentView
            } else if isExpandedDetent {
                expandedContentView
            } else {
                halfContentView
            }
        }
        .standardNavigationDetents(
            selectedDetent: $selectedDetent,
            interactiveUpThrough: NavigationSheetDetent.half.presentationDetent
        )
        .onChange(of: currentLegIndex) { _, newIndex in
            if newIndex >= 0 && newIndex < itinerary.legs.count {
                onFocusLeg?(itinerary.legs[newIndex])
            }
        }
    }
    
    // MARK: - Detent Checks
    
    private var isPeekDetent: Bool {
        selectedDetent == NavigationSheetDetent.peek.presentationDetent
    }
    
    private var isExpandedDetent: Bool {
        selectedDetent == NavigationSheetDetent.expanded.presentationDetent
    }
    
    private var activeLeg: JourneyLeg? {
        guard !itinerary.legs.isEmpty else { return nil }
        let safeIndex = max(0, min(currentLegIndex, itinerary.legs.count - 1))
        return itinerary.legs[safeIndex]
    }
    
    private var activeNaturalCue: NaturalGuidanceCue? {
        if let session = navigationSession {
            return session.currentCue
        }
        guard let leg = activeLeg, leg.mode == .walk else { return nil }
        if let anchor = leg.landmarkAnchors.first {
            let hasSignal = anchor.streetName?.localizedCaseInsensitiveContains("Avenue") == true ||
                            anchor.streetName?.localizedCaseInsensitiveContains("Broadway") == true
            return NaturalWalkingGuidanceEngine.shared.synthesizeDynamicCue(
                anchor: anchor,
                distanceMeters: Double(anchor.distanceMeters),
                hasTrafficSignal: hasSignal,
                isGridTopology: true,
                exitCode: leg.exitCode
            )
        }
        return nil
    }
    
    // MARK: - 15% Detent: Collapsed Peek View
    
    @ViewBuilder
    private var peekContentView: some View {
        VStack(spacing: 0) {
            if let leg = activeLeg {
                NavigationCollapsedPeekView(
                    leg: leg,
                    totalDurationFormatted: itinerary.formattedDuration,
                    arrivalTimeFormatted: itinerary.formattedArrivalTime,
                    naturalCue: activeNaturalCue,
                    recoveryPlan: navigationManager?.activeRecoveryPlan,
                    onExpandToHalf: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedDetent = NavigationSheetDetent.half.presentationDetent
                        }
                    },
                    onQuickAction: {
                        handlePrimaryAction()
                    },
                    onAcceptRecoveryOption: { option in
                        navigationManager?.acceptRecoveryOption(option)
                    }
                )
            }
            
            Spacer(minLength: 0)
        }
        .background(Color.white)
    }
    
    // MARK: - 50% Detent: Half-Screen Guidance View
    
    @ViewBuilder
    private var halfContentView: some View {
        VStack(spacing: 0) {
            // Header Bar
            halfHeaderBar
            
            Divider()
            
            // Dedicated High-Contrast Cycling HUD when active step is a bike leg
            if let leg = activeLeg, (leg.mode == .bikeShare || leg.mode == .personalBike) {
                cyclingHUDSection(for: leg)
            }
            
            // Scrollable Step Timeline
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let plan = navigationManager?.activeRecoveryPlan {
                        DynamicRecoveryCardView(
                            plan: plan,
                            onAcceptOption: { option in
                                navigationManager?.acceptRecoveryOption(option)
                            },
                            onDismiss: {
                                navigationManager?.dismissRecoveryPlan()
                            }
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(itinerary.legs.enumerated()), id: \.element.id) { index, leg in
                            legTimelineRow(leg: leg, index: index, isLast: index == itinerary.legs.count - 1)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(Color(hex: "#F9F9F6"))
            
            // Anchored Lower-Third Thumb-Zone Action Bar
            currentThumbActionBar
        }
        .background(Color.white)
    }
    
    @ViewBuilder
    private func cyclingHUDSection(for leg: JourneyLeg) -> some View {
        let meta = leg.bikeMetadata
        let session = cyclingSession
        
        CyclingHUDView(
            maneuver: session?.currentManeuver ?? meta?.nextManeuver ?? .turnLeft,
            distanceMeters: session?.currentDistanceMeters ?? meta?.nextManeuverDistanceMeters ?? 140,
            streetName: session?.currentStreetName ?? leg.destinationName,
            infrastructureType: session?.infrastructureType ?? meta?.cyclingInfrastructureType ?? .protectedBikeTrack,
            destinationDockName: session?.destinationDockName ?? meta?.destinationStationName ?? leg.destinationName,
            availableDocksAtDest: session?.availableDocksAtDest ?? meta?.availableDocksAtDest ?? 8,
            batterySocPercent: session?.batterySocPercent ?? meta?.batterySocPercent,
            estimatedRangeMiles: session?.estimatedRangeMiles ?? meta?.estimatedRangeMiles,
            fallbackStationName: session?.fallbackStationName ?? meta?.fallbackStationName,
            fallbackExtraWalkMeters: session?.fallbackExtraWalkMeters ?? meta?.fallbackExtraWalkDistanceMeters,
            isHighContrastDark: true, // WCAG AAA Carbon Theme
            onUnlockBike: {
                onUnlockBike?(leg)
            },
            onSwitchToFallback: {
                session?.switchToFallbackStation()
            },
            onAcceptAutoReroute: {
                session?.acceptAutoReroute()
            },
            onReroute: {
                onReroute?()
            },
            onEndRide: {
                session?.endCycling()
                onEndJourney?()
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - 90% Detent: Full-Screen Expanded Alternatives View
    
    @ViewBuilder
    private var expandedContentView: some View {
        VStack(spacing: 0) {
            // Header Bar
            expandedHeaderBar
            
            Divider()
            
            // Alternatives List
            ScrollView {
                VStack(spacing: 12) {
                    if let plan = navigationManager?.activeRecoveryPlan {
                        DynamicRecoveryCardView(
                            plan: plan,
                            onAcceptOption: { option in
                                navigationManager?.acceptRecoveryOption(option)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedDetent = NavigationSheetDetent.half.presentationDetent
                                }
                            },
                            onDismiss: {
                                navigationManager?.dismissRecoveryPlan()
                            }
                        )
                    }
                    
                    if !alternatives.isEmpty {
                        ForEach(alternatives) { alt in
                            RouteComparisonCardView(
                                itinerary: alt,
                                isSelected: alt.id == itinerary.id,
                                showConfidenceBand: true,
                                onSelect: {
                                    onSelectAlternative?(alt)
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        selectedDetent = NavigationSheetDetent.half.presentationDetent
                                    }
                                }
                            )
                        }
                    } else {
                        // Current Itinerary Details if no alternative list
                        RouteLegDetailView(
                            itinerary: itinerary,
                            activeLegIndex: currentLegIndex,
                            onClose: nil,
                            onSelectLeg: { idx in
                                currentLegIndex = idx
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "#F9F9F6"))
            
            // Anchored Thumb Action Bar
            ThumbZoneActionBar(
                primary: .custom(
                    title: "Resume Guidance",
                    icon: "location.fill",
                    backgroundColor: Color(hex: "#FFB300"),
                    foregroundColor: Color(hex: "#0F172A"),
                    action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedDetent = NavigationSheetDetent.half.presentationDetent
                        }
                    }
                ),
                secondary: .endJourney {
                    onEndJourney?()
                }
            )
        }
        .background(Color.white)
    }
    
    // MARK: - Header Bars
    
    @ViewBuilder
    private var halfHeaderBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(itinerary.profile.displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F172A"))
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(itinerary.formattedDuration)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                Text("Arrives \(itinerary.formattedArrivalTime) (\(itinerary.formattedConfidenceInterval))")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "#B45309"))
            }
            
            Spacer()
            
            ConfidenceBadgeView(tier: itinerary.confidenceTier, size: .regular)
            
            Button {
                onEndJourney?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white)
    }
    
    @ViewBuilder
    private var expandedHeaderBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Route Alternatives & Timetables")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#0F172A"))
                
                Text("Select an itinerary to switch routes")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedDetent = NavigationSheetDetent.half.presentationDetent
                }
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white)
    }
    
    // MARK: - Lower-Third Thumb Action Bar
    
    @ViewBuilder
    private var currentThumbActionBar: some View {
        if let leg = activeLeg, leg.mode == .bikeShare {
            ThumbZoneActionBar(
                primary: .unlockBike(
                    batterySoc: leg.bikeMetadata?.batterySocPercent,
                    dockInfo: leg.bikeMetadata?.dockGatingRisk.title,
                    action: {
                        handlePrimaryAction()
                    }
                ),
                secondary: .alternatives {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedDetent = NavigationSheetDetent.expanded.presentationDetent
                    }
                }
            )
        } else {
            ThumbZoneActionBar(
                primary: .reroute(
                    title: "Reroute",
                    action: {
                        handlePrimaryAction()
                    }
                ),
                secondary: .alternatives {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedDetent = NavigationSheetDetent.expanded.presentationDetent
                    }
                }
            )
        }
    }
    
    private func handlePrimaryAction() {
        guard let leg = activeLeg else { return }
        if leg.mode == .bikeShare {
            onUnlockBike?(leg)
        } else {
            onReroute?()
        }
    }
    
    // MARK: - Leg Timeline Row (Delegated to Helper)
    
    @ViewBuilder
    private func legTimelineRow(leg: JourneyLeg, index: Int, isLast: Bool) -> some View {
        let isActive = currentLegIndex == index
        
        Button {
            currentLegIndex = index
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    timelineNode(for: leg, isActive: isActive)
                    
                    if !isLast {
                        Rectangle()
                            .fill(timelineLineColor(for: leg))
                            .frame(width: 2)
                            .frame(minHeight: 40)
                    }
                }
                .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Text(leg.originName)
                                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "#0F172A"))
                            
                            if isActive {
                                Text("Current Step")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "#92400E"))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: "#FFB300").opacity(0.25))
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Spacer()
                        
                        Text(JourneyItinerary.formatSecondsToClock(leg.departureTimeSec))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    legDetails(for: leg)
                    
                    if isLast {
                        HStack {
                            Text(leg.destinationName)
                                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "#0F172A"))
                            
                            Spacer()
                            
                            Text(JourneyItinerary.formatSecondsToClock(leg.arrivalTimeSec))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.bottom, isLast ? 8 : 20)
            }
            .padding(.horizontal, isActive ? 8 : 0)
            .padding(.vertical, isActive ? 6 : 0)
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "#FFB300").opacity(0.08))
                    : nil
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func timelineNode(for leg: JourneyLeg, isActive: Bool) -> some View {
        ZStack {
            if isActive {
                Circle()
                    .strokeBorder(Color(hex: "#FFB300"), lineWidth: 2.5)
                    .frame(width: 28, height: 28)
            }
            
            Circle()
                .fill(leg.lineInfo?.color ?? (leg.mode == .bikeShare ? Color(hex: "#0284C7") : Color.secondary.opacity(0.25)))
                .frame(width: 22, height: 22)
            
            Image(systemName: leg.mode.systemIcon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(leg.lineInfo != nil || leg.mode == .bikeShare ? .white : Color.primary.opacity(0.8))
        }
    }
    
    private func timelineLineColor(for leg: JourneyLeg) -> Color {
        if let line = leg.lineInfo {
            return line.color.opacity(0.5)
        }
        return leg.mode == .bikeShare ? Color(hex: "#0284C7").opacity(0.4) : Color.secondary.opacity(0.2)
    }
    
    @ViewBuilder
    private func legDetails(for leg: JourneyLeg) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch leg.mode {
            case .walk:
                Text("Walk \(leg.formattedDistance) (\(leg.formattedDuration))")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                
                if !leg.landmarkAnchors.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if let cue = activeNaturalCue, leg.id == activeLeg?.id {
                            HStack(spacing: 6) {
                                Image(systemName: cue.iconName)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(cue.intersectionControl == .trafficSignal ? Color(hex: "#D97706") : Color(hex: "#059669"))
                                
                                Text(cue.primaryHeadline)
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "#0F172A"))
                                
                                if let badge = cue.promptBadgeText {
                                    Text(badge)
                                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(hex: "#92400E"))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color(hex: "#FFB300").opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#FFB300").opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        
                        if leg.distanceMeters >= 250,
                           let reassurance = NaturalWalkingGuidanceEngine.shared.synthesizeStraightReassurance(
                                distanceRemainingMeters: Double(leg.distanceMeters) * 0.6,
                                totalSegmentMeters: Double(leg.distanceMeters),
                                prominentLandmark: leg.landmarkAnchors.first?.landmarkName,
                                isGridTopology: true
                           ) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(hex: "#047857"))
                                Text("\(reassurance.primaryHeadline) • \(reassurance.secondaryContext)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(Color(hex: "#065F46"))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: "#D1FAE5").opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        
                        ForEach(leg.landmarkAnchors) { anchor in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: anchor.maneuver.systemIcon)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(anchor.isShaded ? Color(hex: "#047857") : Color(hex: "#D97706"))
                                    .frame(width: 14)
                                    .padding(.top, 2)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(anchor.prompt)
                                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color(hex: "#0F172A"))
                                    
                                    HStack(spacing: 5) {
                                        HStack(spacing: 3) {
                                            Image(systemName: anchor.category.iconName)
                                                .font(.system(size: 9, weight: .bold))
                                            Text(anchor.landmarkName)
                                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                        }
                                        .foregroundColor(Color(hex: "#065F46"))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: "#D1FAE5"))
                                        .clipShape(Capsule())
                                        
                                        if anchor.isShaded, let shade = anchor.shadePercentage {
                                            HStack(spacing: 3) {
                                                Image(systemName: "tree.fill")
                                                    .font(.system(size: 9, weight: .bold))
                                                Text("\(Int(shade))% Shaded")
                                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                            }
                                            .foregroundColor(Color(hex: "#047857"))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(hex: "#D1FAE5").opacity(0.6))
                                            .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                } else if let cue = leg.landmarkCue {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#059669"))
                        Text(cue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#065F46"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#D1FAE5"))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
                if let comfort = leg.thermalComfortSummary {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#059669"))
                        Text(comfort)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#065F46"))
                    }
                    .padding(.top, 2)
                }
                
            case .subway, .bus, .lightRail, .ferry:
                if let routeId = leg.routeId {
                    HStack(spacing: 6) {
                        TransitRouteBadge(routeId: routeId, lineInfo: leg.lineInfo, size: .regular)
                        if let headsign = leg.headsign {
                            Text(headsign)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#1E293B"))
                        }
                    }
                }
                
                if let car = leg.recommendedCarPosition {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.and.right.square.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#D97706"))
                        Text(car)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#92400E"))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color(hex: "#FEF3C7"))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
                if let exit = leg.exitCode {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#2563EB"))
                        Text(exit)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#1E40AF"))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color(hex: "#DBEAFE"))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
            case .bikeShare, .personalBike:
                Text("Ride \(leg.formattedDistance) (\(leg.formattedDuration))")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#0369A1"))
                
                if let meta = leg.bikeMetadata {
                    HStack(spacing: 8) {
                        DockAvailabilityBadgeView(
                            availableDocks: meta.availableDocksAtDest,
                            fallbackStationName: meta.fallbackStationName,
                            isCompact: true
                        )
                        
                        if meta.isEBike, let soc = meta.batterySocPercent {
                            EBikeBatterySOCPill(
                                batterySocPercent: soc,
                                estimatedRangeMiles: meta.estimatedRangeMiles
                            )
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
