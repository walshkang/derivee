import Foundation
import CoreLocation

/// Generates instant multimodal recovery plans upon detected connection misses (Wave N-D.8).
/// Synthesizes next-departure waits, micro-mobility overrides, parallel surface routes, and walking fallbacks.
public struct DynamicRecoveryEngine: Sendable {
    
    public init() {}
    
    /// Generates a prioritized `DynamicRecoveryPlan` with 1-tap alternatives for a missed connection.
    ///
    /// - Parameters:
    ///   - event: The detected missed connection event.
    ///   - activeItinerary: The currently executing journey itinerary.
    ///   - availableBikesAtNearbyDock: Optional count of real-time GBFS bikes at nearest dock.
    ///   - isEBikeAvailable: Whether an e-bike is docked nearby.
    ///   - batterySoc: Optional e-bike battery charge %.
    /// - Returns: A complete `DynamicRecoveryPlan` ready for presentation in the 1-tap recovery card.
    public func generateRecoveryPlan(
        for event: MissedConnectionEvent,
        activeItinerary: JourneyItinerary,
        availableBikesAtNearbyDock: Int = 9,
        isEBikeAvailable: Bool = true,
        batterySoc: Int = 86
    ) -> DynamicRecoveryPlan {
        var options: [DynamicRecoveryOption] = []
        
        let missedLeg = event.missedLeg
        let routeName = missedLeg.routeId ?? "Transit"
        let stationName = event.stationName
        
        // 1. Next Transit Departure Option (Primary by default on rail/subway)
        let headwaySeconds: UInt32 = missedLeg.mode == .subway ? 240 : 360 // 4m subway, 6m bus
        let headwayMinutes = Int(headwaySeconds / 60)
        let nextTransitItinerary = buildNextDepartureItinerary(
            from: activeItinerary,
            missedLegIndex: event.legIndex,
            delaySeconds: headwaySeconds
        )
        
        let nextDepartureOption = DynamicRecoveryOption(
            type: .nextTransitDeparture,
            title: "Next \(routeName) Train in \(headwayMinutes) min",
            subtitle: "Board at \(stationName) • +\(headwayMinutes)m total travel time",
            deltaMinutes: headwayMinutes,
            deltaTransfers: 0,
            mode: missedLeg.mode,
            routeBadge: missedLeg.routeId,
            routeColorHex: missedLeg.lineInfo?.colorHex ?? "#FFB300",
            estimatedArrivalSec: nextTransitItinerary.arrivalTimeSec,
            isPrimaryRecommended: true,
            recoveryItinerary: nextTransitItinerary
        )
        options.append(nextDepartureOption)
        
        // 2. Micro-Mobility / Citi Bike Fallback Option
        let remainingDistanceMeters = calculateRemainingDistance(from: activeItinerary, startingAt: event.legIndex)
        let bikeSpeedMps = 4.0 // ~14.4 km/h urban cycling
        let bikeRideDurationSec = UInt32(Double(remainingDistanceMeters) / bikeSpeedMps)
        let bikeTotalDurationSec = bikeRideDurationSec + 180 // 3m unlock/walk
        let bikeArrivalSec = event.scheduledDepartureSec + bikeTotalDurationSec
        let originalArrivalSec = activeItinerary.arrivalTimeSec
        let bikeDeltaMinutes = Int(Int64(bikeArrivalSec) - Int64(originalArrivalSec)) / 60
        
        let bikeItinerary = buildBikeFallbackItinerary(
            from: activeItinerary,
            missedLegIndex: event.legIndex,
            rideDurationSec: bikeRideDurationSec,
            distanceMeters: remainingDistanceMeters,
            batterySoc: batterySoc
        )
        
        let bikeRisk = GBFSDockGatingRisk.risk(forAvailableDocks: availableBikesAtNearbyDock)
        let bikeOption = DynamicRecoveryOption(
            type: .bikeShareFallback,
            title: "Switch to Citi Bike",
            subtitle: "Dock 90m away • Direct protected cycling path",
            deltaMinutes: bikeDeltaMinutes,
            deltaTransfers: -1,
            mode: .bikeShare,
            routeBadge: "BIKE",
            routeColorHex: "#007AFF",
            estimatedArrivalSec: bikeItinerary.arrivalTimeSec,
            isPrimaryRecommended: false,
            recoveryItinerary: bikeItinerary,
            dockRisk: bikeRisk,
            batterySocPercent: batterySoc
        )
        options.append(bikeOption)
        
        // 3. Direct Walk Fallback (if destination is under 1.6 km)
        if remainingDistanceMeters <= 1600 {
            let walkSpeedMps = 1.2
            let walkDurationSec = UInt32(Double(remainingDistanceMeters) / walkSpeedMps)
            let walkArrivalSec = event.scheduledDepartureSec + walkDurationSec
            let walkDeltaMinutes = Int(Int64(walkArrivalSec) - Int64(originalArrivalSec)) / 60
            
            let walkItinerary = buildWalkFallbackItinerary(
                from: activeItinerary,
                missedLegIndex: event.legIndex,
                walkDurationSec: walkDurationSec,
                distanceMeters: remainingDistanceMeters
            )
            
            let walkOption = DynamicRecoveryOption(
                type: .directWalk,
                title: "Walk Directly to Destination",
                subtitle: "\(Int(Double(remainingDistanceMeters) * 3.28084)) ft • No transit wait required",
                deltaMinutes: walkDeltaMinutes,
                deltaTransfers: -1,
                mode: .walk,
                routeBadge: nil,
                routeColorHex: "#64748B",
                estimatedArrivalSec: walkItinerary.arrivalTimeSec,
                isPrimaryRecommended: false,
                recoveryItinerary: walkItinerary
            )
            options.append(walkOption)
        }
        
        return DynamicRecoveryPlan(
            event: event,
            options: options
        )
    }
    
    // MARK: - Itinerary Splicing Helpers
    
    private func buildNextDepartureItinerary(
        from base: JourneyItinerary,
        missedLegIndex: Int,
        delaySeconds: UInt32
    ) -> JourneyItinerary {
        var updatedLegs: [JourneyLeg] = []
        var runningOffset: UInt32 = 0
        
        for (index, leg) in base.legs.enumerated() {
            if index < missedLegIndex {
                updatedLegs.append(leg)
            } else if index == missedLegIndex {
                runningOffset = delaySeconds
                let newDep = leg.departureTimeSec + delaySeconds
                let newArr = leg.arrivalTimeSec + delaySeconds
                let modifiedLeg = JourneyLeg(
                    id: UUID(),
                    mode: leg.mode,
                    originName: leg.originName,
                    destinationName: leg.destinationName,
                    departureTimeSec: newDep,
                    arrivalTimeSec: newArr,
                    durationSec: leg.durationSec,
                    distanceMeters: leg.distanceMeters,
                    routeId: leg.routeId,
                    headsign: leg.headsign,
                    stopCount: leg.stopCount,
                    lineInfo: leg.lineInfo,
                    confidenceTier: .verified,
                    disruption: leg.disruption,
                    bikeMetadata: leg.bikeMetadata,
                    isTransferWalk: leg.isTransferWalk,
                    landmarkCue: leg.landmarkCue,
                    landmarkAnchors: leg.landmarkAnchors,
                    exitCode: leg.exitCode,
                    recommendedCarPosition: leg.recommendedCarPosition
                )
                updatedLegs.append(modifiedLeg)
            } else {
                let newDep = leg.departureTimeSec + runningOffset
                let newArr = leg.arrivalTimeSec + runningOffset
                let modifiedLeg = JourneyLeg(
                    id: UUID(),
                    mode: leg.mode,
                    originName: leg.originName,
                    destinationName: leg.destinationName,
                    departureTimeSec: newDep,
                    arrivalTimeSec: newArr,
                    durationSec: leg.durationSec,
                    distanceMeters: leg.distanceMeters,
                    routeId: leg.routeId,
                    headsign: leg.headsign,
                    stopCount: leg.stopCount,
                    lineInfo: leg.lineInfo,
                    confidenceTier: leg.confidenceTier,
                    disruption: leg.disruption,
                    bikeMetadata: leg.bikeMetadata,
                    isTransferWalk: leg.isTransferWalk,
                    landmarkCue: leg.landmarkCue,
                    landmarkAnchors: leg.landmarkAnchors,
                    exitCode: leg.exitCode,
                    recommendedCarPosition: leg.recommendedCarPosition
                )
                updatedLegs.append(modifiedLeg)
            }
        }
        
        let newArrival = base.arrivalTimeSec + delaySeconds
        return JourneyItinerary(
            id: UUID(),
            profile: base.profile,
            departureTimeSec: base.departureTimeSec,
            arrivalTimeSec: newArrival,
            p10ArrivalSec: base.p10ArrivalSec + delaySeconds,
            p50ArrivalSec: base.p50ArrivalSec + delaySeconds,
            p90ArrivalSec: base.p90ArrivalSec + delaySeconds,
            totalCost: base.totalCost,
            legs: updatedLegs,
            confidenceTier: .verified
        )
    }
    
    private func buildBikeFallbackItinerary(
        from base: JourneyItinerary,
        missedLegIndex: Int,
        rideDurationSec: UInt32,
        distanceMeters: UInt32,
        batterySoc: Int
    ) -> JourneyItinerary {
        var priorLegs: [JourneyLeg] = []
        for index in 0..<missedLegIndex {
            priorLegs.append(base.legs[index])
        }
        
        let startDep = priorLegs.last?.arrivalTimeSec ?? base.departureTimeSec
        let arrivalSec = startDep + rideDurationSec + 120 // 2m dock parking
        
        let bikeMeta = BikeLegMetadata(
            originStationName: priorLegs.last?.destinationName ?? "Nearby Citi Bike Dock",
            destinationStationName: base.legs.last?.destinationName ?? "Destination Dock",
            availableBikesAtOrigin: 8,
            availableDocksAtDest: 12,
            isEBike: true,
            batterySocPercent: batterySoc,
            estimatedRangeMiles: Double(batterySoc) * 0.2,
            dockGatingRisk: .low,
            cyclingInfrastructureType: .protectedBikeTrack,
            nextManeuver: .turnLeft,
            nextManeuverDistanceMeters: 120
        )
        
        let bikeLeg = JourneyLeg(
            id: UUID(),
            mode: .bikeShare,
            originName: priorLegs.last?.destinationName ?? "Nearby Citi Bike Dock",
            destinationName: base.legs.last?.destinationName ?? "Destination",
            departureTimeSec: startDep,
            arrivalTimeSec: arrivalSec,
            durationSec: rideDurationSec,
            distanceMeters: distanceMeters,
            confidenceTier: .verified,
            bikeMetadata: bikeMeta
        )
        
        var legs = priorLegs
        legs.append(bikeLeg)
        
        return JourneyItinerary(
            id: UUID(),
            profile: .multiModalBikeRail,
            departureTimeSec: base.departureTimeSec,
            arrivalTimeSec: arrivalSec,
            p10ArrivalSec: arrivalSec > 60 ? arrivalSec - 60 : arrivalSec,
            p50ArrivalSec: arrivalSec,
            p90ArrivalSec: arrivalSec + 120,
            totalCost: base.totalCost,
            legs: legs,
            confidenceTier: .verified
        )
    }
    
    private func buildWalkFallbackItinerary(
        from base: JourneyItinerary,
        missedLegIndex: Int,
        walkDurationSec: UInt32,
        distanceMeters: UInt32
    ) -> JourneyItinerary {
        var priorLegs: [JourneyLeg] = []
        for index in 0..<missedLegIndex {
            priorLegs.append(base.legs[index])
        }
        
        let startDep = priorLegs.last?.arrivalTimeSec ?? base.departureTimeSec
        let arrivalSec = startDep + walkDurationSec
        
        let walkLeg = JourneyLeg(
            id: UUID(),
            mode: .walk,
            originName: priorLegs.last?.destinationName ?? "Current Location",
            destinationName: base.legs.last?.destinationName ?? "Destination",
            departureTimeSec: startDep,
            arrivalTimeSec: arrivalSec,
            durationSec: walkDurationSec,
            distanceMeters: distanceMeters,
            confidenceTier: .verified
        )
        
        var legs = priorLegs
        legs.append(walkLeg)
        
        return JourneyItinerary(
            id: UUID(),
            profile: .stepFree,
            departureTimeSec: base.departureTimeSec,
            arrivalTimeSec: arrivalSec,
            p10ArrivalSec: arrivalSec > 30 ? arrivalSec - 30 : arrivalSec,
            p50ArrivalSec: arrivalSec,
            p90ArrivalSec: arrivalSec + 60,
            totalCost: 0.0,
            legs: legs,
            confidenceTier: .verified
        )
    }
    
    private func calculateRemainingDistance(from base: JourneyItinerary, startingAt legIndex: Int) -> UInt32 {
        var distance: UInt32 = 0
        for index in legIndex..<base.legs.count {
            distance += base.legs[index].distanceMeters
        }
        return max(400, distance)
    }
}
