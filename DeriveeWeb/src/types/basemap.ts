export type MapState = 'map-loading' | 'map-ready' | 'map-error' | 'map-cached';

export type MainToBasemapWorkerMessage = {
  type: 'START_INSTALL';
  slug?: string;
  url?: string;
};

export type BasemapWorkerToMainMessage =
  | {
      type: 'PROGRESS';
      loadedBytes: number;
      totalBytes: number;
      percent: number;
    }
  | {
      type: 'READY';
      fileSize: number;
    }
  | {
      type: 'ERROR';
      message: string;
    };
