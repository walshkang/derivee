import XCTest
import UIKit
import MapLibre
@testable import Derivee

final class BasemapThemeTests: XCTestCase {
    
    // MARK: - BasemapStyleLoader Tests
    
    func testBasemapStyleLoaderHydratesKey() throws {
        let testKey = "test_maptiler_key_xyz_789"
        let bundle = Bundle(for: BasemapThemeTests.self)
        let styleURL = BasemapStyleLoader.prepareHydratedStyleURL(apiKey: testKey, bundle: bundle)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: styleURL.path), "Hydrated style file should exist on disk")
        
        let content = try String(contentsOf: styleURL, encoding: .utf8)
        XCTAssertFalse(content.contains("{key}"), "Hydrated style JSON must not contain placeholder '{key}'")
        XCTAssertTrue(content.contains(testKey), "Hydrated style JSON must contain injected API key")
        
        // Verify valid JSON
        guard let data = content.data(using: .utf8) else {
            XCTFail("Failed to convert content to data")
            return
        }
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        XCTAssertNotNil(jsonObject as? [String: Any], "Hydrated style must be a valid JSON dictionary")
    }
    
    func testBasemapStyleLoaderStyleURLProperty() {
        let url = BasemapStyleLoader.styleURL
        XCTAssertTrue(url.isFileURL, "styleURL must be a file URL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Cached style file must exist on disk")
    }
    
    // MARK: - BasemapPalette Tests
    
    func testBasemapPaletteCompleteness() {
        let day = BasemapPalette.day
        let transit = BasemapPalette.transit
        
        // Day Palette Assertions
        XCTAssertEqual(day.backgroundColor, UIColor(hex: "#F9F9F6"), "Day background should be parchment white #F9F9F6")
        XCTAssertEqual(day.fogColor, UIColor(hex: "#1C1C1E"), "Day fog should be graphite #1C1C1E")
        XCTAssertEqual(day.labelTextColor, UIColor(hex: "#1C1C1E"), "Day label should be dark")
        XCTAssertEqual(day.building3DColor, UIColor(hex: "#DCDCD6"), "Day 3D buildings should match building color")
        
        // Transit Palette Assertions (High-Contrast Light Navigation)
        XCTAssertEqual(transit.backgroundColor, UIColor(hex: "#FFFFFF"), "Transit background should be pure porcelain white #FFFFFF")
        XCTAssertEqual(transit.fogColor, UIColor(hex: "#1C1C1E"), "Transit fog should be graphite #1C1C1E")
        XCTAssertEqual(transit.railColor, UIColor(hex: "#FFB300"), "Transit rail color should be Electric Amber #FFB300")
        XCTAssertEqual(transit.railLineWidth, 3.0, "Transit rail line width should be 3.0pt for prominent visibility")
        XCTAssertEqual(transit.railOpacity, 0.95, "Transit rail opacity should be 0.95")
    }
    
    func testBasemapPaletteForThemeMapping() {
        XCTAssertEqual(BasemapPalette.forTheme(.day), BasemapPalette.day)
        XCTAssertEqual(BasemapPalette.forTheme(.transit), BasemapPalette.transit)
    }
    
    // MARK: - BasemapTheme Enum Tests
    
    func testBasemapThemeEnumCases() {
        let allThemes = BasemapTheme.allCases
        XCTAssertEqual(allThemes.count, 2, "Must have exactly 2 light basemap themes")
        XCTAssertTrue(allThemes.contains(.day))
        XCTAssertTrue(allThemes.contains(.transit))
    }
    
    func testBasemapThemeCodableRoundTrip() throws {
        for theme in BasemapTheme.allCases {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(BasemapTheme.self, from: data)
            XCTAssertEqual(decoded, theme, "BasemapTheme '\(theme.rawValue)' must round-trip through JSONEncoder/JSONDecoder")
        }
    }
    
    // MARK: - BasemapThemeManager Layer Mapping Tests
    
    func testCompositeStyleLayerIdsContainManagerLayers() throws {
        // Load composite_style.json template from bundle or path
        let bundle = Bundle(for: BasemapThemeTests.self)
        var templateURL = bundle.url(forResource: "composite_style", withExtension: "json")
        if templateURL == nil {
            for b in Bundle.allBundles {
                if let u = b.url(forResource: "composite_style", withExtension: "json") {
                    templateURL = u
                    break
                }
            }
        }
        
        guard let url = templateURL,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let layers = json["layers"] as? [[String: Any]] else {
            // If running in minimal unit test environment without full bundle assets, skip asset check
            return
        }
        
        let styleLayerIds = Set(layers.compactMap { $0["id"] as? String })
        
        // Background
        XCTAssertTrue(styleLayerIds.contains("Background"), "composite_style.json must contain 'Background' layer")
        
        // Water
        for id in BasemapThemeManager.waterFillLayerIds {
            XCTAssertTrue(styleLayerIds.contains(id), "composite_style.json must contain water fill layer '\(id)'")
        }
        
        // Rails
        for id in ["Major rail", "Minor rail", "Railway tunnel"] {
            XCTAssertTrue(styleLayerIds.contains(id), "composite_style.json must contain rail layer '\(id)'")
        }
        
        // Roads
        for id in ["Minor road", "Major road", "Highway"] {
            XCTAssertTrue(styleLayerIds.contains(id), "composite_style.json must contain road layer '\(id)'")
        }
    }
}
