import Foundation
import CoreLocation
import UIKit
import MapLibre

/// Cartographic trunk-line dataset and GeoJSON generator for NYC MTA Subway Thoroughfares
public struct MtaSubwayNetworkData: Sendable {
    
    public struct TrunkLine: Sendable {
        public let id: String
        public let name: String
        public let colorHex: String
        public let casingColorHex: String
        public let coordinates: [CLLocationCoordinate2D]
        
        public init(id: String, name: String, colorHex: String, casingColorHex: String = "#FFFFFF", coordinates: [CLLocationCoordinate2D]) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.casingColorHex = casingColorHex
            self.coordinates = coordinates
        }
    }
    
    /// All 11 NYC Subway trunk line groups with official MTA agency color palettes
    public static let trunkLines: [TrunkLine] = [
        // 1. Broadway - Seventh Avenue Line (Red: #EE352E)
        TrunkLine(
            id: "123",
            name: "Broadway - 7 Av Line (1, 2, 3)",
            colorHex: "#EE352E",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.8890, longitude: -73.8980), // Van Cortlandt Park - 242 St
                CLLocationCoordinate2D(latitude: 40.8500, longitude: -73.9330), // 181 St
                CLLocationCoordinate2D(latitude: 40.7930, longitude: -73.9720), // 96 St
                CLLocationCoordinate2D(latitude: 40.7780, longitude: -73.9820), // 72 St
                CLLocationCoordinate2D(latitude: 40.7680, longitude: -73.9818), // Columbus Circle
                CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), // Times Sq - 42 St
                CLLocationCoordinate2D(latitude: 40.7505, longitude: -73.9910), // 34 St - Penn Station
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14 St
                CLLocationCoordinate2D(latitude: 40.7150, longitude: -74.0090), // Chambers St
                CLLocationCoordinate2D(latitude: 40.7020, longitude: -74.0130), // South Ferry / Wall St
                CLLocationCoordinate2D(latitude: 40.6940, longitude: -73.9920), // Borough Hall
                CLLocationCoordinate2D(latitude: 40.6720, longitude: -73.9680), // Franklin Ave
                CLLocationCoordinate2D(latitude: 40.6320, longitude: -73.9480)  // Flatbush Ave - Brooklyn College
            ]
        ),
        
        // 2. Lexington Avenue Line (Green: #00933C)
        TrunkLine(
            id: "456",
            name: "Lexington Av Line (4, 5, 6)",
            colorHex: "#00933C",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.8880, longitude: -73.8680), // Woodlawn / Pelham Bay
                CLLocationCoordinate2D(latitude: 40.8400, longitude: -73.9180), // 161 St - Yankee Stadium
                CLLocationCoordinate2D(latitude: 40.8040, longitude: -73.9370), // 125 St
                CLLocationCoordinate2D(latitude: 40.7790, longitude: -73.9550), // 86 St
                CLLocationCoordinate2D(latitude: 40.7630, longitude: -73.9680), // 59 St
                CLLocationCoordinate2D(latitude: 40.7525, longitude: -73.9775), // Grand Central - 42 St
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14 St - Union Sq
                CLLocationCoordinate2D(latitude: 40.7130, longitude: -74.0040), // Brooklyn Bridge - City Hall
                CLLocationCoordinate2D(latitude: 40.7090, longitude: -74.0080), // Fulton St
                CLLocationCoordinate2D(latitude: 40.7040, longitude: -74.0140), // Bowling Green
                CLLocationCoordinate2D(latitude: 40.6840, longitude: -73.9780), // Atlantic Ave - Barclays Ctr
                CLLocationCoordinate2D(latitude: 40.6680, longitude: -73.9310)  // Crown Hts - Utica Ave
            ]
        ),
        
        // 3. Flushing Line (Purple: #B933AD)
        TrunkLine(
            id: "7",
            name: "Flushing Line (7)",
            colorHex: "#B933AD",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.7550, longitude: -74.0020), // 34 St - Hudson Yards
                CLLocationCoordinate2D(latitude: 40.7558, longitude: -73.9870), // Times Sq - 42 St
                CLLocationCoordinate2D(latitude: 40.7525, longitude: -73.9775), // Grand Central - 42 St
                CLLocationCoordinate2D(latitude: 40.7420, longitude: -73.9580), // Vernon Blvd - Jackson Ave
                CLLocationCoordinate2D(latitude: 40.7460, longitude: -73.9440), // Court Sq
                CLLocationCoordinate2D(latitude: 40.7480, longitude: -73.9380), // Queensboro Plaza
                CLLocationCoordinate2D(latitude: 40.7450, longitude: -73.8910), // 74 St - Broadway
                CLLocationCoordinate2D(latitude: 40.7500, longitude: -73.8440), // Mets - Willets Point
                CLLocationCoordinate2D(latitude: 40.7590, longitude: -73.8300)  // Flushing - Main St
            ]
        ),
        
        // 4. Eighth Avenue Line (Blue: #0039A6)
        TrunkLine(
            id: "ACE",
            name: "Eighth Av Line (A, C, E)",
            colorHex: "#0039A6",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.8680, longitude: -73.9200), // Inwood - 207 St
                CLLocationCoordinate2D(latitude: 40.8400, longitude: -73.9400), // 168 St
                CLLocationCoordinate2D(latitude: 40.8100, longitude: -73.9520), // 125 St
                CLLocationCoordinate2D(latitude: 40.7680, longitude: -73.9818), // 59 St - Columbus Circle
                CLLocationCoordinate2D(latitude: 40.7570, longitude: -73.9890), // 42 St - Port Authority
                CLLocationCoordinate2D(latitude: 40.7505, longitude: -73.9910), // 34 St - Penn Station
                CLLocationCoordinate2D(latitude: 40.7310, longitude: -74.0010), // W 4 St - Wash Sq
                CLLocationCoordinate2D(latitude: 40.7130, longitude: -74.0090), // Chambers St / WTC
                CLLocationCoordinate2D(latitude: 40.7090, longitude: -74.0080), // Fulton St
                CLLocationCoordinate2D(latitude: 40.6990, longitude: -73.9900), // High St / Jay St - MetroTech
                CLLocationCoordinate2D(latitude: 40.6860, longitude: -73.9800), // Hoyt-Schermerhorn
                CLLocationCoordinate2D(latitude: 40.6750, longitude: -73.9210), // Utica Ave
                CLLocationCoordinate2D(latitude: 40.6700, longitude: -73.8750), // Euclid Ave
                CLLocationCoordinate2D(latitude: 40.6030, longitude: -73.7500)  // Far Rockaway - Mott Ave
            ]
        ),
        
        // 5. Sixth Avenue Line (Orange: #FF6319)
        TrunkLine(
            id: "BDFM",
            name: "Sixth Av Line (B, D, F, M)",
            colorHex: "#FF6319",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.8740, longitude: -73.8800), // Bedford Pk Blvd / Norwood
                CLLocationCoordinate2D(latitude: 40.8310, longitude: -73.9220), // 161 St - Yankee Stadium
                CLLocationCoordinate2D(latitude: 40.7588, longitude: -73.9810), // 47-50 Sts - Rockefeller Ctr
                CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857), // 34 St - Herald Sq
                CLLocationCoordinate2D(latitude: 40.7310, longitude: -74.0010), // W 4 St - Wash Sq
                CLLocationCoordinate2D(latitude: 40.7250, longitude: -73.9970), // Broadway-Lafayette St
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -73.9880), // Delancey St - Essex St
                CLLocationCoordinate2D(latitude: 40.7010, longitude: -73.9860), // York St
                CLLocationCoordinate2D(latitude: 40.6840, longitude: -73.9780), // Atlantic Ave - Barclays Ctr
                CLLocationCoordinate2D(latitude: 40.6620, longitude: -73.9800), // 7th Ave (Park Slope)
                CLLocationCoordinate2D(latitude: 40.6150, longitude: -73.9680), // Kings Highway
                CLLocationCoordinate2D(latitude: 40.5750, longitude: -73.9800)  // Coney Island - Stillwell Ave
            ]
        ),
        
        // 6. Brooklyn-Queens Crosstown Line (Lime: #6CBE45)
        TrunkLine(
            id: "G",
            name: "Crosstown Line (G)",
            colorHex: "#6CBE45",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.7470, longitude: -73.9450), // Court Sq
                CLLocationCoordinate2D(latitude: 40.7355, longitude: -73.9555), // 21st St
                CLLocationCoordinate2D(latitude: 40.7280, longitude: -73.9525), // Greenpoint Ave
                CLLocationCoordinate2D(latitude: 40.7215, longitude: -73.9545), // Nassau Ave
                CLLocationCoordinate2D(latitude: 40.7140, longitude: -73.9500), // Metropolitan Ave - Lorimer St
                CLLocationCoordinate2D(latitude: 40.7025, longitude: -73.9505), // Broadway
                CLLocationCoordinate2D(latitude: 40.6920, longitude: -73.9600), // Classon Ave
                CLLocationCoordinate2D(latitude: 40.6890, longitude: -73.9850), // Hoyt-Schermerhorn
                CLLocationCoordinate2D(latitude: 40.6720, longitude: -73.9920), // 4th Ave - 9th St
                CLLocationCoordinate2D(latitude: 40.6620, longitude: -73.9800), // 7th Ave
                CLLocationCoordinate2D(latitude: 40.6500, longitude: -73.9780)  // Church Ave
            ]
        ),
        
        // 7. Nassau Street - Jamaica Line (Brown: #996633)
        TrunkLine(
            id: "JZ",
            name: "Nassau St Line (J, Z)",
            colorHex: "#996633",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.7020, longitude: -73.8010), // Jamaica Center - Parsons/Archer
                CLLocationCoordinate2D(latitude: 40.6910, longitude: -73.8520), // Woodhaven Blvd
                CLLocationCoordinate2D(latitude: 40.6780, longitude: -73.9030), // Broadway Junction
                CLLocationCoordinate2D(latitude: 40.6940, longitude: -73.9350), // Myrtle Ave
                CLLocationCoordinate2D(latitude: 40.7080, longitude: -73.9580), // Marcy Ave
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -73.9880), // Essex St
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -74.0010), // Canal St
                CLLocationCoordinate2D(latitude: 40.7090, longitude: -74.0080), // Fulton St
                CLLocationCoordinate2D(latitude: 40.7060, longitude: -74.0110)  // Broad St
            ]
        ),
        
        // 8. 14th Street - Canarsie Line (Silver: #A7A9AC)
        TrunkLine(
            id: "L",
            name: "Canarsie Line (L)",
            colorHex: "#A7A9AC",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.7410, longitude: -74.0025), // 14th St - 8th Ave
                CLLocationCoordinate2D(latitude: 40.7380, longitude: -73.9963), // 14th St - 6th Ave
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14th St - Union Sq
                CLLocationCoordinate2D(latitude: 40.7330, longitude: -73.9840), // 3rd Ave
                CLLocationCoordinate2D(latitude: 40.7315, longitude: -73.9805), // 1st Ave
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -73.9575), // Bedford Ave
                CLLocationCoordinate2D(latitude: 40.7140, longitude: -73.9500), // Lorimer St
                CLLocationCoordinate2D(latitude: 40.7100, longitude: -73.9440), // Graham Ave
                CLLocationCoordinate2D(latitude: 40.7065, longitude: -73.9330), // Grand St
                CLLocationCoordinate2D(latitude: 40.7000, longitude: -73.9080), // Myrtle-Wyckoff
                CLLocationCoordinate2D(latitude: 40.6780, longitude: -73.9030), // Broadway Junction
                CLLocationCoordinate2D(latitude: 40.6450, longitude: -73.9010)  // Canarsie - Rockaway Pkwy
            ]
        ),
        
        // 9. Broadway Line (Yellow: #FCCC0A)
        TrunkLine(
            id: "NQRW",
            name: "Broadway Line (N, Q, R, W)",
            colorHex: "#FCCC0A",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.7750, longitude: -73.9120), // Astoria - Ditmars Blvd
                CLLocationCoordinate2D(latitude: 40.7640, longitude: -73.9790), // 57 St - 7th Ave
                CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), // Times Sq - 42 St
                CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857), // 34 St - Herald Sq
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14 St - Union Sq
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -74.0010), // Canal St
                CLLocationCoordinate2D(latitude: 40.7030, longitude: -74.0130), // Whitehall St - South Ferry
                CLLocationCoordinate2D(latitude: 40.6840, longitude: -73.9780), // Atlantic Ave - Barclays Ctr
                CLLocationCoordinate2D(latitude: 40.6430, longitude: -74.0030), // 36 St (Brooklyn)
                CLLocationCoordinate2D(latitude: 40.5750, longitude: -73.9800)  // Coney Island - Stillwell Ave
            ]
        ),
        
        // 10. Shuttles (Slate: #808183)
        TrunkLine(
            id: "S",
            name: "Shuttles (S)",
            colorHex: "#808183",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.7558, longitude: -73.9870), // Times Sq - 42 St
                CLLocationCoordinate2D(latitude: 40.7525, longitude: -73.9775)  // Grand Central - 42 St
            ]
        ),
        
        // 11. Staten Island Railway (Blue: #0078C6)
        TrunkLine(
            id: "SIR",
            name: "Staten Island Railway (SIR)",
            colorHex: "#0078C6",
            coordinates: [
                CLLocationCoordinate2D(latitude: 40.6430, longitude: -74.0730), // St. George
                CLLocationCoordinate2D(latitude: 40.6210, longitude: -74.0780), // Clifton
                CLLocationCoordinate2D(latitude: 40.5520, longitude: -74.1510), // Great Kills
                CLLocationCoordinate2D(latitude: 40.5120, longitude: -74.2510)  // Tottenville
            ]
        )
    ]
    
    /// Generates MapLibre Shape Collection Feature containing all subway trunk polylines with style properties
    public static func createSubwayNetworkShape() -> MLNShapeCollectionFeature {
        // 1. Attempt to load high-resolution GTFS GeoJSON from app bundle
        if let bundleURL = Bundle.main.url(forResource: "subway-lines", withExtension: "geojson"),
           let data = try? Data(contentsOf: bundleURL),
           let parsedShape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) as? MLNShapeCollectionFeature {
            
            for shape in parsedShape.shapes {
                if let feature = shape as? MLNFeature {
                    let hex = (feature.attributes["color_hex"] as? String) ?? "#FFB300"
                    var attrs = feature.attributes
                    attrs["color"] = UIColor(hex: hex)
                    feature.attributes = attrs
                }
            }
            return parsedShape
        }
        
        // 2. Fallback to static trunk line features
        var features: [MLNPolylineFeature] = []
        for trunk in trunkLines {
            let polyline = MLNPolylineFeature(coordinates: trunk.coordinates, count: UInt(trunk.coordinates.count))
            polyline.attributes = [
                "route_group": trunk.id,
                "route_name": trunk.name,
                "color_hex": trunk.colorHex,
                "color": UIColor(hex: trunk.colorHex),
                "casing_color_hex": trunk.casingColorHex
            ]
            features.append(polyline)
        }
        
        return MLNShapeCollectionFeature(shapes: features)
    }
}
