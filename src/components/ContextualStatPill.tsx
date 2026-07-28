import React, { useEffect, useState, useRef } from 'react';
import { StyleSheet, Text, View, TouchableOpacity } from 'react-native';
import { BlurView } from 'expo-blur';
import { useExplorationStore } from '@/store/useExplorationStore';
import { useRouter } from 'expo-router';

export function ContextualStatPill() {
  const { currentNeighborhoodStat, sessionUnlockedCount, sessionDistanceMeters } = useExplorationStore();
  const [isActiveState, setIsActiveState] = useState(false);
  const [showSessionStats, setShowSessionStats] = useState(false);
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);
  const router = useRouter();

  // Active state animation triggers
  useEffect(() => {
    if (sessionUnlockedCount > 0) {
      setIsActiveState(true);
      
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }

      timeoutRef.current = setTimeout(() => {
        setIsActiveState(false);
      }, 5000);
    }
    
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, [sessionUnlockedCount]);

  useEffect(() => {
    const interval = setInterval(() => {
      setShowSessionStats(prev => !prev);
    }, 5000);
    return () => clearInterval(interval);
  }, []);

  if (!currentNeighborhoodStat) {
    return null;
  }

  const { name, explored_hexes, total_hexes } = currentNeighborhoodStat;
  // Guard against divide by zero
  const percentage = total_hexes > 0 ? ((explored_hexes / total_hexes) * 100).toFixed(2) : '0.00';
  const distanceKm = (sessionDistanceMeters / 1000).toFixed(2);

  return (
    <View style={styles.container}>
      <TouchableOpacity 
        activeOpacity={0.7} 
        onPress={() => router.push('/stats')}
        hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
      >
        <BlurView intensity={90} tint="light" style={styles.pill}>
          <Text style={styles.text}>
            {showSessionStats 
              ? `🏃 ${distanceKm}km • ${sessionUnlockedCount} New Hexes`
              : `📍 ${name} • ${percentage}% Explored`}
          </Text>
        </BlurView>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 56, // Align at top
    alignSelf: 'center',
    zIndex: 100,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 8,
    elevation: 6,
  },
  pill: {
    backgroundColor: 'rgba(255, 255, 255, 0.95)',
    paddingHorizontal: 18,
    paddingVertical: 10,
    borderRadius: 24,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: '#e2e8f0',
  },
  text: {
    fontSize: 14,
    fontWeight: '800',
    color: '#0f172a',
    letterSpacing: 0.5,
  }
});
