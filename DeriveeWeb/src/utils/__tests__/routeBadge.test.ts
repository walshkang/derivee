import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  getRouteBadge,
  createRoutesMap,
  formatHexColor,
  sanitizeBadgeLabel,
  FALLBACK_ROUTE_COLOR,
} from '../routeBadge.ts';
import type { RouteItem } from '../../types/routing.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '../../..');

describe('M5b Route Badges & FC-2 Invariant Tests', () => {
  // 1. Data Verification: routes.json build artifact & spot-checks
  describe('routes.json Build Artifact Verification', () => {
    const routesJsonPath = path.resolve(REPO_ROOT, 'public/data/routes.json');

    it('routes.json exists and is valid JSON dictionary', () => {
      assert.ok(fs.existsSync(routesJsonPath), 'public/data/routes.json must exist');
      const raw = fs.readFileSync(routesJsonPath, 'utf8');
      const data = JSON.parse(raw);
      assert.strictEqual(typeof data, 'object', 'routes.json must be a JSON object');
      assert.ok(!Array.isArray(data), 'routes.json must be a dictionary, not an array');
      assert.ok(Object.keys(data).length >= 25, `Expected >= 25 NYC routes, got ${Object.keys(data).length}`);
    });

    it('spot-checks known NYC subway lines match real MTA / M4b ribbon colors', () => {
      const raw = fs.readFileSync(routesJsonPath, 'utf8');
      const routes: Record<string, RouteItem> = JSON.parse(raw);

      // Line 7: Flushing Local (Purple #9A38A1, White text)
      assert.ok(routes['7'], 'Route 7 must exist in routes.json');
      assert.strictEqual(routes['7'].shortName, '7');
      assert.strictEqual(routes['7'].color, '9A38A1');
      assert.strictEqual(routes['7'].textColor, 'FFFFFF');

      // Line 1: 7th Ave Local (Red #D82233, White text)
      assert.ok(routes['1'], 'Route 1 must exist in routes.json');
      assert.strictEqual(routes['1'].shortName, '1');
      assert.strictEqual(routes['1'].color, 'D82233');
      assert.strictEqual(routes['1'].textColor, 'FFFFFF');

      // Line 4: Lexington Ave Express (Green #009952, White text)
      assert.ok(routes['4'], 'Route 4 must exist in routes.json');
      assert.strictEqual(routes['4'].shortName, '4');
      assert.strictEqual(routes['4'].color, '009952');
      assert.strictEqual(routes['4'].textColor, 'FFFFFF');

      // Line A: 8th Ave Express (Blue #0062CF, White text)
      assert.ok(routes['A'], 'Route A must exist in routes.json');
      assert.strictEqual(routes['A'].shortName, 'A');
      assert.strictEqual(routes['A'].color, '0062CF');
      assert.strictEqual(routes['A'].textColor, 'FFFFFF');

      // Line D: 6th Ave Express (Orange #EB6800, White text)
      assert.ok(routes['D'], 'Route D must exist in routes.json');
      assert.strictEqual(routes['D'].shortName, 'D');
      assert.strictEqual(routes['D'].color, 'EB6800');
      assert.strictEqual(routes['D'].textColor, 'FFFFFF');

      // Line N: Broadway Express (Yellow #F6BC26, Black text #000000 for contrast)
      assert.ok(routes['N'], 'Route N must exist in routes.json');
      assert.strictEqual(routes['N'].shortName, 'N');
      assert.strictEqual(routes['N'].color, 'F6BC26');
      assert.strictEqual(routes['N'].textColor, '000000');

      // Line G: Brooklyn-Queens Crosstown (Lime #799534, White text)
      assert.ok(routes['G'], 'Route G must exist in routes.json');
      assert.strictEqual(routes['G'].shortName, 'G');
      assert.strictEqual(routes['G'].color, '799534');
      assert.strictEqual(routes['G'].textColor, 'FFFFFF');

      // Line L: 14 St-Canarsie (Gray #7C858C, White text)
      assert.ok(routes['L'], 'Route L must exist in routes.json');
      assert.strictEqual(routes['L'].shortName, 'L');
      assert.strictEqual(routes['L'].color, '7C858C');
      assert.strictEqual(routes['L'].textColor, 'FFFFFF');

      // Line SI: Staten Island Railway (Dark Blue #08179C, ShortName SIR)
      assert.ok(routes['SI'], 'Route SI must exist in routes.json');
      assert.strictEqual(routes['SI'].shortName, 'SIR');
      assert.strictEqual(routes['SI'].color, '08179C');
      assert.strictEqual(routes['SI'].textColor, 'FFFFFF');
    });

    it('file size budget check: routes.json is compact and lightweight (< 10 KB)', () => {
      const stats = fs.statSync(routesJsonPath);
      assert.ok(stats.size > 500, `routes.json is too small (${stats.size} bytes)`);
      assert.ok(stats.size < 10240, `routes.json exceeds 10 KB budget (${stats.size} bytes)`);
    });
  });

  // 2. formatHexColor utility tests
  describe('formatHexColor utility', () => {
    it('prepends # to hex strings without prefix', () => {
      assert.strictEqual(formatHexColor('9A38A1'), '#9A38A1');
      assert.strictEqual(formatHexColor('00A1DE'), '#00A1DE');
      assert.strictEqual(formatHexColor('FFF'), '#FFF');
    });

    it('preserves existing # prefix', () => {
      assert.strictEqual(formatHexColor('#9A38A1'), '#9A38A1');
      assert.strictEqual(formatHexColor('#000000'), '#000000');
    });

    it('negative cases: falls back on null, undefined, empty, or garbage strings', () => {
      assert.strictEqual(formatHexColor(null), FALLBACK_ROUTE_COLOR);
      assert.strictEqual(formatHexColor(undefined), FALLBACK_ROUTE_COLOR);
      assert.strictEqual(formatHexColor(''), FALLBACK_ROUTE_COLOR);
      assert.strictEqual(formatHexColor('   '), FALLBACK_ROUTE_COLOR);
      assert.strictEqual(formatHexColor('not-a-color'), FALLBACK_ROUTE_COLOR);
      assert.strictEqual(formatHexColor('#GGGGGG'), FALLBACK_ROUTE_COLOR);
    });
  });

  // 3. createRoutesMap utility tests
  describe('createRoutesMap utility', () => {
    it('populates Map with exact keys and case-insensitive keys', () => {
      const fixture: Record<string, RouteItem> = {
        '12': { shortName: '12', color: '00A1DE', textColor: 'FFFFFF' },
        'a': { shortName: 'A', color: '0062CF', textColor: 'FFFFFF' },
      };
      const map = createRoutesMap(fixture);
      assert.strictEqual(map.size, 3); // '12', 'a', 'A'
      assert.strictEqual(map.get('12')?.color, '00A1DE');
      assert.strictEqual(map.get('a')?.color, '0062CF');
      assert.strictEqual(map.get('A')?.color, '0062CF');
    });

    it('negative cases: handles null, undefined, empty, or corrupted inputs cleanly', () => {
      assert.strictEqual(createRoutesMap(null).size, 0);
      assert.strictEqual(createRoutesMap(undefined).size, 0);
      assert.strictEqual(createRoutesMap({} as any).size, 0);
      assert.strictEqual(createRoutesMap('invalid' as any).size, 0);
    });
  });

  // 4. getRouteBadge pure display model tests
  describe('getRouteBadge pure display function', () => {
    const fixtureMap = createRoutesMap({
      '7': { shortName: '7', color: '9A38A1', textColor: 'FFFFFF' },
      'N': { shortName: 'N', color: 'F6BC26', textColor: '000000' },
      'SI': { shortName: 'SIR', color: '08179C', textColor: 'FFFFFF' },
      '1': { shortName: '1', color: 'D82233', textColor: 'FFFFFF' },
    });

    it('known route: renders exact colors and short name badge', () => {
      const badge7 = getRouteBadge('7', fixtureMap);
      assert.ok(badge7, 'badge7 must not be null');
      assert.strictEqual(badge7.label, '7');
      assert.strictEqual(badge7.backgroundColor, '#9A38A1');
      assert.strictEqual(badge7.textColor, '#FFFFFF');
      assert.strictEqual(badge7.isFallback, false);

      const badgeN = getRouteBadge('N', fixtureMap);
      assert.ok(badgeN, 'badgeN must not be null');
      assert.strictEqual(badgeN.label, 'N');
      assert.strictEqual(badgeN.backgroundColor, '#F6BC26');
      assert.strictEqual(badgeN.textColor, '#000000');
      assert.strictEqual(badgeN.isFallback, false);

      const badgeSIR = getRouteBadge('SI', fixtureMap);
      assert.ok(badgeSIR, 'badgeSIR must not be null');
      assert.strictEqual(badgeSIR.label, 'SIR');
      assert.strictEqual(badgeSIR.backgroundColor, '#08179C');
      assert.strictEqual(badgeSIR.textColor, '#FFFFFF');
      assert.strictEqual(badgeSIR.isFallback, false);
    });

    it('numeric route ID: matches numeric lookup key cleanly', () => {
      const badge1 = getRouteBadge(1, fixtureMap);
      assert.ok(badge1, 'badge1 must not be null');
      assert.strictEqual(badge1.label, '1');
      assert.strictEqual(badge1.backgroundColor, '#D82233');
      assert.strictEqual(badge1.textColor, '#FFFFFF');
      assert.strictEqual(badge1.isFallback, false);
    });

    it('short name lookup: resolves route when passed short name directly', () => {
      const badgeSIR = getRouteBadge('SIR', fixtureMap);
      assert.ok(badgeSIR, 'badgeSIR must not be null');
      assert.strictEqual(badgeSIR.label, 'SIR');
      assert.strictEqual(badgeSIR.backgroundColor, '#08179C');
      assert.strictEqual(badgeSIR.isFallback, false);
    });

    it('fallback for unknown route ID: returns null (no badge pill)', () => {
      const badgeUnknown = getRouteBadge('12', fixtureMap);
      assert.strictEqual(badgeUnknown, null);

      const badgeNumericUnknown = getRouteBadge(999, fixtureMap);
      assert.strictEqual(badgeNumericUnknown, null);

      // Real RAPTOR uint16 pattern indices must NEVER leak as badge pills
      const badge167 = getRouteBadge(167, fixtureMap);
      assert.strictEqual(badge167, null);

      const badge36 = getRouteBadge(36, fixtureMap);
      assert.strictEqual(badge36, null);
    });

    it('fetch failure fallback: returns null when map is empty, null, or undefined', () => {
      const badgeNoMap = getRouteBadge('7', undefined);
      assert.strictEqual(badgeNoMap, null);

      const badgeEmptyMap = getRouteBadge('A', new Map());
      assert.strictEqual(badgeEmptyMap, null);
    });

    it('negative cases: missing, null, undefined, or empty route ID returns null (never raw ID or "0")', () => {
      assert.strictEqual(getRouteBadge(null, fixtureMap), null);
      assert.strictEqual(getRouteBadge(undefined, fixtureMap), null);
      assert.strictEqual(getRouteBadge('', fixtureMap), null);
      assert.strictEqual(getRouteBadge('   ', fixtureMap), null);
      assert.strictEqual(getRouteBadge(0, fixtureMap), null);
      assert.strictEqual(getRouteBadge('0', fixtureMap), null);
    });
  });

  // 5. Invariant FC-2: Zero internal identifiers in UI copy
  describe('Invariant FC-2: Internal ID Leak Prevention', () => {
    it('sanitizes internal route_id_ or trip_id_ prefixes if present', () => {
      assert.strictEqual(sanitizeBadgeLabel('route_id_7'), '7');
      assert.strictEqual(sanitizeBadgeLabel('route_12'), '12');
      assert.strictEqual(sanitizeBadgeLabel('trip_id_45'), '45');
      assert.strictEqual(sanitizeBadgeLabel('7'), '7');
      assert.strictEqual(sanitizeBadgeLabel(''), 'Transit');
    });

    it('getRouteBadge returns null instead of leaking raw route_id_ or numeric strings', () => {
      const badge = getRouteBadge('route_id_101', undefined);
      assert.strictEqual(badge, null, 'Unresolvable route ID must return null, never leak raw ID');
    });

    it('RouteComparisonView.tsx contains zero raw route-id displays', () => {
      const rcvPath = path.resolve(REPO_ROOT, 'src/components/RouteComparisonView.tsx');
      const content = fs.readFileSync(rcvPath, 'utf8');

      // The pre-fix code had: <span class="route-id-display">🚇 Route {legModel.routeId}</span>
      assert.ok(
        !content.includes('🚇 Route {'),
        'RouteComparisonView.tsx must NOT contain raw "🚇 Route {" display'
      );
      assert.ok(
        !content.includes('Route {legModel.routeId}'),
        'RouteComparisonView.tsx must NOT render raw "Route {legModel.routeId}"'
      );
      assert.ok(
        content.includes('getRouteBadge(legModel.routeId, routesMap)'),
        'RouteComparisonView.tsx must use getRouteBadge pure display model'
      );
      assert.ok(
        content.includes('route-pill-badge'),
        'RouteComparisonView.tsx must render route-pill-badge'
      );
    });

    it('TripPlanner.tsx fetches routes.json and passes routesMap to RouteComparisonView', () => {
      const tpPath = path.resolve(REPO_ROOT, 'src/components/TripPlanner.tsx');
      const content = fs.readFileSync(tpPath, 'utf8');

      assert.ok(
        content.includes("fetch('/data/routes.json')"),
        'TripPlanner.tsx must fetch /data/routes.json offline'
      );
      assert.ok(
        content.includes('routesMap={routesMap}'),
        'TripPlanner.tsx must pass routesMap prop to RouteComparisonView'
      );
    });
  });
});
