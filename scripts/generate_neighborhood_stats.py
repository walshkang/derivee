import os
import json
import requests
import h3
from shapely.geometry import shape, mapping, Polygon, MultiPolygon
from shapely.ops import unary_union
from shapely.validation import make_valid

# NTA 2020 (Neighborhoods)
NTA_URL = "https://data.cityofnewyork.us/api/geospatial/9nt8-h7nd?method=export&format=GeoJSON"
# NYC Hydrography (Water) - Note: this is a large dataset
WATER_URL = "https://data.cityofnewyork.us/api/views/drh3-e2fd/rows.geojson?accessType=DOWNLOAD"

CACHE_DIR = "cache"
OUTPUT_FILE = "../assets/neighborhood_data.json"

def download_geojson(url, filename):
    if not os.path.exists(CACHE_DIR):
        os.makedirs(CACHE_DIR)
    path = os.path.join(CACHE_DIR, filename)
    if os.path.exists(path):
        print(f"Loading cached {filename}...")
        with open(path, 'r') as f:
            return json.load(f)
    print(f"Downloading {url}...")
    response = requests.get(url)
    response.raise_for_status()
    data = response.json()
    with open(path, 'w') as f:
        json.dump(data, f)
    return data

def shapely_to_h3_poly(geom):
    """Converts a shapely Polygon to h3.LatLngPoly"""
    # H3 expects (lat, lng) but GeoJSON/Shapely is (lng, lat)
    exterior = [(lat, lng) for lng, lat in geom.exterior.coords]
    holes = []
    for interior in geom.interiors:
        holes.append([(lat, lng) for lng, lat in interior.coords])
    return h3.LatLngPoly(exterior, *holes)

def get_h3_hexes_for_geometry(geom, resolution=11):
    hexes = set()
    if isinstance(geom, Polygon):
        try:
            poly = shapely_to_h3_poly(geom)
            hexes.update(h3.polygon_to_cells(poly, resolution))
        except Exception as e:
            print(f"Warning: h3 polyfill error on Polygon: {e}")
    elif isinstance(geom, MultiPolygon):
        for poly_geom in geom.geoms:
            try:
                poly = shapely_to_h3_poly(poly_geom)
                hexes.update(h3.polygon_to_cells(poly, resolution))
            except Exception as e:
                print(f"Warning: h3 polyfill error on MultiPolygon part: {e}")
    return hexes

def main():
    ntas = download_geojson(NTA_URL, "nta.geojson")
    
    # Check if we have water data. If it's too big or slow, we might simplify.
    print("Downloading water geometries...")
    water = download_geojson(WATER_URL, "water.geojson")
    
    print("Parsing water geometries...")
    water_geoms = []
    for feature in water.get('features', []):
        if not feature.get('geometry'):
            continue
        geom = shape(feature['geometry'])
        geom = make_valid(geom)
        water_geoms.append(geom)
    
    print("Unioning water geometries (this may take a moment)...")
    water_union = unary_union(water_geoms)
    print("Water union created.")

    neighborhood_stats = []
    neighborhood_hexes = {} # h3_index -> neighborhood_id

    print("Processing neighborhoods...")
    for feature in ntas['features']:
        props = feature['properties']
        nta_id = props.get('nta2020')
        nta_name = props.get('ntaname')
        
        if not nta_id or not nta_name:
            continue
            
        geom = shape(feature['geometry'])
        geom = make_valid(geom)
        
        # Subtract water
        land_geom = geom.difference(water_union)
        
        if land_geom.is_empty:
            continue
            
        # Polyfill with H3
        hexes = get_h3_hexes_for_geometry(land_geom, resolution=11)
        total_hexes = len(hexes)
        
        if total_hexes == 0:
            continue
            
        centroid = land_geom.centroid
        
        neighborhood_stats.append({
            "id": nta_id,
            "name": nta_name,
            "total_hexes": total_hexes,
            "centroid_lat": centroid.y,
            "centroid_lng": centroid.x
        })
        
        for h in hexes:
            # Note: in rare cases of overlap, last one wins. NTAs shouldn't overlap.
            neighborhood_hexes[h] = nta_id
            
        print(f"Processed {nta_name}: {total_hexes} hexes")

    import sqlite3
    output_db = "../assets/neighborhood.sqlite"
    if os.path.exists(output_db):
        os.remove(output_db)
        
    print(f"Writing output to SQLite database at {output_db}...")
    conn = sqlite3.connect(output_db)
    cursor = conn.cursor()
    
    # Enable WAL mode for the read-only DB as well, just in case
    cursor.execute('PRAGMA journal_mode = WAL;')
    
    # Create tables
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS neighborhood_stats (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            total_hexes INTEGER NOT NULL,
            centroid_lat REAL NOT NULL,
            centroid_lng REAL NOT NULL
        ) WITHOUT ROWID;
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS neighborhood_hexes (
            h3_index TEXT PRIMARY KEY,
            neighborhood_id TEXT NOT NULL
        ) WITHOUT ROWID;
    ''')
    
    # Insert stats
    for stat in neighborhood_stats:
        cursor.execute(
            'INSERT INTO neighborhood_stats (id, name, total_hexes, centroid_lat, centroid_lng) VALUES (?, ?, ?, ?, ?)',
            (stat['id'], stat['name'], stat['total_hexes'], stat['centroid_lat'], stat['centroid_lng'])
        )
        
    # Insert hexes in chunks for performance
    hex_items = list(neighborhood_hexes.items())
    cursor.executemany(
        'INSERT INTO neighborhood_hexes (h3_index, neighborhood_id) VALUES (?, ?)',
        hex_items
    )
    
    conn.commit()
    
    # Create an index on neighborhood_id for fast lookups
    cursor.execute('CREATE INDEX idx_neighborhood_hexes_id ON neighborhood_hexes(neighborhood_id);')
    conn.commit()
    conn.close()
    
    print("Done!")

if __name__ == "__main__":
    main()
