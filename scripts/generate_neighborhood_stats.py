#!/usr/bin/env python3
"""
Generate Neighborhood Stats with GIS Bridge Preservation (Wave L-A.3: WLA3-GIS-BRIDGES)

CLI Tool that compiles neighborhood boundaries, subtracts water polygons, and preserves
OpenStreetMap pedestrian bridges using the boolean formula:
    Walkable_Mask = (Neighborhood_Polygon \\ Water_Polygons) ∪ Pedestrian_Bridges

Emits:
    - assets/neighborhood.sqlite (with WITHOUT ROWID tables, WAL mode, indices, and sqlite_stat1)
    - assets/neighborhood_data.json (for inspection / metadata)
"""

import os
import sys
import json
import argparse
import logging
from typing import Dict, List, Any, Optional

import requests
from shapely.geometry import shape
from shapely.ops import unary_union
from shapely.validation import make_valid

# Ensure scripts directory is on Python path
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from gis_bridge_pipeline import (
    OSMBridgeFetcher,
    BooleanGISProcessor,
    H3Polyfiller,
    SQLitePackWriter,
    DEFAULT_BRIDGE_BUFFER_DEGREES,
    DEFAULT_CATCHMENT_BUFFER_DEGREES
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("generate_neighborhood_stats")

# Default URLs and bounding boxes
CITY_DATA_SOURCES = {
    "nyc": {
        "name": "New York City",
        "bbox": (40.48, -74.28, 40.95, -73.68),
        "neighborhood_url": "https://data.cityofnewyork.us/api/geospatial/9nt8-h7nd?method=export&format=GeoJSON",
        "neighborhood_file": "nta.geojson",
        "water_url": "https://data.cityofnewyork.us/api/views/drh3-e2fd/rows.geojson?accessType=DOWNLOAD",
        "water_file": "water.geojson",
        "bridge_file": "nyc_pedestrian_bridges.geojson",
        "id_prop": "nta2020",
        "name_prop": "ntaname"
    },
    "bos": {
        "name": "Boston",
        "bbox": (42.22, -71.20, 42.45, -70.92),
        "neighborhood_url": "https://bostonopendata-boston.opendata.arcgis.com/datasets/boston::boston-neighborhoods.geojson",
        "neighborhood_file": "bos_neighborhoods.geojson",
        "water_file": "bos_water.geojson",
        "bridge_file": "bos_pedestrian_bridges.geojson",
        "id_prop": "id",
        "name_prop": "Name"
    }
}


def download_or_load_geojson(url: Optional[str], filename: str, cache_dir: str, offline: bool = False) -> Dict[str, Any]:
    """Loads cached GeoJSON file or downloads from URL if not cached."""
    os.makedirs(cache_dir, exist_ok=True)
    cache_path = os.path.join(cache_dir, filename)

    if os.path.exists(cache_path):
        logger.info("Loading cached %s from %s...", filename, cache_path)
        with open(cache_path, "r", encoding="utf-8") as f:
            return json.load(f)

    if offline or not url:
        raise FileNotFoundError(f"File {filename} not found in cache {cache_dir} and offline mode is enabled or URL missing.")

    logger.info("Downloading %s from %s...", filename, url)
    response = requests.get(url, timeout=60)
    response.raise_for_status()
    data = response.json()

    with open(cache_path, "w", encoding="utf-8") as f:
        json.dump(data, f)
    logger.info("Saved %s to cache.", filename)
    return data


def process_city_neighborhoods(
    city_slug: str,
    cache_dir: str,
    output_db: str,
    output_json: Optional[str] = None,
    offline: bool = False,
    bridge_buffer: float = DEFAULT_BRIDGE_BUFFER_DEGREES,
    catchment_buffer: float = DEFAULT_CATCHMENT_BUFFER_DEGREES,
    export_geojson_path: Optional[str] = None
) -> Tuple[List[Dict[str, Any]], Dict[str, str]]:
    """
    Executes the full GIS bridge preservation pipeline for a given city.
    Returns (neighborhood_stats, neighborhood_hexes).
    """
    if city_slug not in CITY_DATA_SOURCES:
        raise ValueError(f"Unknown city slug '{city_slug}'. Supported cities: {list(CITY_DATA_SOURCES.keys())}")

    city_info = CITY_DATA_SOURCES[city_slug]
    logger.info("=== Processing GIS Walkable Mask & Bridge Preservation for %s (%s) ===", city_info["name"], city_slug)

    # 1. Load Neighborhood Geometries
    logger.info("1/5 Loading neighborhood boundaries...")
    neighborhood_data = download_or_load_geojson(
        city_info.get("neighborhood_url"),
        city_info.get("neighborhood_file", "nta.geojson"),
        cache_dir,
        offline=offline
    )

    # 2. Load and Union Water Geometries
    logger.info("2/5 Loading and unioning water geometries...")
    water_data = download_or_load_geojson(
        city_info.get("water_url"),
        city_info.get("water_file", "water.geojson"),
        cache_dir,
        offline=offline
    )

    water_geoms = []
    for feature in water_data.get("features", []):
        if not feature.get("geometry"):
            continue
        try:
            g = shape(feature["geometry"])
            g = make_valid(g)
            water_geoms.append(g)
        except Exception as e:
            logger.warning("Failed to parse water geometry: %s", e)

    logger.info("Dissolving %d water features into unified water mask...", len(water_geoms))
    water_union = unary_union(water_geoms) if water_geoms else None
    if water_union is not None:
        water_union = make_valid(water_union)
    logger.info("Water union created.")

    # 3. Fetch / Load Pedestrian Bridges
    logger.info("3/5 Ingesting OpenStreetMap pedestrian bridges...")
    bridge_fetcher = OSMBridgeFetcher()
    bridge_cache_file = os.path.join(cache_dir, city_info.get("bridge_file", f"{city_slug}_pedestrian_bridges.geojson"))

    if os.path.exists(bridge_cache_file) or offline:
        logger.info("Loading cached bridge geometries from %s...", bridge_cache_file)
        with open(bridge_cache_file, "r", encoding="utf-8") as f:
            bridge_data = json.load(f)
    else:
        logger.info("Fetching bridge geometries from Overpass API for bbox %s...", city_info["bbox"])
        bridge_data = bridge_fetcher.get_pedestrian_bridges_geojson(
            city_info["bbox"],
            cache_path=bridge_cache_file,
            force_download=False
        )

    gis_processor = BooleanGISProcessor(bridge_buffer_degrees=bridge_buffer)
    logger.info("Buffering and unioning %d pedestrian bridge features (~%.1fm corridor)...",
                len(bridge_data.get("features", [])), bridge_buffer * 111000)
    bridges_union = gis_processor.build_bridge_polygon_union(bridge_data)
    logger.info("Bridges union created (area: %.8f sq deg).", bridges_union.area if bridges_union else 0.0)

    # 4. Process Walkable Mask per Neighborhood: (Neighborhood \ Water) ∪ Bridges
    logger.info("4/5 Executing Boolean Formula: Walkable = (Neighborhood \\ Water) ∪ Pedestrian_Bridges...")
    id_prop = city_info.get("id_prop", "nta2020")
    name_prop = city_info.get("name_prop", "ntaname")

    neighborhood_stats: List[Dict[str, Any]] = []
    neighborhood_hexes: Dict[str, str] = {}
    debug_features: List[Dict[str, Any]] = []

    features = neighborhood_data.get("features", [])
    for idx, feature in enumerate(features):
        props = feature.get("properties", {})
        n_id = props.get(id_prop)
        n_name = props.get(name_prop)

        if not n_id or not n_name:
            continue

        raw_geom = shape(feature["geometry"])
        walkable_geom = gis_processor.compute_walkable_mask(
            neighborhood_geom=raw_geom,
            water_union=water_union,
            bridges_union=bridges_union,
            catchment_buffer_degrees=catchment_buffer
        )

        if walkable_geom.is_empty:
            continue

        # Polyfill with H3 (Resolution 11)
        hexes = H3Polyfiller.get_hexes_for_geometry(walkable_geom, resolution=11)
        total_hexes = len(hexes)

        if total_hexes == 0:
            continue

        centroid = walkable_geom.centroid

        neighborhood_stats.append({
            "id": n_id,
            "name": n_name,
            "total_hexes": total_hexes,
            "centroid_lat": centroid.y,
            "centroid_lng": centroid.x
        })

        for h in hexes:
            # First assignment or closest neighborhood wins in case of overlap
            if h not in neighborhood_hexes:
                neighborhood_hexes[h] = n_id

        if export_geojson_path:
            debug_features.append({
                "type": "Feature",
                "geometry": mapping(walkable_geom),
                "properties": {
                    "id": n_id,
                    "name": n_name,
                    "total_hexes": total_hexes
                }
            })

        if (idx + 1) % 50 == 0 or idx == len(features) - 1:
            logger.info("Processed %d / %d neighborhoods (%s: %d hexes)",
                        idx + 1, len(features), n_name, total_hexes)

    # 5. Export SQLite Database and JSON Metadata
    logger.info("5/5 Exporting SQLite database to %s...", output_db)
    SQLitePackWriter.write_neighborhood_db(neighborhood_stats, neighborhood_hexes, output_db)

    if output_json:
        os.makedirs(os.path.dirname(os.path.abspath(output_json)), exist_ok=True)
        with open(output_json, "w", encoding="utf-8") as f:
            json.dump({
                "city": city_slug,
                "total_neighborhoods": len(neighborhood_stats),
                "total_hexes": len(neighborhood_hexes),
                "neighborhoods": neighborhood_stats
            }, f, indent=2)
        logger.info("Exported JSON metadata to %s", output_json)

    if export_geojson_path:
        with open(export_geojson_path, "w", encoding="utf-8") as f:
            json.dump({
                "type": "FeatureCollection",
                "features": debug_features
            }, f)
        logger.info("Exported debug GeoJSON to %s", export_geojson_path)

    logger.info("✅ Finished processing %s! Total neighborhoods: %d, Total hexes: %d",
                city_info["name"], len(neighborhood_stats), len(neighborhood_hexes))

    return neighborhood_stats, neighborhood_hexes


def main():
    parser = argparse.ArgumentParser(description="Generate Neighborhood Stats with GIS Bridge Preservation Pipeline")
    parser.add_argument("--city", default="nyc", choices=["nyc", "bos"], help="City slug to process (default: nyc)")
    parser.add_argument("--cache-dir", default=os.path.join(CURRENT_DIR, "cache"), help="Path to cache directory")
    parser.add_argument("--output-db", default=os.path.join(CURRENT_DIR, "..", "assets", "neighborhood.sqlite"),
                        help="Path to output SQLite database")
    parser.add_argument("--output-json", default=os.path.join(CURRENT_DIR, "..", "assets", "neighborhood_data.json"),
                        help="Path to output JSON metadata file")
    parser.add_argument("--offline", action="store_true", help="Run exclusively offline using cached datasets")
    parser.add_argument("--bridge-buffer", type=float, default=DEFAULT_BRIDGE_BUFFER_DEGREES,
                        help="Corridor buffer for bridge line strings in degrees (default: 0.00015 ≈ 15m)")
    parser.add_argument("--catchment-buffer", type=float, default=DEFAULT_CATCHMENT_BUFFER_DEGREES,
                        help="Neighborhood catchment buffer for bridge spans in degrees (default: 0.0035 ≈ 350m)")
    parser.add_argument("--export-geojson", help="Optional path to export debug walkable mask GeoJSON")
    args = parser.parse_args()

    process_city_neighborhoods(
        city_slug=args.city,
        cache_dir=args.cache_dir,
        output_db=args.output_db,
        output_json=args.output_json,
        offline=args.offline,
        bridge_buffer=args.bridge_buffer,
        catchment_buffer=args.catchment_buffer,
        export_geojson_path=args.export_geojson
    )


if __name__ == "__main__":
    main()
