#!/usr/bin/env python3
"""
MTA Bus Stops Ingestion Script for Dérivée
Downloads official MTA static GTFS bus feeds for all 5 boroughs + MTA Bus Co,
aggregates distinct bus stops and their serving routes, and ingests them into
DeriveeNative/Derivee/derivee_transit.sqlite.
"""

import csv
import io
import os
import re
import sqlite3
import sys
import urllib.request
import zipfile

FEEDS = [
    ("Manhattan", "http://web.mta.info/developers/data/nyct/bus/google_transit_manhattan.zip"),
    ("Brooklyn", "http://web.mta.info/developers/data/nyct/bus/google_transit_brooklyn.zip"),
    ("Queens", "http://web.mta.info/developers/data/nyct/bus/google_transit_queens.zip"),
    ("Bronx", "http://web.mta.info/developers/data/nyct/bus/google_transit_bronx.zip"),
    ("Staten Island", "http://web.mta.info/developers/data/nyct/bus/google_transit_staten_island.zip"),
    ("MTA Bus Co", "http://web.mta.info/developers/data/busco/google_transit.zip"),
]

def clean_stop_name(raw_name: str) -> str:
    """Format raw GTFS stop name into clean, title-cased intersection format."""
    name = raw_name.strip()
    # Replace slashes with &
    name = re.sub(r'\s*/\s*', ' & ', name)
    # Common abbreviations
    words = name.split()
    cleaned_words = []
    for w in words:
        upper = w.upper()
        if upper in ["&", "+", "@"]:
            cleaned_words.append("&")
        elif upper in ["ST", "ST.", "STREET"]:
            cleaned_words.append("St")
        elif upper in ["AV", "AVE", "AVE.", "AVENUE"]:
            cleaned_words.append("Av")
        elif upper in ["RD", "RD.", "ROAD"]:
            cleaned_words.append("Rd")
        elif upper in ["BLVD", "BLVD.", "BOULEVARD"]:
            cleaned_words.append("Blvd")
        elif upper in ["PL", "PL.", "PLACE"]:
            cleaned_words.append("Pl")
        elif upper in ["PKWY", "PKWY.", "PARKWAY"]:
            cleaned_words.append("Pkwy")
        elif upper in ["DR", "DR.", "DRIVE"]:
            cleaned_words.append("Dr")
        elif upper in ["LN", "LN.", "LANE"]:
            cleaned_words.append("Ln")
        elif upper in ["CT", "CT.", "COURT"]:
            cleaned_words.append("Ct")
        elif upper in ["TER", "TERR", "TERRACE"]:
            cleaned_words.append("Ter")
        elif upper in ["N", "NB", "NORTH", "NORTHBOUND"]:
            cleaned_words.append("NB")
        elif upper in ["S", "SB", "SOUTH", "SOUTHBOUND"]:
            cleaned_words.append("SB")
        elif upper in ["E", "EB", "EAST", "EASTBOUND"]:
            cleaned_words.append("EB")
        elif upper in ["W", "WB", "WEST", "WESTBOUND"]:
            cleaned_words.append("WB")
        elif re.match(r'^\d+(ST|ND|RD|TH)$', upper):
            # E.g. "14TH" -> "14 St" or "14th"
            cleaned_words.append(upper)
        elif upper in ["SBS", "SELECT", "BUS", "SERVICE"]:
            cleaned_words.append(upper)
        elif upper in ["MTA", "NYCT", "LIRR", "MET", "WTC", "FDR", "GWB"]:
            cleaned_words.append(upper)
        else:
            cleaned_words.append(w.capitalize())
    return " ".join(cleaned_words)

def process_feed(feed_name: str, feed_url: str, all_stops: dict):
    print(f"📥 Fetching {feed_name} from {feed_url}...")
    try:
        req = urllib.request.Request(feed_url, headers={"User-Agent": "Derivee-GTFS-Ingest/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
    except Exception as e:
        print(f"⚠️ Error downloading {feed_name}: {e}")
        return

    print(f"   Parsing {feed_name} archive ({len(data) / 1024 / 1024:.1f} MB)...")
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        # 1. Map route_id -> clean route name (route_short_name or route_id)
        route_names = {}
        if "routes.txt" in z.namelist():
            with z.open("routes.txt") as f:
                reader = csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))
                for r in reader:
                    r_id = r.get("route_id", "").strip()
                    short_name = r.get("route_short_name", "").strip()
                    route_names[r_id] = short_name if short_name else r_id

        # 2. Map trip_id -> route_id
        trip_routes = {}
        if "trips.txt" in z.namelist():
            with z.open("trips.txt") as f:
                reader = csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))
                for r in reader:
                    t_id = r.get("trip_id", "").strip()
                    r_id = r.get("route_id", "").strip()
                    trip_routes[t_id] = r_id

        # 3. Map stop_id -> set of routes
        stop_routes = {}
        if "stop_times.txt" in z.namelist():
            with z.open("stop_times.txt") as f:
                reader = csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))
                for r in reader:
                    s_id = r.get("stop_id", "").strip()
                    t_id = r.get("trip_id", "").strip()
                    r_id = trip_routes.get(t_id)
                    if s_id and r_id:
                        r_name = route_names.get(r_id, r_id)
                        if s_id not in stop_routes:
                            stop_routes[s_id] = set()
                        stop_routes[s_id].add(r_name)

        # 4. Extract stops
        if "stops.txt" in z.namelist():
            with z.open("stops.txt") as f:
                reader = csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))
                count = 0
                for r in reader:
                    s_id = r.get("stop_id", "").strip()
                    s_name = r.get("stop_name", "").strip()
                    try:
                        lat = float(r.get("stop_lat", "0"))
                        lon = float(r.get("stop_lon", "0"))
                    except ValueError:
                        continue
                    
                    if not s_id or not s_name or lat == 0 or lon == 0:
                        continue
                    
                    # NYC bounding box filter
                    if not (40.48 <= lat <= 40.95 and -74.30 <= lon <= -73.65):
                        continue

                    routes_set = stop_routes.get(s_id, set())
                    # Merge routes if stop already seen from another borough feed
                    if s_id in all_stops:
                        all_stops[s_id]["routes"].update(routes_set)
                    else:
                        all_stops[s_id] = {
                            "name": clean_stop_name(s_name),
                            "lat": lat,
                            "lon": lon,
                            "routes": routes_set,
                        }
                        count += 1
                print(f"   ✅ Parsed {count} unique stops from {feed_name}.")

def main():
    db_path = os.path.join(os.path.dirname(__file__), "../DeriveeNative/Derivee/derivee_transit.sqlite")
    if not os.path.exists(db_path):
        print(f"❌ Database not found at {db_path}")
        sys.exit(1)

    print(f"Connecting to database: {db_path}")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Check subway station count before
    cur.execute("SELECT count(*) FROM stops WHERE location_type = 1")
    subway_stations = cur.fetchone()[0]
    print(f"Current subway stations (location_type=1): {subway_stations}")

    all_stops = {}
    for feed_name, feed_url in FEEDS:
        process_feed(feed_name, feed_url, all_stops)

    print(f"\n📊 Total distinct bus stops collected across all boroughs: {len(all_stops)}")

    # Ingest bus stops
    # Format routes as sorted, comma-separated string
    print("Writing bus stops to transit database...")
    inserted = 0
    for stop_id, info in all_stops.items():
        sorted_routes = sorted(list(info["routes"]))
        routes_str = ",".join(sorted_routes) if sorted_routes else "MTA"
        cur.execute("""
            INSERT OR REPLACE INTO stops (stop_id, stop_name, stop_lat, stop_lon, location_type, routes, parent_station)
            VALUES (?, ?, ?, ?, 0, ?, NULL)
        """, (stop_id, info["name"], info["lat"], info["lon"], routes_str))
        inserted += 1

    print(f"Inserted {inserted} bus stops into `stops` table.")

    # Rebuild indexes
    print("Building spatial & location indexes...")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_stops_coords ON stops(stop_lat, stop_lon);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_stops_loc_type ON stops(location_type);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_stops_parent ON stops(parent_station);")

    # Run optimizer and vacuum
    print("Optimizing and analyzing SQLite database...")
    conn.commit()
    cur.execute("ANALYZE;")
    cur.execute("PRAGMA optimize;")
    conn.commit()
    conn.close()

    # Get final size
    size_mb = os.path.getsize(db_path) / 1024 / 1024
    print(f"🎉 Complete! Final `derivee_transit.sqlite` size: {size_mb:.2f} MB")

if __name__ == "__main__":
    main()
