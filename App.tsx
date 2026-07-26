import React from 'react';
import { StyleSheet, Text, View, Pressable } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { useExplorationStore } from '@/store/useExplorationStore';

export default function App() {
  const { isExploring, currentLocation, unlockedHexes, setIsExploring, setCurrentLocation, addUnlockedHexes, resetExploration } =
    useExplorationStore();

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
      <StatusBar style="light" />
      <Text style={styles.title}>Fog of Wburg</Text>
      <Text style={styles.subtitle}>Wave 1: Foundation & Zustand State</Text>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Exploration Status</Text>
        <Text style={styles.label}>
          Status: <Text style={styles.value}>{isExploring ? 'ACTIVE 🟢' : 'INACTIVE 🔴'}</Text>
        </Text>
        <Text style={styles.label}>
          Location:{' '}
          <Text style={styles.value}>
            {currentLocation
              ? `${currentLocation.latitude.toFixed(4)}, ${currentLocation.longitude.toFixed(4)}`
              : 'None'}
          </Text>
        </Text>
        <Text style={styles.label}>
          Unlocked Hexes: <Text style={styles.value}>{unlockedHexes.length}</Text>
        </Text>
        {unlockedHexes.length > 0 && (
          <Text style={styles.hexSample}>Latest: {unlockedHexes[unlockedHexes.length - 1]}</Text>
        )}
      </View>

      <View style={styles.buttonContainer}>
        <Pressable
          style={[styles.button, isExploring ? styles.buttonActive : styles.buttonInactive]}
          onPress={handleToggleExploration}
        >
          <Text style={styles.buttonText}>{isExploring ? 'Stop Exploring' : 'Start Exploring'}</Text>
        </Pressable>

        <Pressable style={[styles.button, styles.buttonReset]} onPress={resetExploration}>
          <Text style={styles.buttonText}>Reset State</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0d1117',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#ffffff',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 14,
    color: '#8b949e',
    marginBottom: 32,
  },
  card: {
    width: '100%',
    backgroundColor: '#161b22',
    borderRadius: 12,
    padding: 20,
    borderWidth: 1,
    borderColor: '#30363d',
    marginBottom: 24,
  },
  cardTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#58a6ff',
    marginBottom: 16,
  },
  label: {
    fontSize: 15,
    color: '#c9d1d9',
    marginBottom: 8,
  },
  value: {
    fontWeight: 'bold',
    color: '#ffffff',
  },
  hexSample: {
    fontSize: 12,
    color: '#8b949e',
    fontFamily: 'monospace',
    marginTop: 8,
  },
  buttonContainer: {
    width: '100%',
    gap: 12,
  },
  button: {
    paddingVertical: 14,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonInactive: {
    backgroundColor: '#238636',
  },
  buttonActive: {
    backgroundColor: '#da3633',
  },
  buttonReset: {
    backgroundColor: '#21262d',
    borderWidth: 1,
    borderColor: '#30363d',
  },
  buttonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '600',
  },
});
