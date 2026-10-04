import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  getDepartureSeconds,
  computeDepartureSeconds,
} from '../routeComparison.ts';
import {
  matchLiveArrival,
} from '../itineraryDisplay.ts';

describe('Bug-fix wave: "Leave now" mode + realtime leg times', () => {
  describe('Fix 1: "Leave now" departure timing calculation', () => {
    it('computes departure seconds from CURRENT time when mode is "now" (not stale 08:00)', () => {
      // Walsh reproduction: 9:29:00 AM EDT
      const walshTestDate = new Date(2026, 9, 4, 9, 29, 0); // 9:29:00 local time
      const expectedSeconds = 9 * 3600 + 29 * 60; // 34140 seconds

      const result = computeDepartureSeconds('now', '08:00', walshTestDate);
      assert.strictEqual(
        result,
        expectedSeconds,
        `Mode "now" must compute departure seconds for 09:29 (${expectedSeconds}), got ${result}`
      );
      assert.notStrictEqual(
        result,
        28800,
        'Mode "now" must NEVER return stale 08:00 (28800)'
      );
    });

    it('uses explicit departure time string when mode is "depart_at"', () => {
      const walshTestDate = new Date(2026, 9, 4, 9, 29, 0);
      const result = computeDepartureSeconds('depart_at', '10:30', walshTestDate);
      const expectedSeconds = 10 * 3600 + 30 * 60; // 37800 seconds
      assert.strictEqual(result, expectedSeconds);
    });

    it('toggling between "now" and "depart_at" shifts routing departure timestamp', () => {
      const now = new Date(2026, 9, 4, 9, 29, 0);
      const nowDep = computeDepartureSeconds('now', '10:30', now);
      const departAtDep = computeDepartureSeconds('depart_at', '10:30', now);

      assert.strictEqual(nowDep, 34140);
      assert.strictEqual(departAtDep, 37800);
      assert.notStrictEqual(nowDep, departAtDep, 'Toggling mode must shift results');
    });

    it('negative case: invalid or malformed time strings fallback safely to 28800 (8:00 AM)', () => {
      assert.strictEqual(getDepartureSeconds(''), 28800);
      assert.strictEqual(getDepartureSeconds('invalid'), 28800);
      assert.strictEqual(getDepartureSeconds('25:00'), 28800);
      assert.strictEqual(getDepartureSeconds('-1:30'), 28800);
      assert.strictEqual(getDepartureSeconds('10:65'), 28800);
      assert.strictEqual(computeDepartureSeconds('depart_at', 'corrupt'), 28800);
    });

    it('boundary case: midnight and end of day', () => {
      assert.strictEqual(getDepartureSeconds('00:00'), 0);
      assert.strictEqual(getDepartureSeconds('23:59'), 23 * 3600 + 59 * 60);
    });
  });

  describe('Fix 2: Realtime GTFS-RT arrival prediction matching and degradation', () => {
    const fixedNowEpoch = 1728048000; // Reference epoch

    it('resolves live arrival from GTFS-RT predicted_arrival_epoch and computes minutesAway', () => {
      // Real-shape fixture returned by derivee-api GTFS-RT ingestion
      const rawArrivals = [
        {
          route_id: 'Q',
          direction: 'NORTH',
          headsign: '',
          predicted_arrival_epoch: fixedNowEpoch + 240, // 4 minutes away
          is_realtime: true,
        },
        {
          route_id: 'N',
          direction: 'NORTH',
          headsign: '',
          predicted_arrival_epoch: fixedNowEpoch + 600,
          is_realtime: true,
        },
      ];

      const match = matchLiveArrival(rawArrivals, 'Q', fixedNowEpoch);
      assert.ok(match, 'Must match route Q');
      assert.strictEqual(match.isLive, true);
      assert.strictEqual(match.minutesAway, 4);
      assert.strictEqual(match.isApproaching, false);
    });

    it('detects approaching train when minutesAway <= 1', () => {
      const rawArrivals = [
        {
          route_id: 'L',
          direction: 'NORTH',
          predicted_arrival_epoch: fixedNowEpoch + 45, // 45 seconds away
          is_realtime: true,
        },
      ];

      const match = matchLiveArrival(rawArrivals, 'L', fixedNowEpoch);
      assert.ok(match);
      assert.strictEqual(match.isLive, true);
      assert.strictEqual(match.minutesAway, 1);
      assert.strictEqual(match.isApproaching, true);
    });

    it('supports pre-calculated minutesAway property if already enriched', () => {
      const rawArrivals = [
        {
          route_id: '6',
          minutesAway: 3,
          isApproaching: false,
        },
      ];

      const match = matchLiveArrival(rawArrivals, '6', fixedNowEpoch);
      assert.ok(match);
      assert.strictEqual(match.isLive, true);
      assert.strictEqual(match.minutesAway, 3);
    });

    it('negative case: returns null when arrivals list is empty or undefined (probe failure/503 fallback)', () => {
      assert.strictEqual(matchLiveArrival(null, 'Q', fixedNowEpoch), null);
      assert.strictEqual(matchLiveArrival(undefined, 'Q', fixedNowEpoch), null);
      assert.strictEqual(matchLiveArrival([], 'Q', fixedNowEpoch), null);
    });

    it('negative case: returns null when target route is not in arrivals', () => {
      const rawArrivals = [
        {
          route_id: 'F',
          predicted_arrival_epoch: fixedNowEpoch + 300,
        },
      ];
      const match = matchLiveArrival(rawArrivals, 'Q', fixedNowEpoch);
      assert.strictEqual(match, null, 'Must return null for non-matching route');
    });

    it('negative case: returns null when arrival record has no epoch or minutesAway', () => {
      const corruptedArrivals = [
        {
          route_id: 'Q',
          headsign: 'Unknown',
        },
      ];
      const match = matchLiveArrival(corruptedArrivals, 'Q', fixedNowEpoch);
      assert.strictEqual(match, null);
    });

    it('negative case: handles dirty/empty route strings cleanly', () => {
      assert.strictEqual(matchLiveArrival([{ route_id: 'Q', minutesAway: 2 }], '', fixedNowEpoch), null);
      assert.strictEqual(matchLiveArrival([{ route_id: 'Q', minutesAway: 2 }], null, fixedNowEpoch), null);
    });
  });
});
