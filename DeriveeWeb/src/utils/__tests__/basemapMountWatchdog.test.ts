import { describe, it } from 'node:test';
import assert from 'node:assert';
import { withTimeout } from '../withTimeout.ts';
import { BasemapStateMachine } from '../basemapStateMachine.ts';
import { BasemapWatchdog } from '../basemapWatchdog.ts';

describe('Basemap Main Thread Mount & Watchdog Regression Tests', () => {
  it('Candidate 5: releaseWakeLock() never settles -> times out safely without blocking or hanging', async () => {
    let released = false;
    const mockWakeLockSentinel = {
      release: () => new Promise<void>(() => {}), // hangs forever
    };

    let wakeLockSentinel: { release: () => Promise<void> } | null = mockWakeLockSentinel;

    const releaseWakeLock = async () => {
      if (wakeLockSentinel) {
        const lock = wakeLockSentinel;
        wakeLockSentinel = null;
        try {
          await withTimeout(lock.release(), 25, 'Release wake lock timed out');
        } catch {
          // Safe to ignore
        }
        released = true;
      }
    };

    await releaseWakeLock();

    assert.strictEqual(wakeLockSentinel, null, 'Wake lock sentinel must be nulled out');
    assert.strictEqual(released, true, 'releaseWakeLock must settle and not hang forever');
  });

  it('Candidate 6: getBasemapFile() never settles -> times out and transitions state machine to map-error at READING_STORAGE', async () => {
    const sm = new BasemapStateMachine('map-loading');
    const watchdog = new BasemapWatchdog({ timeoutMs: 100, initialStage: 'READING_STORAGE' });

    const hangGetBasemapFile = () => new Promise<File | null>(() => {});

    try {
      await withTimeout(hangGetBasemapFile(), 25, 'Reading offline map file from storage timed out.');
      assert.fail('Should have timed out');
    } catch (err: any) {
      watchdog.stop();
      sm.setError(
        'Unable to load offline map from storage. Please retry download.',
        `Stage: READING_STORAGE\nDiagnostic: ${err.message}`,
        'READING_STORAGE'
      );
    }

    assert.strictEqual(sm.snapshot.state, 'map-error');
    assert.strictEqual(sm.snapshot.lastStage, 'READING_STORAGE');
    assert.ok(sm.snapshot.errorDetails?.includes('READING_STORAGE'));
    assert.ok(sm.snapshot.errorDetails?.includes('timed out'));
  });

  it('Candidate 7 & 8: map load event never fires (tile read or glyph hang) -> mount timeout triggers map-error at MAP_MOUNTING', async () => {
    const sm = new BasemapStateMachine('map-loading');
    let timedOut = false;

    // Simulate initOfflineMap timeout behavior
    const mountTimeoutMs = 30;
    let isSettled = false;

    const timer = setTimeout(() => {
      if (!isSettled) {
        isSettled = true;
        timedOut = true;
        sm.setError(
          'Map setup stalled (stage: MAP_MOUNTING). Please tap Retry.',
          'Stage: MAP_MOUNTING\nDiagnostic: MapLibre failed to load style and tiles within 20s.',
          'MAP_MOUNTING'
        );
      }
    }, mountTimeoutMs);

    // Wait for timeout to fire (50ms > 30ms)
    await new Promise((r) => setTimeout(r, 50));

    assert.strictEqual(timedOut, true, 'Mount timeout must fire when load event never fires');
    assert.strictEqual(sm.snapshot.state, 'map-error');
    assert.strictEqual(sm.snapshot.lastStage, 'MAP_MOUNTING');
    assert.ok(sm.snapshot.errorMessage?.includes('MAP_MOUNTING'));
    assert.ok(sm.snapshot.errorDetails?.includes('MAP_MOUNTING'));

    clearTimeout(timer);
  });

  it('Negative case: map load event fires normally -> sets ready and cancels mount timeout', async () => {
    const sm = new BasemapStateMachine('map-loading');
    let timedOut = false;

    const mountTimeoutMs = 50;
    let isSettled = false;

    let timer: ReturnType<typeof setTimeout> | undefined = setTimeout(() => {
      if (!isSettled) {
        isSettled = true;
        timedOut = true;
        sm.setError('Map setup stalled (stage: MAP_MOUNTING). Please tap Retry.');
      }
    }, mountTimeoutMs);

    // Simulate map load firing after 15ms (healthy)
    await new Promise((r) => setTimeout(r, 15));
    if (!isSettled) {
      isSettled = true;
      if (timer !== undefined) clearTimeout(timer);
      sm.setReady();
    }

    // Wait beyond the original timeout
    await new Promise((r) => setTimeout(r, 50));

    assert.strictEqual(timedOut, false, 'Mount timeout must not fire if load event settled first');
    assert.strictEqual(sm.snapshot.state, 'map-ready');
    assert.strictEqual(sm.snapshot.lastStage, 'MAP_READY');
  });

  it('End-to-end watchdog stall detection: silence after 100% triggers map-error naming stage', async () => {
    const sm = new BasemapStateMachine('map-loading');
    const watchdog = new BasemapWatchdog({ timeoutMs: 30, initialStage: 'DOWNLOADING' });

    watchdog.start((stalledStage) => {
      sm.setError(
        `Map setup stalled (stage: ${stalledStage}). Please tap Retry.`,
        `Stage: ${stalledStage}\nDiagnostic: Operation timed out after 30ms of inactivity with no forward progress.`,
        stalledStage
      );
    });

    // 100% progress received
    sm.updateProgress(24991495, 24991495, 100);
    watchdog.recordProgress('DOWNLOAD_COMPLETE');

    // Simulate complete silence afterwards (Candidate 1 or 2 hang)
    await new Promise((r) => setTimeout(r, 50));

    assert.strictEqual(sm.snapshot.state, 'map-error');
    assert.strictEqual(sm.snapshot.lastStage, 'DOWNLOAD_COMPLETE');
    assert.ok(sm.snapshot.errorMessage?.includes('DOWNLOAD_COMPLETE'));
    assert.ok(sm.snapshot.errorDetails?.includes('DOWNLOAD_COMPLETE'));

    // Retry resets everything cleanly
    watchdog.reset('STARTING_DOWNLOAD');
    sm.retry();

    assert.strictEqual(sm.snapshot.state, 'map-loading');
    assert.strictEqual(sm.snapshot.lastStage, 'STARTING_DOWNLOAD');
    assert.strictEqual(sm.snapshot.errorMessage, null);
    assert.strictEqual(watchdog.isRunning, false);
  });
});
