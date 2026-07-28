import React, { useEffect, useState, useRef } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { BlurView } from 'expo-blur';
import { useExplorationStore } from '@/store/useExplorationStore';

export function ContextualStatPill() {
  const { currentNeighborhoodStat, sessionUnlockedCount } = useExplorationStore();
  const [isActiveState, setIsActiveState] = useState(false);
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);

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

  if (!currentNeighborhoodStat) {
    return null;
  }

  const { name, explored_hexes, total_hexes } = currentNeighborhoodStat;
  // Guard against divide by zero
  const percentage = total_hexes > 0 ? Math.floor((explored_hexes / total_hexes) * 100) : 0;

  return (
    <View style={styles.container} pointerEvents="none">
      <BlurView intensity={70} tint="light" style={styles.pill}>
        <Text style={styles.text}>
          {isActiveState 
            ? `🔥 ${sessionUnlockedCount} New Hexes Unlocked`
            : `📍 ${name} • ${percentage}% Explored`}
        </Text>
      </BlurView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 60, // Align approximately below safe area, similar level to top navigation bar
    alignSelf: 'center',
    zIndex: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 6,
    elevation: 4,
  },
  pill: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 24,
    overflow: 'hidden',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255, 255, 255, 0.5)',
  },
  text: {
    fontSize: 14,
    fontWeight: '700',
    color: '#0f172a',
    letterSpacing: 0.5,
  }
});
