import React from 'react';
import { StyleSheet, Text, View, ScrollView, Pressable } from 'react-native';
import { useExplorationStore } from '@/store/useExplorationStore';

export default function ArchiveScreen() {
  const { unlockedHexes, resetExploration } = useExplorationStore();

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      <Text style={styles.headerTitle}>THE ARCHIVE</Text>
      <Text style={styles.headerSubtitle}>Exploration Records & Discoveries</Text>

      {/* Summary Cards */}
      <View style={styles.gridContainer}>
        <View style={styles.statCard}>
          <Text style={styles.statNumber}>{unlockedHexes.length}</Text>
          <Text style={styles.statLabel}>Total Hexes Unlocked</Text>
        </View>

        <View style={styles.statCard}>
          <Text style={styles.statNumber}>
            {unlockedHexes.length > 0 ? '1' : '0'}
          </Text>
          <Text style={styles.statLabel}>Active Zones</Text>
        </View>
      </View>

      {/* Micro Metrics Section */}
      <View style={styles.sectionCard}>
        <Text style={styles.sectionHeader}>Williamsburg Progress</Text>
        <View style={styles.progressBarBg}>
          <View
            style={[
              styles.progressBarFill,
              { width: `${Math.min(unlockedHexes.length * 10, 100)}%` },
            ]}
          />
        </View>
        <Text style={styles.progressText}>
          {unlockedHexes.length > 0 ? `${unlockedHexes.length * 2}% Uncovered` : '0% Uncovered'}
        </Text>
      </View>

      {/* POI Discovery Gallery Placeholder */}
      <View style={styles.sectionCard}>
        <Text style={styles.sectionHeader}>Discovered Waypoints</Text>
        <View style={styles.poiEmptyState}>
          <Text style={styles.poiIcon}>🏛️</Text>
          <Text style={styles.poiEmptyTitle}>No Waypoints Unlocked</Text>
          <Text style={styles.poiEmptySub}>
            Walk into unexplored hexagons to unlock historic points of interest and POIs.
          </Text>
        </View>
      </View>

      {/* Actions */}
      <Pressable style={styles.resetButton} onPress={resetExploration}>
        <Text style={styles.resetButtonText}>RESET EXPLORATION DATA</Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0d1117',
  },
  contentContainer: {
    padding: 20,
    paddingTop: 64,
    paddingBottom: 40,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '800',
    color: '#ffffff',
    letterSpacing: 2,
  },
  headerSubtitle: {
    fontSize: 14,
    color: '#8b949e',
    marginBottom: 24,
  },
  gridContainer: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 20,
  },
  statCard: {
    flex: 1,
    backgroundColor: '#161b22',
    borderRadius: 12,
    padding: 16,
    borderWidth: 1,
    borderColor: '#30363d',
  },
  statNumber: {
    fontSize: 28,
    fontWeight: '800',
    color: '#58a6ff',
    marginBottom: 4,
  },
  statLabel: {
    fontSize: 12,
    color: '#8b949e',
    fontWeight: '600',
  },
  sectionCard: {
    backgroundColor: '#161b22',
    borderRadius: 12,
    padding: 18,
    borderWidth: 1,
    borderColor: '#30363d',
    marginBottom: 20,
  },
  sectionHeader: {
    fontSize: 16,
    fontWeight: '700',
    color: '#ffffff',
    marginBottom: 12,
  },
  progressBarBg: {
    height: 10,
    backgroundColor: '#0d1117',
    borderRadius: 5,
    overflow: 'hidden',
    marginBottom: 8,
    borderWidth: 1,
    borderColor: '#30363d',
  },
  progressBarFill: {
    height: '100%',
    backgroundColor: '#3fb950',
    borderRadius: 5,
  },
  progressText: {
    fontSize: 13,
    color: '#8b949e',
    fontWeight: '600',
  },
  poiEmptyState: {
    alignItems: 'center',
    paddingVertical: 20,
  },
  poiIcon: {
    fontSize: 36,
    marginBottom: 8,
  },
  poiEmptyTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#c9d1d9',
    marginBottom: 4,
  },
  poiEmptySub: {
    fontSize: 13,
    color: '#8b949e',
    textAlign: 'center',
    maxWidth: 240,
    lineHeight: 18,
  },
  resetButton: {
    backgroundColor: '#21262d',
    borderRadius: 10,
    paddingVertical: 14,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#30363d',
    marginTop: 8,
  },
  resetButtonText: {
    color: '#f85149',
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: 1,
  },
});
