import React, { useState, useEffect, useCallback } from 'react';
import Map from 'react-map-gl/maplibre';
import DeckGL from '@deck.gl/react';
import { ScatterplotLayer, GeoJsonLayer } from '@deck.gl/layers';
import { MTA_SUBWAY_FEEDS } from '../services/transitConfig';
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

const MAP_STYLE = 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json';



export default function TransitMap({ activeMode, onNodeTap }) {
  const [activeVehicles, setActiveVehicles] = useState([]);

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

  const subwayLinesLayer = new GeoJsonLayer({
    id: 'subway-lines',
    data: '/subway-lines.geojson',
    stroked: true,
    filled: false,
    lineWidthMinPixels: 3,
    getLineColor: [170, 59, 255, 120], 
    visible: activeMode === 'subway'
  });

  const subwayStopsLayer = new GeoJsonLayer({
    id: 'subway-stops',
    data: '/subway-stops.geojson',
    pointRadiusMinPixels: 4,
    getFillColor: [255, 255, 255],
    getLineColor: [170, 59, 255],
    stroked: true,
    lineWidthMinPixels: 2,
    pickable: true,
    visible: activeMode === 'subway',
    onClick: (info) => {
      if (info.object && onNodeTap) {
        onNodeTap({
          stopId: info.object.properties.stop_id,
          name: info.object.properties.stop_name,
          route: 'L' // MVP: hardcoded to L train
        });
      }
    }
  });

  return (
    <div className="transit-map-wrapper">
      <DeckGL
        initialViewState={INITIAL_VIEW_STATE}
        controller={true}
        layers={[subwayLinesLayer, subwayStopsLayer, vehicleLayer]}
        style={{ width: '100%', height: '100%' }}
      >
        <Map
          mapStyle={MAP_STYLE}
        />
      </DeckGL>
    </div>
  );
}
