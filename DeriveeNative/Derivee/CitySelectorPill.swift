import SwiftUI
import CoreLocation

public struct CitySelectorPill: View {
    public let browsingMode: StatsBrowsingMode
    public let installedPacks: [CityManifestEntry]
    public let userLocation: CLLocationCoordinate2D?
    public let onSelectMode: (StatsBrowsingMode) -> Void
    public let onOpenSettings: (() -> Void)?
    public let onManageCities: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        browsingMode: StatsBrowsingMode,
        installedPacks: [CityManifestEntry],
        userLocation: CLLocationCoordinate2D? = nil,
        onSelectMode: @escaping (StatsBrowsingMode) -> Void,
        onOpenSettings: (() -> Void)? = nil,
        onManageCities: (() -> Void)? = nil
    ) {
        self.browsingMode = browsingMode
        self.installedPacks = installedPacks
        self.userLocation = userLocation
        self.onSelectMode = onSelectMode
        self.onOpenSettings = onOpenSettings
        self.onManageCities = onManageCities
    }
    
    private var selectedCityEntry: CityManifestEntry? {
        guard let slug = browsingMode.slug else { return nil }
        return installedPacks.first { $0.slug == slug }
    }
    
    private var isPhysicallyPresentInSelectedCity: Bool {
        guard let loc = userLocation, let entry = selectedCityEntry, let bounds = entry.bounds else {
            return false
        }
        return bounds.contains(coordinate: loc)
    }
    
    public var body: some View {
        Menu {
            // 1. Installed Cities Section
            Section("Installed Cities") {
                ForEach(installedPacks) { city in
                    Button(action: {
                        onSelectMode(.city(slug: city.slug))
                    }) {
                        HStack {
                            let isPresent = isPhysicallyPresent(in: city)
                            if isPresent {
                                Label(city.displayName, systemImage: "location.fill")
                            } else {
                                Text(city.displayName)
                            }
                            
                            if browsingMode == .city(slug: city.slug) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            // 2. Global Lifetime Overview Section
            Section("Global") {
                Button(action: {
                    onSelectMode(.allMetros)
                }) {
                    HStack {
                        Label("All Metros Summary", systemImage: "globe.americas.fill")
                        if browsingMode == .allMetros {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            // 3. Manage Cities Quick Action
            if let manageAction = onManageCities ?? onOpenSettings {
                Section {
                    Button(action: manageAction) {
                        Label("Manage Cities...", systemImage: "internaldrive")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                // Leading Icon
                if browsingMode.isAllMetros {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#FFB300"))
                } else if isPhysicallyPresentInSelectedCity {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                } else {
                    Image(systemName: "mappin")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                }
                
                // Title
                Text(currentTitle)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                // Trailing Chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    private var currentTitle: String {
        switch browsingMode {
        case .allMetros:
            return "All Metros Summary"
        case .city(let slug):
            if let entry = selectedCityEntry {
                return entry.displayName
            } else if slug == "nyc" {
                return "New York City"
            } else if slug == "bos" {
                return "Boston"
            } else if slug == "chi" {
                return "Chicago"
            } else {
                return slug.uppercased()
            }
        }
    }
    
    private func isPhysicallyPresent(in city: CityManifestEntry) -> Bool {
        guard let loc = userLocation, let bounds = city.bounds else { return false }
        return bounds.contains(coordinate: loc)
    }
}

#Preview {
    VStack(spacing: 20) {
        CitySelectorPill(
            browsingMode: .city(slug: "nyc"),
            installedPacks: CityManifest.defaultManifest.cities,
            userLocation: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            onSelectMode: { _ in }
        )
        
        CitySelectorPill(
            browsingMode: .city(slug: "bos"),
            installedPacks: CityManifest.defaultManifest.cities,
            userLocation: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            onSelectMode: { _ in }
        )
        
        CitySelectorPill(
            browsingMode: .allMetros,
            installedPacks: CityManifest.defaultManifest.cities,
            userLocation: nil,
            onSelectMode: { _ in }
        )
    }
    .padding()
}
