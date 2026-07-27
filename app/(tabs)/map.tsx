import React, { useEffect, useState, useRef, useMemo, useCallback } from 'react';
import { StyleSheet, Text, View, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import MapLibreGL from '@maplibre/maplibre-react-native';
import { useExplorationStore } from '@/store/useExplorationStore';
import { useBackgroundLocation } from '@/hooks/useBackgroundLocation';
import { usePOIStore } from '@/store/usePOIStore';
import { AmbientRevealBottomSheet } from '@/components/AmbientRevealBottomSheet';
import { TransitBottomSheet } from '@/components/TransitBottomSheet';
import { getPOIByH3Index, POI } from '@/db/poiQueries';
import { coordToH3 } from '@/utils/h3Utils';
import { isWithinVicinityBubble, generateVicinityBubbleGeoJSON } from '@/utils/geoUtils';
import { useTransitStore } from '@/store/useTransitStore';

export default function MapScreen() {
  const router = useRouter();
  const { isExploring, currentLocation, unlockedHexes, fogGeoJSON, updateFogGeoJSON } =
    useExplorationStore();
  const { toggleTracking } = useBackgroundLocation();
  const { loadPOIs } = usePOIStore();
  
  // Transit store integration
  const { selectedTransitNode, setSelectedTransitNode, routePreviewGeoJSON } = useTransitStore();

  const cameraRef = useRef<React.ElementRef<typeof MapLibreGL.Camera>>(null);
  const [is3DMode, setIs3DMode] = useState<boolean>(true);
  const [selectedPOI, setSelectedPOI] = useState<POI | null>(null);

  useEffect(() => {
    loadPOIs();
  }, [loadPOIs]);

  // Update the fog GeoJSON layer whenever location or unlocked hexes change
  useEffect(() => {
    if (currentLocation) {
      updateFogGeoJSON();
    }
  }, [unlockedHexes, currentLocation?.latitude, currentLocation?.longitude, updateFogGeoJSON]);

  // Layer 5: Dynamic 200m Vicinity Bubble GeoJSON Feature
  const vicinityBubbleGeoJSON = useMemo(() => {
    if (!currentLocation) return null;
    return generateVicinityBubbleGeoJSON(currentLocation.latitude, currentLocation.longitude, 200);
  }, [currentLocation?.latitude, currentLocation?.longitude]);

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
        animationDuration: 800,
      });
    }
  };

  const handleNavigateArchive = () => {
    router.push('/(tabs)/archive');
  };

  /**
   * Geospatial Point-in-Polygon (PiP) & Proximity Check on Map Tap.
   */
  const handleMapPress = useCallback(
    (event: any) => {
      const geometry = event?.geometry || event?.payload?.geometry;
      const coordinates = geometry?.coordinates || event?.coordinates;

      if (!coordinates || coordinates.length < 2) return;

      const [tappedLng, tappedLat] = coordinates;

      // 1. Proximity check against user's current GPS location (200m Vicinity Bubble)
      if (currentLocation) {
        const isNearby = isWithinVicinityBubble(
          currentLocation.latitude,
          currentLocation.longitude,
          tappedLat,
          tappedLng,
          200
        );

        if (!isNearby) {
          console.log('Map tap outside 200m Vicinity Bubble. Interaction suppressed.');
          return;
        }
      }

      // 2. Resolve tapped coordinate to H3 resolution 11 index string
      const tappedHex = coordToH3(tappedLat, tappedLng);

      // 3. Ensure the tapped H3 cell has been unlocked/cleared
      const isUnlocked = unlockedHexes.includes(tappedHex);
      if (!isUnlocked) {
        console.log('Map tap inside unexplored fog cell.');
        return;
      }

      // 4. Synchronous SQLite query for Ghost POI at tapped cell
      const matchedPOI = getPOIByH3Index(tappedHex);
      if (matchedPOI) {
        if (matchedPOI.poi_type === 'transit_node') {
          setSelectedTransitNode(matchedPOI);
          setSelectedPOI(null);
        } else {
          setSelectedPOI(matchedPOI);
          setSelectedTransitNode(null);
        }
      }
    },
    [currentLocation, unlockedHexes, setSelectedTransitNode]
  );

  return (
    <View style={styles.container}>
      {/* Top Floating Ambient Navigation Bar */}
      <View style={styles.topAmbientBar}>
        <View style={styles.ambientStatusBadge}>
          <View style={[styles.statusDot, isExploring ? styles.statusDotActive : styles.statusDotInactive]} />
          <Text style={styles.statusText}>{isExploring ? 'EXPEDITION ACTIVE' : 'AMBIENT STANDBY'}</Text>
        </View>

        <Pressable
          style={({ pressed }) => [styles.archiveButton, pressed && styles.archiveButtonPressed]}
          onPress={handleNavigateArchive}
          accessibilityRole="button"
          accessibilityLabel="Open Archive"
        >
          <Text style={styles.archiveButtonText}>ARCHIVE 🏛️</Text>
        </Pressable>
      </View>

      {/* MapLibre Engine Viewport — Edge-to-Edge Map */}
      <View style={StyleSheet.absoluteFillObject}>
        <MapLibreGL.MapView
          style={StyleSheet.absoluteFillObject}
          mapStyle={`https://api.maptiler.com/maps/satellite/style.json?key=${process.env.EXPO_PUBLIC_MAPTILER_API_KEY}`}
          logoEnabled={false}
          attributionEnabled={false}
          onPress={handleMapPress}
        >
          <MapLibreGL.Camera
            ref={cameraRef}
            followUserLocation={isExploring}
            followPitch={is3DMode ? 45 : 0}
            followZoomLevel={16}
          />
          <MapLibreGL.UserLocation visible={true} />

          {/* Layer 3 & Layer 4: Soft Translucent Cloud Fog Mask with Unlocked Hex Holes */}
          {fogGeoJSON && (
            <MapLibreGL.ShapeSource
              id="fog-source"
              shape={fogGeoJSON}
              {...({ withSynchronousUpdate: true } as any)}
            >
              <MapLibreGL.FillLayer
                id="fog-layer"
                style={{
                  fillColor: '#0b0f19',
                  fillOpacity: 0.82,
                }}
              />
            </MapLibreGL.ShapeSource>
          )}

          {/* Layer 5: Active 200m Vicinity Bubble Radius */}
          {vicinityBubbleGeoJSON && (
            <MapLibreGL.ShapeSource id="vicinity-bubble-source" shape={vicinityBubbleGeoJSON}>
              <MapLibreGL.FillLayer
                id="vicinity-bubble-fill"
                style={{
                  fillColor: '#388bfd',
                  fillOpacity: 0.08,
                }}
              />
              <MapLibreGL.LineLayer
                id="vicinity-bubble-line"
                style={{
                  lineColor: '#58a6ff',
                  lineWidth: 1.5,
                  lineDasharray: [2, 2],
                  lineOpacity: 0.6,
                }}
              />
            </MapLibreGL.ShapeSource>
          )}

          {/* Layer 6: Dynamic Transit Route Preview (Global) */}
          {routePreviewGeoJSON && (
            <MapLibreGL.ShapeSource id="route-preview-source" shape={routePreviewGeoJSON}>
              <MapLibreGL.LineLayer
                id="route-preview-line"
                filter={['==', 'isRouteTrace', true]}
                style={{
                  lineColor: '#ef4444',
                  lineWidth: 4,
                  lineOpacity: 0.8,
                }}
              />
              <MapLibreGL.CircleLayer
                id="route-preview-points"
                filter={['!', ['has', 'isRouteTrace']]}
                style={{
                  circleColor: '#ef4444',
                  circleRadius: 6,
                  circleStrokeWidth: 2,
                  circleStrokeColor: '#ffffff',
                }}
              />
            </MapLibreGL.ShapeSource>
          )}
        </MapLibreGL.MapView>
      </View>

      {/* Floating Action Controls Stack */}
      <View style={styles.fabControlsStack}>
        <Pressable
          style={({ pressed }) => [styles.fabButton, pressed && styles.fabButtonPressed]}
          onPress={handleRecenterCamera}
          accessibilityRole="button"
          accessibilityLabel="Recenter location"
        >
          <Text style={styles.fabIcon}>🎯</Text>
        </Pressable>

        <Pressable
          style={({ pressed }) => [styles.fabButton, pressed && styles.fabButtonPressed]}
          onPress={handleTogglePerspective}
          accessibilityRole="button"
          accessibilityLabel="Toggle 3D perspective"
        >
          <Text style={styles.fabText}>{is3DMode ? '3D' : '2D'}</Text>
        </Pressable>

        <Pressable
          style={({ pressed }) => [
            styles.expeditionFab,
            isExploring ? styles.expeditionFabActive : styles.expeditionFabInactive,
            pressed && styles.fabButtonPressed,
          ]}
          onPress={handleToggleExploration}
          accessibilityRole="button"
          accessibilityLabel={isExploring ? 'Stop Expedition' : 'Start Expedition'}
        >
          <Text style={styles.expeditionFabIcon}>{isExploring ? '🛑' : '🛰️'}</Text>
        </Pressable>
      </View>

      {/* Screen 2: The Reveal (Ghost POI Progressive Disclosure Bottom Sheet) */}
      <AmbientRevealBottomSheet
        poi={selectedPOI}
        onClose={() => setSelectedPOI(null)}
      />

      <TransitBottomSheet
        poi={selectedTransitNode}
        onClose={() => setSelectedTransitNode(null)}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#090d16',
  },
  topAmbientBar: {
    position: 'absolute',
    top: 56,
    left: 16,
    right: 16,
    zIndex: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  ambientStatusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.92)',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(226, 232, 240, 0.8)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 6,
    elevation: 3,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 8,
  },
  statusDotActive: {
    backgroundColor: '#10b981',
  },
  statusDotInactive: {
    backgroundColor: '#94a3b8',
  },
  statusText: {
    fontSize: 11,
    fontWeight: '800',
    color: '#0f172a',
    letterSpacing: 0.8,
  },
  archiveButton: {
    backgroundColor: 'rgba(255, 255, 255, 0.92)',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(226, 232, 240, 0.8)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 6,
    elevation: 3,
  },
  archiveButtonPressed: {
    backgroundColor: '#f1f5f9',
    transform: [{ scale: 0.96 }],
  },
  archiveButtonText: {
    fontSize: 12,
    fontWeight: '800',
    color: '#0284c7',
    letterSpacing: 0.5,
  },
  fabControlsStack: {
    position: 'absolute',
    right: 16,
    bottom: 40,
    zIndex: 10,
    gap: 12,
  },
  fabButton: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: 'rgba(255, 255, 255, 0.92)',
    borderWidth: 1,
    borderColor: 'rgba(226, 232, 240, 0.8)',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 3 },
    shadowOpacity: 0.12,
    shadowRadius: 8,
    elevation: 4,
  },
  fabButtonPressed: {
    backgroundColor: '#f1f5f9',
    transform: [{ scale: 0.95 }],
  },
  fabIcon: {
    fontSize: 20,
  },
  fabText: {
    fontSize: 14,
    fontWeight: '800',
    color: '#0284c7',
  },
  expeditionFab: {
    width: 52,
    height: 52,
    borderRadius: 26,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 10,
    elevation: 6,
  },
  expeditionFabInactive: {
    backgroundColor: '#0284c7',
    borderColor: '#38bdf8',
  },
  expeditionFabActive: {
    backgroundColor: '#ef4444',
    borderColor: '#f87171',
  },
  expeditionFabIcon: {
    fontSize: 22,
  },
});
