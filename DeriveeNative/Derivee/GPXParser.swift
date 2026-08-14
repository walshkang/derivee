import Foundation
import CoreLocation

public struct GPXCoordinate: Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date?
    
    public init(latitude: Double, longitude: Double, timestamp: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}

public final class GPXParser: NSObject, XMLParserDelegate {
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
    
    public override init() {
        super.init()
    }
    
    public func parse(url: URL) throws -> [GPXCoordinate] {
        coordinates = []
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        parser.delegate = self
        if parser.parse() {
            return coordinates
        } else {
            throw parser.parserError ?? NSError(domain: "GPXParser", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unknown parsing error"])
        }
    }
    
    // MARK: - XMLParserDelegate
    
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
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
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "time" {
            currentDateString += string
        }
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
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
