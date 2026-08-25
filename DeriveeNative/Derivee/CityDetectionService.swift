import Foundation
import CoreLocation
import Observation

/// Toast payload for silent city auto-switch notifications.
public struct CityAutoSwitchToastData: Identifiable, Equatable, Sendable {
    public var id: String { slug }
    public let slug: String
    public let cityName: String
    public let message: String
    
    public init(slug: String, cityName: String) {
        self.slug = slug
        self.cityName = cityName
        self.message = "Welcome to \(cityName) • Switched active city"
    }
}

/// Protocol for reverse geocoding fallback, enabling deterministic unit testing.
public protocol CityGeocoder: Sendable {
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String?
}

/// Default Apple CoreLocation reverse geocoder implementation.
public struct AppleCityGeocoder: CityGeocoder {
    public init() {}
    public func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        return placemarks.first?.locality
    }
}

/// Coordinates GPS-based city detection, auto-switch toasts, 7-day download prompt snoozing, and pack installation state.
@Observable
@MainActor
public final class CityDetectionService {
    public var activeCitySlug: String {
        didSet {
            userDefaults.set(activeCitySlug, forKey: AppStorageKeys.activeCitySlug)
        }
    }
    
    /// Uninstalled city pending user confirmation in `CityDownloadPromptSheet`.
    public var promptCity: CityManifestEntry? = nil
    
    /// Active 3-second auto-switch toast when an installed city is detected.
    public var autoSwitchToast: CityAutoSwitchToastData? = nil
    
    /// Set of currently installed city slugs.
    public var installedCitySlugs: Set<String> {
        didSet {
            userDefaults.set(Array(installedCitySlugs), forKey: AppStorageKeys.installedCityPacks)
        }
    }
    
    public let manifest: CityManifest
    private let userDefaults: UserDefaults
    private let geocoder: any CityGeocoder
    
    /// Callback fired whenever active city switches (e.g. for MapLibre and DB hot-swap).
    public var onActiveCityChanged: ((String) -> Void)? = nil
    
    /// Default nag snooze duration: 7 days in seconds.
    public nonisolated static let defaultSnoozeDuration: TimeInterval = 7 * 86400
    
    public init(
        manifest: CityManifest = .defaultManifest,
        userDefaults: UserDefaults = .standard,
        geocoder: any CityGeocoder = AppleCityGeocoder()
    ) {
        self.manifest = manifest
        self.userDefaults = userDefaults
        self.geocoder = geocoder
        
        let storedActiveSlug = userDefaults.string(forKey: AppStorageKeys.activeCitySlug) ?? "nyc"
        self.activeCitySlug = storedActiveSlug
        
        let storedInstalled = userDefaults.stringArray(forKey: AppStorageKeys.installedCityPacks)
        if let stored = storedInstalled, !stored.isEmpty {
            var set = Set(stored)
            set.insert("nyc") // NYC bundled core metro is always installed
            self.installedCitySlugs = set
        } else {
            self.installedCitySlugs = ["nyc"]
        }
    }
    
    // MARK: - Core Detection Pipeline
    
    /// Evaluates a live GPS fix against the city manifest.
    /// - Parameters:
    ///   - location: The GPS fix to evaluate.
    ///   - accuracyThreshold: Maximum allowable horizontal accuracy (defaults to 25m).
    public func evaluateLocation(_ location: CLLocation, accuracyThreshold: CLLocationDistance = 25.0) {
        // Gate on GPS accuracy
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= accuracyThreshold else {
            return
        }
        
        let coordinate = location.coordinate
        
        // 1. Fast path: If coordinate is within currently active city, no switch needed
        if let activeEntry = manifest.findCity(bySlug: activeCitySlug),
           let bounds = activeEntry.bounds,
           bounds.contains(coordinate: coordinate) {
            return
        }
        
        // 2. Fast offline check against all known city bounding boxes in manifest
        if let detectedEntry = manifest.findCity(containing: coordinate) {
            handleCityMatch(detectedEntry)
            return
        }
        
        // 3. Fallback for ambiguous/unknown zones outside hard bounding boxes
        Task { [weak self] in
            guard let self = self else { return }
            do {
                if let locality = try await self.geocoder.reverseGeocode(coordinate: coordinate) {
                    if let matchedEntry = self.manifest.cities.first(where: {
                        $0.displayName.localizedCaseInsensitiveContains(locality) ||
                        locality.localizedCaseInsensitiveContains($0.displayName)
                    }) {
                        self.handleCityMatch(matchedEntry)
                    }
                }
            } catch {
                // Ambiguous zone or offline — proceed with ambient tracking under generic envelope
            }
        }
    }
    
    private func handleCityMatch(_ entry: CityManifestEntry) {
        guard entry.slug != activeCitySlug else { return }
        
        if isCityInstalled(entry.slug) {
            // City pack is installed -> Silent auto-switch + 3s toast
            performAutoSwitch(to: entry)
        } else {
            // City pack not installed -> check 7-day nag snooze
            if !isSnoozed(slug: entry.slug) {
                promptCity = entry
            }
        }
    }
    
    /// Executes the silent auto-switch to an installed city pack.
    public func performAutoSwitch(to entry: CityManifestEntry) {
        activeCitySlug = entry.slug
        autoSwitchToast = CityAutoSwitchToastData(slug: entry.slug, cityName: entry.displayName)
        onActiveCityChanged?(entry.slug)
        logPipeline("🏙️ [CityDetectionService] Auto-switched active city to: \(entry.displayName) (\(entry.slug))")
    }
    
    // MARK: - Pack Installation State
    
    public func isCityInstalled(_ slug: String) -> Bool {
        if slug == "nyc" { return true } // Bundled NYC pack
        return installedCitySlugs.contains(slug)
    }
    
    public func markCityInstalled(_ slug: String) {
        installedCitySlugs.insert(slug)
        clearSnooze(slug: slug)
    }
    
    public func markCityUninstalled(_ slug: String) {
        guard slug != "nyc" else { return } // NYC cannot be deleted
        installedCitySlugs.remove(slug)
    }
    
    // MARK: - 7-Day Nag Snooze Logic
    
    private var snoozeTimestamps: [String: Double] {
        get {
            userDefaults.dictionary(forKey: AppStorageKeys.cityPromptSnoozeTimestamps) as? [String: Double] ?? [:]
        }
        set {
            userDefaults.set(newValue, forKey: AppStorageKeys.cityPromptSnoozeTimestamps)
        }
    }
    
    /// Snoozes download prompts for the specified city.
    public func snoozeCity(slug: String, duration: TimeInterval = defaultSnoozeDuration, from date: Date = Date()) {
        var dict = snoozeTimestamps
        dict[slug] = date.timeIntervalSince1970
        snoozeTimestamps = dict
        if promptCity?.slug == slug {
            promptCity = nil
        }
        logPipeline("💤 [CityDetectionService] Snoozed prompt for \(slug) for \(Int(duration / 86400)) days")
    }
    
    /// Checks whether download prompts for the specified city are currently snoozed.
    public func isSnoozed(slug: String, duration: TimeInterval = defaultSnoozeDuration, referenceDate: Date = Date()) -> Bool {
        guard let timestamp = snoozeTimestamps[slug] else { return false }
        let elapsed = referenceDate.timeIntervalSince1970 - timestamp
        return elapsed >= 0 && elapsed < duration
    }
    
    /// Clears any active snooze for the specified city.
    public func clearSnooze(slug: String) {
        var dict = snoozeTimestamps
        dict.removeValue(forKey: slug)
        snoozeTimestamps = dict
    }
    
    /// Clears all active snoozes.
    public func clearAllSnoozes() {
        snoozeTimestamps = [:]
    }
}
