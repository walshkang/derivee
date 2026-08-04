import Foundation
import CoreLocation

struct GPXCoordinate {
    let latitude: Double
    let longitude: Double
    let timestamp: Date?
}

final class GPXParser: NSObject, XMLParserDelegate {
    private var coordinates: [GPXCoordinate] = []
    
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentElement = ""
    private var currentDateString = ""
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    func parse(url: URL) throws -> [GPXCoordinate] {
        coordinates = []
        guard let parser = XMLParser(contentsOf: url) else {
            throw NSError(domain: "GPXParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize XML parser"])
        }
        parser.delegate = self
        if parser.parse() {
            return coordinates
        } else {
            throw parser.parserError ?? NSError(domain: "GPXParser", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unknown parsing error"])
        }
    }
    
    // MARK: - XMLParserDelegate
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "trkpt" || elementName == "wpt" {
            if let latStr = attributeDict["lat"], let lat = Double(latStr),
               let lonStr = attributeDict["lon"], let lon = Double(lonStr) {
                currentLat = lat
                currentLon = lon
            }
            currentDateString = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "time" {
            currentDateString += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "trkpt" || elementName == "wpt" {
            if let lat = currentLat, let lon = currentLon {
                let timestamp = dateFormatter.date(from: currentDateString.trimmingCharacters(in: .whitespacesAndNewlines))
                coordinates.append(GPXCoordinate(latitude: lat, longitude: lon, timestamp: timestamp))
            }
            currentLat = nil
            currentLon = nil
            currentDateString = ""
        }
    }
}
