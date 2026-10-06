/**
 * Utilities for managing tab suspension, backgrounding, wake lock re-acquisition,
 * and graceful recovery for long-running network downloads and routing queries.
 */

export interface VisibilityChangeDetail {
  wasHidden: boolean;
  suspendedDurationMs: number;
}

/**
 * Tracks document visibility transitions and background suspension duration.
 */
export class TabVisibilityTracker {
  private lastHiddenTimestamp: number = 0;
  private lastVisibleTimestamp: number = Date.now();
  private listeners: Set<(detail: VisibilityChangeDetail) => void> = new Set();
  private isListening: boolean = false;
  private doc: Document | null;

  public get lastVisibleTime(): number {
    return this.lastVisibleTimestamp;
  }

  constructor(doc?: Document) {
    this.doc = doc ?? (typeof document !== 'undefined' ? document : null);
  }

  public start(): void {
    if (this.isListening || !this.doc) return;
    this.isListening = true;
    this.doc.addEventListener('visibilitychange', this.handleVisibilityChange);
  }

  public stop(): void {
    if (!this.isListening || !this.doc) return;
    this.isListening = false;
    this.doc.removeEventListener('visibilitychange', this.handleVisibilityChange);
    this.listeners.clear();
  }

  public onResume(callback: (detail: VisibilityChangeDetail) => void): () => void {
    this.listeners.add(callback);
    return () => {
      this.listeners.delete(callback);
    };
  }

  public get isVisible(): boolean {
    return this.doc?.visibilityState !== 'hidden';
  }

  public getSuspendedDurationMs(): number {
    if (this.lastHiddenTimestamp === 0) return 0;
    return Math.max(0, Date.now() - this.lastHiddenTimestamp);
  }

  private handleVisibilityChange = (): void => {
    if (!this.doc) return;

    if (this.doc.visibilityState === 'hidden') {
      this.lastHiddenTimestamp = Date.now();
    } else if (this.doc.visibilityState === 'visible') {
      const suspendedDurationMs = this.lastHiddenTimestamp > 0
        ? Date.now() - this.lastHiddenTimestamp
        : 0;
      this.lastVisibleTimestamp = Date.now();

      const detail: VisibilityChangeDetail = {
        wasHidden: this.lastHiddenTimestamp > 0,
        suspendedDurationMs,
      };

      for (const listener of this.listeners) {
        try {
          listener(detail);
        } catch {
          // Prevent listener exceptions from breaking dispatcher
        }
      }
    }
  };
}

/**
 * Screen Wake Lock manager with automatic re-acquisition upon visibility resume
 * and proper release tracking.
 */
export class WakeLockManager {
  private sentinel: { release: () => Promise<void>; released?: boolean } | null = null;
  private isRequested: boolean = false;
  private onStateChange?: (active: boolean) => void;
  private nav?: Navigator;
  private doc?: Document;
  private visibilityUnsub?: () => void;

  constructor(options?: {
    navigatorObj?: Navigator;
    documentObj?: Document;
    onStateChange?: (active: boolean) => void;
  }) {
    this.nav = options?.navigatorObj ?? (typeof navigator !== 'undefined' ? navigator : undefined);
    this.doc = options?.documentObj ?? (typeof document !== 'undefined' ? document : undefined);
    this.onStateChange = options?.onStateChange;

    if (this.doc) {
      const handleVisChange = () => {
        if (this.doc?.visibilityState === 'visible' && this.isRequested && !this.sentinel) {
          this.acquireInternal();
        }
      };
      this.doc.addEventListener('visibilitychange', handleVisChange);
      this.visibilityUnsub = () => {
        this.doc?.removeEventListener('visibilitychange', handleVisChange);
      };
    }
  }

  public async request(): Promise<boolean> {
    this.isRequested = true;
    return await this.acquireInternal();
  }

  public async release(): Promise<void> {
    this.isRequested = false;
    if (this.sentinel) {
      const lock = this.sentinel;
      this.sentinel = null;
      try {
        await lock.release();
      } catch {
        // Safe to ignore release errors
      }
    }
    this.notify(false);
  }

  public destroy(): void {
    this.release();
    this.visibilityUnsub?.();
  }

  public get isActive(): boolean {
    return this.sentinel !== null && !this.sentinel.released;
  }

  private async acquireInternal(): Promise<boolean> {
    if (!this.nav || !('wakeLock' in this.nav)) {
      return false;
    }
    if (this.doc?.visibilityState === 'hidden') {
      return false;
    }

    try {
      const navAny = this.nav as unknown as {
        wakeLock: {
          request: (type: 'screen') => Promise<{
            release: () => Promise<void>;
            released?: boolean;
            addEventListener?: (event: string, cb: () => void) => void;
          }>;
        };
      };
      const lock = await navAny.wakeLock.request('screen');
      this.sentinel = lock;
      this.notify(true);

      if (typeof lock.addEventListener === 'function') {
        lock.addEventListener('release', () => {
          if (this.sentinel === lock) {
            this.sentinel = null;
            this.notify(false);
          }
        });
      }
      return true;
    } catch {
      this.notify(false);
      return false;
    }
  }

  private notify(active: boolean): void {
    try {
      this.onStateChange?.(active);
    } catch {
      // Safe to ignore subscriber error
    }
  }
}

/**
 * Watchdog for transit routing queries.
 * Prevents UI from silently wedging if a worker query hangs or is suspended in the background.
 */
export class RoutingQueryWatchdog {
  private timer: ReturnType<typeof setTimeout> | null = null;
  private readonly timeoutMs: number;
  private onTimeout: (reason: string) => void;

  constructor(timeoutMs: number = 8_000, onTimeout: (reason: string) => void) {
    this.timeoutMs = timeoutMs;
    this.onTimeout = onTimeout;
  }

  public start(): void {
    this.stop();
    this.timer = setTimeout(() => {
      this.timer = null;
      this.onTimeout('Route calculation timed out. Please try again.');
    }, this.timeoutMs);
  }

  public stop(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }

  /**
   * Called when visibility changes back to visible.
   * If a routing query was backgrounded for more than threshold, immediately fail gracefully.
   */
  public handleResume(suspendedDurationMs: number): void {
    if (this.timer !== null && suspendedDurationMs >= 2_000) {
      this.stop();
      this.onTimeout('Routing was interrupted when the app was backgrounded. Please tap Route Trip again.');
    }
  }

  public get isRunning(): boolean {
    return this.timer !== null;
  }
}

/**
 * Stall watchdog for pack downloads and installations.
 * Monitors forward progress; triggers graceful recovery if execution stalls or tab suspend kills stream.
 */
export class PackInstallWatchdog {
  private timer: ReturnType<typeof setInterval> | null = null;
  private lastProgressTimestamp: number = 0;
  private readonly stallTimeoutMs: number;
  private onStall: (diagnostic: string) => void;

  constructor(stallTimeoutMs: number = 20_000, onStall: (diagnostic: string) => void) {
    this.stallTimeoutMs = stallTimeoutMs;
    this.onStall = onStall;
  }

  public start(): void {
    this.stop();
    this.lastProgressTimestamp = Date.now();
    const intervalMs = Math.min(1_000, Math.max(10, Math.floor(this.stallTimeoutMs / 2)));
    this.timer = setInterval(() => {
      const elapsed = Date.now() - this.lastProgressTimestamp;
      if (elapsed >= this.stallTimeoutMs) {
        this.stop();
        this.onStall('Download stalled with no network progress for 20s.');
      }
    }, intervalMs);
  }

  public recordProgress(): void {
    this.lastProgressTimestamp = Date.now();
  }

  public stop(): void {
    if (this.timer !== null) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  public handleResume(suspendedDurationMs: number): void {
    if (this.timer !== null) {
      const elapsed = Date.now() - this.lastProgressTimestamp;
      if (suspendedDurationMs >= this.stallTimeoutMs || elapsed >= this.stallTimeoutMs) {
        this.stop();
        this.onStall('Download was interrupted while the app was backgrounded. Please tap Download to resume.');
      }
    }
  }

  public get isRunning(): boolean {
    return this.timer !== null;
  }
}
