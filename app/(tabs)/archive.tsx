import React, { useState } from 'react';
import { StyleSheet, Text, View, ScrollView, Pressable, Alert } from 'react-native';
import { useExplorationStore } from '@/store/useExplorationStore';
import { PRIVACY_STATEMENT, exportSpatialDataJSON } from '@/utils/privacyExporter';
import * as DocumentPicker from 'expo-document-picker';
import { useRouter } from 'expo-router';
import { insertUnlockedHexes } from '@/db/database';
import { parseGPXToH3 } from '@/utils/gpxParser';

export default function ArchiveScreen() {
  const { unlockedHexes, resetExploration, addUnlockedHexes, triggerMacroReveal } = useExplorationStore();
  const [exportedStatus, setExportedStatus] = useState<string | null>(null);
  const router = useRouter();

  const handleUploadGPX = async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: ['*/*'],
        copyToCacheDirectory: true,
      });

      if (result.canceled || !result.assets || result.assets.length === 0) {
        return;
      }

      const fileUri = result.assets[0].uri;
      const response = await fetch(fileUri);
      const fileText = await response.text();

      const newHexes = parseGPXToH3(fileText);
      if (newHexes.length === 0) {
        Alert.alert('No Data Found', 'Could not extract any valid coordinates from this file.');
        return;
      }

      // Bulk insert into SQLite
      insertUnlockedHexes(newHexes);
      
      // Update store
      const actuallyAddedCount = addUnlockedHexes(newHexes);

      // Trigger the macro reveal and switch tabs
      if (actuallyAddedCount > 0) {
        triggerMacroReveal(actuallyAddedCount);
        router.replace('/(tabs)/map');
      } else {
        Alert.alert('Import Complete', 'All coordinates in this file were already explored!');
      }
    } catch (err: any) {
      console.warn('GPX import error:', err);
      Alert.alert('Import Failed', err.message || 'Failed to parse the GPX file.');
    }
  };

  const handleExportData = () => {
    const exportedJSON = exportSpatialDataJSON(unlockedHexes, unlockedHexes.length);
    setExportedStatus(`Exported ${unlockedHexes.length} hexes successfully.`);
    Alert.alert(
      'Spatial Data Exported',
      `Exported ${unlockedHexes.length} spatial records in JSON format.\n\nOffline-First Guarantee: 0 bytes sent off-device.`
    );
  };

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

      {/* The Historian Import (Wave 10) */}
      <View style={styles.sectionCard}>
        <Text style={styles.sectionHeader}>The Historian Import</Text>
        <Text style={styles.privacyBody}>
          Import historical tracking data to instantly uncover vast regions of the map.
        </Text>
        
        <Pressable style={styles.importButtonPrimary} onPress={handleUploadGPX}>
          <Text style={styles.importButtonText}>UPLOAD GPX/FIT FILE</Text>
        </Pressable>

        <View style={styles.placeholderRow}>
          <Pressable style={styles.importButtonSecondary} onPress={() => Alert.alert('Coming Soon', 'Apple HealthKit integration is planned for a future update.')}>
            <Text style={styles.importButtonSecondaryText}>APPLE HEALTHKIT</Text>
          </Pressable>
          <Pressable style={styles.importButtonSecondary} onPress={() => Alert.alert('Coming Soon', 'Strava integration is planned for a future update.')}>
            <Text style={styles.importButtonSecondaryText}>CONNECT STRAVA</Text>
          </Pressable>
        </View>
      </View>

      {/* Offline-First Privacy & Data Sovereignty Card */}
      <View style={styles.privacyCard}>
        <View style={styles.privacyHeaderRow}>
          <Text style={styles.privacyIcon}>🔒</Text>
          <Text style={styles.privacyTitle}>Offline-First Privacy Guarantee</Text>
        </View>
        <Text style={styles.privacyBody}>{PRIVACY_STATEMENT}</Text>
        
        <Pressable style={styles.exportButton} onPress={handleExportData}>
          <Text style={styles.exportButtonText}>EXPORT SPATIAL LOG (JSON)</Text>
        </Pressable>
        {exportedStatus && (
          <Text style={styles.exportStatusText}>{exportedStatus}</Text>
        )}
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
  privacyCard: {
    backgroundColor: '#161b22',
    borderRadius: 12,
    padding: 18,
    borderWidth: 1,
    borderColor: '#30363d',
    marginBottom: 20,
  },
  privacyHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 10,
  },
  privacyIcon: {
    fontSize: 18,
    marginRight: 8,
  },
  privacyTitle: {
    fontSize: 15,
    fontWeight: '700',
    color: '#58a6ff',
  },
  privacyBody: {
    fontSize: 13,
    color: '#8b949e',
    lineHeight: 19,
    marginBottom: 14,
  },
  exportButton: {
    backgroundColor: '#1f6feb',
    borderRadius: 8,
    paddingVertical: 12,
    alignItems: 'center',
  },
  exportButtonText: {
    color: '#ffffff',
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 1,
  },
  exportStatusText: {
    marginTop: 8,
    fontSize: 12,
    color: '#3fb950',
    textAlign: 'center',
    fontWeight: '600',
  },
  importButtonPrimary: {
    backgroundColor: '#eab308', // Warm morning sun hue
    borderRadius: 8,
    paddingVertical: 12,
    alignItems: 'center',
    marginBottom: 10,
  },
  importButtonText: {
    color: '#000000',
    fontSize: 13,
    fontWeight: '800',
    letterSpacing: 1,
  },
  placeholderRow: {
    flexDirection: 'row',
    gap: 10,
  },
  importButtonSecondary: {
    flex: 1,
    backgroundColor: '#21262d',
    borderRadius: 8,
    paddingVertical: 10,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#30363d',
  },
  importButtonSecondaryText: {
    color: '#8b949e',
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
});
