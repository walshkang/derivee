import Foundation

/// Handles loading the bundled `composite_style.json`, injecting the runtime MapTiler API key,
/// and returning a local `file://` URL for `MLNMapView`.
public enum BasemapStyleLoader {
    private static var cachedStyleURL: URL?
    
    /// Returns the hydrated `file://` URL for `composite_style.json` with the runtime MapTiler API key injected.
    public static var styleURL: URL {
        if let cached = cachedStyleURL, FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        
        let url = prepareHydratedStyleURL(apiKey: Secrets.mapTilerKey)
        cachedStyleURL = url
        return url
    }
    
    /// Prepares the hydrated style JSON with a given API key and writes it to the app cache directory.
    public static func prepareHydratedStyleURL(apiKey: String, bundle: Bundle = .main) -> URL {
        // Look in provided bundle or any loaded bundle (useful for testing/previews)
        var templateURL = bundle.url(forResource: "composite_style", withExtension: "json")
        if templateURL == nil {
            for b in Bundle.allBundles {
                if let u = b.url(forResource: "composite_style", withExtension: "json") {
                    templateURL = u
                    break
                }
            }
        }
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let destinationURL = cacheDir.appendingPathComponent("composite_style_hydrated.json")
        
        guard let sourceURL = templateURL,
              let rawString = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            // Fallback minimal valid style if bundle resource is missing
            let fallbackJSON = """
            {
              "version": 8,
              "name": "Composite Fallback",
              "sources": {
                "maptiler_planet": {
                  "url": "https://api.maptiler.com/tiles/v3/tiles.json?key=\(apiKey)",
                  "type": "vector"
                }
              },
              "layers": [
                {
                  "id": "Background",
                  "type": "background",
                  "paint": { "background-color": "#12121A" }
                }
              ]
            }
            """
            try? fallbackJSON.write(to: destinationURL, atomically: true, encoding: .utf8)
            return destinationURL
        }
        
        let hydratedString = rawString.replacingOccurrences(of: "{key}", with: apiKey)
        do {
            try hydratedString.write(to: destinationURL, atomically: true, encoding: .utf8)
            return destinationURL
        } catch {
            print("⚠️ Failed to write hydrated composite style: \(error)")
            return sourceURL
        }
    }
}
