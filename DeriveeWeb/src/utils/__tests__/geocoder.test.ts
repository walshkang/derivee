import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  parseNominatimResponse,
  searchPlaces,
  throttleNominatimRequest,
  resetRateLimiterForTesting,
  searchLocationsWithFallback,
  findNearestStopByCoordinates,
  resolvePlaceToNearestStation,
  debounce,
  DEFAULT_USER_AGENT,
} from '../geocoder.ts';
import type { StopItem } from '../../types/routing';

describe('geocoder', () => {
  describe('parseNominatimResponse', () => {
    it('maps valid Nominatim JSON array to GeocodedPlace array', () => {
      const fixture = [
        {
          place_id: 101,
          display_name: 'Times Square, Manhattan, New York, NY',
          lat: '40.7580',
          lon: '-73.9855',
          type: 'attraction',
          class: 'tourism',
        },
        {
          place_id: '202',
          display_name: 'Central Park, New York, NY',
          lat: 40.785091,
          lon: -73.968285,
        },
      ];

      const places = parseNominatimResponse(fixture);
      assert.strictEqual(places.length, 2);
      assert.deepStrictEqual(places[0], {
        displayName: 'Times Square, Manhattan, New York, NY',
        lat: 40.758,
        lon: -73.9855,
        placeId: 101,
        type: 'attraction',
        class: 'tourism',
      });
      assert.deepStrictEqual(places[1], {
        displayName: 'Central Park, New York, NY',
        lat: 40.785091,
        lon: -73.968285,
        placeId: '202',
        type: undefined,
        class: undefined,
      });
    });

    it('negative: handles garbage non-array inputs without throwing', () => {
      assert.deepStrictEqual(parseNominatimResponse(null), []);
      assert.deepStrictEqual(parseNominatimResponse(undefined), []);
      assert.deepStrictEqual(parseNominatimResponse({}), []);
      assert.deepStrictEqual(parseNominatimResponse('invalid string'), []);
      assert.deepStrictEqual(parseNominatimResponse(42), []);
    });

    it('negative: filters out malformed or missing fields in array items', () => {
      const malformed = [
        null,
        {},
        { display_name: '', lat: '40.0', lon: '-73.0' },
        { display_name: 'Valid Name', lat: 'not-a-number', lon: '-73.0' },
        { display_name: 'Valid Name', lat: '40.0', lon: 'not-a-number' },
        { display_name: '   ', lat: '40.0', lon: '-73.0' },
      ];

      const places = parseNominatimResponse(malformed);
      assert.strictEqual(places.length, 0);
    });
  });

  describe('searchPlaces', () => {
    beforeEach(() => {
      resetRateLimiterForTesting();
    });

    it('calls fetchFn with correct parameters and returns parsed places', async () => {
      const fixturePlaces = [
        {
          place_id: 101,
          display_name: 'Grand Central Terminal',
          lat: '40.7527',
          lon: '-73.9772',
        },
      ];

      let requestedUrl = '';
      let requestedHeaders: Record<string, string> | undefined;

      const mockFetch: typeof fetch = async (input, init) => {
        requestedUrl = String(input);
        requestedHeaders = init?.headers as Record<string, string>;
        return {
          ok: true,
          json: async () => fixturePlaces,
        } as Response;
      };

      const results = await searchPlaces('Grand Central', {
        fetchFn: mockFetch,
        minIntervalMs: 0,
        userAgent: 'CustomAgent/1.0',
      });

      assert.strictEqual(results.length, 1);
      assert.strictEqual(results[0].displayName, 'Grand Central Terminal');
      assert.ok(requestedUrl.includes('q=Grand+Central'));
      assert.ok(requestedUrl.includes('format=json'));
      assert.strictEqual(requestedHeaders?.['User-Agent'], 'CustomAgent/1.0');
    });

    it('uses DEFAULT_USER_AGENT when userAgent option is omitted', async () => {
      let requestedHeaders: Record<string, string> | undefined;

      const mockFetch: typeof fetch = async (_input, init) => {
        requestedHeaders = init?.headers as Record<string, string>;
        return {
          ok: true,
          json: async () => [],
        } as Response;
      };

      await searchPlaces('Penn Station', {
        fetchFn: mockFetch,
        minIntervalMs: 0,
      });

      assert.strictEqual(requestedHeaders?.['User-Agent'], DEFAULT_USER_AGENT);
    });

    it('negative: query shorter than 2 characters returns empty array without fetching', async () => {
      let called = false;
      const mockFetch: typeof fetch = async () => {
        called = true;
        return { ok: true, json: async () => [] } as Response;
      };

      const result1 = await searchPlaces('a', { fetchFn: mockFetch, minIntervalMs: 0 });
      const result2 = await searchPlaces('  ', { fetchFn: mockFetch, minIntervalMs: 0 });

      assert.deepStrictEqual(result1, []);
      assert.deepStrictEqual(result2, []);
      assert.strictEqual(called, false);
    });

    it('negative: handles fetchFn rejection (offline) gracefully without throwing', async () => {
      const failingFetch: typeof fetch = async () => {
        throw new Error('Network offline');
      };

      const result = await searchPlaces('Times Square', {
        fetchFn: failingFetch,
        minIntervalMs: 0,
      });

      assert.deepStrictEqual(result, []);
    });

    it('negative: handles non-ok HTTP responses gracefully', async () => {
      const errorFetch: typeof fetch = async () => {
        return {
          ok: false,
          status: 503,
          json: async () => ({ error: 'Service Unavailable' }),
        } as Response;
      };

      const result = await searchPlaces('Times Square', {
        fetchFn: errorFetch,
        minIntervalMs: 0,
      });

      assert.deepStrictEqual(result, []);
    });
  });

  describe('throttleNominatimRequest', () => {
    beforeEach(() => {
      resetRateLimiterForTesting();
    });

    it('first request resolves immediately without delay', async () => {
      const start = Date.now();
      await throttleNominatimRequest(50);
      const elapsed = Date.now() - start;
      assert.ok(elapsed < 25, `Expected immediate execution, took ${elapsed}ms`);
    });

    it('rapid successive calls throttle to minIntervalMs', async () => {
      await throttleNominatimRequest(50);
      const start = Date.now();
      await throttleNominatimRequest(50);
      const elapsed = Date.now() - start;
      assert.ok(elapsed >= 35, `Expected throttling delay >= 35ms, took ${elapsed}ms`);
    });

    it('negative: minIntervalMs = 0 does not delay', async () => {
      await throttleNominatimRequest(0);
      const start = Date.now();
      await throttleNominatimRequest(0);
      const elapsed = Date.now() - start;
      assert.ok(elapsed < 20, `Expected no delay with 0ms interval, took ${elapsed}ms`);
    });
  });

  describe('searchLocationsWithFallback', () => {
    const stopsFixture: StopItem[] = [
      { id: 1, name: 'Times Square - 42 St', lat: 40.755, lon: -73.987 },
      { id: 2, name: 'Times Square - 42 St', lat: 40.756, lon: -73.986 }, // Duplicate name
      { id: 3, name: 'Grand Central - 42 St', lat: 40.752, lon: -73.977 },
      { id: 4, name: 'Wall St', lat: 40.707, lon: -74.009 },
    ];

    it('returns both matched stations and geocoded places when fetch succeeds', async () => {
      const mockFetch: typeof fetch = async () => {
        return {
          ok: true,
          json: async () => [
            {
              place_id: 99,
              display_name: 'Times Square Diner, NYC',
              lat: '40.760',
              lon: '-73.989',
            },
          ],
        } as Response;
      };

      const res = await searchLocationsWithFallback({
        query: 'times',
        stops: stopsFixture,
        fetchFn: mockFetch,
        minIntervalMs: 0,
      });

      assert.strictEqual(res.stations.length, 1);
      assert.strictEqual(res.stations[0].name, 'Times Square - 42 St');
      assert.strictEqual(res.places.length, 1);
      assert.strictEqual(res.places[0].displayName, 'Times Square Diner, NYC');
    });

    it('negative: falls back to station-only results when fetchFn throws (offline)', async () => {
      const failingFetch: typeof fetch = async () => {
        throw new Error('Connection refused');
      };

      const res = await searchLocationsWithFallback({
        query: 'times',
        stops: stopsFixture,
        fetchFn: failingFetch,
        minIntervalMs: 0,
      });

      assert.strictEqual(res.stations.length, 1);
      assert.strictEqual(res.stations[0].name, 'Times Square - 42 St');
      assert.deepStrictEqual(res.places, []);
    });

    it('negative: query shorter than 2 chars returns empty stations and places', async () => {
      let called = false;
      const mockFetch: typeof fetch = async () => {
        called = true;
        return { ok: true, json: async () => [] } as Response;
      };

      const res = await searchLocationsWithFallback({
        query: 't',
        stops: stopsFixture,
        fetchFn: mockFetch,
        minIntervalMs: 0,
      });

      assert.deepStrictEqual(res, { stations: [], places: [] });
      assert.strictEqual(called, false);
    });
  });

  describe('findNearestStopByCoordinates', () => {
    const stopsFixture: StopItem[] = [
      { id: 1, name: 'Stop A', lat: 40.0, lon: -70.0 },
      { id: 2, name: 'Stop B', lat: 40.5, lon: -70.5 },
      { id: 3, name: 'Stop C', lat: 41.0, lon: -71.0 },
    ];

    it('finds stop with closest coordinate distance', () => {
      const nearest = findNearestStopByCoordinates(40.48, -70.49, stopsFixture);
      assert.ok(nearest);
      assert.strictEqual(nearest.id, 2);
      assert.strictEqual(nearest.name, 'Stop B');
    });

    it('negative: returns null for empty or missing stops array without throwing', () => {
      assert.strictEqual(findNearestStopByCoordinates(40.0, -70.0, []), null);
      assert.strictEqual(findNearestStopByCoordinates(40.0, -70.0, null as unknown as StopItem[]), null);
      assert.strictEqual(findNearestStopByCoordinates(40.0, -70.0, undefined as unknown as StopItem[]), null);
    });
  });

  describe('resolvePlaceToNearestStation', () => {
    const stopsFixture: StopItem[] = [
      { id: 10, name: 'Stop 10', lat: 40.1, lon: -73.1 },
      { id: 20, name: 'Stop 20', lat: 40.2, lon: -73.2 },
    ];

    it('resolves place to matching stop using candidate lookup function', async () => {
      const candidateLookup = async () => [20, 10];
      const resolved = await resolvePlaceToNearestStation(
        { lat: 40.21, lon: -73.21 },
        candidateLookup,
        stopsFixture
      );

      assert.ok(resolved);
      assert.strictEqual(resolved.id, 20);
    });

    it('resolves place when stops is passed as a Map', async () => {
      const stopsMap = new Map<number, StopItem>([
        [10, stopsFixture[0]],
        [20, stopsFixture[1]],
      ]);
      const candidateLookup = async () => [10];
      const resolved = await resolvePlaceToNearestStation(
        { lat: 40.1, lon: -73.1 },
        candidateLookup,
        stopsMap
      );

      assert.ok(resolved);
      assert.strictEqual(resolved.id, 10);
    });

    it('negative: returns null when candidates do not match any known stops', async () => {
      const candidateLookup = async () => [999, 888];
      const resolved = await resolvePlaceToNearestStation(
        { lat: 40.0, lon: -73.0 },
        candidateLookup,
        stopsFixture
      );

      assert.strictEqual(resolved, null);
    });

    it('negative: gracefully degrades when candidateLookup throws', async () => {
      const failingLookup = async () => {
        throw new Error('Routing engine worker failure');
      };

      const resolved = await resolvePlaceToNearestStation(
        { lat: 40.0, lon: -73.0 },
        failingLookup,
        stopsFixture
      );

      assert.strictEqual(resolved, null);
    });

    it('falls back to Euclidean distance when candidate lookup returns no matches and fallbackToDistance is enabled', async () => {
      const candidateLookup = async () => [];
      const resolved = await resolvePlaceToNearestStation(
        { lat: 40.11, lon: -73.11 },
        candidateLookup,
        stopsFixture,
        { fallbackToDistance: true }
      );

      assert.ok(resolved);
      assert.strictEqual(resolved.id, 10);
    });
  });

  describe('debounce', () => {
    it('executes debounced callback after specified delay', async () => {
      let callCount = 0;
      let lastArg = '';
      const fn = debounce((arg: string) => {
        callCount++;
        lastArg = arg;
      }, 30);

      fn('first');
      fn('second');
      fn('final');

      assert.strictEqual(callCount, 0);
      await new Promise((resolve) => setTimeout(resolve, 60));
      assert.strictEqual(callCount, 1);
      assert.strictEqual(lastArg, 'final');
    });

    it('negative: cancel prevents pending debounced execution', async () => {
      let callCount = 0;
      const fn = debounce(() => {
        callCount++;
      }, 30);

      fn();
      fn.cancel();

      await new Promise((resolve) => setTimeout(resolve, 60));
      assert.strictEqual(callCount, 0);
    });
  });
});
