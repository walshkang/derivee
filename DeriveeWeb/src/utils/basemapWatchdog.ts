import type { BasemapStage } from '../types/basemap.ts';

export interface WatchdogOptions {
  timeoutMs?: number;
  initialStage?: BasemapStage;
}

export type StallHandler = (stalledStage: BasemapStage) => void;

/**
 * Watchdog timer for basemap download and mounting pipelines.
 * Tracks forward progress (data chunks, worker stage messages, mounting steps).
 * If no progress is recorded within timeoutMs of silence, invokes onStall handler
 * with the last successfully reached stage.
 */
export class BasemapWatchdog {
  private timeoutMs: number;
  private currentStage: BasemapStage;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private onStallCallback: StallHandler | null = null;
  private isActive: boolean = false;

  constructor(options?: number | WatchdogOptions) {
    if (typeof options === 'number') {
      this.timeoutMs = options;
      this.currentStage = 'IDLE';
    } else {
      this.timeoutMs = options?.timeoutMs ?? 20_000;
      this.currentStage = options?.initialStage ?? 'IDLE';
    }
  }

  getStage(): BasemapStage {
    return this.currentStage;
  }

  get isRunning(): boolean {
    return this.isActive;
  }

  start(onStall: StallHandler): void {
    this.onStallCallback = onStall;
    this.isActive = true;
    this.armTimer();
  }

  recordProgress(stage?: BasemapStage): void {
    if (stage !== undefined) {
      this.currentStage = stage;
    }
    if (this.isActive) {
      this.armTimer();
    }
  }

  stop(): void {
    this.isActive = false;
    this.disarmTimer();
  }

  reset(initialStage: BasemapStage = 'IDLE'): void {
    this.stop();
    this.currentStage = initialStage;
    this.onStallCallback = null;
  }

  private armTimer(): void {
    this.disarmTimer();
    this.timer = setTimeout(() => {
      if (this.isActive && this.onStallCallback) {
        const stalledStage = this.currentStage;
        this.isActive = false;
        this.onStallCallback(stalledStage);
      }
    }, this.timeoutMs);
  }

  private disarmTimer(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }
}
