
import React, { useEffect, useState } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { View, StyleSheet } from 'react-native';
import * as SplashScreen from 'expo-splash-screen';
import { initDatabase, attachNeighborhoodDB, backfillLegacyGeoJSONCache } from '@/db/database';
import { useExplorationStore } from '@/store/useExplorationStore';
import { usePOIStore } from '@/store/usePOIStore';
import { initAppStateListener } from '@/services/appStateListener';

// Keep native splash screen visible while migrations and initial load execute
SplashScreen.preventAutoHideAsync().catch(() => {});

export default function RootLayout() {
  const [appIsReady, setAppIsReady] = useState(false);

  useEffect(() => {
    // 5. Initialize AppState listener for delta-buffer auto commit
    const cleanupAppStateListener = initAppStateListener();

    async function prepareApp() {
      try {
        // 1. Initialize op-sqlite database & run schema migrations
        initDatabase();

        // 2. Perform legacy user data backfill behind splash screen
        await backfillLegacyGeoJSONCache();

        // 3. Attach auxiliary databases
        await attachNeighborhoodDB();

        // 4. Hydrate Zustand stores
        useExplorationStore.getState().loadUnlockedHexes();
        usePOIStore.getState().loadPOIs();
      } catch (e) {
        console.warn('[RootLayout] Error during startup migration gate:', e);
      } finally {
        setAppIsReady(true);
        await SplashScreen.hideAsync().catch(() => {});
      }
    }

    prepareApp();

    return () => {
      cleanupAppStateListener();
    };
  }, []);

  if (!appIsReady) {
    return null;
  }

  return (
    <View style={styles.container}>
      <StatusBar style="light" />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: '#0d1117' },
          animation: 'fade',
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0d1117',
  },
});
