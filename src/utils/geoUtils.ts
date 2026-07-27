import type { Feature, Polygon } from 'geojson';
import destination from '@turf/destination';
import { point } from '@turf/helpers';

/**
 * Calculates the great-circle distance in meters between two GPS coordinates using the Haversine formula.
 *
 * @param lat1 Latitude of point 1
 * @param lon1 Longitude of point 1
 * @param lat2 Latitude of point 2
 * @param lon2 Longitude of point 2
 * @returns Distance in meters
 */
export function calculateDistanceMeters(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  if (
    typeof lat1 !== 'number' || isNaN(lat1) ||
    typeof lon1 !== 'number' || isNaN(lon1) ||
    typeof lat2 !== 'number' || isNaN(lat2) ||
    typeof lon2 !== 'number' || isNaN(lon2)
  ) {
    throw new Error('Invalid coordinates provided to calculateDistanceMeters');
  }

  const R = 6371000; // Earth's mean radius in meters
  const rad = Math.PI / 180;
  const dLat = (lat2 - lat1) * rad;
  const dLon = (lon2 - lon1) * rad;

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLon / 2) * Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Checks if a target GPS coordinate lies within the user's active Vicinity Bubble.
 *
 * @param userLat User's current latitude
 * @param userLng User's current longitude
 * @param targetLat Target point latitude
 * @param targetLng Target point longitude
 * @param maxRadiusMeters Maximum distance threshold in meters (default: 200m)
 * @returns True if within radius, false otherwise
 */
export function isWithinVicinityBubble(
  userLat: number,
  userLng: number,
  targetLat: number,
  targetLng: number,
  maxRadiusMeters: number = 200
): boolean {
  const distance = calculateDistanceMeters(userLat, userLng, targetLat, targetLng);
  return distance <= maxRadiusMeters;
}

/**
 * Generates a GeoJSON Polygon feature representing a circular Vicinity Bubble centered on a GPS coordinate.
 *
 * @param latitude Center latitude
 * @param longitude Center longitude
 * @param radiusMeters Circle radius in meters (default: 200)
 * @param steps Number of polygon vertices (default: 64 for smooth circle)
 * @returns GeoJSON Feature containing Polygon geometry
 */
export function generateVicinityBubbleGeoJSON(
  latitude: number,
  longitude: number,
  radiusMeters: number = 200,
  steps: number = 64
): Feature<Polygon> {
  const center = point([longitude, latitude]);
  const radiusKm = radiusMeters / 1000;
  const coordinates: number[][] = [];

  for (let i = 0; i < steps; i++) {
    const bearing = (i * 360) / steps;
    const dest = destination(center, radiusKm, bearing, { units: 'kilometers' });
    coordinates.push(dest.geometry.coordinates);
  }

  // Close the polygon ring by repeating the first coordinate
  coordinates.push(coordinates[0]);

  return {
    type: 'Feature',
    properties: {
      radiusMeters,
    },
    geometry: {
      type: 'Polygon',
      coordinates: [coordinates],
    },
  };
}
