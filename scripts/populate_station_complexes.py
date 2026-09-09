#!/usr/bin/env python3
"""
Populate Station Complexes & Clustered Stop Resolution Hierarchy in transit.sqlite
Implements Research Docs 15 & 16 for Wave Q Task Q.1.
"""

import csv
import io
import math
import os
import sqlite3
import sys
import urllib.request

REGIONAL_HUB_ANCHORS = [
    {
        "complex_id": 600001,
        "name": "Penn Station - Moynihan Train Hall Complex",
        "borough": "Manhattan",
        "keywords": ["PENN", "MOYNIHAN", "34 ST-PENN"],
        "lat": 40.750568,
        "lon": -73.993519,
        "radius_m": 500.0,
    },
    {
        "complex_id": 600002,
        "name": "Grand Central Terminal Complex",
        "borough": "Manhattan",
        "keywords": ["GRAND CENTRAL", "GCM", "METRO-NORTH"],
        "lat": 40.752726,
        "lon": -73.977229,
        "radius_m": 450.0,
    },
    {
        "complex_id": 600003,
        "name": "Atlantic Avenue - Barclays Center Complex",
        "borough": "Brooklyn",
        "keywords": ["ATLANTIC", "BARCLAYS", "FLATBUSH"],
        "lat": 40.684411,
        "lon": -73.977821,
        "radius_m": 350.0,
    },
]

MTA_STATIONS_URL = "http://web.mta.info/developers/data/nyct/subway/Stations.csv"

def haversine(lat1, lon1, lat2, lon2):
    r = 6371000.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    return 2 * r * math.asin(math.sqrt(a))

def fetch_mta_stations():
    print(f"📥 Fetching MTA Stations.csv from {MTA_STATIONS_URL}...")
    req = urllib.request.Request(MTA_STATIONS_URL, headers={"User-Agent": "DeriveeBuilder/1.0"})
    with urllib.request.urlopen(req) as resp:
        content = resp.read().decode("utf-8", errors="replace")
    
    reader = csv.DictReader(io.StringIO(content))
    mta_lookup = {}
    complex_metadata = {}
    
    for row in reader:
        gtfs_id = row.get("GTFS Stop ID", "").strip()
        complex_id_str = row.get("Complex ID", "").strip()
        stop_name = row.get("Stop Name", "").strip()
        borough = row.get("Borough", "").strip()
        lat = float(row.get("GTFS Latitude", 0) or 0)
        lon = float(row.get("GTFS Longitude", 0) or 0)
        
        if not gtfs_id or not complex_id_str:
            continue
        try:
            cid = int(complex_id_str)
        except ValueError:
            continue
        
        mta_lookup[gtfs_id] = cid
        mta_lookup[gtfs_id.upper()] = cid
        
        if cid not in complex_metadata:
            complex_metadata[cid] = {
                "name": stop_name,
                "borough": normalize_borough(borough),
                "lats": [lat] if lat else [],
                "lons": [lon] if lon else []
            }
        else:
            if lat and lon:
                complex_metadata[cid]["lats"].append(lat)
                complex_metadata[cid]["lons"].append(lon)
                
    print(f"✅ Loaded {len(mta_lookup)} MTA GTFS Stop -> Complex mappings across {len(complex_metadata)} complexes.")
    return mta_lookup, complex_metadata

def normalize_borough(b):
    b = b.upper()
    if b in ("M", "MANHATTAN"): return "Manhattan"
    if b in ("BK", "B", "BROOKLYN"): return "Brooklyn"
    if b in ("Q", "QUEENS"): return "Queens"
    if b in ("BX", "BRONX"): return "Bronx"
    if b in ("SI", "STATEN ISLAND"): return "Staten Island"
    return b.title()

def main():
    db_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../DeriveeNative/Derivee/derivee_transit.sqlite")
    print(f"🚀 Updating transit database at: {db_path}")
    
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    
    # 1. Fetch MTA Stations
    mta_lookup, mta_complex_meta = fetch_mta_stations()
    
    # 2. Re-create tables
    print("🛠️ Creating `complexes` and `stop_resolution` tables (WITHOUT ROWID)...")
    cur.execute("DROP TABLE IF EXISTS complexes;")
    cur.execute("""
        CREATE TABLE complexes (
            complex_id          INTEGER NOT NULL,
            complex_name        TEXT    NOT NULL,
            borough             TEXT,
            latitude            REAL    NOT NULL,
            longitude           REAL    NOT NULL,
            is_hub              INTEGER NOT NULL DEFAULT 0 CHECK(is_hub IN (0, 1)),
            PRIMARY KEY (complex_id)
        ) WITHOUT ROWID;
    """)
    
    cur.execute("DROP TABLE IF EXISTS stop_resolution;")
    cur.execute("""
        CREATE TABLE stop_resolution (
            complex_id          INTEGER NOT NULL,
            feed_id             TEXT    NOT NULL,
            parent_station_id   TEXT    NOT NULL,
            child_stop_id       TEXT    NOT NULL,
            platform_code       TEXT,
            direction_id        INTEGER CHECK(direction_id IN (0, 1, NULL)),
            wheelchair_boarding INTEGER NOT NULL DEFAULT 0 CHECK(wheelchair_boarding IN (0, 1, 2)),
            PRIMARY KEY (complex_id, feed_id, parent_station_id, child_stop_id)
        ) WITHOUT ROWID;
    """)
    cur.execute("""
        CREATE UNIQUE INDEX idx_stop_resolution_reverse 
        ON stop_resolution (feed_id, child_stop_id, complex_id, parent_station_id);
    """)
    cur.execute("""
        CREATE INDEX idx_stop_resolution_parent
        ON stop_resolution (feed_id, parent_station_id, complex_id);
    """)
    
    # 3. Read existing stops from transit.sqlite
    cur.execute("SELECT stop_id, stop_name, stop_lat, stop_lon, location_type, parent_station FROM stops;")
    stops_rows = cur.fetchall()
    print(f"📊 Analyzing {len(stops_rows)} existing stops...")
    
    stops_by_id = {}
    for r in stops_rows:
        sid, sname, slat, slon, loctype, parent = r
        stops_by_id[sid] = {
            "id": sid, "name": sname, "lat": slat, "lon": slon,
            "location_type": loctype, "parent": parent
        }
    
    # Helper to find root parent station
    def find_root_parent(stop_id):
        curr = stop_id
        visited = set()
        while curr and curr not in visited:
            visited.add(curr)
            info = stops_by_id.get(curr)
            if not info or not info["parent"] or info["parent"] == curr:
                break
            curr = info["parent"]
        return curr
    
    complexes_dict = {}
    stop_resolutions = []
    generated_complex_seq = 800000
    
    parent_to_complex = {}
    
    # First pass: map parent stations to complexes
    for sid, stop in stops_by_id.items():
        root_parent = find_root_parent(sid)
        if root_parent in parent_to_complex:
            continue
            
        parent_stop = stops_by_id.get(root_parent, stop)
        p_name = parent_stop["name"]
        norm_name = p_name.upper()
        p_lat = parent_stop["lat"]
        p_lon = parent_stop["lon"]
        
        assigned_cid = None
        assigned_name = p_name
        assigned_borough = None
        is_hub = 0
        
        # Stage 1: Regional Mega-Hub Anchors
        for anchor in REGIONAL_HUB_ANCHORS:
            if p_lat and p_lon:
                dist = haversine(p_lat, p_lon, anchor["lat"], anchor["lon"])
                if dist <= anchor["radius_m"]:
                    for kw in anchor["keywords"]:
                        if kw in norm_name:
                            assigned_cid = anchor["complex_id"]
                            assigned_name = anchor["name"]
                            assigned_borough = anchor["borough"]
                            is_hub = 1
                            break
            if is_hub:
                break
                
        # Stage 2: MTA Subway Stations.csv lookup
        if not assigned_cid:
            clean_parent = root_parent.upper()
            if clean_parent in mta_lookup:
                assigned_cid = mta_lookup[clean_parent]
                if assigned_cid in mta_complex_meta:
                    assigned_name = mta_complex_meta[assigned_cid]["name"]
                    assigned_borough = mta_complex_meta[assigned_cid]["borough"]
                    
        # Stage 3: Independent Station Fallback
        if not assigned_cid:
            try:
                numeric_val = int(root_parent)
                if 0 < numeric_val < 600000:
                    assigned_cid = numeric_val
                else:
                    assigned_cid = generated_complex_seq
                    generated_complex_seq += 1
            except ValueError:
                assigned_cid = generated_complex_seq
                generated_complex_seq += 1
                
        parent_to_complex[root_parent] = assigned_cid
        
        if assigned_cid not in complexes_dict:
            complexes_dict[assigned_cid] = {
                "id": assigned_cid,
                "name": assigned_name,
                "borough": assigned_borough,
                "is_hub": is_hub,
                "lat_sum": p_lat or 0,
                "lon_sum": p_lon or 0,
                "count": 1 if p_lat and p_lon else 0
            }
        else:
            entry = complexes_dict[assigned_cid]
            if is_hub:
                entry["is_hub"] = 1
                entry["name"] = assigned_name
                entry["borough"] = assigned_borough
            if p_lat and p_lon:
                entry["lat_sum"] += p_lat
                entry["lon_sum"] += p_lon
                entry["count"] += 1

    # Second pass: generate stop_resolution records
    seen_resolutions = set()
    for sid, stop in stops_by_id.items():
        root_parent = find_root_parent(sid)
        cid = parent_to_complex[root_parent]
        
        # Feed classification: subway vs bus
        feed_id = "subway" if (stop["location_type"] == 1 or sid.endswith("N") or sid.endswith("S") or any(char.isdigit() for char in sid)) else "bus"
        
        # Direction ID
        dir_id = None
        sid_upper = sid.upper()
        if sid_upper.endswith("N") or sid_upper.endswith("E"):
            dir_id = 0
        elif sid_upper.endswith("S") or sid_upper.endswith("W"):
            dir_id = 1
            
        key = (cid, feed_id, root_parent, sid)
        if key not in seen_resolutions:
            seen_resolutions.add(key)
            stop_resolutions.append((cid, feed_id, root_parent, sid, "", dir_id, 0))
            
        # Ensure root_parent self-resolution exists
        if root_parent != sid:
            parent_key = (cid, feed_id, root_parent, root_parent)
            if parent_key not in seen_resolutions:
                seen_resolutions.add(parent_key)
                stop_resolutions.append((cid, feed_id, root_parent, root_parent, "", None, 0))
                
    # Ensure all 3 Regional Hub Anchors explicitly exist in complexes table
    for anchor in REGIONAL_HUB_ANCHORS:
        aid = anchor["complex_id"]
        if aid not in complexes_dict:
            complexes_dict[aid] = {
                "id": aid,
                "name": anchor["name"],
                "borough": anchor["borough"],
                "is_hub": 1,
                "lat_sum": anchor["lat"],
                "lon_sum": anchor["lon"],
                "count": 1
            }
        else:
            complexes_dict[aid]["name"] = anchor["name"]
            complexes_dict[aid]["borough"] = anchor["borough"]
            complexes_dict[aid]["is_hub"] = 1
            
    # Insert complexes
    print(f"💾 Inserting {len(complexes_dict)} complexes...")
    complexes_rows = []
    for c in complexes_dict.values():
        avg_lat = (c["lat_sum"] / c["count"]) if c["count"] > 0 else 40.7128
        avg_lon = (c["lon_sum"] / c["count"]) if c["count"] > 0 else -74.0060
        complexes_rows.append((c["id"], c["name"], c["borough"], avg_lat, avg_lon, c["is_hub"]))
        
    cur.executemany("""
        INSERT INTO complexes (complex_id, complex_name, borough, latitude, longitude, is_hub)
        VALUES (?, ?, ?, ?, ?, ?);
    """, complexes_rows)
    
    # Insert stop_resolution
    print(f"💾 Inserting {len(stop_resolutions)} stop_resolution rows...")
    cur.executemany("""
        INSERT INTO stop_resolution (complex_id, feed_id, parent_station_id, child_stop_id, platform_code, direction_id, wheelchair_boarding)
        VALUES (?, ?, ?, ?, ?, ?, ?);
    """, stop_resolutions)
    
    # Run optimizer
    print("⚡ Running PRAGMA optimize...")
    cur.execute("PRAGMA optimize;")
    conn.commit()
    conn.close()
    
    print(f"🎉 Complete! Updated {db_path} with {len(complexes_rows)} complexes and {len(stop_resolutions)} stop resolutions.")

if __name__ == "__main__":
    main()
