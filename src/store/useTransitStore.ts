import { create } from 'zustand';
import { transitService, TransitArrival, TransitVehicle } from '@/services/transitService';
import { POI } from '@/db/poiQueries';

interface TransitState {
  selectedTransitNode: POI | null;
  arrivals: TransitArrival[];
  vehicles: TransitVehicle[];
  routePreviewGeoJSON: GeoJSON.FeatureCollection | null;
  isLoading: boolean;
  error: string | null;

  setSelectedTransitNode: (node: POI | null) => void;
  fetchLiveTransitData: () => Promise<void>;
  generateRoutePreview: (vehicles: TransitVehicle[]) => void;
}

export const useTransitStore = create<TransitState>((set, get) => ({
  selectedTransitNode: null,
  arrivals: [],
  vehicles: [],
  routePreviewGeoJSON: null,
  isLoading: false,
  error: null,

  setSelectedTransitNode: (node: POI | null) => {
    set({ selectedTransitNode: node });
    if (node) {
      get().fetchLiveTransitData();
    } else {
      set({ arrivals: [], vehicles: [], routePreviewGeoJSON: null, error: null });
    }
  },

  fetchLiveTransitData: async () => {
    set({ isLoading: true, error: null });
    try {
      const { arrivals, vehicles } = await transitService.fetchLiveFeed();
      set({ arrivals, vehicles, isLoading: false });
      get().generateRoutePreview(vehicles);
    } catch (err: any) {
      set({ error: err.message, isLoading: false });
    }
  },

  generateRoutePreview: (vehicles: TransitVehicle[]) => {
    // Generate a simple GeoJSON FeatureCollection from vehicle positions for now
    // In the future, this could map vehicle positions to static shapes.txt geometries
    if (vehicles.length === 0) {
      set({ routePreviewGeoJSON: null });
      return;
    }

    const features: any[] = vehicles.map(vehicle => ({
      type: 'Feature' as const,
      properties: {
        routeId: vehicle.routeId,
        bearing: vehicle.bearing,
      },
      geometry: {
        type: 'Point' as const,
        coordinates: [vehicle.longitude, vehicle.latitude],
      },
    }));

    // For a line trace, if we have multiple vehicles on the same route, we might connect them.
    // Or we just display the live vehicles as points on the map for now.
    // Let's create a LineString if we have more than 1 point to simulate a "trace"
    const coordinates = vehicles.map(v => [v.longitude, v.latitude]);
    if (coordinates.length > 1) {
      features.push({
        type: 'Feature' as const,
        properties: {
          isRouteTrace: true,
        },
        geometry: {
          type: 'LineString' as const,
          coordinates,
        },
      });
    }

    const geojson: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features,
    };

    set({ routePreviewGeoJSON: geojson });
  },
}));
