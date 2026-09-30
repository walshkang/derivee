export interface CityManifestItem {
  slug: string;
  name: string;
  pack_bytes: number;
  version: string | number;
  bbox: [number, number, number, number] | null;
}

export type CityPickerStatus =
  | 'loading'
  | 'load-error'
  | 'one_city'
  | 'multiple_cities'
  | 'switching';

export interface CitySwitchProgress {
  targetSlug: string;
  targetName: string;
  stage: string;
  percent?: number;
  message?: string;
}

export interface CityPickerState {
  status: CityPickerStatus;
  activeCitySlug: string;
  cities: CityManifestItem[];
  errorMessage: string | null;
  switchProgress: CitySwitchProgress | null;
}

export interface CityPickerDisplayOption {
  slug: string;
  displayName: string;
  formattedSize: string;
  fullLabel: string;
  isSelected: boolean;
}

export interface CityPickerDisplayModel {
  status: CityPickerStatus;
  title: string;
  subtitle: string;
  canRetry: boolean;
  canSelectCity: boolean;
  activeCityName: string;
  options: CityPickerDisplayOption[];
  progressMessage?: string;
}

export type CityPickerAction =
  | { type: 'FETCH_START' }
  | { type: 'FETCH_SUCCESS'; cities: CityManifestItem[] }
  | { type: 'FETCH_ERROR'; error: string }
  | { type: 'START_SWITCH'; targetSlug: string; targetName: string }
  | { type: 'SWITCH_PROGRESS'; stage: string; percent?: number; message?: string }
  | { type: 'SWITCH_SUCCESS'; newActiveSlug: string }
  | { type: 'SWITCH_ERROR'; error: string }
  | { type: 'RETRY' };
