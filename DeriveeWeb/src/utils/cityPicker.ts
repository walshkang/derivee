import type {
  CityManifestItem,
  CityPickerState,
  CityPickerDisplayModel,
  CityPickerDisplayOption,
  CityPickerAction,
} from '../types/cityPicker';

/**
 * Formats byte counts into clean human-readable strings (e.g. "28.3 MB", "9.4 MB", "500 KB").
 */
export function formatCityPackSize(bytes: number | null | undefined): string {
  if (bytes === null || bytes === undefined || isNaN(bytes)) {
    return 'Size unknown';
  }
  if (bytes < 0) {
    return 'Size unknown';
  }
  if (bytes === 0) {
    return '0 MB';
  }

  const ONE_KB = 1024;
  const ONE_MB = 1024 * 1024;
  const ONE_GB = 1024 * 1024 * 1024;

  if (bytes >= ONE_GB) {
    return `${(bytes / ONE_GB).toFixed(1)} GB`;
  }
  if (bytes >= ONE_MB) {
    return `${(bytes / ONE_MB).toFixed(1)} MB`;
  }
  if (bytes >= ONE_KB) {
    return `${Math.round(bytes / ONE_KB)} KB`;
  }
  return `${bytes} B`;
}

/**
 * Parses remote cities manifest JSON into normalized CityManifestItem array.
 * Supports both direct array format [{slug, name, pack_bytes, version, bbox}]
 * and Go pack_builder CitiesManifest format {version, cities: [{slug, displayName, compressedSizeBytes, ...}]}.
 */
export function parseCitiesManifest(raw: unknown): CityManifestItem[] {
  if (!raw || typeof raw !== 'object') {
    return [];
  }

  let entries: unknown[] = [];
  if (Array.isArray(raw)) {
    entries = raw;
  } else if ('cities' in raw && Array.isArray((raw as any).cities)) {
    entries = (raw as any).cities;
  } else {
    return [];
  }

  const result: CityManifestItem[] = [];

  for (const item of entries) {
    if (!item || typeof item !== 'object') continue;
    const obj = item as Record<string, any>;

    const slug = typeof obj.slug === 'string' ? obj.slug.trim() : '';
    if (!slug) continue;

    const rawName = obj.name || obj.displayName || '';
    const name = typeof rawName === 'string' && rawName.trim().length > 0
      ? rawName.trim()
      : slug.toUpperCase();

    const rawBytes = obj.pack_bytes ?? obj.compressedSizeBytes ?? 0;
    const pack_bytes = typeof rawBytes === 'number' && !isNaN(rawBytes) && rawBytes >= 0
      ? rawBytes
      : 0;

    const version = obj.version !== undefined ? obj.version : '1.0.0';

    let bbox: [number, number, number, number] | null = null;
    if (Array.isArray(obj.bbox) && obj.bbox.length === 4) {
      const validNumbers = obj.bbox.every((n: any) => typeof n === 'number' && !isNaN(n));
      if (validNumbers) {
        bbox = [obj.bbox[0], obj.bbox[1], obj.bbox[2], obj.bbox[3]];
      }
    } else if (obj.bounds && typeof obj.bounds === 'object') {
      const b = obj.bounds;
      const minLon = b.minLongitude ?? b.minLon;
      const minLat = b.minLatitude ?? b.minLat;
      const maxLon = b.maxLongitude ?? b.maxLon;
      const maxLat = b.maxLatitude ?? b.maxLat;
      if (
        typeof minLon === 'number' &&
        typeof minLat === 'number' &&
        typeof maxLon === 'number' &&
        typeof maxLat === 'number'
      ) {
        bbox = [minLon, minLat, maxLon, maxLat];
      }
    }

    result.push({
      slug,
      name,
      pack_bytes,
      version,
      bbox,
    });
  }

  return result;
}

/**
 * Pure display model function mapping internal CityPickerState to user-facing copy.
 * Guarantees zero internal IDs, file extensions, or technical error codes in UI strings (Rule 12).
 */
export function getCityPickerDisplayModel(state: CityPickerState): CityPickerDisplayModel {
  const activeEntry = state.cities.find((c) => c.slug === state.activeCitySlug);
  const activeCityName = activeEntry?.name
    || (state.activeCitySlug === 'nyc' ? 'New York City' : 'Active City');

  const options: CityPickerDisplayOption[] = state.cities.map((city) => {
    const formattedSize = formatCityPackSize(city.pack_bytes);
    return {
      slug: city.slug,
      displayName: city.name,
      formattedSize,
      fullLabel: `${city.name} (${formattedSize})`,
      isSelected: city.slug === state.activeCitySlug,
    };
  });

  switch (state.status) {
    case 'loading':
      return {
        status: 'loading',
        title: 'Available Metros',
        subtitle: 'Loading available cities...',
        canRetry: false,
        canSelectCity: false,
        activeCityName,
        options,
      };

    case 'load-error':
      return {
        status: 'load-error',
        title: 'Available Metros',
        subtitle: 'Unable to load available cities',
        canRetry: true,
        canSelectCity: false,
        activeCityName,
        options,
      };

    case 'one_city':
      return {
        status: 'one_city',
        title: 'Active Metro',
        subtitle: '1 metro available',
        canRetry: false,
        canSelectCity: false,
        activeCityName,
        options,
      };

    case 'multiple_cities':
      return {
        status: 'multiple_cities',
        title: 'Select Metro',
        subtitle: `${state.cities.length} metros available`,
        canRetry: false,
        canSelectCity: true,
        activeCityName,
        options,
      };

    case 'switching': {
      const targetName = state.switchProgress?.targetName || 'new metro area';
      const stage = state.switchProgress?.stage;
      const percent = state.switchProgress?.percent;

      let progressMessage = `Switching to ${targetName}...`;
      if (stage === 'downloading') {
        progressMessage = percent !== undefined && percent > 0
          ? `Downloading transit pack (${Math.round(percent)}%)...`
          : 'Downloading transit pack...';
      } else if (stage === 'decompressing') {
        progressMessage = 'Decompressing transit pack...';
      } else if (stage === 'writing') {
        progressMessage = 'Saving offline data to device...';
      } else if (stage === 'verifying') {
        progressMessage = 'Verifying transit pack...';
      } else if (stage === 'hydrating') {
        progressMessage = 'Starting routing engine...';
      }

      return {
        status: 'switching',
        title: 'Switching Metro',
        subtitle: `Switching to ${targetName}...`,
        canRetry: false,
        canSelectCity: false,
        activeCityName,
        options,
        progressMessage,
      };
    }
  }
}

/**
 * Pure state reducer for city picker state transitions.
 */
export function reduceCityPickerState(
  state: CityPickerState,
  action: CityPickerAction
): CityPickerState {
  switch (action.type) {
    case 'FETCH_START':
      return {
        ...state,
        status: 'loading',
        errorMessage: null,
      };

    case 'FETCH_SUCCESS': {
      const count = action.cities.length;
      const status = count > 1 ? 'multiple_cities' : 'one_city';
      return {
        ...state,
        status,
        cities: action.cities,
        errorMessage: null,
      };
    }

    case 'FETCH_ERROR':
      return {
        ...state,
        status: 'load-error',
        errorMessage: 'Unable to load available cities',
      };

    case 'START_SWITCH':
      if (state.status === 'switching') {
        return state; // Guard against concurrent switches
      }
      return {
        ...state,
        status: 'switching',
        errorMessage: null,
        switchProgress: {
          targetSlug: action.targetSlug,
          targetName: action.targetName,
          stage: 'downloading',
          percent: 0,
        },
      };

    case 'SWITCH_PROGRESS':
      if (state.status !== 'switching' || !state.switchProgress) {
        return state;
      }
      return {
        ...state,
        switchProgress: {
          ...state.switchProgress,
          stage: action.stage,
          percent: action.percent,
          message: action.message,
        },
      };

    case 'SWITCH_SUCCESS': {
      const count = state.cities.length;
      const status = count > 1 ? 'multiple_cities' : 'one_city';
      return {
        ...state,
        status,
        activeCitySlug: action.newActiveSlug,
        switchProgress: null,
        errorMessage: null,
      };
    }

    case 'SWITCH_ERROR':
      return {
        ...state,
        status: 'load-error',
        switchProgress: null,
        errorMessage: 'Unable to switch metro area',
      };

    case 'RETRY':
      return {
        ...state,
        status: 'loading',
        errorMessage: null,
      };

    default:
      return state;
  }
}

/**
 * Fetches the remote /api/cities endpoint with timeout and credentials.
 */
export async function fetchCitiesManifest(
  url: string = '/api/cities',
  timeoutMs: number = 8000
): Promise<CityManifestItem[]> {
  const controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
  const timer = controller ? setTimeout(() => controller.abort(), timeoutMs) : null;

  try {
    const res = await fetch(url, {
      credentials: 'include',
      headers: {
        Accept: 'application/json',
      },
      signal: controller ? controller.signal : undefined,
    });

    if (!res.ok) {
      throw new Error(`Failed to load cities: HTTP ${res.status}`);
    }

    const data = await res.json();
    return parseCitiesManifest(data);
  } finally {
    if (timer) clearTimeout(timer);
  }
}
