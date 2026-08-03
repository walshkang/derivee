import urllib.request
import zipfile
import csv
import json
import io

url = "http://web.mta.info/developers/data/nyct/subway/google_transit.zip"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
with urllib.request.urlopen(req) as response:
    with zipfile.ZipFile(io.BytesIO(response.read())) as z:
        # Generate stops.geojson
        with z.open('stops.txt') as f:
            reader = csv.DictReader(io.TextIOWrapper(f))
            rows = list(reader)
            features = []
            for row in rows:
                # We only want parent stations, not individual platforms
                if row['location_type'] == '1' or row['parent_station'] == '':
                    features.append({
                        "type": "Feature",
                        "properties": {
                            "stop_id": row['stop_id'],
                            "stop_name": row['stop_name']
                        },
                        "geometry": {
                            "type": "Point",
                            "coordinates": [float(row['stop_lon']), float(row['stop_lat'])]
                        }
                    })
            
            with open('public/subway-stops.geojson', 'w') as out:
                json.dump({"type": "FeatureCollection", "features": features}, out)
            
            # Write to SQLite
            import sqlite3
            import os
            
            db_path = '../observer/transit_delta.sqlite'
            conn = sqlite3.connect(db_path)
            c = conn.cursor()
            c.execute('''
                CREATE TABLE IF NOT EXISTS stops (
                    stop_id TEXT PRIMARY KEY,
                    stop_name TEXT,
                    stop_lat REAL,
                    stop_lon REAL,
                    location_type INTEGER
                ) WITHOUT ROWID;
            ''')
            
            for row in rows:
                loc_type = int(row['location_type']) if row['location_type'] else 0
                c.execute('''
                    INSERT OR REPLACE INTO stops (stop_id, stop_name, stop_lat, stop_lon, location_type)
                    VALUES (?, ?, ?, ?, ?)
                ''', (row['stop_id'], row['stop_name'], float(row['stop_lat']), float(row['stop_lon']), loc_type))
            
            conn.commit()
            conn.close()
                
        # Generate lines.geojson from shapes.txt and routes.txt
        # shapes.txt has shape_id, shape_pt_lat, shape_pt_lon, shape_pt_sequence
        with z.open('shapes.txt') as f:
            reader = csv.DictReader(io.TextIOWrapper(f))
            shapes = {}
            for row in reader:
                shape_id = row['shape_id']
                if shape_id not in shapes:
                    shapes[shape_id] = []
                shapes[shape_id].append((int(row['shape_pt_sequence']), float(row['shape_pt_lon']), float(row['shape_pt_lat'])))
            
            features = []
            for shape_id, pts in shapes.items():
                pts.sort() # sort by sequence
                coords = [[lon, lat] for seq, lon, lat in pts]
                route_id = shape_id.split('..')[0] if '..' in shape_id else shape_id
                features.append({
                    "type": "Feature",
                    "properties": { "route_id": route_id, "shape_id": shape_id },
                    "geometry": { "type": "LineString", "coordinates": coords }
                })
                
            with open('public/subway-lines.geojson', 'w') as out:
                json.dump({"type": "FeatureCollection", "features": features}, out)

print("GeoJSON generated successfully!")
