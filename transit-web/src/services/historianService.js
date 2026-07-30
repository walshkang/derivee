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

  async getSparklineData(routeId, stopId) {
    if (!db) await this.init();
    if (!db) return [];

    try {
      const res = db.exec(`
        SELECT day_of_week, hour_of_day, on_time_pct 
        FROM stop_reliability_hourly 
        WHERE route_id = '${routeId}' AND stop_id = '${stopId}' 
        ORDER BY day_of_week, hour_of_day
      `);
      
      if (res.length === 0 || !res[0].values || res[0].values.length === 0) {
        return [];
      }

      // Initialize array of 168 points to 0
      const dataPoints = new Array(168).fill(0);
      
      const values = res[0].values;
      let hasData = false;
      for (const row of values) {
        const dayOfWeek = row[0];
        const hourOfDay = row[1];
        const onTimePct = row[2];
        const index = (dayOfWeek * 24) + hourOfDay;
        if (index >= 0 && index < 168) {
          dataPoints[index] = onTimePct;
          hasData = true;
        }
      }

      if (!hasData) {
        // Fallback dummy data for MVP demonstration when DB is empty for a stop
        return Array.from({ length: 168 }, (_, i) => 70 + Math.sin(i / 12) * 20 + Math.random() * 10);
      }

      return dataPoints;
    } catch (e) {
      console.error('Sparkline Query failed:', e);
      return [];
    }
  }
};
