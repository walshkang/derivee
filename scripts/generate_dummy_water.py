import json
import os

dummy_water = {
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": {"name": "East River Dummy"},
            "geometry": {
                "type": "Polygon",
                "coordinates": [[
                    [-73.98, 40.71],
                    [-73.98, 40.72],
                    [-73.97, 40.72],
                    [-73.97, 40.71],
                    [-73.98, 40.71]
                ]]
            }
        }
    ]
}

os.makedirs("cache", exist_ok=True)
with open("cache/water.geojson", "w") as f:
    json.dump(dummy_water, f)
print("Generated dummy water.geojson in cache/")
