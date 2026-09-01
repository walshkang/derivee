import Foundation
import CoreLocation
import UIKit

public actor GBFSSyncService {
    public static let shared = GBFSSyncService()
    
    private var config: GBFSConfig?
    private let databaseManager: GBFSDatabaseManager
    private let dockValidator: GBFSDockValidator
    private let session: URLSession
    
    private var pollingTask: Task<Void, Never>?
    private var lastETagInfo: String?
    private var lastETagStatus: String?
    private var lastInfoFetchTime: Date?
    
    private let minPollIntervalNanos: UInt64 = 15_000_000_000 // 15s
    private let maxPollIntervalNanos: UInt64 = 120_000_000_000 // 120s
    private var currentBackoffFactor: UInt64 = 1
    
    private var isObservingLifecycle = false
    
    // MARK: - Initialization
    
    public init(
        config: GBFSConfig? = CityConfig.nycDefault.effectiveGBFS,
        databaseManager: GBFSDatabaseManager = .shared,
        session: URLSession = .shared
    ) {
        self.config = config
        self.databaseManager = databaseManager
        self.dockValidator = GBFSDockValidator(databaseManager: databaseManager)
        self.session = session
    }
    
    public static func makeForTesting(
        config: GBFSConfig?,
        databaseManager: GBFSDatabaseManager,
        session: URLSession = .shared
    ) -> GBFSSyncService {
        GBFSSyncService(config: config, databaseManager: databaseManager, session: session)
    }
    
    // MARK: - Configuration & City Switching
    
    public func configureForCity(config: GBFSConfig?) {
        stopPolling()
        self.config = config
        self.lastETagInfo = nil
        self.lastETagStatus = nil
        self.lastInfoFetchTime = nil
        self.currentBackoffFactor = 1
    }
    
    public func prepareForCitySwap() {
        logPipeline("🛑 [GBFSSyncService] prepareForCitySwap executing — cancelling active GBFS polling")
        stopPolling()
        self.lastETagInfo = nil
        self.lastETagStatus = nil
        self.lastInfoFetchTime = nil
        self.databaseManager.releaseMemory()
    }
    
    // MARK: - Polling Lifecycle
    
    public func startPolling() {
        stopPolling()
        guard let config = config,
              !config.stationStatusUrl.isEmpty else {
            return
        }
        
        let targetIntervalNanos = UInt64(config.pollIntervalSeconds * 1_000_000_000)
        
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                
                let success = await self.fetchAndIngestLatest()
                let nextInterval = await self.calculateNextInterval(success: success, targetIntervalNanos: targetIntervalNanos)
                
                do {
                    try await Task.sleep(nanoseconds: nextInterval)
                } catch {
                    // Task cancellation immediately breaks the polling loop
                    break
                }
            }
        }
    }
    
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
    
    public var isPolling: Bool {
        pollingTask != nil && !(pollingTask?.isCancelled ?? true)
    }
    
    // MARK: - Ingestion Pipeline
    
    @discardableResult
    public func fetchAndIngestLatest() async -> Bool {
        guard let config = config else { return false }
        
        // 1. Refresh static station info if missing or older than 1 hour (3600s)
        var infoSuccess = true
        let shouldFetchInfo: Bool = {
            guard let last = lastInfoFetchTime else { return true }
            return Date().timeIntervalSince(last) > 3600
        }()
        
        if shouldFetchInfo && !config.stationInfoUrl.isEmpty {
            infoSuccess = await fetchAndIngestStationInfo(urlStr: config.stationInfoUrl, systemId: config.systemId, headers: config.headers)
            if infoSuccess {
                lastInfoFetchTime = Date()
            }
        }
        
        // 2. Refresh dynamic station status
        let statusSuccess = await fetchAndIngestStationStatus(urlStr: config.stationStatusUrl, headers: config.headers)
        return infoSuccess && statusSuccess
    }
    
    public func fetchAndIngestStationInfo(urlStr: String, systemId: String, headers: [String: String]? = nil) async -> Bool {
        guard let url = URL(string: urlStr) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        
        if let lastETag = lastETagInfo {
            request.setValue(lastETag, forHTTPHeaderField: "If-None-Match")
        }
        if let customHeaders = headers {
            for (k, v) in customHeaders {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            
            if httpResponse.statusCode == 304 {
                // Not modified: cache is fresh
                return true
            }
            guard (200...299).contains(httpResponse.statusCode) else { return false }
            
            if let newETag = httpResponse.value(forHTTPHeaderField: "ETag") {
                self.lastETagInfo = newETag
            }
            
            let infoFeed = try JSONDecoder().decode(GBFSStationInfoResponse.self, from: data)
            try await databaseManager.upsertStationInfo(infoFeed.data.stations, systemId: systemId)
            return true
        } catch {
            return false
        }
    }
    
    public func fetchAndIngestStationStatus(urlStr: String, headers: [String: String]? = nil) async -> Bool {
        guard let url = URL(string: urlStr) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        
        if let lastETag = lastETagStatus {
            request.setValue(lastETag, forHTTPHeaderField: "If-None-Match")
        }
        if let customHeaders = headers {
            for (k, v) in customHeaders {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            
            if httpResponse.statusCode == 304 {
                // Not modified: cache is fresh
                return true
            }
            guard (200...299).contains(httpResponse.statusCode) else { return false }
            
            if let newETag = httpResponse.value(forHTTPHeaderField: "ETag") {
                self.lastETagStatus = newETag
            }
            
            let statusFeed = try JSONDecoder().decode(GBFSStationStatusResponse.self, from: data)
            try await databaseManager.upsertStationStatus(statusFeed.data.stations)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Backoff & Jitter
    
    public func calculateNextInterval(success: Bool, targetIntervalNanos: UInt64) -> UInt64 {
        if success {
            currentBackoffFactor = 1
            return max(targetIntervalNanos, minPollIntervalNanos)
        } else {
            // Exponential backoff with random jitter
            currentBackoffFactor = min(currentBackoffFactor * 2, 8)
            let baseInterval = minPollIntervalNanos * currentBackoffFactor
            let jitter = UInt64.random(in: 0...3_000_000_000)
            return min(baseInterval + jitter, maxPollIntervalNanos)
        }
    }
    
    // MARK: - Spatial & Dock Gating API Forwarding
    
    public func fetchCandidateStations(
        near centerCoordinate: CLLocationCoordinate2D,
        radiusMeters: Double = 500.0,
        preference: GBFSVehiclePreference = .anyBike
    ) async throws -> [GBFSStation] {
        try await databaseManager.fetchCandidateStations(
            near: centerCoordinate,
            radiusMeters: radiusMeters,
            preference: preference
        )
    }
    
    public func validateOriginDock(
        stationId: String,
        preference: GBFSVehiclePreference = .anyBike,
        minBikes: Int? = nil,
        referenceDate: Date = Date()
    ) async throws -> GBFSDockGatingResult {
        try await dockValidator.validateOriginDock(
            stationId: stationId,
            preference: preference,
            minBikes: minBikes,
            stalenessThreshold: config?.stalenessThresholdSeconds,
            referenceDate: referenceDate
        )
    }
    
    public func validateDestinationDock(
        stationId: String,
        minDocks: Int? = nil,
        referenceDate: Date = Date()
    ) async throws -> GBFSDockGatingResult {
        try await dockValidator.validateDestinationDock(
            stationId: stationId,
            minDocks: minDocks,
            stalenessThreshold: config?.stalenessThresholdSeconds,
            referenceDate: referenceDate
        )
    }
    
    public func evaluateTransferEdge(
        originStationId: String,
        destinationStationId: String,
        preference: GBFSVehiclePreference = .anyBike,
        minBikes: Int? = nil,
        minDocks: Int? = nil,
        referenceDate: Date = Date(),
        attemptFallbackIfDestinationGated: Bool = true,
        transitEntryCoordinate: CLLocationCoordinate2D? = nil
    ) async throws -> GBFSDockGatingResult {
        try await dockValidator.evaluateTransferEdge(
            originStationId: originStationId,
            destinationStationId: destinationStationId,
            preference: preference,
            minBikes: minBikes,
            minDocks: minDocks,
            stalenessThreshold: config?.stalenessThresholdSeconds,
            referenceDate: referenceDate,
            attemptFallbackIfDestinationGated: attemptFallbackIfDestinationGated,
            transitEntryCoordinate: transitEntryCoordinate
        )
    }
}
