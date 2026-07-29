ATTACH DATABASE 'assets/neighborhood.sqlite' AS neighborhood_db;
SELECT COUNT(*) FROM neighborhood_db.neighborhood_hexes h JOIN explored_hexes e ON h.h3_index = e.h3_index;
