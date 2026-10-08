#!/usr/bin/env python3
"""
gen_routes.py
Reads routes table from transit.sqlite and exports dictionary of route metadata
{ route_id: { "shortName": ..., "color": ..., "textColor": ... } }
to DeriveeWeb/public/data/routes.json for offline line badge rendering.
"""

import os
import sys
import sqlite3
import json

def is_valid_routes_db(path):
    if not path or not os.path.exists(path):
        return False
    try:
        conn = sqlite3.connect(path)
        cur = conn.cursor()
        cur.execute("SELECT 1 FROM routes LIMIT 1")
        conn.close()
        return True
    except Exception:
        return False

def find_transit_db(repo_root):
    # Allow overriding db_path via args or environment
    db_candidates = [
        sys.argv[1] if len(sys.argv) > 1 else None,
        os.environ.get('TRANSIT_SQLITE_PATH'),
        # NOTE: no audit fallbacks — the T1-era subway-only snapshot
        # (derivee-audits/t1/transit.sqlite) silently clobbered production
        # bus data on 2026-10-08. Pass the production sqlite explicitly.
        os.path.join(repo_root, 'transit.sqlite'),
        os.path.join(repo_root, 'DeriveeNative/Derivee/transit.sqlite'),
    ]
    for p in db_candidates:
        if is_valid_routes_db(p):
            return p
    # Fallback search if not found in explicit candidates
    for root, dirs, files in os.walk(repo_root):
        if 'transit.sqlite' in files:
            p = os.path.join(root, 'transit.sqlite')
            if is_valid_routes_db(p):
                return p
    return None

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, '../../..'))

    db_path = find_transit_db(repo_root)
    if not db_path:
        print("ERROR: valid transit.sqlite with 'routes' table not found in repo or candidates.", file=sys.stderr)
        sys.exit(1)

    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(repo_root, 'DeriveeWeb/public/data/routes.json')
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    print(f"[gen_routes] Reading routes from {db_path}...")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("SELECT route_id, route_short_name, route_color, route_text_color FROM routes ORDER BY route_id ASC")
    rows = cur.fetchall()

    routes = {}
    for route_id, short_name, color, text_color in rows:
        clean_route_id = str(route_id).strip()
        clean_short_name = str(short_name).strip() if short_name else clean_route_id
        clean_color = color.lstrip('#').strip().upper() if color else "7C858C"
        clean_text_color = text_color.lstrip('#').strip().upper() if text_color else "FFFFFF"

        routes[clean_route_id] = {
            "shortName": clean_short_name,
            "color": clean_color,
            "textColor": clean_text_color
        }

    conn.close()

    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(routes, f, indent=2)

    size_bytes = os.path.getsize(out_path)
    size_kb = size_bytes / 1024.0

    print(f"[gen_routes] Successfully generated {len(routes)} routes into {out_path}")
    print(f"[gen_routes] File size: {size_bytes} bytes ({size_kb:.2f} KB)")

if __name__ == '__main__':
    main()
