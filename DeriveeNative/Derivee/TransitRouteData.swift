import SwiftUI
import CoreLocation
import MapLibre

struct TransitRouteData {
    struct LineInfo {
        let routeId: String
        let name: String
        let colorHex: String
        let textColorHex: String
        
        var color: Color {
            Color(hex: colorHex)
        }
        
        var uiColor: UIColor {
            UIColor(hex: colorHex)
        }
    }
    
    static func lineInfo(for routeId: String) -> LineInfo {
        let cleanId = routeId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch cleanId {
        case "1", "2", "3":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#EE352E", textColorHex: "#FFFFFF")
        case "4", "5", "6", "6X":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#00933C", textColorHex: "#FFFFFF")
        case "7", "7X":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#B933AD", textColorHex: "#FFFFFF")
        case "A", "C", "E":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#0039A6", textColorHex: "#FFFFFF")
        case "B", "D", "F", "FX", "M":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#FF6319", textColorHex: "#FFFFFF")
        case "G":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#6CBE45", textColorHex: "#FFFFFF")
        case "J", "Z":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#996633", textColorHex: "#FFFFFF")
        case "L":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#A7A9AC", textColorHex: "#000000")
        case "N", "Q", "R", "W":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#FCCC0A", textColorHex: "#000000")
        case "S", "GS", "FS", "H":
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#808183", textColorHex: "#FFFFFF")
        case "SIR":
            return LineInfo(routeId: cleanId, name: "SIR", colorHex: "#0078C6", textColorHex: "#FFFFFF")
        default:
            if cleanId.hasPrefix("M") || cleanId.hasPrefix("B") || cleanId.hasPrefix("Q") || cleanId.hasPrefix("Bx") || cleanId.hasPrefix("S") {
                return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#00A1DE", textColorHex: "#FFFFFF")
            }
            return LineInfo(routeId: cleanId, name: cleanId, colorHex: "#FFB300", textColorHex: "#000000")
        }
    }
    
    /// Parses GeoJSON / track route polyline off the main thread, querying local database first
    static func loadRouteCoordinates(for stopOrRouteId: String) async -> [CLLocationCoordinate2D] {
        return await Task.detached(priority: .userInitiated) {
            let cleanId = stopOrRouteId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // If it's a bus stop ID or bus route, do not render a subway polyline
            if isBusIdentifier(cleanId) {
                return []
            }
            
            let routeId = inferRouteId(from: cleanId)
            
            // 1. Attempt to fetch real physical track geometry from local SQLite database
            if let dbCoords = try? await SpatialDatabaseManager.shared.fetchRouteCoordinates(for: routeId), !dbCoords.isEmpty {
                return dbCoords
            }
            
            // 2. Attempt to load from bundled GeoJSON shapes
            if let geoCoords = loadCoordinatesFromGeoJSON(for: routeId), !geoCoords.isEmpty {
                return geoCoords
            }
            
            // 3. Fallback polylines across all NYC transit lines
            return fallbackCoordinates(for: routeId)
        }.value
    }
    
    private static func isBusIdentifier(_ id: String) -> Bool {
        let clean = id.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("BUS_") { return true }
        if clean.hasPrefix("BX") || clean.hasPrefix("SBS") { return true }
        if clean.contains("/") || clean.contains(" - SBS") { return true }
        if (clean.hasPrefix("M") || clean.hasPrefix("B") || clean.hasPrefix("Q") || clean.hasPrefix("S")) && clean.count >= 2 && clean.dropFirst().first?.isNumber == true {
            return true
        }
        if clean.count >= 5, Int(clean) != nil {
            return true
        }
        return false
    }
    
    private static func loadCoordinatesFromGeoJSON(for routeId: String) -> [CLLocationCoordinate2D]? {
        guard let bundleURL = Bundle.main.url(forResource: "subway-lines", withExtension: "geojson") ?? Bundle(for: SpatialDatabaseManager.self).url(forResource: "subway-lines", withExtension: "geojson"),
              let data = try? Data(contentsOf: bundleURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return nil
        }
        
        let targetRoute = routeId.uppercased()
        for feature in features {
            if let props = feature["properties"] as? [String: Any],
               let routeGroup = props["route_group"] as? String {
                
                let matches: Bool
                switch routeGroup {
                case "123": matches = ["1", "2", "3"].contains(targetRoute)
                case "456": matches = ["4", "5", "6", "6X"].contains(targetRoute)
                case "7": matches = ["7", "7X"].contains(targetRoute)
                case "ACE": matches = ["A", "C", "E"].contains(targetRoute)
                case "BDFM": matches = ["B", "D", "F", "FX", "M"].contains(targetRoute)
                case "G": matches = targetRoute == "G"
                case "JZ": matches = ["J", "Z"].contains(targetRoute)
                case "L": matches = targetRoute == "L"
                case "NQRW": matches = ["N", "Q", "R", "W"].contains(targetRoute)
                case "S": matches = ["S", "GS", "FS", "H"].contains(targetRoute)
                case "SIR": matches = targetRoute == "SIR" || targetRoute == "SI"
                default: matches = routeGroup == targetRoute
                }
                
                if matches, let geom = feature["geometry"] as? [String: Any] {
                    let geomType = (geom["type"] as? String) ?? ""
                    if geomType == "MultiLineString", let multiCoords = geom["coordinates"] as? [[[Double]]] {
                        if let longest = multiCoords.max(by: { $0.count < $1.count }) {
                            return longest.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                        }
                    } else if geomType == "LineString", let coords = geom["coordinates"] as? [[Double]] {
                        return coords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    }
                }
            }
        }
        return nil
    }
    
    public static func inferRouteId(from id: String) -> String {
        let clean = id.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let validRoutes = ["1", "2", "3", "4", "5", "6", "7", "A", "B", "C", "D", "E", "F", "G", "J", "L", "M", "N", "Q", "R", "S", "W", "Z", "SIR"]
        if validRoutes.contains(clean) {
            return clean
        }
        
        // Stop ID prefix matching for subway stations
        if clean.hasPrefix("1") && clean.count == 3 { return "1" }
        if clean.hasPrefix("2") && clean.count == 3 { return "2" }
        if clean.hasPrefix("3") && clean.count == 3 { return "3" }
        if clean.hasPrefix("4") && clean.count == 3 { return "4" }
        if clean.hasPrefix("5") && clean.count == 3 { return "5" }
        if clean.hasPrefix("6") && clean.count == 3 { return "6" }
        if clean.hasPrefix("7") && clean.count == 3 { return "7" }
        if clean.hasPrefix("A") { return "A" }
        if clean.hasPrefix("B") { return "B" }
        if clean.hasPrefix("C") { return "C" }
        if clean.hasPrefix("D") { return "F" }
        if clean.hasPrefix("E") { return "E" }
        if clean.hasPrefix("F") { return "F" }
        if clean.hasPrefix("G") { return "G" }
        if clean.hasPrefix("J") || clean.hasPrefix("Z") { return "J" }
        if clean.hasPrefix("L") { return "L" }
        if clean.hasPrefix("M") && clean.count == 3 { return "M" }
        if clean.hasPrefix("N") { return "N" }
        if clean.hasPrefix("Q") { return "Q" }
        if clean.hasPrefix("R") { return "R" }
        if clean.hasPrefix("W") { return "W" }
        if clean.hasPrefix("S") && clean.count == 3 { return "SIR" }
        if clean.hasPrefix("H") { return "S" }
        
        return "L"
    }
    
    private static func fallbackCoordinates(for routeId: String) -> [CLLocationCoordinate2D] {
        switch routeId.uppercased() {
        case "L":
            // MTA L Train (14th St - Canarsie Line)
            return [
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
            
        case "G":
            // MTA G Train (Brooklyn-Queens Crosstown Line)
            return [
                CLLocationCoordinate2D(latitude: 40.7470, longitude: -73.9450), // Court Sq
                CLLocationCoordinate2D(latitude: 40.7355, longitude: -73.9555), // 21st St
                CLLocationCoordinate2D(latitude: 40.7280, longitude: -73.9525), // Greenpoint Ave
                CLLocationCoordinate2D(latitude: 40.7215, longitude: -73.9545), // Nassau Ave
                CLLocationCoordinate2D(latitude: 40.7140, longitude: -73.9500), // Metropolitan Ave
                CLLocationCoordinate2D(latitude: 40.7025, longitude: -73.9505), // Broadway
                CLLocationCoordinate2D(latitude: 40.6920, longitude: -73.9600), // Classon Ave
                CLLocationCoordinate2D(latitude: 40.6890, longitude: -73.9850), // Hoyt-Schermerhorn
                CLLocationCoordinate2D(latitude: 40.6620, longitude: -73.9800), // 7th Ave (Park Slope)
                CLLocationCoordinate2D(latitude: 40.6500, longitude: -73.9780)  // Church Ave
            ]
            
        case "7", "7X":
            // MTA 7 Train (Flushing Line)
            return [
                CLLocationCoordinate2D(latitude: 40.7550, longitude: -74.0020), // 34 St Hudson Yards
                CLLocationCoordinate2D(latitude: 40.7558, longitude: -73.9870), // Times Sq - 42 St
                CLLocationCoordinate2D(latitude: 40.7525, longitude: -73.9775), // Grand Central - 42 St
                CLLocationCoordinate2D(latitude: 40.7420, longitude: -73.9580), // Vernon Blvd-Jackson Ave
                CLLocationCoordinate2D(latitude: 40.7480, longitude: -73.9380), // Queensboro Plaza
                CLLocationCoordinate2D(latitude: 40.7450, longitude: -73.8910), // 74 St-Broadway
                CLLocationCoordinate2D(latitude: 40.7590, longitude: -73.8300)  // Flushing - Main St
            ]
            
        case "1", "2", "3":
            // MTA 1/2/3 Trains (Seventh Ave - Broadway Line)
            return [
                CLLocationCoordinate2D(latitude: 40.8890, longitude: -73.8980), // Van Cortlandt Park - 242 St
                CLLocationCoordinate2D(latitude: 40.8500, longitude: -73.9330), // 181 St
                CLLocationCoordinate2D(latitude: 40.7930, longitude: -73.9720), // 96 St
                CLLocationCoordinate2D(latitude: 40.7780, longitude: -73.9820), // 72 St
                CLLocationCoordinate2D(latitude: 40.7680, longitude: -73.9818), // Columbus Circle
                CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), // Times Square
                CLLocationCoordinate2D(latitude: 40.7505, longitude: -73.9910), // 34 St - Penn Station
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14 St
                CLLocationCoordinate2D(latitude: 40.7150, longitude: -74.0090), // Chambers St
                CLLocationCoordinate2D(latitude: 40.7020, longitude: -74.0130), // South Ferry / Wall St
                CLLocationCoordinate2D(latitude: 40.6940, longitude: -73.9920), // Borough Hall
                CLLocationCoordinate2D(latitude: 40.6320, longitude: -73.9480)  // Flatbush Ave - Brooklyn College
            ]
            
        case "4", "5", "6", "6X":
            // MTA 4/5/6 Trains (Lexington Ave Line)
            return [
                CLLocationCoordinate2D(latitude: 40.8880, longitude: -73.8680), // Woodlawn / Pelham Bay
                CLLocationCoordinate2D(latitude: 40.8040, longitude: -73.9370), // 125 St
                CLLocationCoordinate2D(latitude: 40.7790, longitude: -73.9550), // 86 St
                CLLocationCoordinate2D(latitude: 40.7525, longitude: -73.9775), // Grand Central - 42 St
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14 St - Union Sq
                CLLocationCoordinate2D(latitude: 40.7130, longitude: -74.0040), // Brooklyn Bridge - City Hall
                CLLocationCoordinate2D(latitude: 40.7090, longitude: -74.0080), // Fulton St
                CLLocationCoordinate2D(latitude: 40.7040, longitude: -74.0140), // Bowling Green
                CLLocationCoordinate2D(latitude: 40.6840, longitude: -73.9780), // Atlantic Ave - Barclays Ctr
                CLLocationCoordinate2D(latitude: 40.6680, longitude: -73.9310)  // Crown Hts - Utica Ave
            ]
            
        case "A", "C", "E":
            // MTA A/C/E Trains (Eighth Ave Line)
            return [
                CLLocationCoordinate2D(latitude: 40.8680, longitude: -73.9200), // Inwood - 207 St
                CLLocationCoordinate2D(latitude: 40.8400, longitude: -73.9400), // 168 St
                CLLocationCoordinate2D(latitude: 40.8100, longitude: -73.9520), // 125 St
                CLLocationCoordinate2D(latitude: 40.7680, longitude: -73.9818), // 59 St - Columbus Circle
                CLLocationCoordinate2D(latitude: 40.7570, longitude: -73.9890), // 42 St - Port Authority
                CLLocationCoordinate2D(latitude: 40.7505, longitude: -73.9910), // 34 St - Penn Station
                CLLocationCoordinate2D(latitude: 40.7310, longitude: -74.0010), // W 4 St - Wash Sq
                CLLocationCoordinate2D(latitude: 40.7130, longitude: -74.0090), // Chambers St / World Trade Ctr
                CLLocationCoordinate2D(latitude: 40.7090, longitude: -74.0080), // Fulton St
                CLLocationCoordinate2D(latitude: 40.6990, longitude: -73.9900), // High St / Jay St - MetroTech
                CLLocationCoordinate2D(latitude: 40.6750, longitude: -73.9210)  // Utica Ave / Far Rockaway
            ]
            
        case "B", "D", "F", "FX", "M":
            // MTA B/D/F/M Trains (Sixth Ave Line)
            return [
                CLLocationCoordinate2D(latitude: 40.8740, longitude: -73.8800), // Bedford Pk / Norwood
                CLLocationCoordinate2D(latitude: 40.7588, longitude: -73.9810), // 47-50 Sts - Rockefeller Ctr
                CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857), // 34 St - Herald Sq
                CLLocationCoordinate2D(latitude: 40.7310, longitude: -74.0010), // W 4 St - Wash Sq
                CLLocationCoordinate2D(latitude: 40.7250, longitude: -73.9970), // Broadway-Lafayette St
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -73.9880), // Delancey St · Essex St
                CLLocationCoordinate2D(latitude: 40.7010, longitude: -73.9860), // York St
                CLLocationCoordinate2D(latitude: 40.6840, longitude: -73.9780), // Atlantic Ave - Barclays Ctr
                CLLocationCoordinate2D(latitude: 40.5750, longitude: -73.9800)  // Coney Island - Stillwell Ave
            ]
            
        case "N", "Q", "R", "W":
            // MTA N/Q/R/W Trains (Broadway Line)
            return [
                CLLocationCoordinate2D(latitude: 40.7750, longitude: -73.9120), // Astoria - Ditmars Blvd
                CLLocationCoordinate2D(latitude: 40.7640, longitude: -73.9790), // 57 St - 7th Ave
                CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), // Times Sq - 42 St
                CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857), // 34 St - Herald Sq
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // 14 St - Union Sq
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -74.0010), // Canal St
                CLLocationCoordinate2D(latitude: 40.7030, longitude: -74.0130), // Whitehall St - South Ferry
                CLLocationCoordinate2D(latitude: 40.6840, longitude: -73.9780), // Atlantic Ave - Barclays Ctr
                CLLocationCoordinate2D(latitude: 40.5750, longitude: -73.9800)  // Coney Island - Stillwell Ave
            ]
            
        case "J", "Z":
            // MTA J/Z Trains (Nassau St - Jamaica Line)
            return [
                CLLocationCoordinate2D(latitude: 40.7020, longitude: -73.8010), // Jamaica Center - Parsons/Archer
                CLLocationCoordinate2D(latitude: 40.6910, longitude: -73.8520), // Woodhaven Blvd
                CLLocationCoordinate2D(latitude: 40.6780, longitude: -73.9030), // Broadway Junction
                CLLocationCoordinate2D(latitude: 40.7080, longitude: -73.9580), // Marcy Ave
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -73.9880), // Essex St
                CLLocationCoordinate2D(latitude: 40.7180, longitude: -74.0010), // Canal St
                CLLocationCoordinate2D(latitude: 40.7090, longitude: -74.0080), // Fulton St
                CLLocationCoordinate2D(latitude: 40.7060, longitude: -74.0110)  // Broad St
            ]
            
        case "S", "GS", "FS", "H":
            // Shuttles (42nd St Shuttle / Franklin / Rockaway)
            return [
                CLLocationCoordinate2D(latitude: 40.7558, longitude: -73.9870), // Times Sq - 42 St
                CLLocationCoordinate2D(latitude: 40.7525, longitude: -73.9775)  // Grand Central - 42 St
            ]
            
        case "SIR":
            // Staten Island Railway
            return [
                CLLocationCoordinate2D(latitude: 40.6430, longitude: -74.0730), // St. George
                CLLocationCoordinate2D(latitude: 40.6210, longitude: -74.0780), // Clifton
                CLLocationCoordinate2D(latitude: 40.5520, longitude: -74.1510), // Great Kills
                CLLocationCoordinate2D(latitude: 40.5120, longitude: -74.2510)  // Tottenville
            ]
            
        default:
            // Generic NYC Midtown-Downtown corridor
            return [
                CLLocationCoordinate2D(latitude: 40.7680, longitude: -73.9818), // Columbus Circle
                CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), // Times Square
                CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857), // Herald Square
                CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905), // Union Square
                CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)  // City Hall / Wall St
            ]
        }
    }
}

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
