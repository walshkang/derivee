#!/usr/bin/env python3
"""
Populate route_directions Table in derivee_transit.sqlite (Wave PB.5)
Extracts statistical mode headsigns from scheduled_hourly_patterns for rail/subway lines,
populates canonical bus route directions, and computes spatial extrema fallbacks
for all remaining surface bus corridors from transit.stops.
"""

import os
import sqlite3
import sys

KNOWN_BUS_DIRECTIONS = {
    # Staten Island Corridors
    "S51": {0: "St George Ferry", 1: "Midland Beach"},
    "S81": {0: "St George Ferry", 1: "Midland Beach"},
    "S79-SBS": {0: "Bay Ridge - 86 St", 1: "Staten Island Mall"},
    "S53": {0: "Bay Ridge - 86 St", 1: "Port Richmond"},
    "S52": {0: "St George Ferry", 1: "Staten Island Univ Hospital"},
    "S40": {0: "St George Ferry", 1: "Matrix Global Park"},
    "S42": {0: "St George Ferry", 1: "Clyde Pl"},
    "S44": {0: "St George Ferry", 1: "Staten Island Mall"},
    "S46": {0: "St George Ferry", 1: "West Shore Plaza"},
    "S48": {0: "St George Ferry", 1: "Holland Av"},
    "S54": {0: "West New Brighton", 1: "Eltingville"},
    "S55": {0: "Rossville", 1: "Staten Island Mall"},
    "S56": {0: "Huguenot", 1: "Staten Island Mall"},
    "S57": {0: "Port Richmond", 1: "New Dorp"},
    "S59": {0: "Port Richmond", 1: "Tottenville"},
    "S61": {0: "St George Ferry", 1: "Staten Island Mall"},
    "S62": {0: "St George Ferry", 1: "Travis"},
    "S66": {0: "St George Ferry", 1: "Port Richmond"},
    "S74": {0: "St George Ferry", 1: "Tottenville"},
    "S76": {0: "St George Ferry", 1: "Oakwood"},
    "S78": {0: "St George Ferry", 1: "Bricktown Mall"},
    "S84": {0: "St George Ferry", 1: "Tottenville"},
    "S86": {0: "St George Ferry", 1: "Oakwood"},
    "S89": {0: "Bayonne - 34 St Light Rail", 1: "Eltingville"},
    "S90": {0: "St George Ferry", 1: "Matrix Global Park"},
    "S91": {0: "St George Ferry", 1: "Staten Island Mall"},
    "S92": {0: "St George Ferry", 1: "Travis"},
    "S93": {0: "Bay Ridge - 86 St", 1: "CSI"},
    "S94": {0: "St George Ferry", 1: "Staten Island Mall"},
    "S96": {0: "St George Ferry", 1: "West Shore Plaza"},
    "S98": {0: "St George Ferry", 1: "Holland Av"},
    # Manhattan / Brooklyn / Queens Trunks
    "M10": {0: "Harlem - 159 St / Frederick Douglass Blvd", 1: "Columbus Circle - 58 St / 8 Ave"},
    "M15": {0: "East Harlem - 125 St", 1: "South Ferry"},
    "M15-SBS": {0: "East Harlem - 125 St", 1: "South Ferry"},
    "B32": {0: "Long Island City - Queens Plaza", 1: "Williamsburg Bridge Plaza"},
    "B24": {0: "Greenpoint - Manhattan Ave", 1: "Williamsburg Bridge Plaza"},
    "B43": {0: "Greenpoint - Box St", 1: "Lefferts Gardens - Lincoln Rd"},
    "B41": {0: "Downtown Brooklyn - Cadman Plaza", 1: "Kings Plaza / Bergen Beach"},
    "B44-SBS": {0: "Williamsburg Bridge Plaza", 1: "Sheepshead Bay - Knapp St"},
    "B62": {0: "Long Island City - Queens Plaza", 1: "Downtown Brooklyn - Boerum Pl"},
    "Q54": {0: "Jamaica - 170 St / Jamaica Ave", 1: "Williamsburg Bridge Plaza"},
    "Q59": {0: "Rego Park - 63 Dr / Queens Blvd", 1: "Williamsburg Bridge Plaza"},
    "Q32": {0: "Jackson Heights - 82 St / Northern Blvd", 1: "Midtown - Penn Station"},
    "Q70-SBS": {0: "LaGuardia Airport - Terminals B/C", 1: "Woodside - 61 St / 74 St-Broadway"},
}

def main():
    db_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "../DeriveeNative/Derivee/derivee_transit.sqlite"
    )
    if not os.path.exists(db_path):
        print(f"❌ Database not found at {db_path}")
        sys.exit(1)

    print(f"Connecting to database: {db_path}")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # 1. Create table
    cur.execute("""
        CREATE TABLE IF NOT EXISTS route_directions (
            route_id TEXT NOT NULL,
            direction_id INTEGER NOT NULL,
            headsign TEXT NOT NULL,
            terminal_stop_id TEXT NOT NULL,
            PRIMARY KEY (route_id, direction_id)
        );
    """)

    # 2. Extract statistical mode from scheduled_hourly_patterns (Rail / Subway)
    cur.execute("""
        SELECT route_id, direction_id, headsign, count(*) as cnt
        FROM scheduled_hourly_patterns
        WHERE headsign != ''
        GROUP BY route_id, direction_id, headsign
        ORDER BY route_id, direction_id, cnt DESC
    """)
    rows = cur.fetchall()

    seen_rail = set()
    inserted = 0
    for r_id, dir_id, headsign, _ in rows:
        key = (r_id, dir_id)
        if key in seen_rail:
            continue
        seen_rail.insert if hasattr(seen_rail, "insert") else seen_rail.add(key)
        cur.execute("""
            INSERT OR REPLACE INTO route_directions (route_id, direction_id, headsign, terminal_stop_id)
            VALUES (?, ?, ?, '')
        """, (r_id, dir_id, headsign))
        inserted += 1

    print(f"✅ Ingested {inserted} rail route directions from scheduled_hourly_patterns")

    # 3. Ingest known bus route directions
    bus_inserted = 0
    for r_id, dirs in KNOWN_BUS_DIRECTIONS.items():
        for dir_id, headsign in dirs.items():
            cur.execute("""
                INSERT OR REPLACE INTO route_directions (route_id, direction_id, headsign, terminal_stop_id)
                VALUES (?, ?, ?, '')
            """, (r_id, dir_id, headsign))
            bus_inserted += 1

    print(f"✅ Ingested {bus_inserted} known bus route directions")

    # 4. Compute spatial corridor extrema for all remaining distinct routes in stops
    cur.execute("SELECT DISTINCT routes FROM stops WHERE routes IS NOT NULL AND routes != ''")
    all_route_tokens = set()
    for (r_str,) in cur.fetchall():
        for tok in r_str.split(","):
            tok = tok.strip()
            if tok:
                all_route_tokens.add(tok)

    extrema_inserted = 0
    for r_id in sorted(all_route_tokens):
        for dir_id in (0, 1):
            cur.execute("SELECT 1 FROM route_directions WHERE route_id = ? AND direction_id = ?", (r_id, dir_id))
            if cur.fetchone() is not None:
                continue

            # Query stops for this route
            cur.execute("""
                SELECT stop_name, stop_lat, stop_lon
                FROM stops
                WHERE (',' || routes || ',') LIKE ?
            """, (f"%,{r_id},%",))
            stop_rows = cur.fetchall()
            if not stop_rows:
                continue

            lats = [r[1] for r in stop_rows if r[1] is not None]
            lons = [r[2] for r in stop_rows if r[2] is not None]
            if not lats or not lons:
                continue

            lat_span = max(lats) - min(lats)
            lon_span = max(lons) - min(lons)
            is_east_west = lon_span > lat_span

            # Sort stops
            if is_east_west:
                sorted_stops = sorted(stop_rows, key=lambda s: s[2])
            else:
                sorted_stops = sorted(stop_rows, key=lambda s: s[1])

            # For dir 0, pick first or last based on direction
            terminal_stop = sorted_stops[-1] if dir_id == 0 else sorted_stops[0]
            headsign = terminal_stop[0]
            if headsign:
                cur.execute("""
                    INSERT OR REPLACE INTO route_directions (route_id, direction_id, headsign, terminal_stop_id)
                    VALUES (?, ?, ?, '')
                """, (r_id, dir_id, headsign))
                extrema_inserted += 1

    print(f"✅ Ingested {extrema_inserted} spatial corridor extrema fallbacks")

    # Final count
    cur.execute("SELECT count(*) FROM route_directions")
    total = cur.fetchone()[0]
    print(f"🎉 Total route_directions rows: {total}")

    conn.commit()
    cur.execute("ANALYZE;")
    cur.execute("PRAGMA optimize;")
    conn.commit()
    conn.close()

if __name__ == "__main__":
    main()
