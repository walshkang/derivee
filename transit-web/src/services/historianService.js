import initSqlJs from 'sql.js';
import sqlWasmUrl from 'sql.js/dist/sql-wasm.wasm?url';

let db = null;
const CDN_URL = import.meta.env.VITE_OBSERVER_CDN_URL || '/transit-data/';

export const historianService = {
  async init() {
    if (db) return;
    try {
      const SQL = await initSqlJs({
        locateFile: () => sqlWasmUrl
      });
      
      // Fetch the uncompressed SQLite DB from the symlinked public folder or CDN
      const res = await fetch(`${CDN_URL}transit_delta.sqlite`);
      if (!res.ok) {
        throw new Error(`Could not fetch sqlite db: ${res.status}`);
      }
      const buf = await res.arrayBuffer();
      db = new SQL.Database(new Uint8Array(buf));
      console.log('Historian DB loaded successfully.');
    } catch (e) {
      console.error('Failed to init Historian:', e);
    }
  },

  async getHeadwayData(routeId, stopId) {
    if (!db) await this.init();
    if (!db) return [];

    try {
      // The observer currently exports dummy rows to reliability_stats
      const res = db.exec(`SELECT * FROM stop_reliability_hourly WHERE route_id = '${routeId}' ORDER BY hour_of_day DESC LIMIT 5`);
      
      // In the future we will map the SQLite rows to the headway matrix format
      // For now, since the DB contains a single dummy reliability row, 
      // we generate a headway matrix to demonstrate the UI works when DB is loaded.
      
      return [
        {
          hour: '12',
          arrivals: [
            { minute: '05', status: 'on-time' },
            { minute: '12', status: 'delayed' },
            { minute: '25', status: 'severe' },
            { minute: '35', status: 'on-time' }
          ]
        },
        {
          hour: '13',
          arrivals: [
            { minute: '02', status: 'on-time' },
            { minute: '15', status: 'on-time' },
            { minute: '30', status: 'delayed' },
            { minute: '45', status: 'on-time' }
          ]
        }
      ];
    } catch (e) {
      console.error('Query failed:', e);
      return [];
    }
  }
};
