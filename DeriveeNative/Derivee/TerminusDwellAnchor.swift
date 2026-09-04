//
//  TerminusDwellAnchor.swift
//  Derivee
//
//  Implements the Terminal Origin Dwell Anchor and Anti-Ghost Movement Engine
//  specified in Research Doc 17 (§3 & §4).
//

import Foundation
import CoreLocation

/// Telemetry and visual states for consist progression along transit geometry.
public enum ConsistVisualState: String, Sendable, Codable {
    case boardingTerminal      // Consist staged at terminal bumper block within boarding window
    case stoppedInStation      // Consist stopped at intermediate platform
    case holdingStation        // Departure delayed > 120s; train held at platform/terminal
    case transitingNominal     // Nominal inter-station transit (0 < lambda < 0.85)
    case approachingStation    // Signal approach circuit entered (0.85 <= lambda < 0.995)
    case holdingMidTunnel      // Mid-tunnel signal hold clamp (lambda = 0.85)
    case telemetryStale        // Telemetry feed timestamp exceeds 90s threshold
}

/// Dwell evaluation state for an active or scheduled consist.
public struct ConsistDwellState: Sendable, Equatable {
    /// Normalized linear progress along geometry [0.0, 1.0]. Strictly 0.0 during terminal origin dwell.
    public let linearProgress: Double
    
    /// Visual state classification per Doc 17.
    public let visualState: ConsistVisualState
    
    /// True if departure is delayed > 120s past scheduled departure while in STOPPED_AT.
    public let isHolding: Bool
    
    /// Seconds elapsed past scheduled departure time (signed, positive = overdue).
    public let dwellDelaySeconds: Double
    
    /// True if the consist is confirmed dwelling at origin terminal.
    public let isDwellingAtOrigin: Bool
    
    public init(
        linearProgress: Double,
        visualState: ConsistVisualState,
        isHolding: Bool,
        dwellDelaySeconds: Double,
        isDwellingAtOrigin: Bool
    ) {
        self.linearProgress = linearProgress
        self.visualState = visualState
        self.isHolding = isHolding
        self.dwellDelaySeconds = dwellDelaySeconds
        self.isDwellingAtOrigin = isDwellingAtOrigin
    }
    
    /// Returns the disambiguated distance / dwell description for a given stop index in the sequence.
    public func displayDistance(isOriginStop: Bool, isAssigned: Bool) -> String {
        if isHolding {
            return isOriginStop ? "Holding at Station" : "Held at Terminus"
        }
        
        if isDwellingAtOrigin {
            if isOriginStop {
                return (visualState == .boardingTerminal || dwellDelaySeconds >= 0) ? "Boarding" : (isAssigned ? "At Terminus" : "Scheduled")
            } else {
                return isAssigned ? "At Terminus" : "Scheduled"
            }
        }
        
        return isAssigned ? "Approaching" : "Scheduled"
    }
}

/// Algorithmic engine for terminal dwell suppression and anti-ghost movement.
public enum TerminusDwellAnchor {
    /// Station hold threshold in seconds before transitioning to HOLDING_STATION (Doc 17 §4: 120.0s).
    public static let stationHoldThresholdSeconds: Double = 120.0
    
    /// Evaluates consist telemetry to enforce the terminal origin dwell anchor.
    ///
    /// - Parameters:
    ///   - isAssigned: True if ATS has assigned a physical train to this trip (nyctTripDescriptor.is_assigned).
    ///   - firstStopSequence: Stop sequence of the first stop in the trip's updates (1 = origin terminal).
    ///   - isVehicleStoppedAt: True if vehicle position status is STOPPED_AT (or stopped at station).
    ///   - isVehicleInTransit: True if vehicle position status is IN_TRANSIT_TO or sequence > 1.
    ///   - hasVehicleTelemetry: True if active VehiclePosition telemetry matched for this trip.
    ///   - departureEpoch: Scheduled or estimated departure timestamp in seconds since epoch.
    ///   - nowEpoch: Current reference timestamp in seconds since epoch.
    /// - Returns: Evaluated `ConsistDwellState` with clamped linear progress $\lambda \equiv 0.0$.
    public static func evaluateDwell(
        isAssigned: Bool,
        firstStopSequence: UInt32,
        isVehicleStoppedAt: Bool,
        isVehicleInTransit: Bool,
        hasVehicleTelemetry: Bool,
        departureEpoch: Int64,
        nowEpoch: Int64
    ) -> ConsistDwellState {
        // Inter-station transit clears terminal dwell immediately
        if isVehicleInTransit || firstStopSequence > 1 {
            return ConsistDwellState(
                linearProgress: 0.5,
                visualState: .transitingNominal,
                isHolding: false,
                dwellDelaySeconds: 0.0,
                isDwellingAtOrigin: false
            )
        }
        
        let dwellDelay = Double(nowEpoch - departureEpoch)
        
        // 1. Vehicle position telemetry present
        if hasVehicleTelemetry {
            if isVehicleStoppedAt {
                let isHolding = (dwellDelay > stationHoldThresholdSeconds)
                let visualState: ConsistVisualState = isHolding ? .holdingStation : ((dwellDelay >= 0) ? .boardingTerminal : .stoppedInStation)
                
                return ConsistDwellState(
                    linearProgress: 0.0, // Strictly clamped lambda ≡ 0.0 per Doc 17 §4
                    visualState: visualState,
                    isHolding: isHolding,
                    dwellDelaySeconds: dwellDelay,
                    isDwellingAtOrigin: true
                )
            } else {
                // Vehicle telemetry present but not stopped at station (e.g. INCOMING_AT entering platform)
                return ConsistDwellState(
                    linearProgress: 0.9,
                    visualState: .approachingStation,
                    isHolding: false,
                    dwellDelaySeconds: dwellDelay,
                    isDwellingAtOrigin: false
                )
            }
        }
        
        // 2. Fallback when no active vehicle telemetry: evaluate schedule departure window
        if departureEpoch > nowEpoch {
            // Scheduled departure is in the future
            return ConsistDwellState(
                linearProgress: 0.0,
                visualState: .stoppedInStation,
                isHolding: false,
                dwellDelaySeconds: dwellDelay,
                isDwellingAtOrigin: true
            )
        } else if dwellDelay <= 60.0 {
            // Within 60s of departure window without vehicle movement
            return ConsistDwellState(
                linearProgress: 0.0,
                visualState: .boardingTerminal,
                isHolding: false,
                dwellDelaySeconds: dwellDelay,
                isDwellingAtOrigin: true
            )
        }
        
        return ConsistDwellState(
            linearProgress: 0.1,
            visualState: .transitingNominal,
            isHolding: false,
            dwellDelaySeconds: dwellDelay,
            isDwellingAtOrigin: false
        )
    }
}
