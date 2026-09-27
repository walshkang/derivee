export interface PackFileEntry {
  name: string;
  size: number;
}

export interface CityConfig {
  version: number;
  slug: string;
  displayName: string;
  region: string;
  bounds?: {
    minLatitude: number;
    maxLatitude: number;
    minLongitude: number;
    maxLongitude: number;
  };
  center?: {
    latitude: number;
    longitude: number;
    defaultZoom: number;
  };
  routing?: {
    timetableBinFile: string;
    ultraCsrFile: string;
    walkGraphFile: string;
    maxWalkMinutes?: number;
    maxRounds?: number;
  };
  transit?: {
    agencyName?: string;
    attributions?: string[];
    scheduleValidity?: {
      startDate?: string;
      endDate?: string;
      seasonLabel?: string;
    };
  };
}

export interface InstalledPackState {
  isInstalled: boolean;
  slug: string;
  version: number;
  displayName: string;
  seasonLabel?: string;
  installedAt: string;
  totalBytes: number;
  files: PackFileEntry[];
}

export type InstallerStage = 'downloading' | 'decompressing' | 'writing' | 'verifying';

export type MainToWorkerMessage = {
  type: 'START_INSTALL';
  slug?: string;
  packUrl?: string;
};

export type WorkerToMainMessage =
  | {
      type: 'PROGRESS';
      stage: InstallerStage;
      loadedBytes?: number;
      totalBytes?: number;
      filesWritten?: number;
      totalFiles?: number;
      currentFile?: string;
      percent?: number;
      message?: string;
    }
  | {
      type: 'SUCCESS';
      packState: InstalledPackState;
    }
  | {
      type: 'ERROR';
      code?: number;
      message: string;
    };
