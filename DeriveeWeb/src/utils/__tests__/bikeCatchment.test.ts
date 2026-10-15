import { describe, it } from 'node:test';
import assert from 'node:assert';
import { findBikeCandidates, GridIndex } from '../bikeCatchment.ts';

describe('findBikeCandidates', () => {
  const bikeStations = [
    { station_id: 'dock1', lat: 40.717, lon: -73.962, name: 'N 11th St & Wythe Av', capacity: 30 },
    { station_id: 'dock2', lat: 40.684, lon: -73.977, name: 'Atlantic Av & Fort Greene Pl', capacity: 40 },
  ];

  const transitStops = [
    { id: 'L06', lat: 40.717, lon: -73.962, name: 'Bedford Av (L)' },
    { id: 'A41', lat: 40.684, lon: -73.977, name: 'Atlantic Av-Barclays Ctr (2/3/4/5)' },
  ];

  it('finds bike-reachable stations within 5km', () => {
    // Origin near Bedford Av
    const candidates = findBikeCandidates(40.718, -73.963, bikeStations, transitStops);
    
    // Should find both stations (Bedford is walkable, Atlantic is bikeable)
    assert.ok(candidates.length >= 1, 'Should find at least one candidate');
    
    // Atlantic Av should be reachable by bike (about 3.5km)
    const atlantic = candidates.find(c => c.stopId === 'A41');
    assert.ok(atlantic, 'Should find Atlantic Av via bike');
    assert.ok(atlantic.bikeTimeSeconds > 0, 'Bike time should be positive');
    // ~4km ride at 8mph + 2min walk-to-dock + 90s penalties ≈ 27.5 min
    assert.ok(atlantic.bikeTimeSeconds < 1800, 'Bike time should be under 30 min');
    
    console.log(`  Atlantic Av via bike: ${Math.round(atlantic.bikeTimeSeconds / 60)} min`);
  });

  it('returns empty when no docks nearby', () => {
    // Origin far from any dock (middle of ocean)
    const candidates = findBikeCandidates(40.0, -74.5, bikeStations, transitStops);
    assert.strictEqual(candidates.length, 0, 'Should find no candidates far from docks');
  });

  it('deduplicates stops by name and keeps the fastest platform candidate', () => {
    const docks = [
      { station_id: 'd_orig', lat: 40.718, lon: -73.963, name: 'Origin Dock', capacity: 20 },
      { station_id: 'd_near', lat: 40.730, lon: -73.955, name: 'Near Platform Dock', capacity: 20 },
      { station_id: 'd_far', lat: 40.732, lon: -73.955, name: 'Far Platform Dock', capacity: 20 },
    ];
    // Two platforms with identical name ("Court Sq"), one closer to a dropoff dock
    const duplicateNameStops = [
      { id: 'STOP_SLOW', lat: 40.7335, lon: -73.955, name: 'Court Sq' },
      { id: 'STOP_FAST', lat: 40.7301, lon: -73.955, name: 'Court Sq' },
    ];

    const candidates = findBikeCandidates(40.718, -73.963, docks, duplicateNameStops);
    const courtSqCands = candidates.filter(c => c.stopName === 'Court Sq');

    assert.strictEqual(courtSqCands.length, 1, 'Should deduplicate stops sharing the same name');
    assert.strictEqual(courtSqCands[0].stopId, 'STOP_FAST', 'Should retain the faster platform');
  });

  it('GridIndex finds items across cell boundaries within the radius', () => {
    // Cell boundary at 40.7205 (40.7205 / 0.0045 = 9049.0 exactly)
    const items = [
      { id: 'inside_lower_cell', lat: 40.7204, lon: -73.9595 },
      { id: 'across_lat_lon_boundary', lat: 40.7206, lon: -73.9594 },
      { id: 'outside_radius', lat: 40.7260, lon: -73.9595 },
    ];
    const index = new GridIndex(items);
    const nearby = index.nearby(40.72045, -73.95945, 100); // 100m radius straddling the boundary

    const ids = nearby.map(i => i.id).sort();
    assert.deepStrictEqual(ids, ['across_lat_lon_boundary', 'inside_lower_cell']);
  });
});
