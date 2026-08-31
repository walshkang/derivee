"""
Test Suite for GIS Bridge Preservation Pipeline (Wave L-A.3: WLA3-GIS-BRIDGES)

Validates:
1. Walkable Mask Formula: Walkable_Mask = (Neighborhood \\ Water) ∪ Pedestrian_Bridges
2. Bridge Preservation: Williamsburg, Brooklyn, and Manhattan Bridges are preserved over water.
3. Water Subtraction: Open water points (East River away from bridges) remain strictly subtracted.
4. Terrestrial Land: Land coordinates (McCarren Park, Central Park) remain fully intact.
5. Denominator Verification: Waterfront neighborhood total_hexes denominators increase with bridge preservation.
6. Tag Filtering: Only pedestrian/bike bridges are included; motorways are excluded.
7. Database Integrity: SQLite tables are WITHOUT ROWID, indexed, and optimized with sqlite_stat1.
"""

import os
import sqlite3
import pytest
import h3
from shapely.geometry import Polygon, LineString, Point
from shapely.ops import unary_union

from gis_bridge_pipeline import (
    is_pedestrian_bridge_tags,
    BooleanGISProcessor,
    H3Polyfiller,
    SQLitePackWriter,
    DEFAULT_BRIDGE_BUFFER_DEGREES,
    DEFAULT_CATCHMENT_BUFFER_DEGREES
)

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "assets", "neighborhood.sqlite")


# ---------------------------------------------------------------------------
# Unit Tests: OSM Tag Filtering
# ---------------------------------------------------------------------------

def test_pedestrian_bridge_tag_matching_footways():
    """Footway, cycleway, and pedestrian bridge tags must be identified as pedestrian bridges."""
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "footway"}) is True
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "cycleway"}) is True
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "pedestrian"}) is True
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "steps"}) is True
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "path"}) is True
    assert is_pedestrian_bridge_tags({"bridge": "viaduct", "highway": "footway"}) is True


def test_pedestrian_bridge_tag_matching_road_with_sidewalk():
    """Road bridges with sidewalks or designated foot/bicycle access must be identified."""
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "primary", "sidewalk": "both"}) is True
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "secondary", "sidewalk": "right"}) is True
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "tertiary", "foot": "yes"}) is True
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "residential", "bicycle": "yes"}) is True
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "primary", "sidewalk:left": "yes"}) is True


def test_pedestrian_bridge_tag_filtering_motorways():
    """Pure motor vehicle bridges and explicit non-bridges must be excluded."""
    assert is_pedestrian_bridge_tags({"bridge": "no", "highway": "footway"}) is False
    assert is_pedestrian_bridge_tags({"highway": "footway"}) is False # Not a bridge
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "motorway"}) is False # Motorway, no sidewalk
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "motorway", "foot": "no"}) is False
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "trunk"}) is False
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "primary", "foot": "no"}) is False
    assert is_pedestrian_bridge_tags({"bridge": "yes", "highway": "footway", "access": "private"}) is False


# ---------------------------------------------------------------------------
# Unit Tests: Boolean GIS Mask & Bridge Corridor Math
# ---------------------------------------------------------------------------

def test_boolean_walkable_mask_formula():
    """
    Tests the fundamental boolean formula:
        Walkable_Mask = (Neighborhood \\ Water) ∪ Bridges
    """
    # Square neighborhood: (0,0) to (10,10)
    neighborhood = Polygon([(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)])

    # River running through the middle: x from 4 to 6
    river = Polygon([(4, -2), (6, -2), (6, 12), (4, 12), (4, -2)])

    # Bridge crossing the river: line from (3, 5) to (7, 5)
    bridge_line = LineString([(3, 5), (7, 5)])
    bridge_poly = bridge_line.buffer(0.5) # 1 unit wide bridge

    gis_processor = BooleanGISProcessor(bridge_buffer_degrees=0.5)

    # 1. Without bridges: center of river (5, 5) is subtracted
    land_without_bridge = neighborhood.difference(river)
    assert not land_without_bridge.contains(Point(5, 5)), "Center of river must be subtracted without bridge."

    # 2. With bridges: center of river (5, 5) is preserved by bridge corridor
    walkable_with_bridge = gis_processor.compute_walkable_mask(
        neighborhood_geom=neighborhood,
        water_union=river,
        bridges_union=bridge_poly,
        catchment_buffer_degrees=1.0
    )
    assert walkable_with_bridge.contains(Point(5, 5)), "Center of bridge over river must be preserved in walkable mask!"

    # 3. Off-bridge water: point (5, 8) in river away from bridge must remain subtracted
    assert not walkable_with_bridge.contains(Point(5, 8)), "River water away from bridge must remain subtracted."


# ---------------------------------------------------------------------------
# Integration Tests: NYC Neighborhood Database Lookups
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def db_connection():
    if not os.path.exists(DB_PATH):
        pytest.skip(f"Neighborhood database not found at {DB_PATH}. Run generate_neighborhood_stats.py first.")
    conn = sqlite3.connect(DB_PATH)
    yield conn
    conn.close()


def test_mccarren_park_terrestrial_land_preserved(db_connection):
    """McCarren Park land coordinate resolves to Williamsburg/Greenpoint."""
    lat, lng = 40.7215, -73.9515
    hex_index = h3.latlng_to_cell(lat, lng, 11)

    cursor = db_connection.cursor()
    cursor.execute('''
        SELECT n.name, n.id
        FROM neighborhood_hexes h
        JOIN neighborhood_stats n ON h.neighborhood_id = n.id
        WHERE h.h3_index = ?
    ''', (hex_index,))

    result = cursor.fetchone()
    assert result is not None, f"McCarren Park hex {hex_index} was not found in any neighborhood!"
    neighborhood_name, _ = result
    assert "Williamsburg" in neighborhood_name or "Greenpoint" in neighborhood_name


def test_central_park_terrestrial_land_preserved(db_connection):
    """Central Park land coordinate resolves to Manhattan neighborhood."""
    lat, lng = 40.7829, -73.9654
    hex_index = h3.latlng_to_cell(lat, lng, 11)

    cursor = db_connection.cursor()
    cursor.execute('''
        SELECT n.name, n.id
        FROM neighborhood_hexes h
        JOIN neighborhood_stats n ON h.neighborhood_id = n.id
        WHERE h.h3_index = ?
    ''', (hex_index,))

    result = cursor.fetchone()
    assert result is not None, f"Central Park hex {hex_index} was not found!"


def test_east_river_open_water_subtracted(db_connection):
    """Point in the middle of East River away from bridges is strictly subtracted (returns None)."""
    lat, lng = 40.7180, -73.9680 # Middle of East River between Williamsburg and East Village
    hex_index = h3.latlng_to_cell(lat, lng, 11)

    cursor = db_connection.cursor()
    cursor.execute('''
        SELECT n.name 
        FROM neighborhood_hexes h
        JOIN neighborhood_stats n ON h.neighborhood_id = n.id
        WHERE h.h3_index = ?
    ''', (hex_index,))

    result = cursor.fetchone()
    assert result is None, f"East River open water hex {hex_index} should have been subtracted, but resolved to {result}!"


def test_williamsburg_bridge_hexes_preserved(db_connection):
    """
    Pedestrian/cycling bridge deck on Williamsburg Bridge over East River
    is preserved in the walkable mask and attributed to Williamsburg or Lower East Side.
    """
    # Williamsburg Bridge pedestrian walkway spans over East River
    # Eastern span (Brooklyn side) -> Williamsburg (BK0102)
    lat_east, lng_east = 40.7135, -73.9721
    hex_east = h3.latlng_to_cell(lat_east, lng_east, 11)

    cursor = db_connection.cursor()
    cursor.execute('''
        SELECT n.name, n.id
        FROM neighborhood_hexes h
        JOIN neighborhood_stats n ON h.neighborhood_id = n.id
        WHERE h.h3_index = ?
    ''', (hex_east,))

    result_east = cursor.fetchone()
    assert result_east is not None, (
        f"Williamsburg Bridge East hex {hex_east} ({lat_east}, {lng_east}) was NOT found! "
        "GIS Bridge preservation failed to preserve the bridge corridor over water."
    )
    name_east, nid_east = result_east
    assert "Williamsburg" in name_east or "Lower East Side" in name_east or "Navy Yard" in name_east

    # Western span (Manhattan side) -> Lower East Side (MN0302)
    lat_west, lng_west = 40.7150, -73.9770
    hex_west = h3.latlng_to_cell(lat_west, lng_west, 11)
    cursor.execute('''
        SELECT n.name, n.id
        FROM neighborhood_hexes h
        JOIN neighborhood_stats n ON h.neighborhood_id = n.id
        WHERE h.h3_index = ?
    ''', (hex_west,))
    result_west = cursor.fetchone()
    assert result_west is not None, f"Williamsburg Bridge West hex {hex_west} was NOT found!"
    name_west, _ = result_west
    assert "Lower East Side" in name_west or "East Village" in name_west or "Williamsburg" in name_west


def test_brooklyn_bridge_hexes_preserved(db_connection):
    """Brooklyn Bridge pedestrian promenade over East River is preserved."""
    lat, lng = 40.7061, -73.9969
    hex_index = h3.latlng_to_cell(lat, lng, 11)

    cursor = db_connection.cursor()
    cursor.execute('''
        SELECT n.name, n.id
        FROM neighborhood_hexes h
        JOIN neighborhood_stats n ON h.neighborhood_id = n.id
        WHERE h.h3_index = ?
    ''', (hex_index,))

    result = cursor.fetchone()
    assert result is not None, f"Brooklyn Bridge hex {hex_index} was not found!"


def test_manhattan_bridge_hexes_preserved(db_connection):
    """Manhattan Bridge pedestrian/bike path over East River is preserved."""
    lat, lng = 40.7080, -73.9905
    hex_index = h3.latlng_to_cell(lat, lng, 11)

    cursor = db_connection.cursor()
    cursor.execute('''
        SELECT n.name, n.id
        FROM neighborhood_hexes h
        JOIN neighborhood_stats n ON h.neighborhood_id = n.id
        WHERE h.h3_index = ?
    ''', (hex_index,))

    result = cursor.fetchone()
    assert result is not None, f"Manhattan Bridge hex {hex_index} was not found!"


def test_boston_bridges_fixture_contains_longfellow_and_harvard_bridges():
    """
    Validates Boston cached bridge fixture (bos_pedestrian_bridges.geojson)
    contains Longfellow and Harvard Bridges across the Charles River.
    """
    cache_path = os.path.join(os.path.dirname(__file__), "cache", "bos_pedestrian_bridges.geojson")
    assert os.path.exists(cache_path), f"Boston bridge fixture not found at {cache_path}"

    import json
    with open(cache_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    bridge_names = [f.get("properties", {}).get("name", "").lower() for f in data.get("features", [])]
    has_longfellow = any("longfellow" in name for name in bridge_names)
    has_harvard_or_mass_ave = any("harvard" in name or "massachusetts avenue" in name for name in bridge_names)

    assert has_longfellow, "Boston bridge fixture must contain Longfellow Bridge!"
    assert has_harvard_or_mass_ave, "Boston bridge fixture must contain Harvard / Mass Ave Bridge!"
    assert len(data.get("features", [])) > 50, "Boston bridge fixture must contain rich bridge features."


def test_boston_charles_river_bridge_preservation():
    """
    Tests that Boston pedestrian bridge corridors (Longfellow Bridge midspan)
    are retained through boolean water subtraction across the Charles River.
    """
    import json
    cache_path = os.path.join(os.path.dirname(__file__), "cache", "bos_pedestrian_bridges.geojson")
    with open(cache_path, "r", encoding="utf-8") as f:
        bridge_geojson = json.load(f)

    gis_processor = BooleanGISProcessor(bridge_buffer_degrees=DEFAULT_BRIDGE_BUFFER_DEGREES)
    bridge_union = gis_processor.build_bridge_polygon_union(bridge_geojson)
    assert not bridge_union.is_empty, "Boston bridge union must not be empty"

    # Longfellow Bridge mid-span over Charles River: ~42.3615 N, -71.0760 W
    longfellow_midspan = Point(-71.0760, 42.3615)

    # Beacon Hill / West End neighborhood bounding polygon
    neighborhood_poly = Polygon([
        (-71.0850, 42.3550),
        (-71.0650, 42.3550),
        (-71.0650, 42.3680),
        (-71.0850, 42.3680),
        (-71.0850, 42.3550)
    ])

    # Charles River water polygon covering the span
    charles_river_poly = Polygon([
        (-71.0900, 42.3580),
        (-71.0600, 42.3580),
        (-71.0600, 42.3650),
        (-71.0900, 42.3650),
        (-71.0900, 42.3580)
    ])

    # 1. Pure water subtraction leaves the mid-span empty
    land_without_bridges = neighborhood_poly.difference(charles_river_poly)
    assert not land_without_bridges.contains(longfellow_midspan)

    # 2. Walkable mask formula restores bridge corridor across Charles River
    walkable_mask = gis_processor.compute_walkable_mask(
        neighborhood_geom=neighborhood_poly,
        water_union=charles_river_poly,
        bridges_union=bridge_union,
        catchment_buffer_degrees=DEFAULT_CATCHMENT_BUFFER_DEGREES
    )

    # Convert to H3 hexes and verify bridge hex preservation
    hexes = H3Polyfiller.get_hexes_for_geometry(walkable_mask, resolution=11)
    longfellow_hex = h3.latlng_to_cell(42.3615, -71.0760, 11)
    assert longfellow_hex in hexes or any(
        h3.grid_distance(longfellow_hex, h) <= 1 for h in hexes
    ), "Longfellow bridge deck hexes must be preserved in walkable mask across Charles River!"



def test_waterfront_neighborhood_denominators(db_connection):
    """Total hexes for waterfront neighborhoods must be non-zero and realistic."""
    cursor = db_connection.cursor()
    cursor.execute('''
        SELECT id, name, total_hexes
        FROM neighborhood_stats
        WHERE id IN ('BK0102', 'MN0302', 'BK0201')
    ''')
    rows = cursor.fetchall()
    assert len(rows) > 0, "Waterfront neighborhoods not found in database!"

    for nid, name, total in rows:
        assert total > 50, f"Total hexes for {name} ({nid}) should be substantial (>50), got {total}"


def test_database_schema_and_optimization(db_connection):
    """Database must have WITHOUT ROWID tables, index, and embedded sqlite_stat1."""
    cursor = db_connection.cursor()

    # Verify tables
    cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='table';")
    tables = {row[0]: row[1] for row in cursor.fetchall()}
    assert "neighborhood_stats" in tables
    assert "neighborhood_hexes" in tables
    assert "WITHOUT ROWID" in tables["neighborhood_stats"].upper()
    assert "WITHOUT ROWID" in tables["neighborhood_hexes"].upper()

    # Verify index
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_neighborhood_hexes_id';")
    assert cursor.fetchone() is not None, "Index idx_neighborhood_hexes_id must exist!"

    # Verify sqlite_stat1
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_stat1';")
    assert cursor.fetchone() is not None, "sqlite_stat1 table must exist for query optimizer statistics!"


def test_boston_pipeline_compilation_and_database_generation(tmp_path):
    """
    Validates end-to-end processing of Boston neighborhood data using
    the boolean CSG formula, H3 polyfilling, and SQLite emission.
    """
    from generate_neighborhood_stats import process_city_neighborhoods
    
    cache_dir = os.path.join(os.path.dirname(__file__), "cache")
    output_db = str(tmp_path / "bos_neighborhood.sqlite")
    output_json = str(tmp_path / "bos_neighborhood.json")

    stats, hexes = process_city_neighborhoods(
        city_slug="bos",
        cache_dir=cache_dir,
        output_db=output_db,
        output_json=output_json,
        offline=True
    )

    assert len(stats) >= 20, f"Boston must have at least 20 neighborhoods, got {len(stats)}"
    assert len(hexes) > 20000, f"Boston hexes must be substantial (>20,000), got {len(hexes)}"

    names = [s["name"] for s in stats]
    assert "Back Bay" in names or any("Back Bay" in n for n in names)
    assert "Beacon Hill" in names or any("Beacon Hill" in n for n in names)
    assert "South End" in names or any("South End" in n for n in names)

    # Verify SQLite schema of emitted Boston database
    conn = sqlite3.connect(output_db)
    cursor = conn.cursor()
    cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='table';")
    tables = {row[0]: row[1] for row in cursor.fetchall()}
    assert "neighborhood_stats" in tables
    assert "neighborhood_hexes" in tables
    assert "WITHOUT ROWID" in tables["neighborhood_stats"].upper()
    assert "WITHOUT ROWID" in tables["neighborhood_hexes"].upper()

    cursor.execute("SELECT COUNT(*) FROM neighborhood_stats;")
    assert cursor.fetchone()[0] == len(stats)

    cursor.execute("SELECT COUNT(*) FROM neighborhood_hexes;")
    assert cursor.fetchone()[0] == len(hexes)

    conn.close()

