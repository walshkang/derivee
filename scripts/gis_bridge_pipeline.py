"""
GIS OpenStreetMap Pedestrian Bridge Preservation Pipeline (Wave L-A.3: WLA3-GIS-BRIDGES)

Implements the mandatory GIS pipeline formula:
    Walkable_Mask = (Neighborhood_Polygon \\ Water_Polygons) ∪ Pedestrian_Bridges

Extracts pedestrian-accessible bridges from OpenStreetMap (Overpass API / cached GeoJSON),
buffers bridge line geometries into 2D corridors, performs boolean geographic subtraction
with water bodies while restoring bridge decks, polyfills with Uber H3 at resolution 11,
and emits optimized SQLite databases with pre-compiled query optimizer statistics (sqlite_stat1).
"""

import os
import json
import time
import sqlite3
import logging
from typing import List, Dict, Tuple, Optional, Set, Any
import requests
import h3
from shapely.geometry import shape, mapping, Polygon, MultiPolygon, LineString, MultiLineString, Point
from shapely.ops import unary_union
from shapely.validation import make_valid

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("gis_bridge_pipeline")

# Default Overpass interpreter mirrors
OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://lz4.overpass-api.de/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
]

USER_AGENT = "Derivee-GIS-Pipeline/1.0 (https://github.com/walshkang/derivee)"

# Degrees per meter approximation (at ~40.7 deg latitude)
# 1 degree lat ≈ 111,000m, 1 degree lon ≈ 84,000m
# 25 meters ≈ 0.00025 degrees (matches H3 resolution 11 hexagon radius)
DEFAULT_BRIDGE_BUFFER_DEGREES = 0.00025 # ~25m buffer covering walkways, bike paths, and approaches
DEFAULT_CATCHMENT_BUFFER_DEGREES = 0.0050 # ~500m catchment expansion into water for bridge attribution


def is_pedestrian_bridge_tags(tags: Dict[str, str]) -> bool:
    """
    Evaluates whether OSM tags represent a pedestrian or cycling-accessible bridge.
    Matches:
      - bridge=* (where bridge != 'no')
      - highway in (footway, cycleway, pedestrian, path, steps, living_street, track)
      - OR highway in (primary, secondary, tertiary, trunk, residential, unclassified) WITH
        sidewalk in (both, left, right, yes, separate) OR foot/bicycle in (yes, designated, permissive).
    Explicitly filters out motor-only spans (e.g., motorways without sidewalks).
    """
    bridge = tags.get("bridge", "").strip().lower()
    if not bridge or bridge in ("no", "none", "0", "false"):
        return False

    # Check explicit pedestrian/cycle highway tags
    highway = tags.get("highway", "").strip().lower()
    pedestrian_highways = {
        "footway", "cycleway", "pedestrian", "path", "steps",
        "living_street", "platform", "corridor", "track"
    }
    if highway in pedestrian_highways:
        # Check that foot/access is not explicitly forbidden
        foot = tags.get("foot", "").strip().lower()
        access = tags.get("access", "").strip().lower()
        if foot in ("no", "prohibited", "private") or access in ("no", "private"):
            return False
        return True

    # Check road types with pedestrian access or designated sidewalks
    road_highways = {
        "primary", "secondary", "tertiary", "trunk", "residential",
        "unclassified", "service", "primary_link", "secondary_link",
        "tertiary_link", "trunk_link"
    }
    if highway in road_highways:
        sidewalk = tags.get("sidewalk", "").strip().lower()
        sidewalk_left = tags.get("sidewalk:left", "").strip().lower()
        sidewalk_right = tags.get("sidewalk:right", "").strip().lower()
        sidewalk_both = tags.get("sidewalk:both", "").strip().lower()
        has_sidewalk = (
            sidewalk in ("both", "left", "right", "yes", "separate") or
            sidewalk_left in ("yes", "separate") or
            sidewalk_right in ("yes", "separate") or
            sidewalk_both in ("yes", "separate")
        )

        foot = tags.get("foot", "").strip().lower()
        bicycle = tags.get("bicycle", "").strip().lower()
        has_foot_access = foot in ("yes", "designated", "permissive")
        has_bike_access = bicycle in ("yes", "designated", "permissive")

        if (has_sidewalk or has_foot_access or has_bike_access):
            if foot in ("no", "prohibited") or tags.get("access") in ("no", "private"):
                return False
            return True

    # Check explicit foot/bicycle permissions
    foot = tags.get("foot", "").strip().lower()
    bicycle = tags.get("bicycle", "").strip().lower()
    if foot in ("yes", "designated", "permissive") or bicycle in ("yes", "designated", "permissive"):
        return True

    return False


class OSMBridgeFetcher:
    """Fetches, filters, and caches pedestrian bridge features from OpenStreetMap."""

    def __init__(self, endpoints: Optional[List[str]] = None, user_agent: str = USER_AGENT):
        self.endpoints = endpoints or OVERPASS_ENDPOINTS
        self.user_agent = user_agent

    def build_overpass_query(self, bbox: Tuple[float, float, float, float]) -> str:
        """
        Builds an Overpass QL query for pedestrian and cycling bridges in a bounding box.
        bbox: (min_lat, min_lon, max_lat, max_lon)
        """
        min_lat, min_lon, max_lat, max_lon = bbox
        return f"""
[out:json][timeout:60];
(
  way["bridge"]["bridge"!="no"]["highway"~"^(footway|cycleway|pedestrian|path|steps|living_street|track)$"]({min_lat},{min_lon},{max_lat},{max_lon});
  way["bridge"]["bridge"!="no"]["highway"~"^(primary|secondary|tertiary|trunk|residential|unclassified|service)$"]["sidewalk"~"^(both|left|right|yes|separate)$"]({min_lat},{min_lon},{max_lat},{max_lon});
  way["bridge"]["bridge"!="no"]["highway"~"^(primary|secondary|tertiary|trunk|residential|unclassified|service)$"]["foot"~"^(yes|designated|permissive)$"]({min_lat},{min_lon},{max_lat},{max_lon});
  way["bridge"]["bridge"!="no"]["highway"~"^(primary|secondary|tertiary|trunk|residential|unclassified|service)$"]["bicycle"~"^(yes|designated|permissive)$"]({min_lat},{min_lon},{max_lat},{max_lon});
  way["bridge"]["bridge"!="no"]["foot"~"^(yes|designated|permissive)$"]({min_lat},{min_lon},{max_lat},{max_lon});
);
out body;
>;
out skel qt;
"""

    def fetch_from_overpass(self, bbox: Tuple[float, float, float, float]) -> Optional[Dict[str, Any]]:
        """Queries Overpass API endpoints with failover and exponential backoff."""
        query = self.build_overpass_query(bbox)
        headers = {"User-Agent": self.user_agent}

        for endpoint in self.endpoints:
            logger.info("Querying Overpass endpoint: %s", endpoint)
            try:
                resp = requests.post(endpoint, data={"data": query}, headers=headers, timeout=45)
                if resp.status_code == 200:
                    data = resp.json()
                    logger.info("Successfully fetched %d elements from %s", len(data.get("elements", [])), endpoint)
                    return data
                logger.warning("Endpoint %s returned HTTP status %d", endpoint, resp.status_code)
            except Exception as e:
                logger.warning("Endpoint %s failed: %s", endpoint, e)
            time.sleep(2)

        return None

    def overpass_to_geojson(self, overpass_data: Dict[str, Any]) -> Dict[str, Any]:
        """Converts Overpass elements to a GeoJSON FeatureCollection of LineStrings."""
        elements = overpass_data.get("elements", [])
        nodes = {n["id"]: (n["lon"], n["lat"]) for n in elements if n.get("type") == "node"}
        features = []

        for el in elements:
            if el.get("type") == "way" and "nodes" in el:
                coords = [nodes[nid] for nid in el["nodes"] if nid in nodes]
                if len(coords) >= 2:
                    tags = el.get("tags", {})
                    if not is_pedestrian_bridge_tags(tags):
                        continue
                    feat = {
                        "type": "Feature",
                        "geometry": {
                            "type": "LineString",
                            "coordinates": coords
                        },
                        "properties": {
                            "osm_id": el.get("id"),
                            "name": tags.get("name", ""),
                            "highway": tags.get("highway", ""),
                            "bridge": tags.get("bridge", ""),
                            "sidewalk": tags.get("sidewalk", ""),
                            "foot": tags.get("foot", ""),
                            "bicycle": tags.get("bicycle", ""),
                            "tags": tags
                        }
                    }
                    features.append(feat)

        return {
            "type": "FeatureCollection",
            "features": features
        }

    def get_pedestrian_bridges_geojson(
        self,
        bbox: Tuple[float, float, float, float],
        cache_path: Optional[str] = None,
        force_download: bool = False
    ) -> Dict[str, Any]:
        """Loads cached bridge GeoJSON if available, or fetches from Overpass and caches."""
        if not force_download and cache_path and os.path.exists(cache_path):
            logger.info("Loading cached pedestrian bridges from %s", cache_path)
            with open(cache_path, "r", encoding="utf-8") as f:
                return json.load(f)

        logger.info("Fetching pedestrian bridges from Overpass for bbox: %s", bbox)
        overpass_data = self.fetch_from_overpass(bbox)
        if not overpass_data:
            if cache_path and os.path.exists(cache_path):
                logger.warning("Overpass fetch failed; falling back to cached file %s", cache_path)
                with open(cache_path, "r", encoding="utf-8") as f:
                    return json.load(f)
            raise RuntimeError(f"Failed to fetch pedestrian bridges from Overpass and no cache found at {cache_path}")

        geojson = self.overpass_to_geojson(overpass_data)
        if cache_path:
            os.makedirs(os.path.dirname(os.path.abspath(cache_path)), exist_ok=True)
            with open(cache_path, "w", encoding="utf-8") as f:
                json.dump(geojson, f, indent=2)
            logger.info("Cached %d pedestrian bridge features to %s", len(geojson["features"]), cache_path)

        return geojson


class BooleanGISProcessor:
    """Executes boolean geographic operations to compute walkable landmass and preserve bridges."""

    def __init__(self, bridge_buffer_degrees: float = DEFAULT_BRIDGE_BUFFER_DEGREES):
        self.bridge_buffer_degrees = bridge_buffer_degrees

    def build_bridge_polygon_union(self, bridge_geojson: Dict[str, Any]) -> Any:
        """Buffers bridge geometries into 2D corridors and creates a unified geometry."""
        bridge_polys = []
        for feature in bridge_geojson.get("features", []):
            geom = feature.get("geometry")
            if not geom:
                continue
            try:
                s_geom = shape(geom)
                s_geom = make_valid(s_geom)
                if isinstance(s_geom, (LineString, MultiLineString)):
                    buffered = s_geom.buffer(self.bridge_buffer_degrees)
                    buffered = make_valid(buffered)
                    bridge_polys.append(buffered)
                elif isinstance(s_geom, (Polygon, MultiPolygon)):
                    bridge_polys.append(s_geom)
            except Exception as e:
                logger.warning("Failed to process bridge geometry %s: %s", feature.get("properties", {}).get("osm_id"), e)

        if not bridge_polys:
            return Polygon()

        union_geom = unary_union(bridge_polys)
        return make_valid(union_geom)

    def compute_walkable_mask(
        self,
        neighborhood_geom: Any,
        water_union: Any,
        bridges_union: Any,
        catchment_buffer_degrees: float = DEFAULT_CATCHMENT_BUFFER_DEGREES
    ) -> Any:
        """
        Implements the boolean formula:
            Walkable_Mask = (Neighborhood_Polygon \\ Water_Polygons) ∪ Pedestrian_Bridges_In_Catchment
        """
        neighborhood_geom = make_valid(neighborhood_geom)

        # 1. Terrestrial Landmass = Neighborhood \ Water
        if water_union and not water_union.is_empty:
            land_geom = neighborhood_geom.difference(water_union)
        else:
            land_geom = neighborhood_geom
        land_geom = make_valid(land_geom)

        # 2. Bridge Attribution: Intersect bridges with neighborhood expanded catchment
        if bridges_union and not bridges_union.is_empty:
            # Expand neighborhood geometry into water corridor to catch attached bridge spans
            catchment_geom = make_valid(neighborhood_geom.buffer(catchment_buffer_degrees))
            neighborhood_bridges = bridges_union.intersection(catchment_geom)
            neighborhood_bridges = make_valid(neighborhood_bridges)

            if not neighborhood_bridges.is_empty:
                # 3. Walkable = Land ∪ Bridges
                walkable_geom = unary_union([land_geom, neighborhood_bridges])
                return make_valid(walkable_geom)

        return land_geom


class H3Polyfiller:
    """Polyfills 2D Shapely geometries with Uber H3 resolution 11 hexagons."""

    @staticmethod
    def shapely_to_h3_poly(geom: Polygon) -> h3.LatLngPoly:
        """Converts a Shapely Polygon to h3.LatLngPoly with (lat, lng) coordinates."""
        exterior = [(lat, lng) for lng, lat in geom.exterior.coords]
        holes = []
        for interior in geom.interiors:
            holes.append([(lat, lng) for lng, lat in interior.coords])
        return h3.LatLngPoly(exterior, *holes)

    @classmethod
    def get_hexes_for_geometry(cls, geom: Any, resolution: int = 11) -> Set[str]:
        """Polyfills a Polygon or MultiPolygon with H3 cells at the given resolution."""
        hexes: Set[str] = set()
        if geom is None or geom.is_empty:
            return hexes

        if isinstance(geom, Polygon):
            try:
                poly = cls.shapely_to_h3_poly(geom)
                hexes.update(h3.polygon_to_cells(poly, resolution))
            except Exception as e:
                logger.warning("H3 polyfill error on Polygon: %s", e)
        elif isinstance(geom, MultiPolygon):
            for part in geom.geoms:
                try:
                    poly = cls.shapely_to_h3_poly(part)
                    hexes.update(h3.polygon_to_cells(poly, resolution))
                except Exception as e:
                    logger.warning("H3 polyfill error on MultiPolygon part: %s", e)
        return hexes


class SQLitePackWriter:
    """Exports neighborhood stats and hex mappings to a high-performance SQLite database."""

    @staticmethod
    def write_neighborhood_db(
        neighborhood_stats: List[Dict[str, Any]],
        neighborhood_hexes: Dict[str, str],
        output_db_path: str
    ) -> None:
        """
        Emits SQLite database with WITHOUT ROWID tables, WAL mode, indices,
        and embedded sqlite_stat1 query optimizer statistics.
        """
        if os.path.exists(output_db_path):
            os.remove(output_db_path)

        os.makedirs(os.path.dirname(os.path.abspath(output_db_path)), exist_ok=True)
        logger.info("Writing output to SQLite database at %s...", output_db_path)

        conn = sqlite3.connect(output_db_path)
        cursor = conn.cursor()

        # Enable WAL mode
        cursor.execute("PRAGMA journal_mode = WAL;")
        cursor.execute("PRAGMA synchronous = NORMAL;")

        # Create Schema (WITHOUT ROWID for read-only static lookups)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS neighborhood_stats (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                total_hexes INTEGER NOT NULL,
                centroid_lat REAL NOT NULL,
                centroid_lng REAL NOT NULL
            ) WITHOUT ROWID;
        """)

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS neighborhood_hexes (
                h3_index TEXT PRIMARY KEY,
                neighborhood_id TEXT NOT NULL
            ) WITHOUT ROWID;
        """)

        # Insert stats
        for stat in neighborhood_stats:
            cursor.execute(
                "INSERT INTO neighborhood_stats (id, name, total_hexes, centroid_lat, centroid_lng) VALUES (?, ?, ?, ?, ?)",
                (stat["id"], stat["name"], stat["total_hexes"], stat["centroid_lat"], stat["centroid_lng"])
            )

        # Bulk insert hexes
        hex_items = list(neighborhood_hexes.items())
        cursor.executemany(
            "INSERT INTO neighborhood_hexes (h3_index, neighborhood_id) VALUES (?, ?)",
            hex_items
        )
        conn.commit()

        # Create index for fast reverse lookup
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_neighborhood_hexes_id ON neighborhood_hexes(neighborhood_id);")
        conn.commit()

        # Run optimizer & ANALYZE to embed sqlite_stat1
        cursor.execute("PRAGMA analysis_limit = 1000;")
        cursor.execute("ANALYZE;")
        cursor.execute("PRAGMA optimize(0x10000);")
        conn.commit()
        conn.close()

        logger.info("Successfully exported SQLite database with %d neighborhoods and %d hexes.",
                    len(neighborhood_stats), len(neighborhood_hexes))
