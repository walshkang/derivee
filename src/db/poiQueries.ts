import { getDb } from './database';
import { coordToH3 } from '../utils/h3Utils';

export interface POI {
  id: string;
  name: string;
  description: string;
  latitude: number;
  longitude: number;
  h3_index: string;
  discovered: boolean;
  reward_type: string;
}

const MOCK_POIS = [
  {
    id: 'poi_1',
    name: 'Domino Park',
    description: 'A beautiful waterfront park built on the former Domino Sugar Refinery site.',
    latitude: 40.7153,
    longitude: -73.9678,
    reward_type: 'Silver Coin',
  },
  {
    id: 'poi_2',
    name: 'McCarren Park',
    description: 'A vibrant community hub featuring sports fields, a pool, and weekend farmer markets.',
    latitude: 40.7208,
    longitude: -73.9515,
    reward_type: 'Gold Coin',
  },
  {
    id: 'poi_3',
    name: "L'Industrie Pizzeria",
    description: 'Some of the best slices in Williamsburg, combining NY style with Italian ingredients.',
    latitude: 40.7116,
    longitude: -73.9578,
    reward_type: 'Pizza Slice Badge',
  },
  {
    id: 'poi_4',
    name: 'Brooklyn Brewery',
    description: 'Iconic brewery offering tours and a bustling tasting room.',
    latitude: 40.7215,
    longitude: -73.9575,
    reward_type: 'Beer Pint Badge',
  },
  {
    id: 'poi_5',
    name: 'Marsha P. Johnson State Park',
    description: 'Riverfront park offering stunning views of the Manhattan skyline.',
    latitude: 40.7212,
    longitude: -73.9616,
    reward_type: 'Sunset Badge',
  }
];

/**
 * Seeds the database with mock Williamsburg POIs if none exist.
 */
export function seedPOIs(): void {
  const db = getDb();
  const countResult = db.execute('SELECT COUNT(*) as count FROM pois;');
  
  let count = 0;
  if (countResult && countResult.rows && countResult.rows.length > 0) {
    const row: any = Array.isArray(countResult.rows) ? countResult.rows[0] : (countResult.rows as any)._array?.[0] || (countResult.rows as any).item?.(0);
    count = row ? (row.count ?? row['COUNT(*)'] ?? 0) : 0;
  }

  if (count === 0) {
    MOCK_POIS.forEach(poi => {
      // Calculate h3_index right before insertion using our shared utility
      const h3Index = coordToH3(poi.latitude, poi.longitude);
      
      db.execute(
        `INSERT INTO pois (id, name, description, latitude, longitude, h3_index, discovered, reward_type) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?);`,
        [poi.id, poi.name, poi.description, poi.latitude, poi.longitude, h3Index, 0, poi.reward_type]
      );
    });
    console.log('Seeded mock POIs into the database.');
  }
}

/**
 * Retrieves all POIs from the database.
 */
export function getAllPOIs(): POI[] {
  const db = getDb();
  const result = db.execute('SELECT * FROM pois;');
  
  let rows: any[] = [];
  if (result && result.rows) {
    if (Array.isArray(result.rows)) {
      rows = result.rows;
    } else if (Array.isArray((result.rows as any)._array)) {
      rows = (result.rows as any)._array;
    } else if (typeof (result.rows as any).item === 'function') {
      const len = (result.rows as any).length || 0;
      for (let i = 0; i < len; i++) {
        rows.push((result.rows as any).item(i));
      }
    }
  }

  return rows.map(r => ({
    ...r,
    discovered: Boolean(r.discovered)
  })) as POI[];
}

/**
 * Marks a POI as discovered in the database.
 */
export function markPOIDiscovered(id: string): void {
  const db = getDb();
  db.execute('UPDATE pois SET discovered = 1 WHERE id = ?;', [id]);
}
