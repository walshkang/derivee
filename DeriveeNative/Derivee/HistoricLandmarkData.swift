import Foundation
import CoreLocation
import H3

public struct HistoricLandmarkItem: Sendable {
    public let id: String
    public let name: String
    public let borough: String
    public let category: String
    public let description: String
    public let coordinate: CLLocationCoordinate2D
    public let h3Index: String
    
    public init(
        id: String,
        name: String,
        borough: String,
        category: String,
        description: String,
        coordinate: CLLocationCoordinate2D
    ) {
        self.id = id
        self.name = name
        self.borough = borough
        self.category = category
        self.description = description
        self.coordinate = coordinate
        if let cell = try? H3.latLngToCell(latitude: coordinate.latitude, longitude: coordinate.longitude, resolution: 11) {
            self.h3Index = String(cell, radix: 16)
        } else {
            self.h3Index = ""
        }
    }
}

public enum HistoricLandmarkCatalog {
    public static let landmarks: [HistoricLandmarkItem] = [
        // Manhattan
        HistoricLandmarkItem(
            id: "landmark_grand_central",
            name: "Grand Central Terminal",
            borough: "Manhattan",
            category: "Architectural",
            description: "Beaux-Arts railroad cathedral with celestial vaulted ceiling.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        ),
        HistoricLandmarkItem(
            id: "landmark_empire_state",
            name: "Empire State Building",
            borough: "Manhattan",
            category: "Architectural",
            description: "Art Deco 102-story skyscraper dominating midtown skyline.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857)
        ),
        HistoricLandmarkItem(
            id: "landmark_flatiron",
            name: "Flatiron Building",
            borough: "Manhattan",
            category: "Architectural",
            description: "Groundbreaking triangular steel-framed landmark at 23rd St.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7411, longitude: -73.9897)
        ),
        HistoricLandmarkItem(
            id: "landmark_nypl_main",
            name: "New York Public Library (Main)",
            borough: "Manhattan",
            category: "Cultural",
            description: "Stephen A. Schwarzman flagship guarded by marble lions Patience & Fortitude.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7532, longitude: -73.9822)
        ),
        HistoricLandmarkItem(
            id: "landmark_stonewall",
            name: "Stonewall National Monument",
            borough: "Manhattan",
            category: "Historic",
            description: "Historic Greenwich Village birthplace of the modern LGBTQ+ civil rights movement.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7338, longitude: -74.0021)
        ),
        HistoricLandmarkItem(
            id: "landmark_apollo",
            name: "Apollo Theater",
            borough: "Manhattan",
            category: "Cultural",
            description: "Harlem's iconic music hall celebrating African American musical legacy.",
            coordinate: CLLocationCoordinate2D(latitude: 40.8101, longitude: -73.9501)
        ),
        HistoricLandmarkItem(
            id: "landmark_bethesda_terrace",
            name: "Bethesda Terrace",
            borough: "Manhattan",
            category: "Historic",
            description: "Vaux and Olmsted's architectural heart of Central Park overlooking the Lake.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7740, longitude: -73.9709)
        ),
        HistoricLandmarkItem(
            id: "landmark_high_line",
            name: "The High Line",
            borough: "Manhattan",
            category: "Urban",
            description: "Elevated freight railway transformed into a 1.45-mile linear park.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7480, longitude: -74.0048)
        ),

        // Brooklyn
        HistoricLandmarkItem(
            id: "landmark_brooklyn_bridge",
            name: "Brooklyn Bridge",
            borough: "Brooklyn",
            category: "Architectural",
            description: "Roebling's 1883 neo-Gothic suspension bridge spanning the East River.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7061, longitude: -73.9969)
        ),
        HistoricLandmarkItem(
            id: "landmark_prospect_park_boathouse",
            name: "Prospect Park Boathouse",
            borough: "Brooklyn",
            category: "Historic",
            description: "1905 classical terracotta boathouse on the Prospect Park Lullwater.",
            coordinate: CLLocationCoordinate2D(latitude: 40.6628, longitude: -73.9634)
        ),
        HistoricLandmarkItem(
            id: "landmark_coney_island_wonder_wheel",
            name: "Coney Island Wonder Wheel",
            borough: "Brooklyn",
            category: "Cultural",
            description: "1920 eccentric Ferris wheel standing 150 feet above the Atlantic boardwalk.",
            coordinate: CLLocationCoordinate2D(latitude: 40.5753, longitude: -73.9786)
        ),
        HistoricLandmarkItem(
            id: "landmark_brooklyn_museum",
            name: "Brooklyn Museum",
            borough: "Brooklyn",
            category: "Cultural",
            description: "McKim, Mead & White Beaux-Arts museum holding world-class antiquities.",
            coordinate: CLLocationCoordinate2D(latitude: 40.6712, longitude: -73.9636)
        ),
        HistoricLandmarkItem(
            id: "landmark_green_wood_cemetery",
            name: "Green-Wood Cemetery Arch",
            borough: "Brooklyn",
            category: "Historic",
            description: "1861 Gothic Revival double-pinnacled gateway and national historic landmark.",
            coordinate: CLLocationCoordinate2D(latitude: 40.6581, longitude: -73.9948)
        ),

        // Queens
        HistoricLandmarkItem(
            id: "landmark_unisphere",
            name: "The Unisphere",
            borough: "Queens",
            category: "Cultural",
            description: "120-foot stainless steel globe built for the 1964–1965 World's Fair.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7464, longitude: -73.8448)
        ),
        HistoricLandmarkItem(
            id: "landmark_queensboro_bridge",
            name: "Queensboro Bridge",
            borough: "Queens",
            category: "Architectural",
            description: "Double-deck cantilever bridge connecting Long Island City to 59th Street.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7569, longitude: -73.9547)
        ),
        HistoricLandmarkItem(
            id: "landmark_fort_totten",
            name: "Fort Totten Historic Battery",
            borough: "Queens",
            category: "Historic",
            description: "Civil War fortress and coastal defense battery on the Long Island Sound.",
            coordinate: CLLocationCoordinate2D(latitude: 40.7933, longitude: -73.7744)
        ),

        // Bronx
        HistoricLandmarkItem(
            id: "landmark_woodlawn_cemetery",
            name: "Woodlawn Cemetery Gate",
            borough: "Bronx",
            category: "Historic",
            description: "Historic resting place of jazz legends Miles Davis and Duke Ellington.",
            coordinate: CLLocationCoordinate2D(latitude: 40.8887, longitude: -73.8732)
        ),
        HistoricLandmarkItem(
            id: "landmark_pelham_bay_split_rock",
            name: "Split Rock (Pelham Bay)",
            borough: "Bronx",
            category: "Historic",
            description: "Historic colonial boulder landmark within NYC's largest public park.",
            coordinate: CLLocationCoordinate2D(latitude: 40.8741, longitude: -73.8118)
        ),

        // Staten Island
        HistoricLandmarkItem(
            id: "landmark_st_george_theatre",
            name: "St. George Theatre",
            borough: "Staten Island",
            category: "Cultural",
            description: "1929 Spanish and Italian Renaissance movie palace near the ferry terminal.",
            coordinate: CLLocationCoordinate2D(latitude: 40.6433, longitude: -74.0772)
        ),
        HistoricLandmarkItem(
            id: "landmark_snug_harbor",
            name: "Snug Harbor Cultural Center",
            borough: "Staten Island",
            category: "Cultural",
            description: "19th-century Greek Revival home for retired sailors converted to arts center.",
            coordinate: CLLocationCoordinate2D(latitude: 40.6447, longitude: -74.1028)
        )
    ]
}
