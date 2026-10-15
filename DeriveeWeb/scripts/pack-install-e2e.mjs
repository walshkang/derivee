#!/usr/bin/env node
// pack-install-e2e.mjs — End-to-end test for the pack installer worker.
//
// What it does: bundles the REAL pack-installer.worker.ts from current source,
// serves it plus a REAL .pack.zst over HTTP, and drives a full install in
// headless Chromium (real OPFS). Then:
//   phase 1 — full install must SUCCEED; every extracted file must be
//             byte-identical (SHA-256) to a node-side reference extraction;
//             reported version must match EXPECT_VERSION when set.
//   phase 2 — a truncated .zst must fail CLEANLY (ERROR message) with the
//             previously installed pack left intact in OPFS (no half-written
//             state).
// It also samples the Chromium renderer RSS during install and reports the
// peak. The 400MB gate is a smoke gate against pathological retention/OOM,
// not a precise bar (renderer RSS is process-level and noisy); the precise
// memory discipline lives in code review of the worker's buffer releases.
//
// Why this exists: the 1A wave's buffer-release optimization introduced a
// use-after-release bug (step 8 iterated the emptied validFiles array) that
// made installs "succeed" with zero files copied. No unit test covered the
// worker, and diff review missed it. This test is the red→green proof:
// it FAILS on the pre-fix worker and PASSES on the fixed one.
//
// Usage:
//   node scripts/pack-install-e2e.mjs [--worker-src <path/to/worker.ts>]
// Env:
//   PACK_PATH       path to a .pack.zst to install
//                   (default: ~/workspace/bus-build/pack-subway-v7/city-nyc.pack.zst)
//   EXPECT_VERSION  expected packState.version (default: unset — version reported only)
// Exit: 0 pass, 1 fail, 2 setup error (missing pack, build failure, ...).

import { execFileSync, execSync } from 'node:child_process';
import { createServer } from 'node:http';
import { readFileSync, writeFileSync, copyFileSync, mkdirSync, rmSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join, resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const __dirname = dirname(fileURLToPath(import.meta.url));
const WEB_DIR = resolve(__dirname, '..');

const args = process.argv.slice(2);
let workerSrc = resolve(WEB_DIR, 'src/workers/pack-installer.worker.ts');
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--worker-src' && args[i + 1]) { workerSrc = resolve(args[i + 1]); i++; }
  else { console.error(`unknown arg: ${args[i]}`); process.exit(2); }
}
const PACK_PATH = process.env.PACK_PATH ||
  join(process.env.HOME || '/home/hatch', 'workspace/bus-build/pack-subway-v7/city-nyc.pack.zst');
const EXPECT_VERSION = process.env.EXPECT_VERSION || null;
const MEM_GATE_MB = 400;

const failures = [];
function check(name, cond, detail = '') {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
  if (!cond) failures.push(name);
}

const workdir = join(tmpdir(), `pack-e2e-${Date.now()}`);
mkdirSync(workdir, { recursive: true });
const cleanup = () => { try { rmSync(workdir, { recursive: true, force: true }); } catch {} };
process.on('exit', cleanup);

// --- setup: pack present? ---
if (!existsSync(PACK_PATH)) {
  console.error(`PACK_PATH not found: ${PACK_PATH}\nSet PACK_PATH to a .pack.zst to test.`);
  process.exit(2);
}
if (!existsSync(workerSrc)) { console.error(`worker src not found: ${workerSrc}`); process.exit(2); }

// --- reference extraction (node side, same decoder family as the browser) ---
const { init, decompress } = await import('@bokuweb/zstd-wasm');
const { parseTar } = await import('nanotar');
await init();
const packBytes = readFileSync(PACK_PATH);
const refEntries = parseTar(decompress(new Uint8Array(packBytes)));
const ref = {};
for (const e of refEntries) {
  if (!e.name || !e.data) continue;
  ref[e.name] = { size: e.data.length, sha256: createHash('sha256').update(e.data).digest('hex') };
}
if (Object.keys(ref).length === 0) { console.error('reference extraction found no files'); process.exit(2); }
console.log(`reference: ${Object.keys(ref).length} files from ${basename(PACK_PATH)}`);

// --- bundle the worker from current source (always tests what's in the tree) ---
const esbuild = join(WEB_DIR, 'node_modules/.bin/esbuild');
try {
  execFileSync(esbuild, [workerSrc, '--bundle', '--platform=browser', '--format=esm',
    `--outfile=${join(workdir, 'worker.js')}`, '--log-level=error'], { cwd: WEB_DIR, stdio: 'pipe' });
} catch (e) {
  console.error(`worker bundle failed for ${workerSrc}\n${e.message}`);
  process.exit(2);
}
copyFileSync(join(WEB_DIR, 'node_modules/@bokuweb/zstd-wasm/dist/web/zstd.wasm'), join(workdir, 'zstd.wasm'));
copyFileSync(PACK_PATH, join(workdir, 'city-nyc.pack.zst'));
const packBuf = readFileSync(PACK_PATH);
writeFileSync(join(workdir, 'city-nyc-truncated.pack.zst'), packBuf.subarray(0, Math.floor(packBuf.length * 0.43)));

const pageHtml = `<!doctype html><html><body><script type="module">
const truncated = new URLSearchParams(location.search).get('truncated') === '1';
window.__messages = []; window.__done = false; window.__result = null;
const worker = new Worker('/worker.js', { type: 'module' });
worker.onmessage = (e) => {
  window.__messages.push(e.data.type);
  if (e.data.type === 'SUCCESS' || e.data.type === 'ERROR') { window.__done = true; window.__result = e.data; }
};
worker.onerror = (e) => { window.__done = true; window.__result = { type: 'WORKER_ERROR', message: String(e.message) }; };
worker.postMessage({ type: 'START_INSTALL', slug: 'nyc',
  packUrl: truncated ? '/city-nyc-truncated.pack.zst' : '/city-nyc.pack.zst',
  expectedVersion: ${EXPECT_VERSION ? JSON.stringify(EXPECT_VERSION) : 'undefined'} });
<\/script></body></html>`;
writeFileSync(join(workdir, 'index.html'), pageHtml);

// --- serve ---
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.zst': 'application/octet-stream' };
const server = createServer((req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const fp = join(workdir, p === '/' ? 'index.html' : p.slice(1));
  if (!fp.startsWith(workdir) || !existsSync(fp)) { res.writeHead(404); res.end(); return; }
  const ext = fp.slice(fp.lastIndexOf('.'));
  res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
  res.end(readFileSync(fp));
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const PORT = server.address().port;
const ORIGIN = `http://127.0.0.1:${PORT}`;

async function opfsSnapshot(page) {
  return page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    let dir;
    try { dir = await root.getDirectoryHandle('nyc'); } catch { return []; }
    const out = [];
    for await (const [name, handle] of dir.entries()) {
      if (handle.kind !== 'file') continue;
      const f = await handle.getFile();
      const buf = new Uint8Array(await f.arrayBuffer());
      const h = await crypto.subtle.digest('SHA-256', buf);
      out.push({ name, size: f.size, sha256: [...new Uint8Array(h)].map((x) => x.toString(16).padStart(2, '0')).join('') });
    }
    out.sort((a, b) => (a.name < b.name ? -1 : 1));
    return out;
  });
}

const browser = await chromium.launch();
const page = await browser.newPage();

// Memory: sample Chromium renderer RSS during the install. Process-level and
// noisy, so the gate is a generous smoke gate (400MB), not a precise bar.
// It exists to catch pathological retention/OOM-class regressions.
function rendererRssMB() {
  try {
    const pids = execSync(`pgrep -f 'type=renderer'`).toString().trim().split('\n').filter(Boolean);
    let total = 0;
    for (const pid of pids) {
      try {
        const rss = parseInt(execSync(`ps -o rss= -p ${pid}`).toString().trim(), 10);
        if (!isNaN(rss)) total += rss;
      } catch {}
    }
    return total / 1024;
  } catch { return 0; }
}

async function runInstall(truncated, sampleMem) {
  await page.goto(`${ORIGIN}/?truncated=${truncated ? '1' : '0'}`);
  await page.waitForFunction(() => window.__messages.length > 0, null, { timeout: 30000 });
  const t0 = Date.now();
  let peak = 0;
  let memInt = null;
  if (sampleMem) {
    memInt = setInterval(() => { const v = rendererRssMB(); if (v > peak) peak = v; }, 200);
  }
  await page.waitForFunction(() => window.__done === true, null, { timeout: 180000 });
  if (memInt) clearInterval(memInt);
  return { result: await page.evaluate(() => window.__result), ms: Date.now() - t0, peakMemMB: peak };
}

// --- phase 1: full install ---
console.log('\n--- phase 1: full install ---');
const p1 = await runInstall(false, true);
check('install succeeds', p1.result.type === 'SUCCESS', `got ${p1.result.type} in ${p1.ms}ms`);
check('peak renderer memory under smoke gate', p1.peakMemMB < MEM_GATE_MB,
  `peak ${p1.peakMemMB.toFixed(0)}MB (gate ${MEM_GATE_MB}MB)`);
const files = await opfsSnapshot(page);
const names = Object.keys(ref).sort();
check('all expected files installed', files.length === names.length && names.every((n) => files.some((f) => f.name === n)),
  `${files.length}/${names.length} files`);
let identical = files.length === names.length;
for (const f of files) {
  const r = ref[f.name];
  if (!r || r.sha256 !== f.sha256 || r.size !== f.size) { identical = false; console.log(`  MISMATCH ${f.name}`); }
}
check('extracted files byte-identical to reference', identical);
if (EXPECT_VERSION) check('reported version matches', p1.result.packState?.version === EXPECT_VERSION,
  `got ${p1.result.packState?.version}`);
else console.log(`INFO  reported version: ${p1.result.packState?.version} (EXPECT_VERSION unset)`);
const afterPhase1 = JSON.stringify(files);

// --- phase 2: truncated install must fail clean, previous pack intact ---
console.log('\n--- phase 2: truncated install ---');
const p2 = await runInstall(true);
check('truncated install fails', p2.result.type === 'ERROR', `got ${p2.result.type}`);
const afterPhase2 = JSON.stringify(await opfsSnapshot(page));
check('previous pack intact after failure', afterPhase1 === afterPhase2);

await browser.close();
server.close();

console.log(failures.length === 0 ? '\nALL CHECKS PASSED' : `\n${failures.length} FAILURES: ${failures.join(', ')}`);
process.exit(failures.length === 0 ? 0 : 1);
