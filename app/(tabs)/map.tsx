import React, { useEffect, useState, useRef, useMemo } from 'react';
import { StyleSheet, Text, View, Pressable } from 'react-native';
import MapLibreGL from '@maplibre/maplibre-react-native';
import { useExplorationStore } from '@/store/useExplorationStore';
import { useBackgroundLocation } from '@/hooks/useBackgroundLocation';
import { usePOIStore } from '@/store/usePOIStore';
import { POIRewardModal } from '@/components/POIRewardModal';

export default function MapScreen() {
  const { isExploring, currentLocation, unlockedHexes, fogGeoJSON, updateFogGeoJSON } =
    useExplorationStore();
  const { toggleTracking, isLoading } = useBackgroundLocation();
  const { pois, recentlyDiscovered, loadPOIs, clearRecentPOI } = usePOIStore();

  const cameraRef = useRef<React.ElementRef<typeof MapLibreGL.Camera>>(null);
  const [is3DMode, setIs3DMode] = useState<boolean>(true);

  useEffect(() => {
    loadPOIs();
  }, [loadPOIs]);

  // Update the fog layer whenever the unlocked hexes change
  useEffect(() => {
    if (isExploring && currentLocation) {
      updateFogGeoJSON();
    }
  }, [unlockedHexes, isExploring, currentLocation?.latitude, currentLocation?.longitude, updateFogGeoJSON]);

  const handleToggleExploration = async () => {
    try {
      await toggleTracking();
    } catch (err: any) {
      console.warn('Exploration tracking toggle error:', err);
    }
  };

  const handleTogglePerspective = () => {
    setIs3DMode((prev) => !prev);
  };

  const handleRecenterCamera = () => {
    if (currentLocation && cameraRef.current) {
      cameraRef.current.setCamera({
        centerCoordinate: [currentLocation.longitude, currentLocation.latitude],
        zoomLevel: 16,
        animationDuration: 1000,
      });
    }
  };

  const undiscoveredPOIsGeoJSON = useMemo<GeoJSON.FeatureCollection>(() => {
    return {
      type: 'FeatureCollection',
      features: pois.filter((p) => !p.discovered).map((p) => ({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [p.longitude, p.latitude] },
        properties: { id: p.id, name: p.name },
      })),
    };
  }, [pois]);

  const discoveredPOIsGeoJSON = useMemo<GeoJSON.FeatureCollection>(() => {
    return {
      type: 'FeatureCollection',
      features: pois.filter((p) => p.discovered).map((p) => ({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [p.longitude, p.latitude] },
        properties: { id: p.id, name: p.name },
      })),
    };
  }, [pois]);

  return (
    <View style={styles.container}>
      {/* Top HUD Overlay Header */}
      <View style={styles.topHud}>
        <View style={styles.topHudCard}>
          <Text style={styles.hudTitle}>FOG OF WBURG</Text>
          <View style={styles.statusBadge}>
            <View style={[styles.statusDot, isExploring ? styles.statusDotActive : styles.statusDotInactive]} />
            <Text style={styles.statusText}>{isExploring ? 'EXPEDITION ACTIVE' : 'STANDBY'}</Text>
          </View>
        </View>
      </View>

      {/* MapLibre Engine Viewport */}
      <View style={StyleSheet.absoluteFillObject}>
        <MapLibreGL.MapView
          style={StyleSheet.absoluteFillObject}
          mapStyle={`https://api.maptiler.com/maps/satellite/style.json?key=${process.env.EXPO_PUBLIC_MAPTILER_API_KEY}`}
          logoEnabled={false}
          attributionEnabled={false}
        >
          <MapLibreGL.Camera
            ref={cameraRef}
            followUserLocation={isExploring}
            followPitch={is3DMode ? 45 : 0}
            followZoomLevel={16}
          />
          <MapLibreGL.UserLocation visible={true} />
          
          {/* Layer 2: The Fog (Inverted Polygon) */}
          {fogGeoJSON && (
            <MapLibreGL.ShapeSource
              id="fog-source"
              shape={fogGeoJSON}
            >
              <MapLibreGL.FillLayer
                id="fog-layer"
                style={{
                  fillColor: '#000000',
                  fillOpacity: 0.85,
                }}
              />
            </MapLibreGL.ShapeSource>
          )}

          {/* Layer 3: Discovered POIs */}
          <MapLibreGL.ShapeSource id="discovered-pois-source" shape={discoveredPOIsGeoJSON}>
            <MapLibreGL.CircleLayer
              id="discovered-pois-layer"
              style={{
                circleRadius: 6,
                circleColor: '#f2cc60',
                circleStrokeWidth: 2,
                circleStrokeColor: '#ffffff',
              }}
            />
          </MapLibreGL.ShapeSource>

          {/* Layer 4: Undiscovered POIs (Beacons) */}
          <MapLibreGL.ShapeSource id="undiscovered-pois-source" shape={undiscoveredPOIsGeoJSON}>
            <MapLibreGL.CircleLayer
              id="undiscovered-pois-layer"
              style={{
                circleRadius: 8,
                circleColor: '#58a6ff',
                circleOpacity: 0.8,
                circleStrokeWidth: 3,
                circleStrokeColor: '#1f6feb',
                circleStrokeOpacity: 0.6,
              }}
            />
          </MapLibreGL.ShapeSource>
        </MapLibreGL.MapView>
      </View>

      {/* Floating Action Controls Stack */}
      <View style={styles.fabControlsStack}>
        <Pressable
          style={styles.fabButton}
          onPress={handleRecenterCamera}
          accessibilityRole="button"
          accessibilityLabel="Recenter location"
        >
          <Text style={styles.fabIcon}>🎯</Text>
        </Pressable>
        <Pressable
          style={styles.fabButton}
          onPress={handleTogglePerspective}
          accessibilityRole="button"
          accessibilityLabel="Toggle 3D perspective"
        >
          <Text style={styles.fabText}>{is3DMode ? '3D' : '2D'}</Text>
        </Pressable>
      </View>

      {/* Bottom HUD Actions & Overlay */}
      <View style={styles.bottomHud}>
        <View style={styles.metricsRow}>
          <View style={styles.metricCard}>
            <Text style={styles.metricLabel}>Unlocked Hexes</Text>
            <Text style={styles.metricValue}>{unlockedHexes.length}</Text>
          </View>

          <View style={styles.metricCard}>
            <Text style={styles.metricLabel}>Coverage</Text>
            <Text style={styles.metricValue}>
              {unlockedHexes.length > 0 ? `${(unlockedHexes.length * 0.05).toFixed(1)} km²` : '0.0 km²'}
            </Text>
          </View>
        </View>

        <Pressable
          style={[styles.actionButton, isExploring ? styles.actionButtonActive : styles.actionButtonInactive]}
          onPress={handleToggleExploration}
          accessibilityRole="button"
          accessibilityLabel={isExploring ? 'Stop Exploring' : 'Start Exploring'}
        >
          <Text style={styles.actionButtonText}>
            {isExploring ? 'STOP EXPEDITION' : 'START EXPLORING'}
          </Text>
        </Pressable>
      </View>

      <POIRewardModal poi={recentlyDiscovered} onClose={clearRecentPOI} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0d1117',
  },
  topHud: {
    position: 'absolute',
    top: 54,
    left: 16,
    right: 16,
    zIndex: 10,
  },
  topHudCard: {
    backgroundColor: 'rgba(22, 27, 34, 0.92)',
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderWidth: 1,
    borderColor: '#30363d',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  hudTitle: {
    fontSize: 16,
    fontWeight: '800',
    color: '#ffffff',
    letterSpacing: 1.5,
  },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#0d1117',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: '#30363d',
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 6,
  },
  statusDotActive: {
    backgroundColor: '#3fb950',
  },
  statusDotInactive: {
    backgroundColor: '#f85149',
  },
  statusText: {
    fontSize: 11,
    fontWeight: '700',
    color: '#c9d1d9',
    letterSpacing: 0.5,
  },
  mapPlaceholder: {
    flex: 1,
    backgroundColor: '#090d13',
    alignItems: 'center',
    justifyContent: 'center',
  },
  gridOverlay: {
    alignItems: 'center',
    padding: 24,
  },
  placeholderIcon: {
    fontSize: 56,
    marginBottom: 12,
  },
  placeholderTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: '#ffffff',
    marginBottom: 6,
  },
  placeholderSubtitle: {
    fontSize: 14,
    color: '#58a6ff',
    fontWeight: '600',
    marginBottom: 16,
  },
  placeholderCoords: {
    fontSize: 12,
    fontFamily: 'monospace',
    color: '#8b949e',
    backgroundColor: '#161b22',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: '#30363d',
  },
  bottomHud: {
    position: 'absolute',
    bottom: 16,
    left: 16,
    right: 16,
    zIndex: 10,
    gap: 12,
  },
  metricsRow: {
    flexDirection: 'row',
    gap: 12,
  },
  metricCard: {
    flex: 1,
    backgroundColor: 'rgba(22, 27, 34, 0.92)',
    paddingVertical: 10,
    paddingHorizontal: 14,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#30363d',
  },
  metricLabel: {
    fontSize: 11,
    color: '#8b949e',
    fontWeight: '600',
    marginBottom: 2,
    textTransform: 'uppercase',
  },
  metricValue: {
    fontSize: 18,
    fontWeight: '700',
    color: '#ffffff',
  },
  actionButton: {
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    elevation: 4,
  },
  actionButtonInactive: {
    backgroundColor: '#238636',
    borderColor: '#2ea043',
  },
  actionButtonActive: {
    backgroundColor: '#da3633',
    borderColor: '#f85149',
  },
  actionButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '800',
    letterSpacing: 1.5,
  },
  fabControlsStack: {
    position: 'absolute',
    right: 16,
    bottom: 140,
    zIndex: 10,
    gap: 10,
  },
  fabButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(22, 27, 34, 0.92)',
    borderWidth: 1,
    borderColor: '#30363d',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 4,
    elevation: 4,
  },
  fabIcon: {
    fontSize: 18,
  },
  fabText: {
    fontSize: 13,
    fontWeight: '800',
    color: '#58a6ff',
  },
});
