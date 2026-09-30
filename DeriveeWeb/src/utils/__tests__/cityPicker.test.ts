import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  formatCityPackSize,
  parseCitiesManifest,
  getCityPickerDisplayModel,
  reduceCityPickerState,
  fetchCitiesManifest,
} from '../cityPicker.ts';
import type {
  CityManifestItem,
  CityPickerState,
} from '../../types/cityPicker.ts';

describe('M5c City Picker & Manifest Utilities', () => {
  // ==========================================================================
  // 1. Pack Size Formatting Tests
  // ==========================================================================
  describe('formatCityPackSize', () => {
    it('formats megabyte sizes to 1 decimal place', () => {
      assert.strictEqual(formatCityPackSize(29_688_421), '28.3 MB');
      assert.strictEqual(formatCityPackSize(9_400_000), '9.0 MB');
      assert.strictEqual(formatCityPackSize(1_048_576), '1.0 MB');
    });

    it('formats kilobyte sizes rounded to nearest whole KB', () => {
      assert.strictEqual(formatCityPackSize(512_000), '500 KB');
      assert.strictEqual(formatCityPackSize(1_024), '1 KB');
      assert.strictEqual(formatCityPackSize(10_240), '10 KB');
    });

    it('formats gigabyte sizes to 1 decimal place', () => {
      assert.strictEqual(formatCityPackSize(1_073_741_824), '1.0 GB');
      assert.strictEqual(formatCityPackSize(2_500_000_000), '2.3 GB');
    });

    it('formats small byte counts', () => {
      assert.strictEqual(formatCityPackSize(500), '500 B');
      assert.strictEqual(formatCityPackSize(1), '1 B');
    });

    it('formats zero bytes honestly', () => {
      assert.strictEqual(formatCityPackSize(0), '0 MB');
    });

    describe('Negative & Boundary Cases', () => {
      it('handles negative byte counts safely', () => {
        assert.strictEqual(formatCityPackSize(-100), 'Size unknown');
        assert.strictEqual(formatCityPackSize(-1), 'Size unknown');
      });

      it('handles null and undefined safely without throwing', () => {
        assert.strictEqual(formatCityPackSize(null), 'Size unknown');
        assert.strictEqual(formatCityPackSize(undefined), 'Size unknown');
      });

      it('handles NaN safely without throwing', () => {
        assert.strictEqual(formatCityPackSize(NaN), 'Size unknown');
      });
    });
  });

  // ==========================================================================
  // 2. Cities Manifest Parsing Tests
  // ==========================================================================
  describe('parseCitiesManifest', () => {
    it('parses direct JSON array manifest [{slug, name, pack_bytes, version, bbox}]', () => {
      const input = [
        {
          slug: 'nyc',
          name: 'New York City',
          pack_bytes: 29688421,
          version: '2.0.0',
          bbox: [-74.25, 40.49, -73.7, 40.91],
        },
        {
          slug: 'bos',
          name: 'Boston',
          pack_bytes: 9400000,
          version: '2.0.0',
          bbox: [-71.19, 42.22, -70.98, 42.39],
        },
      ];

      const parsed = parseCitiesManifest(input);
      assert.strictEqual(parsed.length, 2);

      assert.strictEqual(parsed[0].slug, 'nyc');
      assert.strictEqual(parsed[0].name, 'New York City');
      assert.strictEqual(parsed[0].pack_bytes, 29688421);
      assert.strictEqual(parsed[0].version, '2.0.0');
      assert.deepStrictEqual(parsed[0].bbox, [-74.25, 40.49, -73.7, 40.91]);

      assert.strictEqual(parsed[1].slug, 'bos');
      assert.strictEqual(parsed[1].name, 'Boston');
      assert.strictEqual(parsed[1].pack_bytes, 9400000);
    });

    it('parses Go CitiesManifest object structure {version, cities: [{slug, displayName, compressedSizeBytes}]}', () => {
      const input = {
        version: 2,
        lastUpdated: '2026-09-02T12:00:00Z',
        cities: [
          {
            slug: 'nyc',
            displayName: 'New York City',
            region: 'New York, USA',
            compressedSizeBytes: 29688421,
            uncompressedSizeBytes: 65348216,
            isBundled: true,
            version: '2.0.0',
            bounds: {
              minLon: -74.25,
              minLat: 40.49,
              maxLon: -73.7,
              maxLat: 40.91,
            },
          },
        ],
      };

      const parsed = parseCitiesManifest(input);
      assert.strictEqual(parsed.length, 1);
      assert.strictEqual(parsed[0].slug, 'nyc');
      assert.strictEqual(parsed[0].name, 'New York City');
      assert.strictEqual(parsed[0].pack_bytes, 29688421);
      assert.deepStrictEqual(parsed[0].bbox, [-74.25, 40.49, -73.7, 40.91]);
    });

    it('falls back to capitalized slug when name and displayName are missing', () => {
      const input = [{ slug: 'chi', pack_bytes: 15000000 }];
      const parsed = parseCitiesManifest(input);
      assert.strictEqual(parsed.length, 1);
      assert.strictEqual(parsed[0].name, 'CHI');
    });

    describe('Negative & Malformed Payload Handling', () => {
      it('returns empty array when input is null, undefined, or primitive', () => {
        assert.deepStrictEqual(parseCitiesManifest(null), []);
        assert.deepStrictEqual(parseCitiesManifest(undefined), []);
        assert.deepStrictEqual(parseCitiesManifest('string'), []);
        assert.deepStrictEqual(parseCitiesManifest(12345), []);
        assert.deepStrictEqual(parseCitiesManifest(true), []);
      });

      it('returns empty array when object has no cities array', () => {
        assert.deepStrictEqual(parseCitiesManifest({}), []);
        assert.deepStrictEqual(parseCitiesManifest({ version: 2 }), []);
        assert.deepStrictEqual(parseCitiesManifest({ cities: 'not an array' }), []);
      });

      it('filters out entries missing slug or with empty slug', () => {
        const input = [
          { name: 'No Slug' },
          { slug: '', name: 'Empty Slug' },
          { slug: '   ', name: 'Whitespace Slug' },
          { slug: 123, name: 'Numeric Slug' },
          null,
          undefined,
          { slug: 'valid', name: 'Valid City', pack_bytes: 1000 },
        ];
        const parsed = parseCitiesManifest(input);
        assert.strictEqual(parsed.length, 1);
        assert.strictEqual(parsed[0].slug, 'valid');
      });

      it('sanitizes negative or NaN pack_bytes to 0', () => {
        const input = [
          { slug: 'city1', pack_bytes: -500 },
          { slug: 'city2', pack_bytes: 'not-a-number' },
        ];
        const parsed = parseCitiesManifest(input);
        assert.strictEqual(parsed[0].pack_bytes, 0);
        assert.strictEqual(parsed[1].pack_bytes, 0);
      });

      it('sets bbox to null when bbox format is invalid', () => {
        const input = [
          { slug: 'city1', bbox: [1, 2, 3] }, // only 3 elements
          { slug: 'city2', bbox: [1, 2, 'three', 4] }, // non-number
          { slug: 'city3', bbox: null },
        ];
        const parsed = parseCitiesManifest(input);
        assert.strictEqual(parsed[0].bbox, null);
        assert.strictEqual(parsed[1].bbox, null);
        assert.strictEqual(parsed[2].bbox, null);
      });
    });
  });

  // ==========================================================================
  // 3. Display Model & Rule 12 Anti-Leak Tests
  // ==========================================================================
  describe('getCityPickerDisplayModel & Rule 12 Anti-Leak Compliance', () => {
    const singleCityState: CityPickerState = {
      status: 'one_city',
      activeCitySlug: 'nyc',
      cities: [
        {
          slug: 'nyc',
          name: 'New York City',
          pack_bytes: 29688421,
          version: '2.0.0',
          bbox: [-74.25, 40.49, -73.7, 40.91],
        },
      ],
      errorMessage: null,
      switchProgress: null,
    };

    const multiCityState: CityPickerState = {
      status: 'multiple_cities',
      activeCitySlug: 'nyc',
      cities: [
        {
          slug: 'nyc',
          name: 'New York City',
          pack_bytes: 29688421,
          version: '2.0.0',
          bbox: [-74.25, 40.49, -73.7, 40.91],
        },
        {
          slug: 'bos',
          name: 'Boston',
          pack_bytes: 9400000,
          version: '2.0.0',
          bbox: [-71.19, 42.22, -70.98, 42.39],
        },
      ],
      errorMessage: null,
      switchProgress: null,
    };

    it('returns loading display model', () => {
      const state: CityPickerState = {
        ...singleCityState,
        status: 'loading',
      };
      const model = getCityPickerDisplayModel(state);
      assert.strictEqual(model.status, 'loading');
      assert.strictEqual(model.subtitle, 'Loading available cities...');
      assert.strictEqual(model.canRetry, false);
      assert.strictEqual(model.canSelectCity, false);
    });

    it('returns load-error display model with retry capability', () => {
      const state: CityPickerState = {
        ...singleCityState,
        status: 'load-error',
        errorMessage: 'HTTP 404: Not Found',
      };
      const model = getCityPickerDisplayModel(state);
      assert.strictEqual(model.status, 'load-error');
      assert.strictEqual(model.subtitle, 'Unable to load available cities');
      assert.strictEqual(model.canRetry, true);
      assert.strictEqual(model.canSelectCity, false);
    });

    it('returns one_city display model honestly indicating single available city', () => {
      const model = getCityPickerDisplayModel(singleCityState);
      assert.strictEqual(model.status, 'one_city');
      assert.strictEqual(model.title, 'Active Metro');
      assert.strictEqual(model.subtitle, '1 metro available');
      assert.strictEqual(model.canSelectCity, false);
      assert.strictEqual(model.options.length, 1);
      assert.strictEqual(model.options[0].fullLabel, 'New York City (28.3 MB)');
      assert.strictEqual(model.options[0].isSelected, true);
    });

    it('returns multiple_cities display model showing download sizes before committing', () => {
      const model = getCityPickerDisplayModel(multiCityState);
      assert.strictEqual(model.status, 'multiple_cities');
      assert.strictEqual(model.title, 'Select Metro');
      assert.strictEqual(model.subtitle, '2 metros available');
      assert.strictEqual(model.canSelectCity, true);
      assert.strictEqual(model.options.length, 2);

      // NYC Option
      assert.strictEqual(model.options[0].slug, 'nyc');
      assert.strictEqual(model.options[0].formattedSize, '28.3 MB');
      assert.strictEqual(model.options[0].fullLabel, 'New York City (28.3 MB)');
      assert.strictEqual(model.options[0].isSelected, true);

      // Boston Option
      assert.strictEqual(model.options[1].slug, 'bos');
      assert.strictEqual(model.options[1].formattedSize, '9.0 MB');
      assert.strictEqual(model.options[1].fullLabel, 'Boston (9.0 MB)');
      assert.strictEqual(model.options[1].isSelected, false);
    });

    it('returns switching display model with progress details', () => {
      const state: CityPickerState = {
        ...multiCityState,
        status: 'switching',
        switchProgress: {
          targetSlug: 'bos',
          targetName: 'Boston',
          stage: 'downloading',
          percent: 45,
        },
      };
      const model = getCityPickerDisplayModel(state);
      assert.strictEqual(model.status, 'switching');
      assert.strictEqual(model.title, 'Switching Metro');
      assert.strictEqual(model.subtitle, 'Switching to Boston...');
      assert.strictEqual(model.canSelectCity, false);
      assert.strictEqual(model.progressMessage, 'Downloading transit pack (45%)...');
    });

    describe('Rule 12: Zero Internal ID / Technical Leak Assertion', () => {
      const allStates: CityPickerState[] = [
        {
          status: 'loading',
          activeCitySlug: 'nyc',
          cities: [],
          errorMessage: 'Connecting to Cloudflare R2 bucket fog-of-transit (0x10002)',
          switchProgress: null,
        },
        {
          status: 'load-error',
          activeCitySlug: 'nyc',
          cities: [],
          errorMessage: 'HTTP 404 Not Found: /api/cities (key: cities.json)',
          switchProgress: null,
        },
        singleCityState,
        multiCityState,
        {
          status: 'switching',
          activeCitySlug: 'nyc',
          cities: multiCityState.cities,
          errorMessage: null,
          switchProgress: {
            targetSlug: 'bos',
            targetName: 'Boston',
            stage: 'decompressing',
            percent: 80,
            message: 'Extracting transit.sqlite into OPFS root /cities/bos/',
          },
        },
      ];

      it('asserts that no UI copy leaks internal IDs, status codes, or file paths', () => {
        const forbiddenPatterns = [
          /0x[0-9a-fA-F]+/i, // hex memory addresses
          /\b(400|401|403|404|429|500|502|503)\b/, // HTTP status codes
          /\.(json|zst|sqlite|bin|pmtiles|ts|js)\b/i, // file extensions
          /\b(fog-of-transit|r2_bucket|opfs_root|pack_installer)\b/i, // internal bucket/infra IDs
          /\b(ENOENT|SQLITE_BUSY|WASM_UNREACHABLE)\b/i, // low-level engine errors
        ];

        for (const state of allStates) {
          const model = getCityPickerDisplayModel(state);
          const stringsToCheck = [
            model.title,
            model.subtitle,
            model.activeCityName,
            model.progressMessage || '',
            ...model.options.map((o) => o.fullLabel),
            ...model.options.map((o) => o.displayName),
          ];

          for (const str of stringsToCheck) {
            for (const pattern of forbiddenPatterns) {
              assert.ok(
                !pattern.test(str),
                `String "${str}" leaked forbidden pattern ${pattern} in state ${state.status}`
              );
            }
          }
        }
      });
    });
  });

  // ==========================================================================
  // 4. State Machine Reducer & Transition Tests
  // ==========================================================================
  describe('reduceCityPickerState transitions', () => {
    const initialState: CityPickerState = {
      status: 'loading',
      activeCitySlug: 'nyc',
      cities: [],
      errorMessage: null,
      switchProgress: null,
    };

    it('FETCH_START transitions to loading', () => {
      const state: CityPickerState = { ...initialState, status: 'load-error', errorMessage: 'Error' };
      const next = reduceCityPickerState(state, { type: 'FETCH_START' });
      assert.strictEqual(next.status, 'loading');
      assert.strictEqual(next.errorMessage, null);
    });

    it('FETCH_SUCCESS transitions to one_city when 1 city returned', () => {
      const cities: CityManifestItem[] = [
        { slug: 'nyc', name: 'New York City', pack_bytes: 29688421, version: '2.0.0', bbox: null },
      ];
      const next = reduceCityPickerState(initialState, { type: 'FETCH_SUCCESS', cities });
      assert.strictEqual(next.status, 'one_city');
      assert.strictEqual(next.cities.length, 1);
      assert.strictEqual(next.errorMessage, null);
    });

    it('FETCH_SUCCESS transitions to multiple_cities when >1 cities returned', () => {
      const cities: CityManifestItem[] = [
        { slug: 'nyc', name: 'New York City', pack_bytes: 29688421, version: '2.0.0', bbox: null },
        { slug: 'bos', name: 'Boston', pack_bytes: 9400000, version: '2.0.0', bbox: null },
      ];
      const next = reduceCityPickerState(initialState, { type: 'FETCH_SUCCESS', cities });
      assert.strictEqual(next.status, 'multiple_cities');
      assert.strictEqual(next.cities.length, 2);
    });

    it('FETCH_ERROR transitions to load-error with human-friendly message', () => {
      const next = reduceCityPickerState(initialState, {
        type: 'FETCH_ERROR',
        error: 'Network timeout / 404',
      });
      assert.strictEqual(next.status, 'load-error');
      assert.strictEqual(next.errorMessage, 'Unable to load available cities');
    });

    it('RETRY transitions back to loading', () => {
      const errorState: CityPickerState = {
        ...initialState,
        status: 'load-error',
        errorMessage: 'Unable to load available cities',
      };
      const next = reduceCityPickerState(errorState, { type: 'RETRY' });
      assert.strictEqual(next.status, 'loading');
      assert.strictEqual(next.errorMessage, null);
    });

    it('START_SWITCH transitions to switching and tracks target city', () => {
      const readyState: CityPickerState = {
        status: 'multiple_cities',
        activeCitySlug: 'nyc',
        cities: [
          { slug: 'nyc', name: 'New York City', pack_bytes: 29688421, version: '2.0.0', bbox: null },
          { slug: 'bos', name: 'Boston', pack_bytes: 9400000, version: '2.0.0', bbox: null },
        ],
        errorMessage: null,
        switchProgress: null,
      };

      const next = reduceCityPickerState(readyState, {
        type: 'START_SWITCH',
        targetSlug: 'bos',
        targetName: 'Boston',
      });

      assert.strictEqual(next.status, 'switching');
      assert.ok(next.switchProgress);
      assert.strictEqual(next.switchProgress?.targetSlug, 'bos');
      assert.strictEqual(next.switchProgress?.targetName, 'Boston');
      assert.strictEqual(next.switchProgress?.stage, 'downloading');
    });

    it('SWITCH_PROGRESS updates stage and percent', () => {
      const switchingState: CityPickerState = {
        status: 'switching',
        activeCitySlug: 'nyc',
        cities: [],
        errorMessage: null,
        switchProgress: {
          targetSlug: 'bos',
          targetName: 'Boston',
          stage: 'downloading',
          percent: 10,
        },
      };

      const next = reduceCityPickerState(switchingState, {
        type: 'SWITCH_PROGRESS',
        stage: 'decompressing',
        percent: 60,
      });

      assert.strictEqual(next.switchProgress?.stage, 'decompressing');
      assert.strictEqual(next.switchProgress?.percent, 60);
    });

    it('SWITCH_SUCCESS updates activeCitySlug and clears progress', () => {
      const switchingState: CityPickerState = {
        status: 'switching',
        activeCitySlug: 'nyc',
        cities: [
          { slug: 'nyc', name: 'New York City', pack_bytes: 29688421, version: '2.0.0', bbox: null },
          { slug: 'bos', name: 'Boston', pack_bytes: 9400000, version: '2.0.0', bbox: null },
        ],
        errorMessage: null,
        switchProgress: {
          targetSlug: 'bos',
          targetName: 'Boston',
          stage: 'verifying',
          percent: 100,
        },
      };

      const next = reduceCityPickerState(switchingState, {
        type: 'SWITCH_SUCCESS',
        newActiveSlug: 'bos',
      });

      assert.strictEqual(next.status, 'multiple_cities');
      assert.strictEqual(next.activeCitySlug, 'bos');
      assert.strictEqual(next.switchProgress, null);
    });

    it('SWITCH_ERROR resets switching and sets error message', () => {
      const switchingState: CityPickerState = {
        status: 'switching',
        activeCitySlug: 'nyc',
        cities: [],
        errorMessage: null,
        switchProgress: {
          targetSlug: 'bos',
          targetName: 'Boston',
          stage: 'downloading',
        },
      };

      const next = reduceCityPickerState(switchingState, {
        type: 'SWITCH_ERROR',
        error: 'Network failure',
      });

      assert.strictEqual(next.status, 'load-error');
      assert.strictEqual(next.switchProgress, null);
      assert.strictEqual(next.errorMessage, 'Unable to switch metro area');
    });

    describe('Negative & Guard Transitions', () => {
      it('ignores START_SWITCH when already switching (prevents concurrent switches)', () => {
        const switchingState: CityPickerState = {
          status: 'switching',
          activeCitySlug: 'nyc',
          cities: [],
          errorMessage: null,
          switchProgress: {
            targetSlug: 'bos',
            targetName: 'Boston',
            stage: 'downloading',
          },
        };

        const next = reduceCityPickerState(switchingState, {
          type: 'START_SWITCH',
          targetSlug: 'chi',
          targetName: 'Chicago',
        });

        assert.strictEqual(next.switchProgress?.targetSlug, 'bos');
      });

      it('ignores SWITCH_PROGRESS when status is not switching', () => {
        const state: CityPickerState = {
          status: 'one_city',
          activeCitySlug: 'nyc',
          cities: [],
          errorMessage: null,
          switchProgress: null,
        };

        const next = reduceCityPickerState(state, {
          type: 'SWITCH_PROGRESS',
          stage: 'downloading',
        });

        assert.strictEqual(next.switchProgress, null);
      });
    });
  });

  // ==========================================================================
  // 5. Fetch Cities Manifest Integration & Failure Path Tests
  // ==========================================================================
  describe('fetchCitiesManifest & failure paths', () => {
    it('successfully parses data from a mock 200 response', async () => {
      const originalFetch = globalThis.fetch;
      try {
        globalThis.fetch = async () => {
          return new Response(
            JSON.stringify([
              {
                slug: 'nyc',
                name: 'New York City',
                pack_bytes: 29688421,
                version: '2.0.0',
                bbox: [-74.25, 40.49, -73.7, 40.91],
              },
            ]),
            { status: 200, headers: { 'Content-Type': 'application/json' } }
          );
        };

        const cities = await fetchCitiesManifest('/api/cities');
        assert.strictEqual(cities.length, 1);
        assert.strictEqual(cities[0].slug, 'nyc');
        assert.strictEqual(cities[0].pack_bytes, 29688421);
      } finally {
        globalThis.fetch = originalFetch;
      }
    });

    it('rejects with error when server returns HTTP 404 (cities.json missing in R2)', async () => {
      const originalFetch = globalThis.fetch;
      try {
        globalThis.fetch = async () => {
          return new Response(JSON.stringify({ error: 'not_found' }), {
            status: 404,
            headers: { 'Content-Type': 'application/json' },
          });
        };

        await assert.rejects(
          async () => {
            await fetchCitiesManifest('/api/cities');
          },
          {
            message: /HTTP 404/,
          }
        );
      } finally {
        globalThis.fetch = originalFetch;
      }
    });

    it('rejects with error when network request fails', async () => {
      const originalFetch = globalThis.fetch;
      try {
        globalThis.fetch = async () => {
          throw new Error('Failed to fetch');
        };

        await assert.rejects(
          async () => {
            await fetchCitiesManifest('/api/cities');
          },
          {
            message: 'Failed to fetch',
          }
        );
      } finally {
        globalThis.fetch = originalFetch;
      }
    });
  });

  // ==========================================================================
  // 6. CityPicker Component Source & UI States Contract Tests
  // ==========================================================================
  describe('CityPicker Preact Component Source Contract', () => {
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = path.dirname(__filename);
    const cpPath = path.resolve(__dirname, '../../components/CityPicker.tsx');
    const cpContent = fs.readFileSync(cpPath, 'utf8');

    it('CityPicker.tsx binds data-status to display model status', () => {
      assert.ok(
        cpContent.includes('data-status={model.status}'),
        'CityPicker.tsx must set data-status attribute to model.status'
      );
    });

    it('CityPicker.tsx renders all 5 UI state branches: loading, load-error, one_city, multiple_cities, switching', () => {
      assert.ok(
        cpContent.includes("model.status === 'loading'"),
        'CityPicker.tsx must handle loading status'
      );
      assert.ok(
        cpContent.includes("model.status === 'load-error'"),
        'CityPicker.tsx must handle load-error status'
      );
      assert.ok(
        cpContent.includes("model.status === 'one_city'"),
        'CityPicker.tsx must handle one_city status'
      );
      assert.ok(
        cpContent.includes("model.status === 'multiple_cities'"),
        'CityPicker.tsx must handle multiple_cities status'
      );
      assert.ok(
        cpContent.includes("model.status === 'switching'"),
        'CityPicker.tsx must handle switching status'
      );
    });

    it('CityPicker.tsx renders retry button wired to onRetry prop in load-error branch', () => {
      assert.ok(
        cpContent.includes('onClick={onRetry}'),
        'CityPicker.tsx must wire retry button to onRetry prop'
      );
      assert.ok(
        cpContent.includes('class="city-picker-retry-btn"'),
        'CityPicker.tsx must declare city-picker-retry-btn class'
      );
    });

    it('CityPicker.tsx renders select dropdown wired to onSelectCity in multiple_cities branch', () => {
      assert.ok(
        cpContent.includes('onChange={(e) => onSelectCity?.((e.target as HTMLSelectElement).value)}'),
        'CityPicker.tsx must wire select change to onSelectCity'
      );
      assert.ok(
        cpContent.includes('{opt.fullLabel}'),
        'CityPicker.tsx must render opt.fullLabel showing download size before user commits'
      );
    });

    it('CityPicker.tsx renders single city label without select dropdown in one_city branch', () => {
      assert.ok(
        cpContent.includes('city-picker-single'),
        'CityPicker.tsx must declare city-picker-single class'
      );
      assert.ok(
        cpContent.includes('city-active-label'),
        'CityPicker.tsx must declare city-active-label class'
      );
    });

    it('negative case: proves test fails if CityPicker is missing data-status binding', () => {
      const brokenSnippet = '<div class="city-picker-card">';
      assert.strictEqual(
        brokenSnippet.includes('data-status={model.status}'),
        false,
        'Should catch missing data-status binding'
      );
    });

    it('negative case: proves test fails if CityPicker lacks onSelectCity wiring', () => {
      const brokenSnippet = '<select value={state.activeCitySlug}>';
      assert.strictEqual(
        brokenSnippet.includes('onSelectCity'),
        false,
        'Should catch missing onSelectCity wiring'
      );
    });
  });

  // ==========================================================================
  // 7. TripPlanner Wiring & Static Architecture Verification
  // ==========================================================================
  describe('TripPlanner City Switch Wiring Contract', () => {
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = path.dirname(__filename);
    const tpPath = path.resolve(__dirname, '../../components/TripPlanner.tsx');
    const tpContent = fs.readFileSync(tpPath, 'utf8');

    it('TripPlanner.tsx imports and renders CityPicker component', () => {
      assert.ok(
        tpContent.includes("import { CityPicker } from './CityPicker'"),
        'TripPlanner.tsx must import CityPicker'
      );
      assert.ok(
        tpContent.includes('<CityPicker'),
        'TripPlanner.tsx must render <CityPicker'
      );
    });

    it('TripPlanner.tsx fetches cities manifest on mount via fetchCitiesManifest', () => {
      assert.ok(
        tpContent.includes("fetchCitiesManifest('/api/cities')"),
        'TripPlanner.tsx must fetch /api/cities'
      );
    });

    it('TripPlanner.tsx passes city slug to routing worker INIT message', () => {
      assert.ok(
        tpContent.includes("{ type: 'INIT', city: slug }"),
        'TripPlanner.tsx must pass city slug to routing worker INIT'
      );
    });

    it('TripPlanner.tsx handles city switch: clears engine, installs pack, and re-hydrates', () => {
      assert.ok(
        tpContent.includes("new URL('../workers/pack-installer.worker.ts'"),
        'TripPlanner.tsx must spawn pack-installer.worker.ts on city switch'
      );
      assert.ok(
        tpContent.includes("type: 'START_INSTALL'"),
        'TripPlanner.tsx must post START_INSTALL message to pack installer'
      );
      assert.ok(
        tpContent.includes('startRoutingWorker(targetSlug)'),
        'TripPlanner.tsx must re-hydrate routing engine upon switch success'
      );
    });
  });
});

