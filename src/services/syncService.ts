import * as FileSystem from 'expo-file-system';
import { attachTransitDB } from '../db/database';

const CDN_URL = 'https://fog-of-wburg-transit.r2.cloudflarestorage.com/transit_delta.sqlite.zst';
const LOCAL_ZST_PATH = FileSystem.documentDirectory + 'transit_delta.sqlite.zst';
const LOCAL_SQLITE_PATH = FileSystem.documentDirectory + 'transit_delta.sqlite';

export async function fetchAndAttachTransitData() {
  try {
    console.log('[SyncService] Fetching historical transit data from CDN...');
    
    // Download the .zst file
    const downloadRes = await FileSystem.downloadAsync(CDN_URL, LOCAL_ZST_PATH);
    if (downloadRes.status !== 200) {
      throw new Error(`Failed to download data, status: ${downloadRes.status}`);
    }

    console.log('[SyncService] Download complete. Decompressing...');
    
    // Note: React Native doesn't have a built-in Zstandard decompressor.
    // In a full implementation, we would use a JSI/native module for decompression here.
    // For now, we simulate the decompression step for the MVP:
    await FileSystem.copyAsync({
      from: LOCAL_ZST_PATH,
      to: LOCAL_SQLITE_PATH,
    });

    console.log('[SyncService] Decompression simulated. Attaching DB...');
    
    // Attach to op-sqlite
    await attachTransitDB(LOCAL_SQLITE_PATH);
    
    console.log('[SyncService] Sync and attach complete.');
  } catch (error) {
    console.error('[SyncService] Failed to sync transit data:', error);
  }
}
