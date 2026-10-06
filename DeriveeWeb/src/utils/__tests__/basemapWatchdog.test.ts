import { describe, it } from 'node:test';
import assert from 'node:assert';
import { BasemapWatchdog } from '../basemapWatchdog.ts';
import type { BasemapStage } from '../../types/basemap.ts';

describe('BasemapWatchdog Tests', () => {
  it('fires stall callback naming the last completed stage when silence exceeds timeout', async () => {
    const watchdog = new BasemapWatchdog({ timeoutMs: 30, initialStage: 'DOWNLOADING' });
    let stalledStage: BasemapStage | null = null;

    watchdog.start((stage) => {
      stalledStage = stage;
    });

    assert.strictEqual(watchdog.isRunning, true);
    assert.strictEqual(watchdog.getStage(), 'DOWNLOADING');

    // Wait 50ms for watchdog to fire
    await new Promise((r) => setTimeout(r, 50));

    assert.strictEqual(stalledStage, 'DOWNLOADING');
    assert.strictEqual(watchdog.isRunning, false);
  });

  it('updates stage on progress and passes latest stage to stall callback', async () => {
    const watchdog = new BasemapWatchdog({ timeoutMs: 40, initialStage: 'STARTING_DOWNLOAD' });
    let stalledStage: BasemapStage | null = null;

    watchdog.start((stage) => {
      stalledStage = stage;
    });

    // Advance to DOWNLOADING, then DOWNLOAD_COMPLETE
    watchdog.recordProgress('DOWNLOADING');
    assert.strictEqual(watchdog.getStage(), 'DOWNLOADING');

    await new Promise((r) => setTimeout(r, 15));
    watchdog.recordProgress('DOWNLOAD_COMPLETE');
    assert.strictEqual(watchdog.getStage(), 'DOWNLOAD_COMPLETE');

    // Let silence exceed 40ms from the last progress
    await new Promise((r) => setTimeout(r, 55));

    assert.strictEqual(stalledStage, 'DOWNLOAD_COMPLETE');
  });

  it('negative case: healthy slow download with regular progress events never triggers watchdog', async () => {
    const watchdog = new BasemapWatchdog({ timeoutMs: 35, initialStage: 'DOWNLOADING' });
    let fired = false;

    watchdog.start(() => {
      fired = true;
    });

    // Simulate 4 progress heartbeats spaced 15ms apart (total elapsed 60ms > timeoutMs 35ms)
    for (let i = 0; i < 4; i++) {
      await new Promise((r) => setTimeout(r, 15));
      watchdog.recordProgress(); // Keeps heartbeat alive
      assert.strictEqual(fired, false, `Watchdog must not fire during active progress at step ${i}`);
    }

    watchdog.stop();
    assert.strictEqual(fired, false, 'Watchdog must never fire on a healthy progressing download');
  });

  it('stop() prevents watchdog from firing', async () => {
    const watchdog = new BasemapWatchdog({ timeoutMs: 25, initialStage: 'MAP_MOUNTING' });
    let fired = false;

    watchdog.start(() => {
      fired = true;
    });

    watchdog.stop();
    assert.strictEqual(watchdog.isRunning, false);

    await new Promise((r) => setTimeout(r, 40));
    assert.strictEqual(fired, false, 'Stopped watchdog must not fire callback');
  });

  it('reset() halts active timer and restores stage to initial stage on retry', async () => {
    const watchdog = new BasemapWatchdog({ timeoutMs: 30, initialStage: 'DOWNLOADING' });
    let fired = false;

    watchdog.start(() => {
      fired = true;
    });

    watchdog.recordProgress('CLOSING_FILE');
    assert.strictEqual(watchdog.getStage(), 'CLOSING_FILE');

    // Reset simulating retry
    watchdog.reset('STARTING_DOWNLOAD');
    assert.strictEqual(watchdog.isRunning, false);
    assert.strictEqual(watchdog.getStage(), 'STARTING_DOWNLOAD');

    await new Promise((r) => setTimeout(r, 45));
    assert.strictEqual(fired, false, 'Reset watchdog must not fire old callback');
  });
});
