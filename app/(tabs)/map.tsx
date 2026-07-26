import React, { useEffect } from 'react';
import { StyleSheet, Text, View, Pressable } from 'react-native';
import MapLibreGL from '@maplibre/maplibre-react-native';
import { useExplorationStore } from '@/store/useExplorationStore';

export default function MapScreen() {
  const { isExploring, currentLocation, unlockedHexes, fogGeoJSON, setIsExploring, setCurrentLocation, addUnlockedHexes, updateFogGeoJSON } =
    useExplorationStore();

  // Update the fog layer whenever the unlocked hexes change
  useEffect(() => {
    if (isExploring && currentLocation) {
      updateFogGeoJSON();
    }
  }, [unlockedHexes, isExploring, currentLocation?.latitude, currentLocation?.longitude, updateFogGeoJSON]);

  const handleToggleExploration = () => {
    const nextState = !isExploring;
    setIsExploring(nextState);
    if (nextState) {
      setCurrentLocation({ latitude: 40.7128, longitude: -73.956 });
      addUnlockedHexes(['8b2a100d213fff']);
    }
  };

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
            followUserLocation={isExploring}
            followPitch={45}
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
        </MapLibreGL.MapView>
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
});
