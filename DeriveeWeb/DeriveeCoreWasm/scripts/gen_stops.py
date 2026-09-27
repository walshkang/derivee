#!/usr/bin/env python3
"""
gen_stops.py
Reads stops table from transit.sqlite and exports [{id, name, lat, lon}]
to DeriveeWeb/public/data/stops.json for offline autocomplete and itinerary rendering.
"""

import os
import sys
import sqlite3
import json

def main():
    # Allow overriding db_path or out_path via args or environment
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, '../../..'))
    
    db_candidates = [
        sys.argv[1] if len(sys.argv) > 1 else None,
        os.environ.get('TRANSIT_SQLITE_PATH'),
        '/home/hatch/workspace/derivee-audits/t1/transit.sqlite',
        os.path.join(repo_root, '../derivee-audits/t1/transit.sqlite'),
        os.path.join(repo_root, 'transit.sqlite'),
    ]
    
    db_path = next((p for p in db_candidates if p and os.path.exists(p)), None)
    if not db_path:
        print("ERROR: transit.sqlite not found in candidates:", db_candidates, file=sys.stderr)
        sys.exit(1)

    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(repo_root, 'DeriveeWeb/public/data/stops.json')
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    print(f"[gen_stops] Reading stops from {db_path}...")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Note: Sorting by stop_id ASC matches the exact index order in timetable.bin
    cur.execute("SELECT stop_id, stop_name, stop_lat, stop_lon FROM stops ORDER BY stop_id ASC")
    rows = cur.fetchall()

    stops = []
    for idx, (stop_id, name, lat, lon) in enumerate(rows):
        stops.append({
            "id": idx,
            "name": name,
            "lat": round(lat, 6),
            "lon": round(lon, 6)
        })

    conn.close()

    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(stops, f, separators=(',', ':'))

    size_bytes = os.path.getsize(out_path)
    size_kb = size_bytes / 1024.0
    size_mb = size_bytes / (1024.0 * 1024.0)

    print(f"[gen_stops] Successfully generated {len(stops)} stops into {out_path}")
    print(f"[gen_stops] File size: {size_bytes} bytes ({size_kb:.2f} KB, {size_mb:.2f} MB)")

    if size_mb > 1.0:
        print(f"[gen_stops] WARNING: stops.json is larger than 1 MB ({size_mb:.2f} MB)!", file=sys.stderr)
    else:
        print("[gen_stops] Check passed: stops.json is under 1 MB budget.")

if __name__ == '__main__':
    main()
