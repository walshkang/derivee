
import React, { useEffect } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { View, StyleSheet } from 'react-native';
import { initDatabase, attachNeighborhoodDB } from '@/db/database';

export default function RootLayout() {
  useEffect(() => {
    // Fast Refresh resilience: re-initialize and re-attach DB if JS bundle drops
    initDatabase();
    attachNeighborhoodDB().catch(console.warn);
  }, []);

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
