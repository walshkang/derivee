import { describe, it } from 'node:test';
import assert from 'node:assert';
import { BasemapStateMachine, type BasemapStateSnapshot } from '../basemapStateMachine.ts';

describe('Basemap Download State Machine Tests', () => {
  describe('Rule 11 States & Transitions: Happy path (idle → downloading → ready)', () => {
    it('initializes in map-loading state with zero progress', () => {
      const sm = new BasemapStateMachine();
      const snap = sm.snapshot;

      assert.strictEqual(snap.state, 'map-loading');
      assert.strictEqual(snap.percent, 0);
      assert.strictEqual(snap.loadedBytes, 0);
      assert.strictEqual(snap.errorMessage, null);
    });

    it('transitions idle/initial → downloading → ready', () => {
      const sm = new BasemapStateMachine();
      const snapshots: BasemapStateSnapshot[] = [];
      sm.subscribe((snap) => snapshots.push(snap));

      // Initial snapshot delivered immediately upon subscription
      assert.strictEqual(snapshots.length, 1);
      assert.strictEqual(snapshots[0].state, 'map-loading');

      // Start downloading
      const TOTAL_SIZE = 24991495;
      sm.startDownloading(TOTAL_SIZE);
      assert.strictEqual(sm.snapshot.state, 'map-loading');
      assert.strictEqual(sm.snapshot.totalBytes, TOTAL_SIZE);
      assert.strictEqual(sm.snapshot.percent, 0);

      // Progress updates
      sm.updateProgress(12495747, TOTAL_SIZE, 50);
      assert.strictEqual(sm.snapshot.state, 'map-loading');
      assert.strictEqual(sm.snapshot.percent, 50);
      assert.strictEqual(sm.snapshot.loadedBytes, 12495747);

      // Complete download / ready
      sm.setReady();
      assert.strictEqual(sm.snapshot.state, 'map-ready');
      assert.strictEqual(sm.snapshot.percent, 100);
      assert.strictEqual(sm.snapshot.errorMessage, null);

      // Verify sequence of observed states
      const stateSequence = snapshots.map((s) => s.state);
      assert.deepStrictEqual(stateSequence, [
        'map-loading', // on subscribe
        'map-loading', // startDownloading
        'map-loading', // updateProgress
        'map-ready',   // setReady
      ]);
    });

    it('clamps progress percent between 0 and 100', () => {
      const sm = new BasemapStateMachine();
      sm.startDownloading(1000);

      sm.updateProgress(-50, 1000, -5);
      assert.strictEqual(sm.snapshot.percent, 0);

      sm.updateProgress(1500, 1000, 150);
      assert.strictEqual(sm.snapshot.percent, 100);
    });
  });

  describe('Rule 11 States & Transitions: Failure & Retry (failure → error → retry → ready)', () => {
    it('transitions from downloading to error, then retries back to downloading and completes ready', () => {
      const sm = new BasemapStateMachine();
      const snapshots: BasemapStateSnapshot[] = [];
      sm.subscribe((snap) => snapshots.push(snap));

      const TOTAL_SIZE = 24991495;
      sm.startDownloading(TOTAL_SIZE);
      sm.updateProgress(5000000, TOTAL_SIZE, 20);

      // Failure occurs
      const errorMsg = 'Download was interrupted. Please check your connection and try again.';
      sm.setError(errorMsg);

      assert.strictEqual(sm.snapshot.state, 'map-error');
      assert.strictEqual(sm.snapshot.errorMessage, errorMsg);

      // Subsequent progress updates during error state should be ignored
      sm.updateProgress(6000000, TOTAL_SIZE, 24);
      assert.strictEqual(sm.snapshot.state, 'map-error');
      assert.strictEqual(sm.snapshot.errorMessage, errorMsg);

      // User clicks Retry
      sm.retry(TOTAL_SIZE);
      assert.strictEqual(sm.snapshot.state, 'map-loading');
      assert.strictEqual(sm.snapshot.percent, 0);
      assert.strictEqual(sm.snapshot.loadedBytes, 0);
      assert.strictEqual(sm.snapshot.errorMessage, null);

      // Retry succeeds
      sm.updateProgress(24991495, TOTAL_SIZE, 100);
      sm.setReady();
      assert.strictEqual(sm.snapshot.state, 'map-ready');
      assert.strictEqual(sm.snapshot.percent, 100);
      assert.strictEqual(sm.snapshot.errorMessage, null);

      // Verify sequence of states
      const stateSequence = snapshots.map((s) => s.state);
      assert.deepStrictEqual(stateSequence, [
        'map-loading', // on subscribe
        'map-loading', // startDownloading
        'map-loading', // updateProgress 20%
        'map-error',   // setError
        'map-loading', // retry
        'map-loading', // updateProgress 100%
        'map-ready',   // setReady
      ]);
    });
  });

  describe('Rule 11 States & Transitions: Returning visit (map-cached)', () => {
    it('sets map-cached instantly with zero network and no download flash', () => {
      const sm = new BasemapStateMachine('map-loading');
      const snapshots: BasemapStateSnapshot[] = [];
      sm.subscribe((snap) => snapshots.push(snap));

      // Already in OPFS -> cached
      sm.setCached();
      assert.strictEqual(sm.snapshot.state, 'map-cached');
      assert.strictEqual(sm.snapshot.errorMessage, null);

      // Map loads from OPFS
      sm.setReady();
      assert.strictEqual(sm.snapshot.state, 'map-ready');

      const stateSequence = snapshots.map((s) => s.state);
      assert.deepStrictEqual(stateSequence, [
        'map-loading', // initial
        'map-cached',  // setCached
        'map-ready',   // setReady
      ]);
    });
  });

  describe('Subscription lifecycle and unsubscribe', () => {
    it('stops notifying subscriber after unsubscription', () => {
      const sm = new BasemapStateMachine();
      let callCount = 0;
      const unsubscribe = sm.subscribe(() => {
        callCount++;
      });

      assert.strictEqual(callCount, 1); // initial notification
      sm.startDownloading(100);
      assert.strictEqual(callCount, 2);

      unsubscribe();
      sm.updateProgress(50, 100, 50);
      sm.setReady();
      assert.strictEqual(callCount, 2, 'No further notifications after unsubscription');
    });
  });

  describe('Stage Telemetry Tracking', () => {
    it('tracks stage advances and includes lastStage in snapshot', () => {
      const sm = new BasemapStateMachine();
      assert.strictEqual(sm.snapshot.lastStage, null);

      sm.startDownloading(1000);
      assert.strictEqual(sm.snapshot.lastStage, 'STARTING_DOWNLOAD');

      sm.setStage('DOWNLOADING');
      assert.strictEqual(sm.snapshot.lastStage, 'DOWNLOADING');

      sm.setStage('DOWNLOAD_COMPLETE');
      assert.strictEqual(sm.snapshot.lastStage, 'DOWNLOAD_COMPLETE');

      sm.setError('Stalled', 'Diagnostic details', 'CLOSING_FILE');
      assert.strictEqual(sm.snapshot.state, 'map-error');
      assert.strictEqual(sm.snapshot.lastStage, 'CLOSING_FILE');
      assert.strictEqual(sm.snapshot.errorDetails, 'Diagnostic details');
    });

    it('sets lastStage to READING_STORAGE on cached visit and MAP_READY on ready', () => {
      const sm = new BasemapStateMachine();
      sm.setCached();
      assert.strictEqual(sm.snapshot.lastStage, 'READING_STORAGE');

      sm.setReady();
      assert.strictEqual(sm.snapshot.lastStage, 'MAP_READY');
    });
  });
});
