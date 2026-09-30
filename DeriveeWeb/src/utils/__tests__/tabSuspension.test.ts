import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  TabVisibilityTracker,
  WakeLockManager,
  RoutingQueryWatchdog,
  PackInstallWatchdog,
} from '../tabSuspension.ts';

describe('Background / Tab-Suspend Recovery & Watchdogs', () => {
  describe('TabVisibilityTracker', () => {
    it('dispatches onResume with suspendedDurationMs when document becomes visible', () => {
      let visibilityState = 'visible';
      const listeners = new Map<string, () => void>();

      const mockDoc = {
        get visibilityState() {
          return visibilityState;
        },
        addEventListener: (event: string, cb: () => void) => {
          listeners.set(event, cb);
        },
        removeEventListener: (event: string) => {
          listeners.delete(event);
        },
      } as unknown as Document;

      const tracker = new TabVisibilityTracker(mockDoc);
      tracker.start();

      let resumeDetail: { wasHidden: boolean; suspendedDurationMs: number } | null = null;
      tracker.onResume((detail) => {
        resumeDetail = detail;
      });

      // Simulate tab backgrounding
      visibilityState = 'hidden';
      listeners.get('visibilitychange')?.();

      assert.strictEqual(tracker.isVisible, false);

      // Simulate tab resuming
      visibilityState = 'visible';
      listeners.get('visibilitychange')?.();

      assert.strictEqual(tracker.isVisible, true);
      assert.ok(resumeDetail !== null, 'onResume must have fired');
      assert.strictEqual((resumeDetail as any).wasHidden, true);
      assert.ok((resumeDetail as any).suspendedDurationMs >= 0);

      tracker.stop();
    });

    it('handles undefined document gracefully without throwing (negative case)', () => {
      const tracker = new TabVisibilityTracker(undefined);
      assert.doesNotThrow(() => {
        tracker.start();
        tracker.stop();
        assert.strictEqual(tracker.isVisible, true);
        assert.strictEqual(tracker.getSuspendedDurationMs(), 0);
      });
    });
  });

  describe('WakeLockManager', () => {
    it('acquires wake lock and handles release callback correctly', async () => {
      let releaseListener: (() => void) | null = null;
      let stateChanges: boolean[] = [];

      const mockLock = {
        released: false,
        release: async () => {
          mockLock.released = true;
          releaseListener?.();
        },
        addEventListener: (event: string, cb: () => void) => {
          if (event === 'release') releaseListener = cb;
        },
      };

      const mockNav = {
        wakeLock: {
          request: async () => mockLock,
        },
      } as unknown as Navigator;

      const mockDoc = {
        visibilityState: 'visible',
        addEventListener: () => {},
        removeEventListener: () => {},
      } as unknown as Document;

      const manager = new WakeLockManager({
        navigatorObj: mockNav,
        documentObj: mockDoc,
        onStateChange: (active) => stateChanges.push(active),
      });

      const acquired = await manager.request();
      assert.strictEqual(acquired, true);
      assert.strictEqual(manager.isActive, true);
      assert.deepStrictEqual(stateChanges, [true]);

      // Simulate browser OS auto-releasing the lock on tab suspend
      await mockLock.release();
      assert.strictEqual(manager.isActive, false);
      assert.deepStrictEqual(stateChanges, [true, false]);

      manager.destroy();
    });

    it('does not acquire wake lock when document is hidden (negative case)', async () => {
      const mockNav = {
        wakeLock: {
          request: async () => {
            throw new Error('Should not be requested when hidden');
          },
        },
      } as unknown as Navigator;

      const mockDoc = {
        visibilityState: 'hidden',
        addEventListener: () => {},
        removeEventListener: () => {},
      } as unknown as Document;

      const manager = new WakeLockManager({
        navigatorObj: mockNav,
        documentObj: mockDoc,
      });

      const acquired = await manager.request();
      assert.strictEqual(acquired, false);
      assert.strictEqual(manager.isActive, false);

      manager.destroy();
    });

    it('automatically re-acquires lock when tab becomes visible if lock was requested', async () => {
      let docVisChangeCb: (() => void) | undefined = undefined;
      let docVisState = 'hidden';
      let requestCount = 0;

      const mockLock = {
        released: false,
        release: async () => { mockLock.released = true; },
        addEventListener: () => {},
      };

      const mockNav = {
        wakeLock: {
          request: async () => {
            requestCount++;
            return mockLock;
          },
        },
      } as unknown as Navigator;

      const mockDoc = {
        get visibilityState() {
          return docVisState;
        },
        addEventListener: (event: string, cb: () => void) => {
          if (event === 'visibilitychange') docVisChangeCb = cb;
        },
        removeEventListener: () => {},
      } as unknown as Document;

      const manager = new WakeLockManager({
        navigatorObj: mockNav,
        documentObj: mockDoc,
      });

      // Request while hidden -> acquisition deferred
      await manager.request();
      assert.strictEqual(requestCount, 0);

      // Tab transitions to visible -> triggers re-acquisition
      docVisState = 'visible';
      if (docVisChangeCb) {
        (docVisChangeCb as () => void)();
      }

      // Give microtask tick to settle
      await Promise.resolve();
      assert.strictEqual(requestCount, 1);
      assert.strictEqual(manager.isActive, true);

      manager.destroy();
    });
  });

  describe('RoutingQueryWatchdog', () => {
    it('triggers timeout callback when routing query exceeds timeout', async () => {
      let timeoutMessage: string | null = null;
      const watchdog = new RoutingQueryWatchdog(30, (msg) => {
        timeoutMessage = msg;
      });

      watchdog.start();
      assert.strictEqual(watchdog.isRunning, true);

      await new Promise((r) => setTimeout(r, 60));

      assert.strictEqual(watchdog.isRunning, false);
      assert.strictEqual(timeoutMessage, 'Route calculation timed out. Please try again.');
    });

    it('does not fire when query settles before timeout (negative case)', async () => {
      let timeoutFired = false;
      const watchdog = new RoutingQueryWatchdog(50, () => {
        timeoutFired = true;
      });

      watchdog.start();
      // Query settles immediately (e.g. 5ms)
      await new Promise((r) => setTimeout(r, 10));
      watchdog.stop();
      assert.strictEqual(watchdog.isRunning, false);

      await new Promise((r) => setTimeout(r, 60));
      assert.strictEqual(timeoutFired, false, 'Watchdog must not fire after being stopped');
    });

    it('fires gracefully upon resume if query was in flight during background suspension', () => {
      let message: string | null = null;
      const watchdog = new RoutingQueryWatchdog(10_000, (msg) => {
        message = msg;
      });

      watchdog.start();
      // App was suspended for 3,000ms
      watchdog.handleResume(3_000);

      assert.strictEqual(watchdog.isRunning, false);
      const strMsg = message as string | null;
      assert.ok(
        strMsg?.includes('Routing was interrupted when the app was backgrounded'),
        `Expected interrupted message, got: ${message}`
      );
    });

    it('does not fire upon resume if no query was running (negative case)', () => {
      let message: string | null = null;
      const watchdog = new RoutingQueryWatchdog(10_000, (msg) => {
        message = msg;
      });

      // No start() called
      watchdog.handleResume(5_000);
      assert.strictEqual(message, null);
    });
  });

  describe('PackInstallWatchdog', () => {
    it('triggers stall callback when progress halts past timeout', async () => {
      let stallDiagnostic: string | null = null;
      const watchdog = new PackInstallWatchdog(30, (diagnostic) => {
        stallDiagnostic = diagnostic;
      });

      watchdog.start();
      assert.strictEqual(watchdog.isRunning, true);

      // Do not record any progress
      await new Promise((r) => setTimeout(r, 60));

      assert.strictEqual(watchdog.isRunning, false);
      const strDiag = stallDiagnostic as string | null;
      assert.ok(
        strDiag?.includes('stalled with no network progress'),
        `Expected stall message, got: ${stallDiagnostic}`
      );
    });

    it('does not fire while progress is continually recorded', async () => {
      let stallFired = false;
      const watchdog = new PackInstallWatchdog(40, () => {
        stallFired = true;
      });

      watchdog.start();
      // Record progress every 15ms
      for (let i = 0; i < 4; i++) {
        await new Promise((r) => setTimeout(r, 15));
        watchdog.recordProgress();
      }

      watchdog.stop();
      assert.strictEqual(stallFired, false);
    });

    it('diagnoses interruption when app resumes after being suspended past stall limit', () => {
      let diagnostic: string | null = null;
      const watchdog = new PackInstallWatchdog(20_000, (msg) => {
        diagnostic = msg;
      });

      watchdog.start();
      // Tab suspended for 25s
      watchdog.handleResume(25_000);

      assert.strictEqual(watchdog.isRunning, false);
      const strDiag = diagnostic as string | null;
      assert.ok(
        strDiag?.includes('interrupted while the app was backgrounded'),
        `Expected background interruption diagnostic, got: ${diagnostic}`
      );
    });

    it('does not fire after stop() is called (negative case)', async () => {
      let stallFired = false;
      const watchdog = new PackInstallWatchdog(20, () => {
        stallFired = true;
      });

      watchdog.start();
      watchdog.stop();

      await new Promise((r) => setTimeout(r, 40));
      assert.strictEqual(stallFired, false);
    });
  });
});
