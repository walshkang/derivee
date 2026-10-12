import { describe, it } from 'node:test';
import assert from 'node:assert';
import { findBikeCandidates } from '../bikeCatchment.js';

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
    assert.ok(atlantic.bikeTimeSeconds < 1200, 'Bike time should be under 20 min for 3.5km');
    
    console.log(`  Atlantic Av via bike: ${Math.round(atlantic.bikeTimeSeconds / 60)} min`);
  });

  it('returns empty when no docks nearby', () => {
    // Origin far from any dock (middle of ocean)
    const candidates = findBikeCandidates(40.0, -74.5, bikeStations, transitStops);
    assert.strictEqual(candidates.length, 0, 'Should find no candidates far from docks');
  });
});
