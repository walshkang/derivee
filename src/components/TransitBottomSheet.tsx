import React, { useEffect } from 'react';
import { StyleSheet, Text, View, Pressable, Modal, ActivityIndicator, ScrollView } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withSpring,
} from 'react-native-reanimated';
import { BlurView } from 'expo-blur';
import { POI } from '../db/poiQueries';
import { useTransitStore } from '../store/useTransitStore';

interface TransitBottomSheetProps {
  poi: POI | null;
  onClose: () => void;
}

export function TransitBottomSheet({ poi, onClose }: TransitBottomSheetProps) {
  const { arrivals, isLoading, error } = useTransitStore();
  const opacity = useSharedValue(0);
  const translateY = useSharedValue(300);

  useEffect(() => {
    if (poi) {
      opacity.value = withTiming(1, { duration: 250 });
      translateY.value = withSpring(0, { damping: 18, stiffness: 120 });
    } else {
      opacity.value = withTiming(0, { duration: 200 });
      translateY.value = withTiming(300, { duration: 200 });
    }
  }, [poi, opacity, translateY]);

  const backdropStyle = useAnimatedStyle(() => ({
    opacity: opacity.value,
  }));

  const sheetStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: translateY.value }],
  }));

  if (!poi) return null;

  return (
    <Modal transparent visible={true} animationType="none" onRequestClose={onClose}>
      <View style={styles.overlay}>
        {/* Semi-transparent backdrop */}
        <Animated.View style={[styles.backdrop, backdropStyle]}>
          <Pressable style={StyleSheet.absoluteFill} onPress={onClose} accessibilityLabel="Dismiss sheet" />
        </Animated.View>

        {/* Bottom Sheet Container */}
        <Animated.View style={[styles.sheetContainer, sheetStyle]}>
          {BlurView ? (
            <BlurView intensity={80} tint="light" style={styles.blurContainer}>
              <SheetContent poi={poi} arrivals={arrivals} isLoading={isLoading} error={error} onClose={onClose} />
            </BlurView>
          ) : (
            <View style={styles.fallbackContainer}>
              <SheetContent poi={poi} arrivals={arrivals} isLoading={isLoading} error={error} onClose={onClose} />
            </View>
          )}
        </Animated.View>
      </View>
    </Modal>
  );
}

function SheetContent({
  poi,
  arrivals,
  isLoading,
  error,
  onClose
}: {
  poi: POI;
  arrivals: any[];
  isLoading: boolean;
  error: string | null;
  onClose: () => void;
}) {
  // Sort arrivals by time
  const sortedArrivals = [...arrivals].sort((a, b) => a.arrivalTime - b.arrivalTime);
  // Show up to 3 upcoming arrivals
  const upcomingArrivals = sortedArrivals.slice(0, 3);
  
  const now = Math.floor(Date.now() / 1000);

  return (
    <View style={styles.content}>
      {/* Top Handle Pill */}
      <View style={styles.handlePill} />

      <View style={styles.headerRow}>
        <View style={styles.categoryBadge}>
          <Text style={styles.categoryText}>LIVE TRANSIT</Text>
        </View>
        <Text style={styles.coordsText}>
          {poi.latitude.toFixed(4)}°, {poi.longitude.toFixed(4)}°
        </Text>
      </View>

      <Text style={styles.poiName}>{poi.name}</Text>
      <Text style={styles.poiDescription}>{poi.description}</Text>

      {/* Naver Maps-style countdowns */}
      <View style={styles.arrivalsContainer}>
        {isLoading ? (
          <ActivityIndicator size="small" color="#0284c7" />
        ) : error ? (
          <Text style={styles.errorText}>Failed to load live data.</Text>
        ) : upcomingArrivals.length > 0 ? (
          upcomingArrivals.map((arrival, index) => {
            const diffSeconds = arrival.arrivalTime - now;
            const diffMinutes = Math.max(0, Math.floor(diffSeconds / 60));
            const timeString = diffMinutes === 0 ? 'Due' : `${diffMinutes} min`;

            return (
              <View key={`${arrival.routeId}-${index}`} style={styles.arrivalRow}>
                <View style={styles.routeBadge}>
                  <Text style={styles.routeBadgeText}>{arrival.routeId}</Text>
                </View>
                <Text style={styles.countdownText}>{timeString}</Text>
              </View>
            );
          })
        ) : (
          <Text style={styles.emptyText}>No upcoming arrivals.</Text>
        )}
      </View>

      {/* Placeholder for Historical Sparkline (Wave 9) */}
      <View style={styles.sparklinePlaceholder}>
        <Text style={styles.sparklineText}>Historical Reliability: --% (Loading...)</Text>
      </View>

      <Pressable
        style={({ pressed }) => [styles.dismissButton, pressed && styles.dismissButtonPressed]}
        onPress={onClose}
        accessibilityRole="button"
        accessibilityLabel="Dismiss discovery"
      >
        <Text style={styles.dismissButtonText}>DISMISS</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  backdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(15, 23, 42, 0.35)',
  },
  sheetContainer: {
    width: '100%',
    borderTopLeftRadius: 28,
    borderTopRightRadius: 28,
    overflow: 'hidden',
    shadowColor: '#000000',
    shadowOffset: { width: 0, height: -6 },
    shadowOpacity: 0.15,
    shadowRadius: 16,
    elevation: 12,
  },
  blurContainer: {
    borderTopLeftRadius: 28,
    borderTopRightRadius: 28,
    backgroundColor: 'rgba(255, 255, 255, 0.88)',
    borderWidth: 1,
    borderColor: 'rgba(226, 232, 240, 0.8)',
  },
  fallbackContainer: {
    borderTopLeftRadius: 28,
    borderTopRightRadius: 28,
    backgroundColor: 'rgba(255, 255, 255, 0.96)',
    borderWidth: 1,
    borderColor: '#e2e8f0',
  },
  content: {
    paddingHorizontal: 24,
    paddingTop: 12,
    paddingBottom: 36,
    alignItems: 'center',
  },
  handlePill: {
    width: 36,
    height: 4,
    borderRadius: 2,
    backgroundColor: '#cbd5e1',
    marginBottom: 16,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    width: '100%',
    marginBottom: 12,
  },
  categoryBadge: {
    backgroundColor: '#eff6ff',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#bfdbfe',
  },
  categoryText: {
    fontSize: 10,
    fontWeight: '800',
    color: '#0369a1',
    letterSpacing: 1.2,
  },
  coordsText: {
    fontSize: 11,
    fontFamily: 'monospace',
    color: '#64748b',
    fontWeight: '600',
  },
  poiName: {
    fontSize: 24,
    fontWeight: '800',
    color: '#0f172a',
    letterSpacing: 0.5,
    textAlign: 'center',
    marginBottom: 4,
    width: '100%',
  },
  poiDescription: {
    fontSize: 14,
    color: '#475569',
    lineHeight: 20,
    textAlign: 'center',
    marginBottom: 20,
    width: '100%',
  },
  arrivalsContainer: {
    width: '100%',
    backgroundColor: '#f8fafc',
    borderRadius: 16,
    padding: 16,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: '#e2e8f0',
    minHeight: 80,
    justifyContent: 'center',
  },
  arrivalRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: '#f1f5f9',
  },
  routeBadge: {
    backgroundColor: '#ef4444',
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  routeBadgeText: {
    color: '#fff',
    fontWeight: '800',
    fontSize: 16,
  },
  countdownText: {
    fontSize: 22,
    fontWeight: '800',
    color: '#0f172a',
  },
  errorText: {
    color: '#ef4444',
    textAlign: 'center',
    fontWeight: '600',
  },
  emptyText: {
    color: '#64748b',
    textAlign: 'center',
    fontStyle: 'italic',
  },
  sparklinePlaceholder: {
    width: '100%',
    padding: 12,
    backgroundColor: '#f1f5f9',
    borderRadius: 12,
    marginBottom: 24,
    alignItems: 'center',
  },
  sparklineText: {
    fontSize: 12,
    color: '#64748b',
    fontWeight: '600',
  },
  dismissButton: {
    width: '100%',
    backgroundColor: '#0f172a',
    paddingVertical: 14,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#0f172a',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 6,
    elevation: 3,
  },
  dismissButtonPressed: {
    backgroundColor: '#1e293b',
    transform: [{ scale: 0.99 }],
  },
  dismissButtonText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '800',
    letterSpacing: 1.5,
  },
});
