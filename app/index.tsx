import React, { useEffect, useRef } from 'react';
import { StyleSheet, Text, View, Pressable, Animated } from 'react-native';
import { useRouter } from 'expo-router';

export default function SplashScreen() {
  const router = useRouter();
  const fogAnim = useRef(new Animated.Value(0.4)).current;
  const pulseAnim = useRef(new Animated.Value(1)).current;

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

    return () => {
      fogLoop.stop();
      pulseLoop.stop();
    };
  }, [fogAnim, pulseAnim]);

  const handleAwaken = () => {
    router.replace('/(tabs)/map');
  };

  return (
    <View style={styles.container}>
      {/* Background Atmospheric Fog Layer */}
      <Animated.View
        style={[
          styles.fogBackground,
          {
            opacity: fogAnim,
          },
        ]}
      />

      {/* Central Content */}
      <View style={styles.content}>
        <Animated.View style={[styles.logoContainer, { transform: [{ scale: pulseAnim }] }]}>
          <View style={styles.logoBadge}>
            <Text style={styles.logoIcon}>🌫️</Text>
          </View>
        </Animated.View>

        <Text style={styles.title}>FOG OF WBURG</Text>
        <Text style={styles.subtitle}>The Cartographer's Awakening</Text>

        <View style={styles.divider} />

        <Text style={styles.tagline}>
          Uncover the physical world hexagon by hexagon.
        </Text>

        <Pressable
          style={({ pressed }) => [
            styles.awakenButton,
            pressed && styles.awakenButtonPressed,
          ]}
          onPress={handleAwaken}
          accessibilityRole="button"
          accessibilityLabel="Awaken map"
        >
          <Text style={styles.awakenButtonText}>AWAKEN MAP</Text>
        </Pressable>
      </View>

      <Text style={styles.footerText}>Offline-First • Continuous Native Generation</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0d1117',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  fogBackground: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: '#161b22',
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
    backgroundColor: '#161b22',
    borderWidth: 2,
    borderColor: '#58a6ff',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#58a6ff',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.5,
    shadowRadius: 16,
    elevation: 8,
  },
  logoIcon: {
    fontSize: 40,
  },
  title: {
    fontSize: 32,
    fontWeight: '800',
    color: '#ffffff',
    letterSpacing: 3,
    marginBottom: 6,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#58a6ff',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
    marginBottom: 20,
    textAlign: 'center',
  },
  divider: {
    width: 48,
    height: 2,
    backgroundColor: '#30363d',
    marginBottom: 20,
  },
  tagline: {
    fontSize: 15,
    color: '#8b949e',
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: 36,
  },
  awakenButton: {
    width: '100%',
    backgroundColor: '#1f6feb',
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#388bfd',
    shadowColor: '#1f6feb',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 10,
    elevation: 4,
  },
  awakenButtonPressed: {
    backgroundColor: '#1158c7',
    transform: [{ scale: 0.98 }],
  },
  awakenButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '700',
    letterSpacing: 2,
  },
  footerText: {
    position: 'absolute',
    bottom: 36,
    fontSize: 12,
    color: '#484f58',
    letterSpacing: 0.5,
  },
});
