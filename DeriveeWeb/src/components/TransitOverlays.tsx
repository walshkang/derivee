import { useEffect, useState, useRef } from 'preact/hooks';
import { type Map, Popup, type MapMouseEvent, type MapGeoJSONFeature } from 'maplibre-gl';
import { getCityDirectory } from '../utils/opfs';
import { getTransitLayerDisplayState, type UIState } from '../utils/displayModel';
import type { StopItem } from '../types/routing';
import {
  TRANSIT_LINES_SOURCE_ID,
  TRANSIT_LINES_LAYER_ID,
  TRANSIT_STATIONS_SOURCE_ID,
  TRANSIT_STATIONS_LAYER_ID,
  buildStationGeoJSON,
  getTransitLinesLayerConfig,
  getTransitStationsLayerConfig,
  escapeHtml,
} from '../utils/transitOverlays';

interface TransitOverlaysProps {
  map: Map | null;
  slug?: string;
  isPackInstalled?: boolean;
  onSelectStation?: (station: { id: number; name: string }) => void;
}

export function TransitOverlays({
  map,
  slug = 'nyc',
  isPackInstalled,
  onSelectStation,
}: TransitOverlaysProps) {
  const [transitState, setTransitState] = useState<UIState>('ready');
  const [selectedStation, setSelectedStation] = useState<{ id: number; name: string } | null>(null);
  const popupRef = useRef<Popup | null>(null);

  useEffect(() => {
    if (!map || !isPackInstalled) return;

    let isCancelled = false;
    let clickHandler: ((e: MapMouseEvent & { features?: MapGeoJSONFeature[] }) => void) | null = null;
    let enterHandler: (() => void) | null = null;
    let leaveHandler: (() => void) | null = null;

    const loadOverlays = async () => {
      setTransitState('loading');
      try {
        const [linesGeojson, stopsData] = await Promise.all([
          (async () => {
            const dir = await getCityDirectory(slug);
            if (!dir) throw new Error('City directory not found');
            const handle = await dir.getFileHandle('transit-lines.geojson');
            const file = await handle.getFile();
            const text = await file.text();
            return JSON.parse(text);
          })(),
          (async () => {
            const res = await fetch('/data/stops.json');
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            return (await res.json()) as StopItem[];
          })(),
        ]);

        if (isCancelled) return;

        // 1. Ribbons source & layer (styled by trunk_color_hex)
        if (!map.getSource(TRANSIT_LINES_SOURCE_ID)) {
          map.addSource(TRANSIT_LINES_SOURCE_ID, {
            type: 'geojson',
            data: linesGeojson,
          });
          map.addLayer(getTransitLinesLayerConfig());
        }

        // 2. Station bullets source & layer (built from stops.json data)
        if (!map.getSource(TRANSIT_STATIONS_SOURCE_ID)) {
          const stationsGeojson = buildStationGeoJSON(stopsData);
          map.addSource(TRANSIT_STATIONS_SOURCE_ID, {
            type: 'geojson',
            data: stationsGeojson as unknown as GeoJSON.GeoJSON,
          });
          map.addLayer(getTransitStationsLayerConfig());
        }

        // 3. Tappable stations: select on click & display popup
        clickHandler = (e: MapMouseEvent & { features?: MapGeoJSONFeature[] }) => {
          if (!e.features || e.features.length === 0) return;
          const feat = e.features[0];
          const props = feat.properties || {};
          const id = Number(props.id);
          const name = String(props.name || 'Station');
          const geom = feat.geometry as GeoJSON.Point;
          const coords = geom.coordinates.slice() as [number, number];

          setSelectedStation({ id, name });
          if (onSelectStation) {
            onSelectStation({ id, name });
          }

          if (popupRef.current) {
            popupRef.current.remove();
          }

          const popup = new Popup({
            closeButton: true,
            closeOnClick: false,
            offset: 8,
            className: 'station-bullet-popup',
          })
            .setLngLat(coords)
            .setHTML(`<div class="station-bullet-popup-title">${escapeHtml(name)}</div>`)
            .addTo(map);

          popup.on('close', () => {
            popupRef.current = null;
            setSelectedStation(null);
          });

          popupRef.current = popup;
        };

        enterHandler = () => {
          map.getCanvas().style.cursor = 'pointer';
        };

        leaveHandler = () => {
          map.getCanvas().style.cursor = '';
        };

        if (clickHandler) map.off('click', TRANSIT_STATIONS_LAYER_ID, clickHandler);
        if (enterHandler) map.off('mouseenter', TRANSIT_STATIONS_LAYER_ID, enterHandler);
        if (leaveHandler) map.off('mouseleave', TRANSIT_STATIONS_LAYER_ID, leaveHandler);

        map.on('click', TRANSIT_STATIONS_LAYER_ID, clickHandler);
        map.on('mouseenter', TRANSIT_STATIONS_LAYER_ID, enterHandler);
        map.on('mouseleave', TRANSIT_STATIONS_LAYER_ID, leaveHandler);

        setTransitState('ready');
      } catch (err) {
        if (!isCancelled) {
          setTransitState('error');
        }
      }
    };

    const handleStyleLoad = () => {
      if (!isCancelled) {
        loadOverlays();
      }
    };

    map.on('style.load', handleStyleLoad);
    loadOverlays();

    return () => {
      isCancelled = true;
      map.off('style.load', handleStyleLoad);
      if (popupRef.current) {
        popupRef.current.remove();
        popupRef.current = null;
      }
      if (map.getStyle()) {
        if (clickHandler) map.off('click', TRANSIT_STATIONS_LAYER_ID, clickHandler);
        if (enterHandler) map.off('mouseenter', TRANSIT_STATIONS_LAYER_ID, enterHandler);
        if (leaveHandler) map.off('mouseleave', TRANSIT_STATIONS_LAYER_ID, leaveHandler);
        if (map.getLayer(TRANSIT_STATIONS_LAYER_ID)) map.removeLayer(TRANSIT_STATIONS_LAYER_ID);
        if (map.getLayer(TRANSIT_LINES_LAYER_ID)) map.removeLayer(TRANSIT_LINES_LAYER_ID);
        if (map.getSource(TRANSIT_STATIONS_SOURCE_ID)) map.removeSource(TRANSIT_STATIONS_SOURCE_ID);
        if (map.getSource(TRANSIT_LINES_SOURCE_ID)) map.removeSource(TRANSIT_LINES_SOURCE_ID);
      }
    };
  }, [map, slug, isPackInstalled, onSelectStation]);

  const display = getTransitLayerDisplayState(transitState);

  return (
    <>
      {(transitState === 'loading' || transitState === 'error') && (
        <div class="transit-state-overlay" aria-live="polite">
          <div class={`transit-state-badge badge-${display.badge}`}>
            <span class={`badge-dot badge-dot-${display.badge}`} />
            <span>{display.text}</span>
          </div>
        </div>
      )}
      {selectedStation && (
        <div class="transit-selected-station-overlay" aria-live="polite">
          <div class="transit-selected-station-chip">
            <span class="transit-selected-station-dot" />
            <span class="transit-selected-station-name">{selectedStation.name}</span>
            <button
              type="button"
              class="transit-selected-station-close"
              onClick={() => {
                if (popupRef.current) {
                  popupRef.current.remove();
                  popupRef.current = null;
                }
                setSelectedStation(null);
              }}
              aria-label="Clear selected station"
            >
              ×
            </button>
          </div>
        </div>
      )}
    </>
  );
}
