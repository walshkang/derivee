export type MapState = 'map-loading' | 'map-ready' | 'map-error' | 'map-cached';

export type MountSubStage =
  | 'MOUNT_STYLE_LOADING'
  | 'MOUNT_STYLE_PARSED'
  | 'MOUNT_FIRST_TILE_REQUESTED'
  | 'MOUNT_FIRST_TILE_LOADED'
  | 'MOUNT_GLYPHS_LOADED';

export interface MountDiagnostic {
  subStage: MountSubStage;
  tilesRequested: number;
  tilesLoaded: number;
  tilesErrored: number;
  firstTileError?: string | null;
}

export type BasemapStage =
  | 'IDLE'
  | 'STARTING_DOWNLOAD'
  | 'DOWNLOADING'
  | 'DOWNLOAD_COMPLETE'
  | 'CLOSING_FILE'
  | 'VERIFYING'
  | 'WORKER_READY'
  | 'RELEASING_LOCK'
  | 'READING_STORAGE'
  | 'INITIALIZING_MAP'
  | 'MAP_MOUNTING'
  | 'MAP_READY'
  | MountSubStage;

export type MainToBasemapWorkerMessage = {
  type: 'START_INSTALL';
  slug?: string;
  url?: string;
};

export type BasemapWorkerToMainMessage =
  | {
      type: 'STAGE';
      stage: BasemapStage;
    }
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
      stage?: BasemapStage;
      details?: string;
    };
