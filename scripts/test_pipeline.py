import sqlite3
import h3

DB_PATH = "../assets/neighborhood.sqlite"

def test_mccarren_park_in_williamsburg():
    """
    McCarren Park is definitely in Williamsburg/Greenpoint.
    We test that this land coordinate resolves to a valid neighborhood.
    """
    lat, lng = 40.7215, -73.9515 # McCarren Park
    hex_index = h3.latlng_to_cell(lat, lng, 11)
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT n.name 
        FROM neighborhood_hexes h
        JOIN neighborhood_stats n ON h.neighborhood_id = n.id
        WHERE h.h3_index = ?
    ''', (hex_index,))
    
    result = cursor.fetchone()
    conn.close()
    
    assert result is not None, f"McCarren Park hex {hex_index} was not found in any neighborhood!"
    neighborhood_name = result[0]
    
    print(f"McCarren Park resolved to neighborhood: {neighborhood_name}")
    # NTAs combine Williamsburg and Greenpoint, usually named "Greenpoint" or "Williamsburg"
    assert "Williamsburg" in neighborhood_name or "Greenpoint" in neighborhood_name, \
        f"Expected Williamsburg/Greenpoint, but got {neighborhood_name}"

def test_east_river_is_subtracted():
    """
    Test that a point clearly in the middle of the East River (water)
    is NOT mapped to any neighborhood, proving our Boolean Subtraction works.
    """
    lat, lng = 40.7180, -73.9680 # Middle of East River between Wburg and Manhattan
    hex_index = h3.latlng_to_cell(lat, lng, 11)
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT n.name 
        FROM neighborhood_hexes h
        JOIN neighborhood_stats n ON h.neighborhood_id = n.id
        WHERE h.h3_index = ?
    ''', (hex_index,))
    
    result = cursor.fetchone()
    conn.close()
    
    if result is not None:
        print(f"FAILED: East River hex {hex_index} resolved to neighborhood: {result[0]}")
    
    assert result is None, f"East River hex {hex_index} should have been subtracted as water!"
    print("East River point successfully subtracted (not in database).")

def test_williamsburg_bridge_is_not_in_nta():
    """
    Test that a point on the Williamsburg Bridge is NOT in any neighborhood.
    This is because NYC NTA boundaries strictly cut off at the shoreline.
    """
    lat, lng = 40.7126, -73.9723 # Middle of Williamsburg Bridge
    hex_index = h3.latlng_to_cell(lat, lng, 11)
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT n.name 
        FROM neighborhood_hexes h
        JOIN neighborhood_stats n ON h.neighborhood_id = n.id
        WHERE h.h3_index = ?
    ''', (hex_index,))
    
    result = cursor.fetchone()
    conn.close()
    
    assert result is None, f"Williamsburg Bridge hex {hex_index} was incorrectly assigned to {result}!"
    print("Williamsburg Bridge correctly excluded (NYC NTAs end at the shoreline).")
