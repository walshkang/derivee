import React, { useEffect, useState, useRef, useMemo, useCallback } from 'react';
import { StyleSheet, Text, View, Pressable, useWindowDimensions } from 'react-native';
import { Canvas, Rect, Circle, Mask, Group, RadialGradient, vec } from '@shopify/react-native-skia';
import Animated, { useSharedValue, withTiming, Easing, useAnimatedStyle, runOnJS, useDerivedValue } from 'react-native-reanimated';
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
import { ContextualStatPill } from '@/components/ContextualStatPill';
import * as h3 from 'h3-js';

export default function MapScreen() {
  const router = useRouter();
  const { isExploring, currentLocation, activeBufferHexes, unlockedHexes, isMacroRevealing, clearMacroReveal, selectedHistoricalRoute, setSelectedHistoricalRoute, refreshCurrentNeighborhoodStat, loadUnlockedHexes } =
    useExplorationStore();
  const { startTracking } = useBackgroundLocation();
  const { loadPOIs } = usePOIStore();
  
  // Transit store integration
  const { selectedTransitNode, setSelectedTransitNode, routePreviewGeoJSON } = useTransitStore();

  const cameraRef = useRef<React.ElementRef<typeof MapLibreGL.Camera>>(null);
  const [is3DMode, setIs3DMode] = useState<boolean>(false);
  const [selectedPOI, setSelectedPOI] = useState<POI | null>(null);
  const [isCameraTracking, setIsCameraTracking] = useState<boolean>(true);

  // Wave 10: Morning Sun Reveal Animation Setup
  const { width, height } = useWindowDimensions();
  const center = useMemo(() => vec(width / 2, height / 2), [width, height]);
  const maxRadius = useMemo(() => Math.max(width, height) * 1.5, [width, height]);
  
  const revealProgress = useSharedValue(0);

  useEffect(() => {
    if (isMacroRevealing) {
      revealProgress.value = 0;
      revealProgress.value = withTiming(1, { duration: 3000, easing: Easing.inOut(Easing.ease) }, (finished) => {
        if (finished) {
          runOnJS(clearMacroReveal)();
        }
      });
    } else {
      revealProgress.value = 0;
    }
  }, [isMacroRevealing, clearMacroReveal, revealProgress]);

  const circleRadius = useDerivedValue(() => {
    return revealProgress.value * maxRadius;
  });

  const overlayStyle = useAnimatedStyle(() => {
    return {
      opacity: isMacroRevealing ? (revealProgress.value > 0.85 ? withTiming(0, {duration: 400}) : 1) : 0,
    };
  });

  useEffect(() => {
    loadUnlockedHexes();
    loadPOIs();
  }, [loadUnlockedHexes, loadPOIs]);

  useEffect(() => {
    // Ambient Tracking: Automatically start tracking when map mounts
    startTracking().catch((err) => console.warn('Failed to start ambient tracking:', err));
  }, [startTracking]);

  // Refresh neighborhood stat whenever location changes
  useEffect(() => {
    if (currentLocation) {
      refreshCurrentNeighborhoodStat();
    }
  }, [currentLocation?.latitude, currentLocation?.longitude, refreshCurrentNeighborhoodStat]);

  // Layer 5: Dynamic 200m Vicinity Bubble GeoJSON Feature
  const vicinityBubbleGeoJSON = useMemo(() => {
    if (!currentLocation) return null;
    return generateVicinityBubbleGeoJSON(currentLocation.latitude, currentLocation.longitude, 200);
  }, [currentLocation?.latitude, currentLocation?.longitude]);

  // Ephemeral GeoJSON FeatureCollection for Layer 2 Glow
  const ephemeralGeoJSON = useMemo(() => {
    if (activeBufferHexes.length === 0) return null;
    return {
      type: 'FeatureCollection' as const,
      features: activeBufferHexes.map(hex => ({
        type: 'Feature' as const,
        id: hex,
        geometry: {
          type: 'Polygon' as const,
          coordinates: [h3.cellToBoundary(hex, true)],
        },
        properties: {},
      })),
    };
  }, [activeBufferHexes]);

  // Stale-While-Revalidate Trigger for Ephemeral Glow
  const [glowOpacity, setGlowOpacity] = useState(0);
  const prevBufferRef = useRef<string[]>([]);

  useEffect(() => {
    const newHexes = activeBufferHexes.filter(h => !prevBufferRef.current.includes(h));
    if (newHexes.length > 0) {
      setGlowOpacity(0.8);
      setTimeout(() => {
        setGlowOpacity(0.0);
      }, 50);
    }
    prevBufferRef.current = activeBufferHexes;
  }, [activeBufferHexes]);

  const handleTogglePerspective = () => {
    setIs3DMode((prev) => !prev);
  };

  const handleRecenterCamera = () => {
    setIsCameraTracking(true);
    if (currentLocation && cameraRef.current) {
      cameraRef.current.setCamera({
        centerCoordinate: [currentLocation.longitude, currentLocation.latitude],
        zoomLevel: 15.5,
        pitch: 0,
        animationDuration: 800,
      });
    }
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
      <ContextualStatPill />


      {/* MapLibre Engine Viewport — Edge-to-Edge Map */}
      <View style={StyleSheet.absoluteFillObject}>
        <MapLibreGL.MapView
          style={StyleSheet.absoluteFillObject}
          mapStyle={`https://api.maptiler.com/maps/streets-v2/style.json?key=${process.env.EXPO_PUBLIC_MAPTILER_API_KEY}`}
          logoEnabled={false}
          attributionEnabled={false}
          onPress={handleMapPress}
          onRegionWillChange={(e) => {
            if (e.properties.isUserInteraction) {
              setIsCameraTracking(false);
            }
          }}
        >
          <MapLibreGL.Camera
            ref={cameraRef}
            centerCoordinate={currentLocation && isCameraTracking ? [currentLocation.longitude, currentLocation.latitude] : undefined}
            animationMode="moveTo"
            animationDuration={1000}
            defaultSettings={{
              centerCoordinate: [-73.9599, 40.7180], // Williamsburg fallback
              zoomLevel: 15.5,
              pitch: 0,
            }}
            minZoomLevel={10}
          />
          <MapLibreGL.UserLocation visible={true} />

          {/* Layer 2: Ephemeral Tile Reveal Glow */}
          {ephemeralGeoJSON && (
            <MapLibreGL.ShapeSource
              id="ephemeral-source"
              shape={ephemeralGeoJSON}
            >
              <MapLibreGL.FillLayer
                id="ephemeral-glow-layer"
                style={{
                  fillColor: '#FFBF00',
                  fillOpacity: glowOpacity,
                  fillOpacityTransition: {
                    duration: 1500,
                    delay: 0,
                  } as any,
                }}
              />
            </MapLibreGL.ShapeSource>
          )}

          {/* Layer 3 & 4: Soft Translucent Cloud Fog Mask with Unlocked Hex Holes (Vector Tiles) */}
          <MapLibreGL.VectorSource
            id="fog-source"
            url="mbtiles://fog-grid.mbtiles" // Fallback: pmtiles://https://fog-of-wburg-cdn.r2.dev/fog-grid.pmtiles
          >
            {/* W13-FOG-2D: Flat Fog Mask */}
            <MapLibreGL.FillLayer
              id="fog-layer"
              sourceLayerID="h3_base_grid"
              style={{
                fillColor: '#0f172a',
                fillOpacity: [
                  'match',
                  ['get', 'id'],
                  unlockedHexes.length > 0 ? unlockedHexes : ['none'],
                  0.0,
                  0.9
                ],
              }}
            />
            {/* Subtle Hex Outlines for Unlocked Hexes */}
            <MapLibreGL.LineLayer
              id="fog-hex-outlines"
              sourceLayerID="h3_base_grid"
              style={{
                lineColor: '#64748b',
                lineWidth: 2,
                lineOpacity: [
                  'match',
                  ['get', 'id'],
                  unlockedHexes.length > 0 ? unlockedHexes : ['none'],
                  0.6,
                  0.0
                ],
              }}
            />
          </MapLibreGL.VectorSource>



          {/* Historical Route Highlight */}
          {selectedHistoricalRoute && (
            <MapLibreGL.ShapeSource id="historical-route-source" shape={selectedHistoricalRoute}>
              <MapLibreGL.LineLayer
                id="historical-route-line"
                style={{
                  lineColor: '#fbbf24', // Warm sun hue contrasting but fitting
                  lineWidth: 6,
                  lineOpacity: 0.9,
                  lineJoin: 'round',
                  lineCap: 'round',
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

      {/* Floating Action Controls Stack (Right) */}
      <View style={styles.fabControlsStackRight}>

        <Pressable
          style={({ pressed }) => [styles.fabButton, pressed && styles.fabButtonPressed]}
          onPress={handleRecenterCamera}
          accessibilityRole="button"
          accessibilityLabel="Recenter location"
        >
          {/* Traditional navigation target icon */}
          <Text style={styles.fabIcon}>⌖</Text>
        </Pressable>
      </View>

      {/* Floating Action Controls Stack (Left) */}
      <View style={styles.fabControlsStackLeft}>
        {selectedHistoricalRoute ? (
          <Pressable
            style={({ pressed }) => [styles.fabPillButton, { backgroundColor: '#fef2f2', borderColor: '#fecaca' }, pressed && styles.fabButtonPressed]}
            onPress={() => setSelectedHistoricalRoute(null)}
            accessibilityRole="button"
          >
            <Text style={[styles.fabPillButtonText, { color: '#ef4444' }]}>Clear Route</Text>
          </Pressable>
        ) : (
          <Pressable
            style={({ pressed }) => [styles.fabPillButton, pressed && styles.fabButtonPressed]}
            onPress={() => router.push('/settings')}
            accessibilityRole="button"
            accessibilityLabel="Open Settings"
          >
            <Text style={styles.fabPillButtonText}>Settings</Text>
          </Pressable>
        )}
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

      {/* Wave 10: Skia Morning Sun Sweep Overlay */}
      <Animated.View style={[StyleSheet.absoluteFillObject, overlayStyle, { zIndex: 100 }]} pointerEvents={isMacroRevealing ? 'auto' : 'none'}>
        <Canvas style={StyleSheet.absoluteFillObject}>
          <Mask
            mode="luminance"
            mask={
              <Group>
                <Rect x={0} y={0} width={width} height={height} color="white" />
                <Circle c={center} r={circleRadius} color="black" />
              </Group>
            }
          >
            <Rect x={0} y={0} width={width} height={height}>
              <RadialGradient
                c={center}
                r={maxRadius}
                colors={['#fef08a', '#fbbf24', '#f59e0b', '#0f172a']}
              />
            </Rect>
          </Mask>
        </Canvas>
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8fafc',
  },
  fabControlsStackRight: {
    position: 'absolute',
    right: 16,
    bottom: 40,
    zIndex: 10,
    gap: 12,
  },
  fabControlsStackLeft: {
    position: 'absolute',
    left: 16,
    bottom: 40,
    zIndex: 10,
    gap: 12,
    flexDirection: 'column',
    justifyContent: 'flex-end',
  },
  fabPillButton: {
    backgroundColor: 'rgba(255, 255, 255, 0.92)',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 24,
    borderWidth: 1,
    borderColor: 'rgba(226, 232, 240, 0.8)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 6,
    elevation: 3,
    alignItems: 'center',
    justifyContent: 'center',
    height: 48,
  },
  fabPillButtonText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#0f172a',
    letterSpacing: 0.5,
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

});
