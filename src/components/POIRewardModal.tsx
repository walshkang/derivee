import React, { useEffect } from 'react';
import { StyleSheet, Text, View, Pressable, Modal } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withSpring,
  withSequence,
  withDelay,
} from 'react-native-reanimated';
import { POI } from '../db/poiQueries';

interface POIRewardModalProps {
  poi: POI | null;
  onClose: () => void;
}

export function POIRewardModal({ poi, onClose }: POIRewardModalProps) {
  const opacity = useSharedValue(0);
  const scale = useSharedValue(0.8);
  const translateY = useSharedValue(20);

  useEffect(() => {
    if (poi) {
      opacity.value = withTiming(1, { duration: 300 });
      scale.value = withSpring(1, { damping: 12, stiffness: 90 });
      translateY.value = withSpring(0, { damping: 12, stiffness: 90 });
    } else {
      opacity.value = withTiming(0, { duration: 200 });
      scale.value = withTiming(0.8, { duration: 200 });
      translateY.value = withTiming(20, { duration: 200 });
    }
  }, [poi, opacity, scale, translateY]);

  const animatedStyle = useAnimatedStyle(() => ({
    opacity: opacity.value,
    transform: [{ scale: scale.value }, { translateY: translateY.value }],
  }));

  const backdropStyle = useAnimatedStyle(() => ({
    opacity: opacity.value,
  }));

  if (!poi) return null;

  return (
    <Modal transparent visible={true} animationType="none">
      <View style={styles.overlay}>
        <Animated.View style={[styles.backdrop, backdropStyle]} />
        <Animated.View style={[styles.container, animatedStyle]}>
          <Text style={styles.title}>NEW DISCOVERY!</Text>
          <Text style={styles.poiName}>{poi.name}</Text>
          <Text style={styles.poiDescription}>{poi.description}</Text>
          
          <View style={styles.rewardContainer}>
            <Text style={styles.rewardTitle}>Reward Unlocked</Text>
            <Text style={styles.rewardValue}>{poi.reward_type}</Text>
          </View>

          <Pressable style={styles.button} onPress={onClose}>
            <Text style={styles.buttonText}>ACKNOWLEDGE</Text>
          </Pressable>
        </Animated.View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  backdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.7)',
  },
  container: {
    width: '85%',
    backgroundColor: 'rgba(22, 27, 34, 0.95)',
    borderRadius: 20,
    padding: 24,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#30363d',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.5,
    shadowRadius: 20,
    elevation: 10,
  },
  title: {
    color: '#58a6ff',
    fontSize: 14,
    fontWeight: '800',
    letterSpacing: 2,
    marginBottom: 8,
  },
  poiName: {
    color: '#ffffff',
    fontSize: 24,
    fontWeight: '700',
    textAlign: 'center',
    marginBottom: 12,
  },
  poiDescription: {
    color: '#8b949e',
    fontSize: 15,
    lineHeight: 22,
    textAlign: 'center',
    marginBottom: 24,
  },
  rewardContainer: {
    backgroundColor: '#0d1117',
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#30363d',
    marginBottom: 24,
    alignItems: 'center',
    width: '100%',
  },
  rewardTitle: {
    color: '#8b949e',
    fontSize: 11,
    fontWeight: '600',
    textTransform: 'uppercase',
    marginBottom: 4,
  },
  rewardValue: {
    color: '#f2cc60',
    fontSize: 16,
    fontWeight: '700',
  },
  button: {
    backgroundColor: '#238636',
    paddingVertical: 14,
    paddingHorizontal: 32,
    borderRadius: 12,
    width: '100%',
    alignItems: 'center',
  },
  buttonText: {
    color: '#ffffff',
    fontSize: 15,
    fontWeight: '800',
    letterSpacing: 1,
  },
});
