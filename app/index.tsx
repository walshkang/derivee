import React, { useEffect, useRef } from 'react';
import { StyleSheet, Text, View, Animated } from 'react-native';
import { useRouter } from 'expo-router';
import * as Location from 'expo-location';
import { useExplorationStore } from '@/store/useExplorationStore';
import { attachNeighborhoodDB } from '@/db/database';

export default function SplashScreen() {
  const router = useRouter();
  const fogAnim = useRef(new Animated.Value(0.4)).current;
  const pulseAnim = useRef(new Animated.Value(1)).current;
  const burnAnim = useRef(new Animated.Value(1)).current;
  const contentFadeAnim = useRef(new Animated.Value(1)).current;
  const setCurrentLocation = useExplorationStore(state => state.setCurrentLocation);

  useEffect(() => {
    // Atmospheric fog breathing animation
    const fogLoop = Animated.loop(
      Animated.sequence([
        Animated.timing(fogAnim, {
          toValue: 0.85,
          duration: 3500,
          useNativeDriver: true,
        }),
        Animated.timing(fogAnim, {
          toValue: 0.4,
          duration: 3500,
          useNativeDriver: true,
        }),
      ])
    );

    // Subtle logo pulse animation
    const pulseLoop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulseAnim, {
          toValue: 1.05,
          duration: 2000,
          useNativeDriver: true,
        }),
        Animated.timing(pulseAnim, {
          toValue: 1,
          duration: 2000,
          useNativeDriver: true,
        }),
      ])
    );

    fogLoop.start();
    pulseLoop.start();

    let isMounted = true;

    const splashDelay = new Promise(resolve => setTimeout(resolve, 2000));
    
    const locationFetch = async () => {
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (status === 'granted') {
          const location = await Location.getCurrentPositionAsync({
            accuracy: Location.Accuracy.Balanced,
          });
          if (isMounted) {
            setCurrentLocation({
              latitude: location.coords.latitude,
              longitude: location.coords.longitude,
            });
          }
        }
      } catch (e) {
        console.warn('Failed to get location on splash screen:', e);
      }
    };
    
    const dbInit = async () => {
      try {
        await attachNeighborhoodDB();
        useExplorationStore.getState().loadUnlockedHexes();
      } catch (e) {
        console.warn('Failed to attach neighborhood db:', e);
      }
    };

    Promise.all([splashDelay, locationFetch(), dbInit()]).then(() => {
      if (!isMounted) return;
      Animated.parallel([
        Animated.timing(burnAnim, {
          toValue: 4,
          duration: 600,
          useNativeDriver: true,
        }),
        Animated.timing(contentFadeAnim, {
          toValue: 0,
          duration: 450,
          useNativeDriver: true,
        }),
      ]).start(() => {
        router.replace('/map');
      });
    });

    return () => {
      isMounted = false;
      fogLoop.stop();
      pulseLoop.stop();
    };
  }, [fogAnim, pulseAnim, burnAnim, contentFadeAnim, setCurrentLocation, router]);

  return (
    <View style={styles.container}>
      {/* Background Atmospheric Fog Layer */}
      <Animated.View
        style={[
          styles.fogBackground,
          {
            opacity: fogAnim,
            transform: [{ scale: burnAnim }],
          },
        ]}
      />

      {/* Central Content */}
      <Animated.View style={[styles.content, { opacity: contentFadeAnim }]}>
        <Animated.View style={[styles.logoContainer, { transform: [{ scale: pulseAnim }] }]}>
          <View style={styles.logoBadge}>
            <Text style={styles.logoIcon}>🌫️</Text>
          </View>
        </Animated.View>

        <Text style={styles.title}>Fog of Williamsburg</Text>
        <Text style={styles.subtitle}>The Cartographer's Awakening</Text>

        <View style={styles.divider} />

        <Text style={styles.tagline}>
          Uncover the physical world hexagon by hexagon.
        </Text>
      </Animated.View>

      <Text style={styles.footerText}>Offline-First • Continuous Native Generation</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8fafc',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  fogBackground: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: '#e2e8f0',
    borderRadius: 200,
    transform: [{ scale: 1.8 }],
  },
  content: {
    alignItems: 'center',
    width: '100%',
    maxWidth: 340,
    zIndex: 2,
  },
  logoContainer: {
    marginBottom: 24,
  },
  logoBadge: {
    width: 88,
    height: 88,
    borderRadius: 44,
    backgroundColor: '#f1f5f9',
    borderWidth: 2,
    borderColor: '#0284c7',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#0284c7',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.3,
    shadowRadius: 16,
    elevation: 8,
  },
  logoIcon: {
    fontSize: 40,
  },
  title: {
    fontSize: 32,
    fontWeight: '800',
    color: '#0f172a',
    letterSpacing: 3,
    marginBottom: 6,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#0284c7',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
    marginBottom: 20,
    textAlign: 'center',
  },
  divider: {
    width: 48,
    height: 2,
    backgroundColor: '#cbd5e1',
    marginBottom: 20,
  },
  tagline: {
    fontSize: 15,
    color: '#475569',
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: 36,
  },
  footerText: {
    position: 'absolute',
    bottom: 36,
    fontSize: 12,
    color: '#94a3b8',
    letterSpacing: 0.5,
  },
});
