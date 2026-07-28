import React, { useEffect } from 'react';
import MapLibreGL from '@maplibre/maplibre-react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  useAnimatedProps,
  withTiming,
  withRepeat,
  Easing,
  createAnimatedPropAdapter,
} from 'react-native-reanimated';
import type { Location } from '../store/useExplorationStore';

const AnimatedShapeSource = Animated.createAnimatedComponent(MapLibreGL.ShapeSource);
const AnimatedCircleLayer = Animated.createAnimatedComponent(MapLibreGL.CircleLayer);

const adapter = createAnimatedPropAdapter(
  (props: any) => {
    'worklet';
    if (Object.keys(props).includes('shape')) {
      const coords = props.shape;
      props.shape = {
        type: 'FeatureCollection',
        features: [
          {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: coords,
            },
            properties: {},
          },
        ],
      };
    }
  },
  ['shape']
);

interface AnimatedUserLocationProps {
  location: Location | null;
}

export function AnimatedUserLocation({ location }: AnimatedUserLocationProps) {
  const animatedCoordinate = useSharedValue<[number, number]>([0, 0]);
  const pulsePhase = useSharedValue(0);

  useEffect(() => {
    if (location) {
      if (animatedCoordinate.value[0] === 0) {
        // Initial snap
        animatedCoordinate.value = [location.longitude, location.latitude];
      } else {
        // Smooth interpolate to new GPS tick over 1 second (assumes ~1Hz bg updates max)
        animatedCoordinate.value = withTiming([location.longitude, location.latitude], {
          duration: 1000,
          easing: Easing.linear,
        });
      }
    }
  }, [location, animatedCoordinate]);

  useEffect(() => {
    // Start infinite pulse
    pulsePhase.value = withRepeat(
      withTiming(1, { duration: 2500, easing: Easing.out(Easing.ease) }),
      -1,
      false
    );
  }, [pulsePhase]);

  const animatedProps = useAnimatedProps(() => {
    return {
      shape: animatedCoordinate.value,
    };
  }, [], adapter) as any;

  const pulseStyle = useAnimatedStyle(() => {
    return {
      circleRadius: 6 + pulsePhase.value * 24,
      circleOpacity: (1 - pulsePhase.value) * 0.5,
    } as any;
  });

  if (!location) return null;

  return (
    <AnimatedShapeSource id="animated-user-location-source" animatedProps={animatedProps}>
      <AnimatedCircleLayer
        id="animated-user-location-pulse"
        style={[
          {
            circleColor: '#3b82f6',
            circleStrokeWidth: 0,
            circlePitchAlignment: 'map',
          },
          pulseStyle,
        ] as any}
      />
      <MapLibreGL.CircleLayer
        id="animated-user-location-core"
        style={{
          circleColor: '#2563eb',
          circleRadius: 8,
          circleStrokeWidth: 3,
          circleStrokeColor: '#ffffff',
          circlePitchAlignment: 'map',
        }}
      />
    </AnimatedShapeSource>
  );
}
