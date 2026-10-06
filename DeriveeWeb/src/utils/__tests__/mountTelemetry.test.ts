import '../maplibreEnv.ts';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PMTiles, FileSource } from 'pmtiles';
import {
  formatMountDiagnostic,
  MOUNT_SUB_STAGE_ORDER,
  setActiveTileTracker,
  getGlobalPMTilesProtocol,
  type TileEvent,
} from '../maplibreAdapter.ts';
import { BasemapStateMachine } from '../basemapStateMachine.ts';
import type { MountDiagnostic, MountSubStage } from '../../types/basemap.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REAL_PMTILES_PATH = path.resolve(__dirname, '../../../../DeriveeNative/Derivee/basemap-nyc.pmtiles');

describe('Mount Telemetry & Sub-stage Diagnostic Tests', () => {
  const fileBuffer = fs.readFileSync(REAL_PMTILES_PATH);
  const mockOpfsFile = new File([fileBuffer], 'basemap.pmtiles');
  const pmtiles = new PMTiles(new FileSource(mockOpfsFile));
  const protocol = getGlobalPMTilesProtocol();
  protocol.add(pmtiles);
  describe('formatMountDiagnostic', () => {
    it('formats last reached sub-stage, tile counts, and first tile error correctly', () => {
      const diag: MountDiagnostic = {
        subStage: 'MOUNT_FIRST_TILE_REQUESTED',
        tilesRequested: 12,
        tilesLoaded: 0,
        tilesErrored: 12,
        firstTileError: 'NotReadableError: The requested file could not be read',
      };

      const result = formatMountDiagnostic(diag);
      assert.strictEqual(
        result,
        'Stage: MAP_MOUNTING\nDiagnostic: MapLibre failed to load style and tiles within 20s (sub-stage: MOUNT_FIRST_TILE_REQUESTED, tiles requested: 12, loaded: 0, errored: 12, first error: NotReadableError: The requested file could not be read).'
      );
    });

    it('formats diagnostic cleanly when there are no tile errors', () => {
      const diag: MountDiagnostic = {
        subStage: 'MOUNT_FIRST_TILE_LOADED',
        tilesRequested: 8,
        tilesLoaded: 8,
        tilesErrored: 0,
        firstTileError: null,
      };

      const result = formatMountDiagnostic(diag);
      assert.strictEqual(
        result,
        'Stage: MAP_MOUNTING\nDiagnostic: MapLibre failed to load style and tiles within 20s (sub-stage: MOUNT_FIRST_TILE_LOADED, tiles requested: 8, loaded: 8, errored: 0).'
      );
      assert.strictEqual(result.includes('first error'), false);
    });

    it('formats diagnostic for initial style loading stage with zero tile activity', () => {
      const diag: MountDiagnostic = {
        subStage: 'MOUNT_STYLE_LOADING',
        tilesRequested: 0,
        tilesLoaded: 0,
        tilesErrored: 0,
        firstTileError: null,
      };

      const result = formatMountDiagnostic(diag);
      assert.strictEqual(
        result,
        'Stage: MAP_MOUNTING\nDiagnostic: MapLibre failed to load style and tiles within 20s (sub-stage: MOUNT_STYLE_LOADING, tiles requested: 0, loaded: 0, errored: 0).'
      );
    });

    it('negative case: handles null or undefined diagnostic with fallback diagnostic string', () => {
      const fallbackNull = formatMountDiagnostic(null);
      assert.strictEqual(
        fallbackNull,
        'Stage: MAP_MOUNTING\nDiagnostic: MapLibre failed to load style and tiles within 20s.'
      );

      const fallbackUndefined = formatMountDiagnostic(undefined);
      assert.strictEqual(
        fallbackUndefined,
        'Stage: MAP_MOUNTING\nDiagnostic: MapLibre failed to load style and tiles within 20s.'
      );
    });
  });

  describe('MOUNT_SUB_STAGE_ORDER hierarchy', () => {
    it('defines strictly increasing monotonic ordering across all 5 sub-stages', () => {
      const stages: MountSubStage[] = [
        'MOUNT_STYLE_LOADING',
        'MOUNT_STYLE_PARSED',
        'MOUNT_FIRST_TILE_REQUESTED',
        'MOUNT_FIRST_TILE_LOADED',
        'MOUNT_GLYPHS_LOADED',
      ];

      for (let i = 0; i < stages.length - 1; i++) {
        const current = stages[i];
        const next = stages[i + 1];
        assert.ok(
          MOUNT_SUB_STAGE_ORDER[current] < MOUNT_SUB_STAGE_ORDER[next],
          `Sub-stage ${current} (rank ${MOUNT_SUB_STAGE_ORDER[current]}) must precede ${next} (rank ${MOUNT_SUB_STAGE_ORDER[next]})`
        );
      }
    });

    it('negative case: earlier sub-stages cannot supersede a later sub-stage', () => {
      assert.ok(
        MOUNT_SUB_STAGE_ORDER['MOUNT_STYLE_LOADING'] < MOUNT_SUB_STAGE_ORDER['MOUNT_FIRST_TILE_LOADED']
      );
      assert.ok(
        !(MOUNT_SUB_STAGE_ORDER['MOUNT_FIRST_TILE_LOADED'] < MOUNT_SUB_STAGE_ORDER['MOUNT_STYLE_PARSED'])
      );
    });
  });

  describe('BasemapStateMachine mountSubStage integration', () => {
    it('tracks mountSubStage while preserving lastStage as MAP_MOUNTING', () => {
      const sm = new BasemapStateMachine('map-loading');
      sm.setStage('MAP_MOUNTING');
      sm.setMountSubStage('MOUNT_STYLE_LOADING');

      assert.strictEqual(sm.snapshot.lastStage, 'MAP_MOUNTING');
      assert.strictEqual(sm.snapshot.mountSubStage, 'MOUNT_STYLE_LOADING');

      sm.setMountSubStage('MOUNT_FIRST_TILE_REQUESTED');
      assert.strictEqual(sm.snapshot.lastStage, 'MAP_MOUNTING');
      assert.strictEqual(sm.snapshot.mountSubStage, 'MOUNT_FIRST_TILE_REQUESTED');

      // Error preserves mountSubStage
      const diag: MountDiagnostic = {
        subStage: 'MOUNT_FIRST_TILE_REQUESTED',
        tilesRequested: 6,
        tilesLoaded: 0,
        tilesErrored: 6,
        firstTileError: 'NetworkError',
      };
      sm.setError(
        'Map setup stalled (stage: MAP_MOUNTING). Please tap Retry.',
        formatMountDiagnostic(diag),
        'MAP_MOUNTING'
      );

      assert.strictEqual(sm.snapshot.state, 'map-error');
      assert.strictEqual(sm.snapshot.lastStage, 'MAP_MOUNTING');
      assert.strictEqual(sm.snapshot.mountSubStage, 'MOUNT_FIRST_TILE_REQUESTED');
      assert.ok(sm.snapshot.errorDetails?.includes('sub-stage: MOUNT_FIRST_TILE_REQUESTED'));
      assert.ok(sm.snapshot.errorDetails?.includes('tiles requested: 6, loaded: 0, errored: 6'));
    });

    it('negative case: setReady and retry reset mountSubStage cleanly', () => {
      const sm = new BasemapStateMachine('map-loading');
      sm.setStage('MAP_MOUNTING');
      sm.setMountSubStage('MOUNT_GLYPHS_LOADED');
      assert.strictEqual(sm.snapshot.mountSubStage, 'MOUNT_GLYPHS_LOADED');

      sm.setReady();
      assert.strictEqual(sm.snapshot.state, 'map-ready');
      assert.strictEqual(sm.snapshot.lastStage, 'MAP_READY');
      assert.strictEqual(sm.snapshot.mountSubStage, null);

      // On retry from error
      sm.setMountSubStage('MOUNT_FIRST_TILE_REQUESTED');
      sm.retry();
      assert.strictEqual(sm.snapshot.state, 'map-loading');
      assert.strictEqual(sm.snapshot.mountSubStage, null);
    });
  });

  describe('Protocol tile handler wrapping & event dispatch', () => {
    it('dispatches tile_requested and tile_loaded events for vector tiles', async () => {
      const events: TileEvent[] = [];
      setActiveTileTracker((e) => events.push(e));

      const protocol = getGlobalPMTilesProtocol();

      // Trigger tile request via callback
      await new Promise<void>((resolve) => {
        protocol.tile({ url: 'pmtiles://basemap.pmtiles/12/1206/1539' }, () => {
          resolve();
        });
      });

      setActiveTileTracker(null);

      const reqEvent = events.find((e) => e.type === 'tile_requested');
      assert.ok(reqEvent, 'Must emit tile_requested event');
      assert.strictEqual(reqEvent.url, 'pmtiles://basemap.pmtiles/12/1206/1539');

      const loadEvent = events.find((e) => e.type === 'tile_loaded');
      assert.ok(loadEvent, 'Must emit tile_loaded event');
      assert.strictEqual(loadEvent.url, 'pmtiles://basemap.pmtiles/12/1206/1539');
      assert.ok(loadEvent.byteLength > 0, 'Loaded vector tile must contain non-zero bytes');
    });

    it('dispatches tile_requested and tile_loaded events for vector tiles (Promise / AbortController mode)', async () => {
      const events: TileEvent[] = [];
      setActiveTileTracker((e) => events.push(e));

      const protocol = getGlobalPMTilesProtocol();
      const controller = new AbortController();

      const res: any = await protocol.tile({ url: 'pmtiles://basemap.pmtiles/12/1206/1539' }, controller);

      setActiveTileTracker(null);

      const reqEvent = events.find((e) => e.type === 'tile_requested');
      assert.ok(reqEvent, 'Must emit tile_requested event');
      assert.strictEqual(reqEvent.url, 'pmtiles://basemap.pmtiles/12/1206/1539');

      const loadEvent = events.find((e) => e.type === 'tile_loaded');
      assert.ok(loadEvent, 'Must emit tile_loaded event');
      assert.strictEqual(loadEvent.url, 'pmtiles://basemap.pmtiles/12/1206/1539');
      assert.ok(loadEvent.byteLength > 0, 'Loaded vector tile must contain non-zero bytes');
      assert.ok(res?.data?.byteLength > 0, 'Resolved promise must return tile data');
    });

    it('dispatches tile_error event when tile fetch fails (Promise / AbortController mode)', async () => {
      const events: TileEvent[] = [];
      setActiveTileTracker((e) => events.push(e));

      const protocol = getGlobalPMTilesProtocol();
      const controller = new AbortController();

      try {
        await protocol.tile({ url: 'pmtiles://nonexistent-archive/12/1206/1539' }, controller);
        assert.fail('Should have rejected');
      } catch {
        // Expected
      }

      setActiveTileTracker(null);

      const errEvent = events.find((e) => e.type === 'tile_error');
      assert.ok(errEvent, 'Must emit tile_error event on failure in Promise mode');
      assert.strictEqual(errEvent.url, 'pmtiles://nonexistent-archive/12/1206/1539');
      assert.ok(errEvent.error !== undefined);
    });

    it('dispatches tile_error event when tile fetch fails', async () => {
      const events: TileEvent[] = [];
      setActiveTileTracker((e) => events.push(e));

      const protocol = getGlobalPMTilesProtocol();

      // Request from non-existent source
      await new Promise<void>((resolve) => {
        protocol.tile({ url: 'pmtiles://nonexistent-archive/12/1206/1539' }, () => {
          resolve();
        });
      });

      setActiveTileTracker(null);

      const errEvent = events.find((e) => e.type === 'tile_error');
      assert.ok(errEvent, 'Must emit tile_error event on failure');
      assert.strictEqual(errEvent.url, 'pmtiles://nonexistent-archive/12/1206/1539');
      assert.ok(errEvent.error !== undefined);
    });

    it('negative case: non-tile request (type: json) is ignored by tile tracker', async () => {
      const events: TileEvent[] = [];
      setActiveTileTracker((e) => events.push(e));

      const protocol = getGlobalPMTilesProtocol();

      await new Promise<void>((resolve) => {
        protocol.tile({ url: 'pmtiles://basemap.pmtiles', type: 'json' }, () => {
          resolve();
        });
      });

      setActiveTileTracker(null);

      const tileEvents = events.filter((e) => e.type === 'tile_requested' || e.type === 'tile_loaded');
      assert.strictEqual(tileEvents.length, 0, 'TileJSON metadata requests must not be counted as vector tiles');
    });

    it('negative case: missing tile returning 0 bytes emits tile_loaded with byteLength 0', async () => {
      const events: TileEvent[] = [];
      setActiveTileTracker((e) => events.push(e));

      const protocol = getGlobalPMTilesProtocol();

      // Missing tile (Null Island z=14)
      await new Promise<void>((resolve) => {
        protocol.tile({ url: 'pmtiles://basemap.pmtiles/14/0/0' }, () => {
          resolve();
        });
      });

      setActiveTileTracker(null);

      const loadEvent = events.find((e) => e.type === 'tile_loaded');
      assert.ok(loadEvent, 'Missing tile still resolves cleanly as loaded');
      assert.strictEqual(loadEvent.byteLength, 0, 'Missing tile must have 0 byteLength');
    });
  });

  describe('End-to-end timeout diagnostic contract', () => {
    it('simulates on-device stall producing complete actionable diagnostic string', () => {
      const sm = new BasemapStateMachine('map-loading');
      sm.setStage('MAP_MOUNTING');

      // Telemetry representing Walsh iOS stall: 12 tiles requested, 0 loaded, 12 errored
      const diag: MountDiagnostic = {
        subStage: 'MOUNT_FIRST_TILE_REQUESTED',
        tilesRequested: 12,
        tilesLoaded: 0,
        tilesErrored: 12,
        firstTileError: 'NotReadableError: File could not be read from OPFS',
      };

      const userMessage = 'Map setup stalled (stage: MAP_MOUNTING). Please tap Retry.';
      const diagnosticDetails = formatMountDiagnostic(diag);

      sm.setError(userMessage, diagnosticDetails, 'MAP_MOUNTING');

      assert.strictEqual(sm.snapshot.state, 'map-error');
      assert.strictEqual(sm.snapshot.lastStage, 'MAP_MOUNTING');
      assert.strictEqual(sm.snapshot.errorMessage, userMessage);
      assert.ok(sm.snapshot.errorDetails?.includes('Stage: MAP_MOUNTING'));
      assert.ok(sm.snapshot.errorDetails?.includes('sub-stage: MOUNT_FIRST_TILE_REQUESTED'));
      assert.ok(sm.snapshot.errorDetails?.includes('tiles requested: 12, loaded: 0, errored: 12'));
      assert.ok(sm.snapshot.errorDetails?.includes('first error: NotReadableError: File could not be read from OPFS'));
    });

    it('negative case: healthy mount settles with ready and produces no diagnostic error', () => {
      const sm = new BasemapStateMachine('map-loading');
      sm.setStage('MAP_MOUNTING');
      sm.setMountSubStage('MOUNT_GLYPHS_LOADED');

      sm.setReady();

      assert.strictEqual(sm.snapshot.state, 'map-ready');
      assert.strictEqual(sm.snapshot.errorMessage, null);
      assert.strictEqual(sm.snapshot.errorDetails, null);
    });
  });
});
