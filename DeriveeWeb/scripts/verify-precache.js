import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const distDir = path.resolve(__dirname, '../dist');
const swPath = path.resolve(distDir, 'sw.js');
const manifestPath = path.resolve(distDir, 'manifest.webmanifest');

console.log('\n========================================');
console.log('   PWA SHELL PRECACHE VERIFICATION');
console.log('========================================\n');

if (!fs.existsSync(distDir)) {
  console.error(`ERROR: dist directory does not exist at ${distDir}`);
  process.exit(1);
}

if (!fs.existsSync(swPath)) {
  console.error(`ERROR: Service worker file sw.js does not exist at ${swPath}`);
  process.exit(1);
}

if (!fs.existsSync(manifestPath)) {
  console.error(`ERROR: Web manifest manifest.webmanifest does not exist at ${manifestPath}`);
  process.exit(1);
}

const swContent = fs.readFileSync(swPath, 'utf8');

// Match precacheAndRoute([...])
const match = swContent.match(/precacheAndRoute\(\s*(\[.*?\])\s*,\s*\{/s);

if (!match) {
  console.error('ERROR: Could not find precacheAndRoute call in sw.js');
  process.exit(1);
}

let precacheList;
try {
  // Parse array of { url: "...", revision: "..." }
  precacheList = new Function(`return ${match[1]}`)();
} catch (err) {
  console.error('ERROR: Failed to parse precache manifest array from sw.js:', err);
  process.exit(1);
}

console.log(`Precache Manifest contains ${precacheList.length} assets:\n`);

const forbiddenExtensions = [
  '.pack',
  '.zst',
  '.pmtiles',
  '.bin',
  '.sqlite',
  '.sqlite-wal',
  '.sqlite-shm',
  '.csr',
  '.tar'
];

const forbiddenKeywords = [
  'city-nyc',
  'walk_graph',
  'timetable',
  'ultra_transfers',
  'transit.sqlite'
];

let violationCount = 0;
const uniqueUrls = new Set();

for (const entry of precacheList) {
  const url = entry.url;
  uniqueUrls.add(url);
  const rev = entry.revision ? `[rev: ${entry.revision.slice(0, 8)}]` : '[hash-in-url]';
  console.log(`  ✓ ${url.padEnd(45)} ${rev}`);

  const lowerUrl = url.toLowerCase();

  for (const ext of forbiddenExtensions) {
    if (lowerUrl.endsWith(ext) || lowerUrl.includes(ext + '?')) {
      console.error(`\n🚨 FATAL VIOLATION: Forbidden data pack extension "${ext}" in precache: ${url}`);
      violationCount++;
    }
  }

  for (const kw of forbiddenKeywords) {
    if (lowerUrl.includes(kw)) {
      console.error(`\n🚨 FATAL VIOLATION: Forbidden data pack keyword "${kw}" in precache: ${url}`);
      violationCount++;
    }
  }
}

if (violationCount > 0) {
  console.error(`\n❌ AUDIT FAILED: ${violationCount} data pack violation(s) found in Service Worker!`);
  process.exit(1);
}

console.log(`\n----------------------------------------`);
console.log(`Total unique precached shell assets: ${uniqueUrls.size}`);
console.log(`Precache audit PASSED: ZERO data packs present.`);
console.log(`========================================\n`);
