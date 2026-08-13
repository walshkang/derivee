import Foundation

func generateH3Hexes(count: Int) -> [String] {
    var hexes: [String] = []
    var offset: Double = 0.0
    let baseLat = 40.768075
    let baseLng = -73.981897
    
    while hexes.count < count {
        // We'll just mock H3 cell to string
        let hexStr = "\(offset)"
        if !hexes.contains(hexStr) {
            hexes.append(hexStr)
        }
        offset += 0.005
    }
    
    return hexes
}

print(generateH3Hexes(count: 2))
print(generateH3Hexes(count: 3))
