import React, { useState, useEffect, useCallback } from 'react';
import Map from 'react-map-gl/maplibre';
import DeckGL from '@deck.gl/react';
import { ScatterplotLayer, GeoJsonLayer } from '@deck.gl/layers';
import { MTA_SUBWAY_FEEDS, getRouteColor, hexToRgb } from '../services/transitConfig';
import { transitService } from '../services/transitService';
import 'maplibre-gl/dist/maplibre-gl.css';
import './TransitMap.css';

const INITIAL_VIEW_STATE = {
  longitude: -73.9575,
  latitude: 40.7145,
  zoom: 13,
  pitch: 45,
  bearing: 0
};

const MAP_STYLE = '/map-style.json';



export default function TransitMap({ activeMode, onNodeTap }) {
  const [activeVehicles, setActiveVehicles] = useState([]);
  const [currentZoom, setCurrentZoom] = useState(INITIAL_VIEW_STATE.zoom);

  const fetchLiveTransit = useCallback(async () => {
    try {
      let fetchedVehicles = [];
      if (activeMode === 'subway') {
        // Fetch all subways
        const feedKeys = Object.keys(MTA_SUBWAY_FEEDS);
        const results = await Promise.all(feedKeys.map(key => transitService.fetchSubwayFeed(key)));
        fetchedVehicles = results.flatMap(res => res.vehicles);
      } else {
        // Fetch all buses
        const { vehicles } = await transitService.fetchBusLive();
        fetchedVehicles = vehicles;
      }
      
      const mappedVehicles = fetchedVehicles.map(v => ({
        position: [v.longitude, v.latitude],
        routeId: v.routeId,
        status: 'moving'
      }));
      
      setActiveVehicles(mappedVehicles);
    } catch (e) {
      console.error('Failed to fetch live transit:', e);
    }
  }, [activeMode]);

  useEffect(() => {
    fetchLiveTransit();
    const intervalId = setInterval(fetchLiveTransit, 15000);
    return () => clearInterval(intervalId);
  }, [fetchLiveTransit]);

  const vehicleLayer = new ScatterplotLayer({
    id: 'transit-vehicles',
    data: activeVehicles,
    getPosition: d => d.position,
    getFillColor: d => activeMode === 'subway' ? [170, 59, 255] : [0, 122, 255],
    getRadius: 30,
    radiusScale: 1,
    radiusMinPixels: 6,
    radiusMaxPixels: 20,
    pickable: true,
    onClick: (info) => {
      if (info.object && onNodeTap) {
        onNodeTap(info.object);
      }
    }
  });

  // TODO(Data Pipeline): Parallel subway lines for shared corridors (e.g. 4/5/6)
  // should be pre-offset on the backend by the Go Observer to avoid brittle 
  // client-side rendering complexity.
  const subwayLinesLayer = new GeoJsonLayer({
    id: 'subway-lines',
    data: '/subway-lines.geojson',
    stroked: true,
    filled: false,
    lineWidthMinPixels: 3,
    getLineColor: f => {
      const rgb = hexToRgb(getRouteColor(f.properties.route_id));
      return [...rgb, 180]; // add alpha
    },
    visible: activeMode === 'subway'
  });

  const subwayStopsLayer = new GeoJsonLayer({
    id: 'subway-stops',
    data: '/subway-stops.geojson',
    pointRadiusMinPixels: 4,
    getFillColor: [255, 255, 255],
    getLineColor: f => {
      const routeId = f.properties.stop_id.charAt(0);
      const rgb = hexToRgb(getRouteColor(routeId));
      return rgb;
    },
    stroked: true,
    lineWidthMinPixels: 2,
    pickable: true,
    visible: activeMode === 'subway',
    onClick: (info) => {
      if (info.object && onNodeTap) {
        onNodeTap({
          stopId: info.object.properties.stop_id,
          name: info.object.properties.stop_name,
          route: info.object.properties.stop_id.charAt(0) // Extract route from stop_id
        });
      }
    }
  });

  const busLinesLayer = new GeoJsonLayer({
    id: 'bus-lines',
    data: '/bus-lines.geojson',
    stroked: true,
    filled: false,
    lineWidthMinPixels: 3,
    getLineColor: [0, 122, 255, 180],
    visible: activeMode === 'bus'
  });

  const busStopsLayer = new GeoJsonLayer({
    id: 'bus-stops',
    data: '/bus-stops.geojson',
    pointRadiusMinPixels: 4,
    getFillColor: [255, 255, 255],
    getLineColor: [0, 122, 255],
    stroked: true,
    lineWidthMinPixels: 2,
    pickable: true,
    // Zoom < 13: Hide bus stops
    // Zoom 13-15: Show high-ridership stops (showing all for now as placeholder)
    // Zoom > 15: Show all bus stops
    visible: activeMode === 'bus' && currentZoom >= 13,
    onClick: (info) => {
      if (info.object && onNodeTap) {
        onNodeTap({
          stopId: info.object.properties.stop_id,
          name: info.object.properties.stop_name,
          route: 'bus'
        });
      }
    }
  });

  return (
    <div className="transit-map-wrapper">
      <DeckGL
        initialViewState={INITIAL_VIEW_STATE}
        controller={true}
        onViewStateChange={({ viewState }) => setCurrentZoom(viewState.zoom)}
        layers={[subwayLinesLayer, subwayStopsLayer, busLinesLayer, busStopsLayer, vehicleLayer]}
        style={{ width: '100%', height: '100%' }}
      >
        <Map
          mapStyle={MAP_STYLE}
        />
      </DeckGL>
    </div>
  );
}
