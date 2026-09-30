import type { CityPickerState } from '../types/cityPicker';
import { getCityPickerDisplayModel } from '../utils/cityPicker';

export interface CityPickerProps {
  state: CityPickerState;
  onSelectCity?: (slug: string) => void;
  onRetry?: () => void;
}

export function CityPicker({ state, onSelectCity, onRetry }: CityPickerProps) {
  const model = getCityPickerDisplayModel(state);

  return (
    <div class="city-picker-card" data-status={model.status}>
      <div class="city-picker-header">
        <span class="city-picker-title">{model.title}</span>
        <span class="city-picker-subtitle">{model.subtitle}</span>
      </div>

      {model.status === 'loading' && (
        <div class="city-picker-status-row city-picker-loading">
          <span class="engine-dot engine-dot-pulse" />
          <span class="city-picker-status-text">{model.subtitle}</span>
        </div>
      )}

      {model.status === 'load-error' && (
        <div class="city-picker-status-row city-picker-error">
          <span class="engine-dot engine-dot-red" />
          <span class="city-picker-status-text">{model.subtitle}</span>
          {model.canRetry && (
            <button
              type="button"
              class="city-picker-retry-btn"
              onClick={onRetry}
              aria-label="Retry loading available cities"
            >
              Retry
            </button>
          )}
        </div>
      )}

      {model.status === 'one_city' && (
        <div class="city-picker-status-row city-picker-single">
          <span class="city-pill-icon">📍</span>
          <span class="city-active-label">
            {model.options[0]?.fullLabel || model.activeCityName}
          </span>
        </div>
      )}

      {model.status === 'multiple_cities' && (
        <div class="city-picker-select-wrapper">
          <select
            class="city-picker-select"
            value={state.activeCitySlug}
            onChange={(e) => onSelectCity?.((e.target as HTMLSelectElement).value)}
            aria-label="Select Metro Area"
          >
            {model.options.map((opt) => (
              <option key={opt.slug} value={opt.slug}>
                {opt.fullLabel}
              </option>
            ))}
          </select>
        </div>
      )}

      {model.status === 'switching' && (
        <div class="city-picker-status-row city-picker-switching">
          <span class="engine-dot engine-dot-pulse" />
          <span class="city-picker-status-text">{model.progressMessage}</span>
        </div>
      )}
    </div>
  );
}
