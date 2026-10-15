import { describe, it } from 'node:test';
import assert from 'node:assert';
import { decideBikeOption, selectAvailableCandidate, type DockStatus } from '../bikeDecision.ts';
import { findBikeCandidates, type BikeCandidate, type BikeStation, type TransitStop } from '../bikeCatchment.ts';

const mockCandidates: BikeCandidate[] = [
  {
    stopId: 'L08',
    stopName: 'Bedford Av',
    bikeTimeSeconds: 240, // 4 min
    pickupDockId: 'dock_origin_1',
    pickupDockName: 'N 6 St & Kent Ave',
    walkToDockSeconds: 60,
    bikeRideSeconds: 60,
    dropoffDockId: 'dock_stop_1',
    dropoffDockName: 'Bedford Ave & N 7 St',
    walkFromDockSeconds: 30,
  },
  {
    stopId: 'G29',
    stopName: 'Metropolitan Av',
    bikeTimeSeconds: 360, // 6 min
    pickupDockId: 'dock_origin_2',
    pickupDockName: 'Berry St & N 8 St',
    walkToDockSeconds: 90,
    bikeRideSeconds: 150,
    dropoffDockId: 'dock_stop_2',
    dropoffDockName: 'Metropolitan Ave & Lorimer St',
    walkFromDockSeconds: 30,
  },
];

const mockEbikeCandidates: BikeCandidate[] = [
  {
    ...mockCandidates[0],
    bikeTimeSeconds: 180, // 3 min on e-bike
    bikeRideSeconds: 30,
  },
];

describe('decideBikeOption', () => {
  it('returns walk with reason "no-candidates" when candidate list is empty', () => {
    const status = new Map<string, DockStatus>([
      ['dock_origin_1', { bikes: 5, docks: 5 }],
      ['dock_stop_1', { bikes: 5, docks: 5 }],
    ]);

    const res = decideBikeOption({
      candidates: [],
      availability: status,
      walkTotalSec: 1800,
      bikeTransitSec: 900,
    });

    assert.strictEqual(res.suggestion, 'walk');
    assert.strictEqual(res.reason, 'no-candidates');
    assert.strictEqual(res.bannerData, null);
  });

  it('returns walk with reason "no-availability" when no dock meets availability', () => {
    const emptyStatus = new Map<string, DockStatus>([
      ['dock_origin_1', { bikes: 0, docks: 10 }],
      ['dock_stop_1', { bikes: 5, docks: 0 }],
    ]);

    const res = decideBikeOption({
      candidates: mockCandidates,
      availability: emptyStatus,
      walkTotalSec: 1800,
      bikeTransitSec: 900,
    });

    assert.strictEqual(res.suggestion, 'walk');
    assert.strictEqual(res.reason, 'no-availability');
    assert.strictEqual(res.bannerData, null);
  });

  it('returns walk when availability is unknown (empty map, status fetch failed)', () => {
    // Walk-on-failure is the safe default: with no availability information,
    // never suggest bike. (Ruled 2026-10-15.)
    const res = decideBikeOption({
      candidates: mockCandidates,
      availability: new Map(),
      walkTotalSec: 1800,
      bikeTransitSec: 900,
    });

    assert.strictEqual(res.suggestion, 'walk');
    assert.strictEqual(res.reason, 'no-availability');
    assert.strictEqual(selectAvailableCandidate(mockCandidates, new Map()), null);
  });

  it('enforces availability buffer: 1 bike at pickup -> walk (reason: no-availability)', () => {
    // 6 minutes saved (1800s walk vs 240s access + 1200s transit = 1440s -> 360s savings)
    // Only 1 bike left at dock -> should NOT suggest bike
    const status = new Map<string, DockStatus>([
      ['dock_origin_1', { bikes: 1, docks: 10 }],
      ['dock_stop_1', { bikes: 5, docks: 5 }],
    ]);

    const res = decideBikeOption({
      candidates: [mockCandidates[0]],
      availability: status,
      walkTotalSec: 1800,
      bikeTransitSec: 1200,
    });

    assert.strictEqual(res.suggestion, 'walk');
    assert.strictEqual(res.reason, 'no-availability');
    assert.strictEqual(res.bannerData, null);
  });

  it('enforces availability buffer: 1 open dock at dropoff -> walk (reason: no-availability)', () => {
    const status = new Map<string, DockStatus>([
      ['dock_origin_1', { bikes: 5, docks: 10 }],
      ['dock_stop_1', { bikes: 5, docks: 1 }],
    ]);

    const res = decideBikeOption({
      candidates: [mockCandidates[0]],
      availability: status,
      walkTotalSec: 1800,
      bikeTransitSec: 1200,
    });

    assert.strictEqual(res.suggestion, 'walk');
    assert.strictEqual(res.reason, 'no-availability');
  });

  it('enforces availability buffer: 2 bikes and 2 docks -> bike', () => {
    const status = new Map<string, DockStatus>([
      ['dock_origin_1', { bikes: 2, docks: 10 }],
      ['dock_stop_1', { bikes: 5, docks: 2 }],
    ]);

    const res = decideBikeOption({
      candidates: [mockCandidates[0]],
      ebikeCandidates: mockEbikeCandidates,
      availability: status,
      walkTotalSec: 1800,
      bikeTransitSec: 1200, // bikeTotal = 1440, savings = 360s (6 min)
    });

    assert.strictEqual(res.suggestion, 'bike');
    assert.strictEqual(res.reason, 'threshold');
    assert.ok(res.bannerData);
    assert.strictEqual(res.bannerData.savingsMin, 6);
    assert.strictEqual(res.bannerData.ebikeAccessMin, 3);
  });

  it('falls back to second candidate when first candidate has only 1 bike', () => {
    const status = new Map<string, DockStatus>([
      ['dock_origin_1', { bikes: 1, docks: 10 }], // Fails buffer (<2)
      ['dock_stop_1', { bikes: 5, docks: 5 }],
      ['dock_origin_2', { bikes: 3, docks: 10 }], // Passes buffer (>=2)
      ['dock_stop_2', { bikes: 5, docks: 4 }],
    ]);

    const res = decideBikeOption({
      candidates: mockCandidates,
      availability: status,
      walkTotalSec: 2100,
      bikeTransitSec: 1380, // with cand[1] (360s access) -> 1740s total -> 360s savings
    });

    assert.strictEqual(res.suggestion, 'bike');
    assert.strictEqual(res.selectedCandidate?.stopId, 'G29');
    assert.strictEqual(res.bannerData?.bikeStationName, 'Metropolitan Av');
  });

  it('threshold boundary: 299s savings -> walk (reason: threshold)', () => {
    const status = new Map<string, DockStatus>([
      ['dock_origin_1', { bikes: 4, docks: 4 }],
      ['dock_stop_1', { bikes: 4, docks: 4 }],
    ]);

    // walk = 1500s, bikeAccess = 240s, bikeTransit = 961s -> bikeTotal = 1201s -> savings = 299s
    const res = decideBikeOption({
      candidates: [mockCandidates[0]],
      availability: status,
      walkTotalSec: 1500,
      bikeTransitSec: 961,
    });

    assert.strictEqual(res.savingsSec, 299);
    assert.strictEqual(res.suggestion, 'walk');
    assert.strictEqual(res.reason, 'threshold');
    assert.strictEqual(res.bannerData, null);
  });

  it('threshold boundary: 300s savings -> bike (reason: threshold)', () => {
    const status = new Map<string, DockStatus>([
      ['dock_origin_1', { bikes: 4, docks: 4 }],
      ['dock_stop_1', { bikes: 4, docks: 4 }],
    ]);

    // walk = 1500s, bikeAccess = 240s, bikeTransit = 960s -> bikeTotal = 1200s -> savings = 300s
    const res = decideBikeOption({
      candidates: [mockCandidates[0]],
      availability: status,
      walkTotalSec: 1500,
      bikeTransitSec: 960,
    });

    assert.strictEqual(res.savingsSec, 300);
    assert.strictEqual(res.suggestion, 'bike');
    assert.strictEqual(res.reason, 'threshold');
    assert.ok(res.bannerData);
    assert.strictEqual(res.bannerData.savingsMin, 5);
  });

  it('returns walk with reason "no-data" when RAPTOR times are missing', () => {
    const status = new Map<string, DockStatus>([
      ['dock_origin_1', { bikes: 4, docks: 4 }],
      ['dock_stop_1', { bikes: 4, docks: 4 }],
    ]);

    const res = decideBikeOption({
      candidates: [mockCandidates[0]],
      availability: status,
    });

    assert.strictEqual(res.suggestion, 'walk');
    assert.strictEqual(res.reason, 'no-data');
    assert.strictEqual(res.selectedCandidate?.stopId, 'L08');
  });

  it('is strictly deterministic across repeated runs and computes bikeOnlyMin cleanly', () => {
    const stations: BikeStation[] = [
      { station_id: 'dock_origin_1', lat: 40.7188, lon: -73.9632, name: 'N 6 St & Kent Ave', capacity: 30 },
      { station_id: 'dock_stop_1', lat: 40.7173, lon: -73.9568, name: 'Bedford Ave & N 7 St', capacity: 30 },
      { station_id: 'dock_dest_1', lat: 40.7282, lon: -74.0031, name: 'W Houston St & Hudson St', capacity: 30 },
    ];
    const status = new Map<string, DockStatus>([
      ['dock_origin_1', { bikes: 5, docks: 5 }],
      ['dock_stop_1', { bikes: 5, docks: 5 }],
    ]);

    const input = {
      candidates: [mockCandidates[0]],
      ebikeCandidates: mockEbikeCandidates,
      availability: status,
      walkTotalSec: 2400,
      bikeTransitSec: 1500,
      origin: { lat: 40.7195, lon: -73.9645 },
      destination: { lat: 40.7284, lon: -74.0033 },
      bikeStations: stations,
    };

    const first = decideBikeOption(input);
    for (let i = 0; i < 25; i++) {
      const next = decideBikeOption(input);
      assert.deepStrictEqual(next, first);
    }
    assert.ok(first.bannerData?.bikeOnlyMin && first.bannerData.bikeOnlyMin > 0);
  });

  it('validates the 7 real-world eval pairs deterministically', () => {
    // Anchor coordinates
    const HOME = { lat: 40.7195, lon: -73.9645 }; // 2 Northside Piers, Brooklyn 11211
    const OFFICE = { lat: 40.7587, lon: -73.9787 }; // 30 Rockefeller Plaza
    const FILM_FORUM = { lat: 40.7284, lon: -74.0033 }; // 209 W Houston St
    const NITEHAWK = { lat: 40.6602, lon: -73.9803 }; // 188 Prospect Park West

    const stations: BikeStation[] = [
      { station_id: 'd_home', lat: 40.7188, lon: -73.9632, name: 'Kent Ave & N 6 St', capacity: 40 },
      { station_id: 'd_bedford', lat: 40.7173, lon: -73.9568, name: 'Bedford Ave & N 7 St', capacity: 35 },
      { station_id: 'd_court_sq', lat: 40.7470, lon: -73.9455, name: 'Court Sq & Jackson Ave', capacity: 45 },
      { station_id: 'd_rock', lat: 40.7592, lon: -73.9795, name: '6 Ave & W 49 St', capacity: 50 },
      { station_id: 'd_houston', lat: 40.7282, lon: -74.0031, name: 'Varick St & W Houston St', capacity: 35 },
      { station_id: 'd_nitehawk', lat: 40.6606, lon: -73.9798, name: 'Prospect Park W & 14 St', capacity: 30 },
      { station_id: 'd_atlantic', lat: 40.6842, lon: -73.9772, name: 'Atlantic Ave & Fort Greene Pl', capacity: 45 },
    ];

    const stops: TransitStop[] = [
      { id: 'L08', lat: 40.7173, lon: -73.9568, name: 'Bedford Av (L)' },
      { id: 'G22', lat: 40.7470, lon: -73.9455, name: 'Court Sq (E/M/G/7)' },
      { id: 'D15', lat: 40.7587, lon: -73.9813, name: '47-50 Sts-Rockefeller Ctr (B/D/F/M)' },
      { id: '134', lat: 40.7282, lon: -74.0035, name: 'Houston St (1)' },
      { id: 'F25', lat: 40.6603, lon: -73.9795, name: '15 St-Prospect Park (F/G)' },
      { id: 'A41', lat: 40.6842, lon: -73.9772, name: 'Atlantic Av-Barclays Ctr' },
    ];

    const healthyAvailability = new Map<string, DockStatus>(
      stations.map(s => [s.station_id, { bikes: 8, docks: 12 }])
    );

    const evalPairs = [
      { name: '1. Home -> Office (Weekday AM)', orig: HOME, dest: OFFICE, walkSec: 2340, bikeTransitSec: 1260 },
      { name: '2. Office -> Home (Weekday PM)', orig: OFFICE, dest: HOME, walkSec: 2280, bikeTransitSec: 1680 },
      { name: '3. Home -> Film Forum (Weekday 7PM)', orig: HOME, dest: FILM_FORUM, walkSec: 1980, bikeTransitSec: 1320 },
      { name: '4. Film Forum -> Home (Weekday 10:30PM)', orig: FILM_FORUM, dest: HOME, walkSec: 2100, bikeTransitSec: 1620 },
      { name: '5. Home -> Nitehawk (Fri/Sat 7:30PM)', orig: HOME, dest: NITEHAWK, walkSec: 2820, bikeTransitSec: 1920 },
      { name: '6. Nitehawk -> Home (Fri/Sat 10:30PM)', orig: NITEHAWK, dest: HOME, walkSec: 2940, bikeTransitSec: 2100 },
      { name: '7. Office -> Film Forum (Weekday 6:30PM)', orig: OFFICE, dest: FILM_FORUM, walkSec: 1320, bikeTransitSec: 960 },
    ];

    for (const pair of evalPairs) {
      const cands = findBikeCandidates(pair.orig.lat, pair.orig.lon, stations, stops).slice(0, 3);
      const ecands = findBikeCandidates(pair.orig.lat, pair.orig.lon, stations, stops, true).slice(0, 3);
      const input = {
        candidates: cands,
        ebikeCandidates: ecands,
        availability: healthyAvailability,
        walkTotalSec: pair.walkSec,
        bikeTransitSec: pair.bikeTransitSec,
        origin: pair.orig,
        destination: pair.dest,
        bikeStations: stations,
      };
      const res1 = decideBikeOption(input);
      const res2 = decideBikeOption(input);
      assert.deepStrictEqual(res1, res2, `Non-deterministic result on ${pair.name}`);
    }
  });
});
