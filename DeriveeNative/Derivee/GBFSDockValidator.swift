import Foundation
import CoreLocation

public final class GBFSDockValidator: Sendable {
    public let databaseManager: GBFSDatabaseManager
    public let defaultStalenessThresholdSeconds: Double
    public let defaultMinBikes: Int
    public let defaultMinDocks: Int
    public let defaultFallbackRadiusMeters: Double
    public let defaultDiversionPenaltySeconds: Double
    
    public static let defaultWalkingSpeedMetersPerSec: Double = 1.2
    public static let defaultCyclingSpeedMetersPerSec: Double = 4.2
    
    public init(
        databaseManager: GBFSDatabaseManager = .shared,
        defaultStalenessThresholdSeconds: Double = 600.0,
        defaultMinBikes: Int = 2,
        defaultMinDocks: Int = 2,
        defaultFallbackRadiusMeters: Double = 300.0,
        defaultDiversionPenaltySeconds: Double = 120.0
    ) {
        self.databaseManager = databaseManager
        self.defaultStalenessThresholdSeconds = defaultStalenessThresholdSeconds
        self.defaultMinBikes = defaultMinBikes
        self.defaultMinDocks = defaultMinDocks
        self.defaultFallbackRadiusMeters = defaultFallbackRadiusMeters
        self.defaultDiversionPenaltySeconds = defaultDiversionPenaltySeconds
    }
    
    // MARK: - Origin Dock Gating (g_pick)
    
    public func validateOriginDock(
        stationId: String,
        preference: GBFSVehiclePreference = .anyBike,
        minBikes: Int? = nil,
        stalenessThreshold: Double? = nil,
        referenceDate: Date = Date()
    ) async throws -> GBFSDockGatingResult {
        let minRequiredBikes = minBikes ?? defaultMinBikes
        let maxStaleness = stalenessThreshold ?? defaultStalenessThresholdSeconds
        let nowEpoch = Int(referenceDate.timeIntervalSince1970)
        
        guard let station = try await databaseManager.fetchStation(by: stationId) else {
            return GBFSDockGatingResult(
                isValid: false,
                stationId: stationId,
                gatingType: .origin,
                rejectionReasons: [.stationNotFound],
                metrics: GBFSDockGatingResult.GatingMetrics()
            )
        }
        
        var reasons: [GBFSDockGatingResult.RejectionReason] = []
        let staleness = max(0, nowEpoch - station.lastReported)
        
        if !station.isInstalled {
            reasons.append(.notInstalled)
        }
        if !station.isRenting {
            reasons.append(.notRenting)
        }
        if staleness > Int(maxStaleness) {
            reasons.append(.dataStale)
        }
        
        switch preference {
        case .anyBike:
            if station.numBikesAvailable < minRequiredBikes {
                reasons.append(.insufficientBikes)
            }
        case .electricOnly:
            if station.numEbikesAvailable < minRequiredBikes {
                reasons.append(.insufficientEbikes)
            }
        case .standardOnly:
            if station.numStandardBikesAvailable < minRequiredBikes {
                reasons.append(.insufficientBikes)
            }
        }
        
        let metrics = GBFSDockGatingResult.GatingMetrics(
            availableBikes: station.numBikesAvailable,
            availableEbikes: station.numEbikesAvailable,
            availableDocks: station.numDocksAvailable,
            isInstalled: station.isInstalled,
            isRenting: station.isRenting,
            isReturning: station.isReturning,
            stalenessSeconds: staleness
        )
        
        return GBFSDockGatingResult(
            isValid: reasons.isEmpty,
            stationId: stationId,
            gatingType: .origin,
            rejectionReasons: reasons,
            metrics: metrics
        )
    }
    
    // MARK: - Destination Dock Gating (g_drop)
    
    public func validateDestinationDock(
        stationId: String,
        minDocks: Int? = nil,
        stalenessThreshold: Double? = nil,
        referenceDate: Date = Date()
    ) async throws -> GBFSDockGatingResult {
        let minRequiredDocks = minDocks ?? defaultMinDocks
        let maxStaleness = stalenessThreshold ?? defaultStalenessThresholdSeconds
        let nowEpoch = Int(referenceDate.timeIntervalSince1970)
        
        guard let station = try await databaseManager.fetchStation(by: stationId) else {
            return GBFSDockGatingResult(
                isValid: false,
                stationId: stationId,
                gatingType: .destination,
                rejectionReasons: [.stationNotFound],
                metrics: GBFSDockGatingResult.GatingMetrics()
            )
        }
        
        var reasons: [GBFSDockGatingResult.RejectionReason] = []
        let staleness = max(0, nowEpoch - station.lastReported)
        
        if !station.isInstalled {
            reasons.append(.notInstalled)
        }
        if !station.isReturning {
            reasons.append(.notReturning)
        }
        if staleness > Int(maxStaleness) {
            reasons.append(.dataStale)
        }
        if station.numDocksAvailable < minRequiredDocks {
            reasons.append(.insufficientDocks)
        }
        
        let metrics = GBFSDockGatingResult.GatingMetrics(
            availableBikes: station.numBikesAvailable,
            availableEbikes: station.numEbikesAvailable,
            availableDocks: station.numDocksAvailable,
            isInstalled: station.isInstalled,
            isRenting: station.isRenting,
            isReturning: station.isReturning,
            stalenessSeconds: staleness
        )
        
        return GBFSDockGatingResult(
            isValid: reasons.isEmpty,
            stationId: stationId,
            gatingType: .destination,
            rejectionReasons: reasons,
            metrics: metrics
        )
    }
    
    // MARK: - Composite Transfer Edge Gating (G(e) = g_pick * g_drop)
    
    public func evaluateTransferEdge(
        originStationId: String,
        destinationStationId: String,
        preference: GBFSVehiclePreference = .anyBike,
        minBikes: Int? = nil,
        minDocks: Int? = nil,
        stalenessThreshold: Double? = nil,
        referenceDate: Date = Date(),
        attemptFallbackIfDestinationGated: Bool = true,
        transitEntryCoordinate: CLLocationCoordinate2D? = nil
    ) async throws -> GBFSDockGatingResult {
        let pickResult = try await validateOriginDock(
            stationId: originStationId,
            preference: preference,
            minBikes: minBikes,
            stalenessThreshold: stalenessThreshold,
            referenceDate: referenceDate
        )
        
        let dropResult = try await validateDestinationDock(
            stationId: destinationStationId,
            minDocks: minDocks,
            stalenessThreshold: stalenessThreshold,
            referenceDate: referenceDate
        )
        
        if pickResult.isValid && dropResult.isValid {
            return GBFSDockGatingResult(
                isValid: true,
                stationId: destinationStationId,
                gatingType: .composite,
                rejectionReasons: [],
                metrics: dropResult.metrics
            )
        }
        
        var combinedReasons = pickResult.rejectionReasons + dropResult.rejectionReasons
        var fallbackStation: GBFSStation? = nil
        
        // If pickup is valid but destination failed due to dock capacity / return gating, attempt fallback
        if pickResult.isValid && !dropResult.isValid && attemptFallbackIfDestinationGated {
            if let originStation = try await databaseManager.fetchStation(by: originStationId),
               let targetDropStation = try await databaseManager.fetchStation(by: destinationStationId) {
                fallbackStation = try await resolveFallbackDropoffStation(
                    failedStation: targetDropStation,
                    originCoordinate: originStation.coordinate,
                    transitEntryCoordinate: transitEntryCoordinate,
                    preference: preference,
                    minDocks: minDocks,
                    stalenessThreshold: stalenessThreshold,
                    referenceDate: referenceDate
                )
            }
        }
        
        let isOverallValid = pickResult.isValid && (dropResult.isValid || fallbackStation != nil)
        
        return GBFSDockGatingResult(
            isValid: isOverallValid,
            stationId: destinationStationId,
            gatingType: .composite,
            rejectionReasons: isOverallValid ? [] : combinedReasons,
            metrics: dropResult.metrics,
            fallbackStation: fallbackStation
        )
    }
    
    // MARK: - Dynamic Fallback Dropoff Resolution for Capacity Exhaustion
    
    /// Finds the optimal operational alternative dropoff station within `maxFallbackRadiusMeters` (default: 300m)
    /// minimizing total leg time: cycling time + walking time to target/transit + diversion penalty (120s).
    public func resolveFallbackDropoffStation(
        failedStation: GBFSStation,
        originCoordinate: CLLocationCoordinate2D,
        transitEntryCoordinate: CLLocationCoordinate2D? = nil,
        preference: GBFSVehiclePreference = .anyBike,
        minDocks: Int? = nil,
        maxFallbackRadiusMeters: Double? = nil,
        diversionPenaltySeconds: Double? = nil,
        stalenessThreshold: Double? = nil,
        referenceDate: Date = Date()
    ) async throws -> GBFSStation? {
        let radius = maxFallbackRadiusMeters ?? defaultFallbackRadiusMeters
        let penalty = diversionPenaltySeconds ?? defaultDiversionPenaltySeconds
        let targetCoord = transitEntryCoordinate ?? failedStation.coordinate
        
        let candidateStations = try await databaseManager.fetchCandidateStations(
            near: failedStation.coordinate,
            radiusMeters: radius,
            preference: preference
        )
        
        var bestCandidate: GBFSStation? = nil
        var lowestCost: Double = .infinity
        
        for candidate in candidateStations {
            guard candidate.stationId != failedStation.stationId else { continue }
            
            let validation = try await validateDestinationDock(
                stationId: candidate.stationId,
                minDocks: minDocks,
                stalenessThreshold: stalenessThreshold,
                referenceDate: referenceDate
            )
            
            guard validation.isValid else { continue }
            
            // Distance from pickup to this fallback station
            let cyclingDist = calculateFlatEarthDistance(from: originCoordinate, to: candidate.coordinate)
            let cyclingDuration = cyclingDist / Self.defaultCyclingSpeedMetersPerSec
            
            // Walking distance from fallback station to transit entry (or original destination)
            let walkDist = calculateFlatEarthDistance(from: candidate.coordinate, to: targetCoord)
            let walkDuration = walkDist / Self.defaultWalkingSpeedMetersPerSec
            
            let totalCost = cyclingDuration + walkDuration + penalty
            if totalCost < lowestCost {
                lowestCost = totalCost
                bestCandidate = candidate
            }
        }
        
        return bestCandidate
    }
    
    private func calculateFlatEarthDistance(from c1: CLLocationCoordinate2D, to c2: CLLocationCoordinate2D) -> Double {
        let rad = Double.pi / 180.0
        let dLat = (c2.latitude - c1.latitude) * rad
        let dLon = (c2.longitude - c1.longitude) * rad
        let meanLat = ((c1.latitude + c2.latitude) / 2.0) * rad
        let x = dLon * cos(meanLat)
        let y = dLat
        return 6_371_000.0 * sqrt(x * x + y * y)
    }
}
