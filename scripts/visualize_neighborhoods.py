import sqlite3
import h3
import json
import random

# Connect to the generated database
conn = sqlite3.connect('../assets/neighborhood.sqlite')
cursor = conn.cursor()

print("Fetching neighborhood hexes...")
cursor.execute('SELECT h3_index, neighborhood_id FROM neighborhood_hexes')
rows = cursor.fetchall()
conn.close()

features = []
# Give each neighborhood a random color
neighborhood_colors = {}

print(f"Generating GeoJSON for {len(rows)} hexes... This may take a minute.")
for h3_index, neighborhood_id in rows:
    if neighborhood_id not in neighborhood_colors:
        # Generate a random hex color
        neighborhood_colors[neighborhood_id] = "#{:06x}".format(random.randint(0, 0xFFFFFF))
        
    try:
        # Get the polygon coordinates for the hex
        # h3.cell_to_boundary returns ((lat, lng), ...)
        boundary = h3.cell_to_boundary(h3_index)
        
        # GeoJSON expects (lng, lat)
        coords = [[(lng, lat) for lat, lng in boundary]]
        # Close the polygon
        coords[0].append(coords[0][0])
        
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Polygon",
                "coordinates": coords
            },
            "properties": {
                "h3_index": h3_index,
                "neighborhood_id": neighborhood_id,
                "fill": neighborhood_colors[neighborhood_id],
                "fill-opacity": 0.5,
                "stroke": "#333333",
                "stroke-width": 1
            }
        }
        features.append(feature)
    except Exception as e:
        print(f"Error processing hex {h3_index}: {e}")

# We don't want to write all 300k hexes to one GeoJSON, it will crash geojson.io
# Let's sample a specific bounding box (e.g. Williamsburg / Greenpoint) to keep it lightweight.
# Bounding box roughly around North Brooklyn
MIN_LAT, MAX_LAT = 40.70, 40.74
MIN_LNG, MAX_LNG = -73.97, -73.93

filtered_features = []
for f in features:
    # Check the first coordinate of the polygon
    lng, lat = f["geometry"]["coordinates"][0][0]
    if MIN_LAT <= lat <= MAX_LAT and MIN_LNG <= lng <= MAX_LNG:
        filtered_features.append(f)

geojson = {
    "type": "FeatureCollection",
    "features": filtered_features
}

output_path = "debug_wburg_hexes.geojson"
with open(output_path, "w") as f:
    json.dump(geojson, f)

print(f"Done! Wrote {len(filtered_features)} hexes in North Brooklyn to {output_path}")
print("You can view this file by dragging it into https://geojson.io")
