import { useEffect, useState } from 'preact/hooks';
import type { Map } from 'maplibre-gl';
import { getCityDirectory } from '../utils/opfs';
import { getTransitLayerDisplayState, type UIState } from '../utils/displayModel';

interface TransitOverlaysProps {
  map: Map | null;
  slug?: string;
  isPackInstalled?: boolean;
}

export function TransitOverlays({ map, slug = 'nyc', isPackInstalled }: TransitOverlaysProps) {
  const [transitState, setTransitState] = useState<UIState>('ready');

  useEffect(() => {
    if (!map || !isPackInstalled) return;

    let isCancelled = false;
    const loadTransitLines = async () => {
      setTransitState('loading');
      try {
        const dir = await getCityDirectory(slug);
        if (!dir) throw new Error('City directory not found');
        const handle = await dir.getFileHandle('transit-lines.geojson');
        const file = await handle.getFile();
        const text = await file.text();
        const geojson = JSON.parse(text);

        if (isCancelled) return;

        if (!map.getSource('transit-lines')) {
          map.addSource('transit-lines', {
            type: 'geojson',
            data: geojson,
          });

          // Ribbons (lines)
          map.addLayer({
            id: 'transit-lines-layer',
            type: 'line',
            source: 'transit-lines',
            filter: ['==', ['geometry-type'], 'LineString'],
            paint: {
              'line-color': ['get', 'color'],
              'line-width': 4,
            },
          });

          // Station bullets
          map.addLayer({
            id: 'transit-stations-layer',
            type: 'circle',
            source: 'transit-lines',
            filter: ['==', ['geometry-type'], 'Point'],
            paint: {
              'circle-color': '#ffffff',
              'circle-stroke-color': '#000000',
              'circle-stroke-width': 2,
              'circle-radius': 4,
            },
          });
          
          // Stations tappable - mouse interactions
          map.on('mouseenter', 'transit-stations-layer', () => {
            map.getCanvas().style.cursor = 'pointer';
          });
          map.on('mouseleave', 'transit-stations-layer', () => {
            map.getCanvas().style.cursor = '';
          });
        }
        setTransitState('ready');
      } catch (err) {
        if (!isCancelled) {
          setTransitState('error');
        }
      }
    };

    loadTransitLines();

    return () => {
      isCancelled = true;
      if (map.getStyle()) {
        if (map.getLayer('transit-stations-layer')) map.removeLayer('transit-stations-layer');
        if (map.getLayer('transit-lines-layer')) map.removeLayer('transit-lines-layer');
        if (map.getSource('transit-lines')) map.removeSource('transit-lines');
      }
    };
  }, [map, slug, isPackInstalled]);

  if (transitState === 'loading' || transitState === 'error') {
    const display = getTransitLayerDisplayState(transitState);
    return (
      <div class="transit-state-overlay" aria-live="polite">
        <div class={`transit-state-badge badge-${display.badge}`}>
          <span class={`badge-dot badge-dot-${display.badge}`} />
          <span>{display.text}</span>
        </div>
      </div>
    );
  }

  return null;
}
