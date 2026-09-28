import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('UI Copy Cleanliness & Retrospective Rule 12 Enforcement', () => {
  // Rule 12: No internal identifiers in any new UI copy (applies to progress/error strings too)
  const FORBIDDEN_TOKENS = [
    'pmtiles',
    'protomaps',
    'maplibre',
    'opfs',
    'sqlite',
    'wasm',
    'mvt',
    'pbf',
    'zstd',
    'trip_id',
    'stop_id',
    'route_id',
    'undefined',
    'null',
    'nan',
    '[object',
    'error:',
    'exception',
    'stack',
    'traceback',
    'filesystem',
    'createwritable',
    'createsyncaccesshandle',
    '/api/',
    '.pmtiles',
    'cities/',
  ];

  const UI_STRINGS: string[] = [
    // Loading overlay strings
    'Downloading Map',
    'Downloading offline map',
    'Preparing New York City vector basemap for offline navigation...',
    // Error overlay strings
    'Map Error',
    'Unable to load offline map',
    'Retry',
    'Check your connection and try again.',
    // Worker / View error messages displayed to user
    'Download was interrupted. Please check your connection and try again.',
    'Unable to initialize map download. Please check your connection and try again.',
    'The downloaded map file is corrupt. Please try again.',
    'Offline map file is not available. Please retry download.',
    'Unable to display offline map. Please check your connection and try again.',
    'Unable to load offline map from storage. Please retry download.',
  ];

  it('all UI copy strings contain zero forbidden technical tokens or internal identifiers', () => {
    for (const text of UI_STRINGS) {
      const lower = text.toLowerCase();
      for (const token of FORBIDDEN_TOKENS) {
        assert.ok(
          !lower.includes(token),
          `UI string "${text}" contains forbidden internal token "${token}" (Rule 12 violation)`
        );
      }
    }
  });

  it('all UI copy strings are non-empty, user-friendly English sentences or concise badges', () => {
    for (const text of UI_STRINGS) {
      assert.ok(text.trim().length > 0, 'UI string must not be empty');
      assert.ok(text.length < 120, `UI string "${text}" should be concise (got ${text.length} chars)`);
    }
  });

  it('BasemapView.tsx source contains no raw unhandled error or internal token leakage in JSX text', () => {
    const basemapViewPath = path.resolve(__dirname, '../../components/BasemapView.tsx');
    const content = fs.readFileSync(basemapViewPath, 'utf8');

    // Extract rendered strings inside JSX headings and paragraphs
    const titleMatches = Array.from(content.matchAll(/<h2[^>]*>([^<]+)<\/h2>/g)).map((m) => m[1].trim());
    const descMatches = Array.from(content.matchAll(/<p[^>]*>([^<]+)<\/p>/g)).map((m) => m[1].trim());
    const badgeMatches = Array.from(content.matchAll(/<span>([^<]+)<\/span>/g)).map((m) => m[1].trim());
    const btnMatches = Array.from(content.matchAll(/<button[^>]*>([^<]+)<\/button>/g)).map((m) => m[1].trim());

    const renderedJSXStrings = [...titleMatches, ...descMatches, ...badgeMatches, ...btnMatches];

    assert.ok(renderedJSXStrings.length > 0, 'Should find rendered JSX text');

    for (const str of renderedJSXStrings) {
      const lower = str.toLowerCase();
      for (const token of FORBIDDEN_TOKENS) {
        assert.ok(
          !lower.includes(token),
          `JSX rendered string "${str}" in BasemapView.tsx contains forbidden token "${token}"`
        );
      }
    }
  });
});
