import React, { useState, useEffect } from 'react';
import { StyleSheet, Text, View, ScrollView, Pressable, Alert, TouchableOpacity } from 'react-native';
import { useExplorationStore } from '@/store/useExplorationStore';
import { PRIVACY_STATEMENT, exportSpatialDataJSON } from '@/utils/privacyExporter';
import * as DocumentPicker from 'expo-document-picker';
import { useRouter } from 'expo-router';
import { insertUnlockedHexes, insertTrackingSession, getAllTrackingSessions, TrackingSession, getNeighborhoodCompletion, NeighborhoodStat } from '@/db/database';
import { parseGPX, parseFIT } from '@/utils/workoutParser';

export default function ArchiveScreen() {
  const { unlockedHexes, resetExploration, addUnlockedHexes, triggerMacroReveal, setSelectedHistoricalRoute } = useExplorationStore();
  const [exportedStatus, setExportedStatus] = useState<string | null>(null);
  const [sessions, setSessions] = useState<TrackingSession[]>([]);
  const [neighborhoodStats, setNeighborhoodStats] = useState<NeighborhoodStat[]>([]);
  const [isNYCExpanded, setIsNYCExpanded] = useState(false);
  const router = useRouter();

  useEffect(() => {
    loadSessions();
  }, []);

  const loadSessions = () => {
    try {
      const data = getAllTrackingSessions();
      setSessions(data || []);
      const stats = getNeighborhoodCompletion();
      setNeighborhoodStats(stats || []);
    } catch (e) {
      console.warn('Failed to load tracking sessions or stats:', e);
    }
  };

  const handleUploadFile = async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: ['*/*'],
        copyToCacheDirectory: true,
      });

      if (result.canceled || !result.assets || result.assets.length === 0) {
        return;
      }

      const fileUri = result.assets[0].uri;
      const fileName = result.assets[0].name.toLowerCase();
      
      const response = await fetch(fileUri);
      
      let parsedData;
      if (fileName.endsWith('.fit')) {
        const arrayBuffer = await response.arrayBuffer();
        parsedData = await parseFIT(arrayBuffer);
      } else if (fileName.endsWith('.gpx')) {
        const text = await response.text();
        parsedData = await parseGPX(text);
      } else {
        Alert.alert('Unsupported File', 'Please upload a .gpx or .fit file.');
        return;
      }

      if (parsedData.hexes.length === 0) {
        Alert.alert('No Data Found', 'Could not extract any valid coordinates from this file.');
        return;
      }

      // Bulk insert into SQLite
      insertUnlockedHexes(parsedData.hexes);
      
      // Save session history
      const sessionId = `session_${Date.now()}`;
      insertTrackingSession({
        id: sessionId,
        name: fileName,
        started_at: parsedData.startedAt,
        hex_count: parsedData.hexes.length,
        distance_meters: parsedData.distanceMeters,
        duration_seconds: parsedData.durationSeconds,
        route_geojson: parsedData.routeGeoJSON,
      });

      // Refresh list
      loadSessions();
      
      // Update store
      const actuallyAddedCount = addUnlockedHexes(parsedData.hexes);

      // Trigger the macro reveal and switch tabs
      if (actuallyAddedCount > 0) {
        triggerMacroReveal(actuallyAddedCount);
        router.replace('/map');
      } else {
        Alert.alert('Import Complete', 'All coordinates in this file were already explored!');
      }
    } catch (err: any) {
      console.warn('Import error:', err);
      Alert.alert('Import Failed', err.message || 'Failed to parse the file.');
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

  const formatDistance = (meters: number) => {
    return (meters / 1000).toFixed(2) + ' km';
  };

  const formatDuration = (seconds: number) => {
    const m = Math.floor(seconds / 60);
    const h = Math.floor(m / 60);
    if (h > 0) {
      return `${h}h ${m % 60}m`;
    }
    return `${m}m`;
  };

  const formatDate = (timestamp: number) => {
    return new Date(timestamp).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    });
  };

  const cityTotalHexes = neighborhoodStats.reduce((acc, curr) => acc + curr.total_hexes, 0);
  const cityExploredHexes = neighborhoodStats.reduce((acc, curr) => acc + curr.explored_hexes, 0);
  const cityCompletion = cityTotalHexes > 0 ? ((cityExploredHexes / cityTotalHexes) * 100).toFixed(2) : '0.00';

  const sortedNeighborhoods = [...neighborhoodStats]
    .filter(n => n.explored_hexes > 0)
    .sort((a, b) => {
      const aPct = a.total_hexes > 0 ? (a.explored_hexes / a.total_hexes) : 0;
      const bPct = b.total_hexes > 0 ? (b.explored_hexes / b.total_hexes) : 0;
      return bPct - aPct;
    });

  return (
    <View style={styles.container}>
      {/* Header with Back Button */}
      <View style={styles.headerBar}>
        <TouchableOpacity 
          hitSlop={{ top: 20, bottom: 20, left: 20, right: 20 }} 
          style={styles.backButton}
          activeOpacity={0.6}
          onPress={() => {
            if (router.canGoBack()) {
              router.back();
            } else {
              router.replace('/map');
            }
          }}
        >
          <Text style={styles.backButtonText}>{'‹ Back'}</Text>
        </TouchableOpacity>
        <View style={styles.headerTitles}>
          <Text style={styles.headerTitle}>STATISTICS</Text>
          <Text style={styles.headerSubtitle}>Exploration Records & Discoveries</Text>
        </View>
      </View>
      <ScrollView style={{ flex: 1, zIndex: 1 }} contentContainerStyle={styles.contentContainer}>
        {/* Summary Cards */}
      <View style={styles.gridContainer}>
        <View style={styles.statCard}>
          <Text style={styles.statNumber}>{unlockedHexes.length}</Text>
          <Text style={styles.statLabel}>Total Hexes Unlocked</Text>
        </View>

        <View style={styles.statCard}>
          <Text style={styles.statNumber}>{cityCompletion}%</Text>
          <Text style={styles.statLabel}>City-Wide Complete</Text>
        </View>
      </View>

      {/* Cities Section */}
      <View style={styles.sectionCard}>
        <Text style={styles.sectionHeader}>Cities</Text>
        
        {/* NYC Card */}
        <View style={styles.cityCard}>

          <TouchableOpacity 
            style={styles.cityHeader}
            activeOpacity={0.7}
            onPress={() => setIsNYCExpanded(!isNYCExpanded)}
          >
            <View>
              <Text style={styles.cityName}>New York City</Text>
              <Text style={styles.cityProgress}>{cityCompletion}% Complete</Text>
            </View>
            <Text style={styles.expandIcon}>{isNYCExpanded ? '▼' : '▶'}</Text>
          </TouchableOpacity>


          {/* Neighborhood Leaderboard Dropdown */}
          {isNYCExpanded && (
            <View style={styles.neighborhoodList}>
              <Text style={styles.neighborhoodHeader}>Neighborhoods</Text>
              
              {sortedNeighborhoods.length === 0 ? (
                <View style={styles.poiEmptyState}>
                  <Text style={styles.poiEmptyTitle}>No Neighborhoods Explored</Text>
                  <Text style={styles.poiEmptySub}>Walk around to unlock your first NYC neighborhood.</Text>
                </View>
              ) : (
                sortedNeighborhoods.map((n, index) => {
                  const pct = n.total_hexes > 0 ? ((n.explored_hexes / n.total_hexes) * 100).toFixed(2) : '0.00';
                  return (
                    <View key={n.id} style={styles.leaderboardItem}>
                      <Text style={styles.leaderboardRank}>{index + 1}</Text>
                      <Text style={styles.leaderboardName}>{n.name}</Text>
                      <Text style={styles.leaderboardPct}>{pct}%</Text>
                    </View>
                  );
                })
              )}
            </View>
          )}
        </View>
      </View>

      {/* The Historian Import (Wave 10) */}
      <View style={styles.sectionCard}>
        <Text style={styles.sectionHeader}>The Historian Import</Text>
        <Text style={styles.privacyBody}>
          Import historical tracking data to instantly uncover vast regions of the map.
        </Text>
        
        <TouchableOpacity style={styles.importButtonPrimary} activeOpacity={0.8} onPress={handleUploadFile}>
          <Text style={styles.importButtonText}>UPLOAD GPX/FIT FILE</Text>
        </TouchableOpacity>

        <View style={styles.placeholderRow}>
          <TouchableOpacity style={styles.importButtonSecondary} activeOpacity={0.7} onPress={() => Alert.alert('Coming Soon', 'Apple HealthKit integration is planned for a future update.')}>
            <Text style={styles.importButtonSecondaryText}>APPLE HEALTHKIT</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.importButtonSecondary} activeOpacity={0.7} onPress={() => Alert.alert('Coming Soon', 'Strava integration is planned for a future update.')}>
            <Text style={styles.importButtonSecondaryText}>CONNECT STRAVA</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* Workout History List */}
      {sessions.length > 0 && (
        <View style={styles.sectionCard}>
          <Text style={styles.sectionHeader}>Past Workouts</Text>
          {sessions.map((session) => (
            <TouchableOpacity 
              key={session.id} 
              style={styles.sessionItem}
              activeOpacity={0.7}
              onPress={() => {
                if (session.route_geojson) {
                  try {
                    const feature = JSON.parse(session.route_geojson);
                    setSelectedHistoricalRoute(feature);
                    router.replace('/map');
                  } catch (e) {
                    console.error("Invalid GeoJSON in session");
                  }
                } else {
                  Alert.alert('No Route Data', 'This session does not contain route data to display.');
                }
              }}
            >
              <View style={styles.sessionHeaderRow}>
                <Text style={styles.sessionDate}>{formatDate(session.started_at)}</Text>
                <Text style={styles.sessionName} numberOfLines={1}>{session.name}</Text>
              </View>
              <View style={styles.sessionMetricsRow}>
                <View style={styles.sessionMetric}>
                  <Text style={styles.sessionMetricValue}>{formatDistance(session.distance_meters)}</Text>
                  <Text style={styles.sessionMetricLabel}>Distance</Text>
                </View>
                <View style={styles.sessionMetric}>
                  <Text style={styles.sessionMetricValue}>{formatDuration(session.duration_seconds)}</Text>
                  <Text style={styles.sessionMetricLabel}>Time</Text>
                </View>
                <View style={styles.sessionMetric}>
                  <Text style={styles.sessionMetricValue}>{session.hex_count}</Text>
                  <Text style={styles.sessionMetricLabel}>Hexes</Text>
                </View>
              </View>
            </TouchableOpacity>
          ))}
        </View>
      )}

      {/* Offline-First Privacy & Data Sovereignty Card */}
      <View style={styles.privacyCard}>
        <View style={styles.privacyHeaderRow}>
          <Text style={styles.privacyIcon}>🔒</Text>
          <Text style={styles.privacyTitle}>Offline-First Privacy Guarantee</Text>
        </View>
        <Text style={styles.privacyBody}>{PRIVACY_STATEMENT}</Text>
        
        <TouchableOpacity style={styles.exportButton} activeOpacity={0.8} onPress={handleExportData}>
          <Text style={styles.exportButtonText}>EXPORT SPATIAL LOG (JSON)</Text>
        </TouchableOpacity>
        {exportedStatus && (
          <Text style={styles.exportStatusText}>{exportedStatus}</Text>
        )}
      </View>

      {/* Actions */}
      <TouchableOpacity style={styles.resetButton} activeOpacity={0.7} onPress={resetExploration}>
        <Text style={styles.resetButtonText}>RESET EXPLORATION DATA</Text>
      </TouchableOpacity>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8fafc',
  },
  headerBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 60,
    paddingHorizontal: 20,
    paddingBottom: 10,
    backgroundColor: '#f8fafc',
    borderBottomWidth: 1,
    borderBottomColor: '#e2e8f0',
    zIndex: 100,
    elevation: 10,
  },
  backButton: {
    paddingRight: 16,
    paddingVertical: 8,
  },
  backButtonText: {
    fontSize: 16,
    fontWeight: '700',
    color: '#0284c7',
  },
  headerTitles: {
    flex: 1,
  },
  contentContainer: {
    padding: 20,
    paddingBottom: 40,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '800',
    color: '#0f172a',
    letterSpacing: 2,
  },
  headerSubtitle: {
    fontSize: 14,
    color: '#64748b',
  },
  gridContainer: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 20,
  },
  statCard: {
    flex: 1,
    backgroundColor: '#ffffff',
    borderRadius: 12,
    padding: 16,
    borderWidth: 1,
    borderColor: '#e2e8f0',
  },
  statNumber: {
    fontSize: 28,
    fontWeight: '800',
    color: '#0284c7',
    marginBottom: 4,
  },
  statLabel: {
    fontSize: 12,
    color: '#64748b',
    fontWeight: '600',
  },
  sectionCard: {
    backgroundColor: '#ffffff',
    borderRadius: 12,
    padding: 18,
    borderWidth: 1,
    borderColor: '#e2e8f0',
    marginBottom: 20,
  },
  sectionHeader: {
    fontSize: 16,
    fontWeight: '700',
    color: '#0f172a',
    marginBottom: 12,
  },
  progressBarBg: {
    height: 10,
    backgroundColor: '#f1f5f9',
    borderRadius: 5,
    overflow: 'hidden',
    marginBottom: 8,
    borderWidth: 1,
    borderColor: '#e2e8f0',
  },
  progressBarFill: {
    height: '100%',
    backgroundColor: '#10b981',
    borderRadius: 5,
  },
  progressText: {
    fontSize: 13,
    color: '#64748b',
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
    color: '#334155',
    marginBottom: 4,
  },
  poiEmptySub: {
    fontSize: 13,
    color: '#64748b',
    textAlign: 'center',
    maxWidth: 240,
    lineHeight: 18,
  },
  resetButton: {
    backgroundColor: '#fef2f2',
    borderRadius: 10,
    paddingVertical: 14,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#fecaca',
    marginTop: 8,
  },
  resetButtonText: {
    color: '#ef4444',
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: 1,
  },
  privacyCard: {
    backgroundColor: '#ffffff',
    borderRadius: 12,
    padding: 18,
    borderWidth: 1,
    borderColor: '#e2e8f0',
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
    color: '#0284c7',
  },
  privacyBody: {
    fontSize: 13,
    color: '#64748b',
    lineHeight: 19,
    marginBottom: 14,
  },
  exportButton: {
    backgroundColor: '#0f172a',
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
    color: '#10b981',
    textAlign: 'center',
    fontWeight: '600',
  },
  importButtonPrimary: {
    backgroundColor: '#fbbf24', // Warm morning sun hue
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
    backgroundColor: '#f8fafc',
    borderRadius: 8,
    paddingVertical: 10,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#e2e8f0',
  },
  importButtonSecondaryText: {
    color: '#475569',
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  sessionItem: {
    backgroundColor: '#f8fafc',
    borderRadius: 8,
    padding: 16,
    marginBottom: 10,
    borderWidth: 1,
    borderColor: '#e2e8f0',
  },
  sessionHeaderRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  sessionDate: {
    fontSize: 12,
    fontWeight: '600',
    color: '#64748b',
  },
  sessionName: {
    fontSize: 12,
    color: '#94a3b8',
    flex: 1,
    textAlign: 'right',
    marginLeft: 10,
  },
  sessionMetricsRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  sessionMetric: {
    flex: 1,
  },
  sessionMetricValue: {
    fontSize: 18,
    fontWeight: '700',
    color: '#0f172a',
    marginBottom: 2,
  },
  sessionMetricLabel: {
    fontSize: 11,
    color: '#64748b',
    fontWeight: '600',
  },
  leaderboardItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#e2e8f0',
  },
  leaderboardRank: {
    width: 24,
    fontSize: 14,
    fontWeight: '700',
    color: '#94a3b8',
  },
  leaderboardName: {
    flex: 1,
    fontSize: 15,
    fontWeight: '600',
    color: '#334155',
  },
  leaderboardPct: {
    fontSize: 15,
    fontWeight: '800',
    color: '#0284c7',
  },
  cityCard: {
    backgroundColor: '#f8fafc',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#e2e8f0',
    overflow: 'hidden',
  },
  cityHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 16,
    backgroundColor: '#ffffff',
    borderBottomWidth: 1,
    borderBottomColor: '#e2e8f0',
  },
  cityName: {
    fontSize: 18,
    fontWeight: '800',
    color: '#0f172a',
  },
  cityProgress: {
    fontSize: 13,
    color: '#64748b',
    fontWeight: '600',
    marginTop: 2,
  },
  expandIcon: {
    fontSize: 16,
    color: '#94a3b8',
  },

  neighborhoodList: {
    padding: 16,
    backgroundColor: '#ffffff',
  },
  neighborhoodHeader: {
    fontSize: 14,
    fontWeight: '700',
    color: '#64748b',
    marginBottom: 8,
  },
});
