#!/usr/bin/env node
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import child_process from 'node:child_process';
import { firefox } from 'playwright';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DIST_DIR = path.resolve(__dirname, '../dist');
const FIXTURE_PATH = path.resolve(__dirname, '../../DeriveeNative/Derivee/basemap-nyc.pmtiles');
const TRANSIT_LINES_GEOJSON_PATH = path.resolve(__dirname, '../../../derivee-audits/t1/pack_tmp/transit-lines.geojson');
const transitLinesGeojsonText = fs.existsSync(TRANSIT_LINES_GEOJSON_PATH)
  ? fs.readFileSync(TRANSIT_LINES_GEOJSON_PATH, 'utf8')
  : JSON.stringify({ type: 'FeatureCollection', features: [] });

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.pbf': 'application/x-protobuf',
  '.wasm': 'application/wasm',
};

export function resolveRunContext(args = process.argv.slice(2)) {
  const repoRoot = path.resolve(__dirname, '../..');
  const auditsDir = process.env.AUDITS_DIR || path.resolve(repoRoot, '../derivee-audits');
  const runsDir = path.join(auditsDir, 'runs');

  let runId = process.env.RUN_ID || null;
  let reportDirArg = null;
  let screenshotsDirArg = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--run-id' && args[i + 1]) {
      runId = args[i + 1];
      i++;
    } else if (args[i] === '--report-dir' && args[i + 1]) {
      reportDirArg = args[i + 1];
      i++;
    } else if (args[i] === '--screenshots-dir' && args[i + 1]) {
      screenshotsDirArg = args[i + 1];
      i++;
    }
  }

  if (!runId && fs.existsSync(runsDir)) {
    const entries = fs.readdirSync(runsDir, { withFileTypes: true })
      .filter((d) => d.isDirectory() && !d.name.startsWith('.'))
      .map((d) => {
        const fullPath = path.join(runsDir, d.name);
        const stat = fs.statSync(fullPath);
        return { name: d.name, fullPath, mtimeMs: stat.mtimeMs };
      })
      .sort((a, b) => b.mtimeMs - a.mtimeMs);

    if (entries.length > 0 && (Date.now() - entries[0].mtimeMs < 3 * 3600 * 1000)) {
      runId = entries[0].name;
    }
  }

  if (!runId) {
    const now = new Date();
    const ts = now.toISOString().replace(/[-:T]/g, '').slice(0, 15);
    runId = `r${ts}`;
  }

  const runDir = path.join(runsDir, runId);
  fs.mkdirSync(runDir, { recursive: true });

  const reportDir = reportDirArg ? path.resolve(reportDirArg) : path.join(runDir, 'report');
  const screenshotsDir = screenshotsDirArg ? path.resolve(screenshotsDirArg) : path.join(runDir, 'screenshots');

  fs.mkdirSync(reportDir, { recursive: true });
  fs.mkdirSync(screenshotsDir, { recursive: true });

  let commit = 'unknown';
  try {
    commit = child_process.execSync('git rev-parse --short HEAD', { cwd: repoRoot, stdio: ['pipe', 'pipe', 'ignore'] }).toString().trim();
  } catch {}

  return { repoRoot, auditsDir, runsDir, runId, runDir, reportDir, screenshotsDir, commit };
}

function generateHtmlReport({ runId, commit, timestamp, stats, scenarios }) {
  const statusColor = (status) => status === 'passed' ? '#10b981' : '#ef4444';
  const statusBadge = (status) => status === 'passed' ? '✅ PASSED' : '❌ FAILED';

  const scenarioCards = scenarios.map((s) => {
    const shotImgs = s.screenshots.map((shotPath) => {
      const relShot = `../screenshots/${path.basename(shotPath)}`;
      return `
        <div style="margin-top: 10px;">
          <a href="${relShot}" target="_blank" style="color: #60a5fa; text-decoration: none;">
            <img src="${relShot}" alt="${s.name}" style="max-width: 100%; max-height: 400px; border-radius: 6px; border: 1px solid #374151; display: block;" />
            <span style="font-size: 12px; display: block; margin-top: 4px;">🔍 View full image (${path.basename(shotPath)})</span>
          </a>
        </div>
      `;
    }).join('');

    const errorBlock = s.error ? `
      <div style="background: #1f1212; border: 1px solid #ef4444; border-radius: 6px; padding: 12px; margin-top: 10px; color: #fca5a5; font-family: monospace; font-size: 12px; white-space: pre-wrap;">
        <strong>Error:</strong> ${s.error.message}\n\n${s.error.stack || ''}
      </div>
    ` : '';

    return `
      <div style="background: #1e293b; border-radius: 8px; padding: 16px; margin-bottom: 16px; border: 1px solid #334155;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
          <h3 style="margin: 0; font-size: 16px; color: #f8fafc;">${s.name}</h3>
          <span style="background: ${statusColor(s.status)}22; color: ${statusColor(s.status)}; border: 1px solid ${statusColor(s.status)}; border-radius: 4px; padding: 2px 8px; font-weight: bold; font-size: 12px;">
            ${statusBadge(s.status)}
          </span>
        </div>
        <div style="font-size: 13px; color: #94a3b8; margin-bottom: 8px;">
          <span>Flow: <strong style="color: #cbd5e1;">${s.flow}</strong></span> &bull;
          <span>Duration: <strong style="color: #cbd5e1;">${s.durationMs}ms</strong></span>
        </div>
        ${errorBlock}
        ${shotImgs ? `<div style="margin-top: 12px;"><h4 style="margin: 0 0 6px 0; font-size: 13px; color: #94a3b8;">Screenshots</h4>${shotImgs}</div>` : ''}
      </div>
    `;
  }).join('');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Diagnostic Harness Report — ${runId}</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      background: #0f172a;
      color: #e2e8f0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      padding: 24px;
    }
    .container {
      max-width: 900px;
      margin: 0 auto;
    }
    .header {
      border-bottom: 1px solid #334155;
      padding-bottom: 16px;
      margin-bottom: 24px;
    }
    .stats-bar {
      display: flex;
      gap: 16px;
      margin-top: 12px;
    }
    .stat-pill {
      background: #1e293b;
      padding: 6px 14px;
      border-radius: 6px;
      font-size: 14px;
      border: 1px solid #334155;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1 style="margin: 0 0 8px 0; font-size: 24px;">Diagnostic Harness Report</h1>
      <div style="color: #94a3b8; font-size: 13px;">
        <span>Run ID: <strong style="color: #f1f5f9;">${runId}</strong></span> &bull;
        <span>Commit: <strong style="color: #f1f5f9;">${commit}</strong></span> &bull;
        <span>Date: <strong style="color: #f1f5f9;">${timestamp}</strong></span>
      </div>
      <div class="stats-bar">
        <div class="stat-pill">Total: <strong>${stats.total}</strong></div>
        <div class="stat-pill" style="border-color: #10b981; color: #10b981;">Passed: <strong>${stats.passed}</strong></div>
        <div class="stat-pill" style="${stats.failed > 0 ? 'border-color: #ef4444; color: #ef4444;' : 'color: #94a3b8;'}">Failed: <strong>${stats.failed}</strong></div>
        <div class="stat-pill">Duration: <strong>${stats.durationMs}ms</strong></div>
      </div>
    </div>
    <div class="scenarios-list">
      ${scenarioCards}
    </div>
  </div>
</body>
</html>`;
}

// 1. Start Xvfb if DISPLAY is not set
let xvfbProc = null;
if (!process.env.DISPLAY) {
  const displayNum = ':99';
  console.log(`[Harness] DISPLAY not set. Spawning Xvfb on ${displayNum}...`);
  xvfbProc = spawn('Xvfb', [displayNum, '-screen', '0', '1280x800x24']);
  process.env.DISPLAY = displayNum;
  await new Promise((r) => setTimeout(r, 600));
}

// 2. Start static file server
function startServer(port = 4173) {
  const server = http.createServer((req, res) => {
    try {
      const parsedUrl = new URL(req.url, `http://localhost:${port}`);
      let reqPath = decodeURIComponent(parsedUrl.pathname);
      if (reqPath === '/') reqPath = '/index.html';

      const filePath = path.join(DIST_DIR, reqPath);
      if (!filePath.startsWith(DIST_DIR)) {
        res.writeHead(403);
        res.end('Forbidden');
        return;
      }

      if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
        res.writeHead(404);
        res.end(`Not found: ${reqPath}`);
        return;
      }

      const ext = path.extname(filePath).toLowerCase();
      const mime = MIME_TYPES[ext] || 'application/octet-stream';
      const fileData = fs.readFileSync(filePath);

      res.writeHead(200, {
        'Content-Type': mime,
        'Content-Length': fileData.length,
        'Cache-Control': 'no-cache',
      });
      res.end(fileData);
    } catch (err) {
      res.writeHead(500);
      res.end(String(err));
    }
  });

  return new Promise((resolve) => {
    server.listen(port, '127.0.0.1', () => {
      console.log(`[Harness] Static server listening on http://127.0.0.1:${port}`);
      resolve(server);
    });
  });
}

const server = await startServer(4173);
const runContext = resolveRunContext();
const { runId, commit, reportDir, screenshotsDir } = runContext;
console.log(`[Harness] Target Run ID: ${runId}`);
console.log(`[Harness] Report Directory: ${reportDir}`);
console.log(`[Harness] Screenshots Directory: ${screenshotsDir}`);

const scenarioResults = [];

async function recordScenario(name, flow, fn) {
  if (process.env.HARNESS_FILTER && !name.includes(process.env.HARNESS_FILTER)) {
    return;
  }
  console.log(`\n========================================`);
  console.log(`[Harness] Scenario: ${name} (flow: ${flow})`);
  console.log(`========================================`);
  const startTime = Date.now();
  const screenshots = [];

  const takeScreenshot = async (pageInstance, filename) => {
    const filePath = path.join(screenshotsDir, filename);
    await pageInstance.screenshot({ path: filePath });
    console.log(`[Harness] Saved screenshot to ${filePath}`);
    screenshots.push(filePath);
    return filePath;
  };

  try {
    await fn({ takeScreenshot });
    const durationMs = Date.now() - startTime;
    console.log(`[Harness] ✅ PASSED: ${name} (${durationMs}ms)`);
    scenarioResults.push({
      name,
      flow,
      status: 'passed',
      durationMs,
      error: null,
      screenshots,
    });
  } catch (err) {
    const durationMs = Date.now() - startTime;
    console.error(`[Harness] ❌ FAILED: ${name} (${durationMs}ms) - ${err.message}`);
    scenarioResults.push({
      name,
      flow,
      status: 'failed',
      durationMs,
      error: {
        message: err.message,
        stack: err.stack,
      },
      screenshots,
    });
  }
}

let browser = null;

try {
  console.log('[Harness] Launching Firefox...');
  browser = await firefox.launch({
    headless: true,
    firefoxUserPrefs: {
      'webgl.force-enabled': true,
      'webgl.disabled': false,
    },
  });

  const context = await browser.newContext();
  const page = await context.newPage();

  const consoleLogs = [];
  const pageErrors = [];
  const failedRequests = [];
  const pendingRequests = new Map();

  page.on('console', (msg) => {
    const text = `[Browser Console ${msg.type()}] ${msg.text()}`;
    consoleLogs.push(text);
    console.log(text);
  });

  page.on('pageerror', (err) => {
    const text = `[Browser PageError] ${err.stack || err.message}`;
    pageErrors.push(text);
    console.error(text);
  });

  page.on('request', (req) => {
    pendingRequests.set(req, {
      url: req.url(),
      method: req.method(),
      startTime: Date.now(),
    });
  });

  page.on('requestfinished', async (req) => {
    pendingRequests.delete(req);
    const resp = await req.response();
    const info = `${req.method()} ${req.url()} -> ${resp ? resp.status() : 'no-resp'}`;
    console.log(`[Request Finished] ${info}`);
  });

  page.on('requestfailed', (req) => {
    const failure = req.failure()?.errorText || 'Unknown failure';
    failedRequests.push({ url: req.url(), method: req.method(), error: failure });
    pendingRequests.delete(req);
    console.warn(`[Request Failed] ${req.method()} ${req.url()}: ${failure}`);
  });

  // Load basemap fixture buffer
  if (!fs.existsSync(FIXTURE_PATH)) {
    throw new Error(`PMTiles fixture not found at: ${FIXTURE_PATH}`);
  }
  const basemapBuffer = fs.readFileSync(FIXTURE_PATH);
  console.log(`[Harness] Loaded PMTiles fixture (${basemapBuffer.length} bytes)`);

  // Route mocking: Mocks /api/* requests
  await page.route(/\/api\/.*/, (route) => {
    const req = route.request();
    const parsed = new URL(req.url());
    if (parsed.pathname === '/api/basemap') {
      route.fulfill({
        status: 200,
        headers: {
          'Content-Type': 'application/vnd.pmtiles',
          'Content-Length': String(basemapBuffer.length),
          'Access-Control-Allow-Origin': '*',
        },
        body: basemapBuffer,
      });
    } else if (parsed.pathname === '/api/cities') {
      route.fulfill({
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
        body: JSON.stringify({
          cities: [
            {
              slug: 'nyc',
              name: 'New York City',
              pack_bytes: 29688421,
              bbox: [-74.28, 40.48, -73.68, 40.95],
            },
          ],
        }),
      });
    } else if (parsed.pathname === '/api/me') {
      route.fulfill({
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
        body: JSON.stringify({
          email: 'test@example.com',
        }),
      });
    } else {
      route.fulfill({
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
        body: JSON.stringify({}),
      });
    }
  });

  // SCENARIO 1: Map mounts to ready
  await recordScenario('Map mounts to ready', 'map', async ({ takeScreenshot }) => {
    console.log('[Harness] Navigating to http://127.0.0.1:4173/...');
    await page.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded' });
    console.log('[Harness] Page loaded. Watching for basemap download and mount...');

    const webglStatus = await page.evaluate(() => {
      const canvas = document.createElement('canvas');
      const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
      if (!gl) return { ok: false, error: 'No WebGL context' };
      return { ok: true, renderer: gl.getParameter(gl.RENDERER) };
    });
    console.log('[Harness] In-page WebGL check:', webglStatus);

    const retryBtn = page.locator('.map-retry-btn');
    if (await retryBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
      console.log('[Harness] Retry button visible. Clicking it...');
      await retryBtn.click();
    }

    const startTime = Date.now();
    let settled = false;
    let finalState = null;
    let errorDesc = null;
    let errorDetails = null;

    while (Date.now() - startTime < 60_000) {
      const state = await page.evaluate(() => {
        const wrapper = document.querySelector('.basemap-view-wrapper');
        const desc = document.querySelector('.map-state-desc')?.textContent || null;
        const details = document.querySelector('.map-error-details div')?.textContent || null;
        const hasCanvas = !!document.querySelector('#map-container canvas');
        return {
          state: wrapper ? wrapper.getAttribute('data-state') : null,
          desc,
          details,
          hasCanvas,
        };
      });

      if (state.state !== finalState) {
        console.log(`[Harness] State transition: ${finalState} -> ${state.state} (canvas: ${state.hasCanvas})`);
        finalState = state.state;
      }

      if (state.state === 'map-ready') {
        settled = true;
        console.log('[Harness] SUCCESS: Basemap reached map-ready state!');

        const mapDiagnostics = await page.evaluate(() => {
          const canvas = document.querySelector('#map-container canvas');
          let nonZeroPixels = 0;
          let totalPixels = 0;
          let contextType = null;
          if (canvas) {
            const gl = canvas.getContext('webgl2') || canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
            if (gl) {
              contextType = gl instanceof WebGL2RenderingContext ? 'webgl2' : 'webgl';
              const pixels = new Uint8Array(gl.drawingBufferWidth * gl.drawingBufferHeight * 4);
              gl.readPixels(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
              totalPixels = pixels.length / 4;
              for (let i = 0; i < pixels.length; i += 4) {
                if (pixels[i] !== 0 || pixels[i+1] !== 0 || pixels[i+2] !== 0 || pixels[i+3] !== 0) {
                  nonZeroPixels++;
                }
              }
            }
          }
          return {
            canvasWidth: canvas?.width,
            canvasHeight: canvas?.height,
            contextType,
            totalPixels,
            nonZeroPixels,
          };
        });
        console.log('[Harness] Map diagnostics after ready:', mapDiagnostics);

        await takeScreenshot(page, 'map-ready.png');
        break;
      }

      if (state.state === 'map-error') {
        settled = true;
        errorDesc = state.desc;
        errorDetails = state.details;
        await takeScreenshot(page, 'map-ready-failed.png').catch(() => {});
        throw new Error(`Basemap entered map-error state: ${errorDesc}\n${errorDetails}`);
      }

      await new Promise((r) => setTimeout(r, 500));
    }

    if (!settled) {
      await takeScreenshot(page, 'map-ready-failed.png').catch(() => {});
      throw new Error('Timeout: 60s elapsed without reaching map-ready or map-error');
    }
  });

  // SCENARIO 2: Footer shows build hash
  await recordScenario('Footer shows build hash', 'system info', async ({ takeScreenshot }) => {
    const footerBuildText = await page.evaluate(() => {
      return document.querySelector('.footer-build-item')?.textContent || null;
    });
    console.log('[Harness] Footer Build Info:', footerBuildText);
    if (!footerBuildText || !footerBuildText.includes('Build:')) {
      await takeScreenshot(page, 'footer-build-failed.png').catch(() => {});
      throw new Error(`Expected footer build identity to be rendered, got: ${footerBuildText}`);
    }
    await takeScreenshot(page, 'footer-build.png');
  });

  // SCENARIO 3: Cached reload reaches ready
  await recordScenario('Cached reload reaches ready', 'map', async ({ takeScreenshot }) => {
    console.log('\n[Harness] --- TESTING CACHED VISIT (RELOAD) ---');
    await page.reload({ waitUntil: 'domcontentloaded' });
    console.log('[Harness] Page reloaded. Waiting for cached mount...');

    let reloadSettled = false;
    const reloadStart = Date.now();
    let reloadState = null;
    while (Date.now() - reloadStart < 30_000) {
      const cur = await page.evaluate(() => {
        const wrapper = document.querySelector('.basemap-view-wrapper');
        return {
          state: wrapper ? wrapper.getAttribute('data-state') : null,
          desc: document.querySelector('.map-state-desc')?.textContent || null,
          details: document.querySelector('.map-error-details div')?.textContent || null,
        };
      });
      if (cur.state !== reloadState) {
        console.log(`[Harness Reload] State transition: ${reloadState} -> ${cur.state}`);
        reloadState = cur.state;
      }
      if (cur.state === 'map-ready') {
        reloadSettled = true;
        console.log('[Harness Reload] SUCCESS: Cached basemap reached map-ready state!');
        await takeScreenshot(page, 'cached-reload.png');
        break;
      }
      if (cur.state === 'map-error') {
        await takeScreenshot(page, 'cached-reload-failed.png').catch(() => {});
        throw new Error(`Cached basemap entered map-error: ${cur.details || cur.desc}`);
      }
      await new Promise((r) => setTimeout(r, 500));
    }

    if (!reloadSettled) {
      await takeScreenshot(page, 'cached-reload-failed.png').catch(() => {});
      throw new Error('Timeout: 30s elapsed without reaching cached map-ready');
    }
  });

  // SCENARIO 4: Route cards scroll on swipe, sheet stays put
  await recordScenario('Route cards scroll on swipe, sheet stays put', 'trip planning', async ({ takeScreenshot }) => {
    console.log('\n[Harness] --- TESTING TRIP PLANNER CARD SCROLL GESTURE REGRESSION ---');
    const mobileContext = await browser.newContext({
      viewport: { width: 390, height: 844 },
      hasTouch: true,
      isMobile: true,
    });
    const mobilePage = await mobileContext.newPage();

    try {
      await mobilePage.route(/\/api\/.*/, (route) => {
        const pathname = new URL(route.request().url()).pathname;
        if (pathname === '/api/me') {
          return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'test@example.com' }) });
        }
        if (pathname === '/api/basemap') {
          return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/vnd.pmtiles' }, body: basemapBuffer });
        }
        return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: '{}' });
      });

      await mobilePage.addInitScript(() => {
        localStorage.setItem('derivee_pack_nyc', JSON.stringify({
          isInstalled: true, slug: 'nyc', version: '3',
          files: ['city_config.json', 'transit.sqlite', 'transit-lines.geojson', 'ultra_transfers.csr', 'timetable.bin', 'walk_graph.bin'].map((name) => ({ name, size: 1000 })),
          totalBytes: 6000,
        }));

        const REQUIRED = ['city_config.json', 'transit.sqlite', 'transit-lines.geojson', 'ultra_transfers.csr', 'timetable.bin', 'walk_graph.bin'];
        const fakeFile = { size: 1000, async arrayBuffer() { return new ArrayBuffer(8); } };
        const fakeDir = {
          async getFileHandle(name) {
            if (!REQUIRED.includes(name)) throw new DOMException('nf', 'NotFoundError');
            return { async getFile() { return fakeFile; } };
          },
        };
        Object.defineProperty(navigator, 'storage', {
          value: {
            async getDirectory() {
              return { async getDirectoryHandle(name) { if (name === 'nyc') return fakeDir; throw new DOMException('nf', 'NotFoundError'); } };
            },
          },
          configurable: true,
        });

        const CANNED = [
          { board_stop_id: 72, exit_stop_id: 150, trip_id: 1, departure_time: 28800, arrival_time: 29400, route_id: 2, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 150, exit_stop_id: 151, trip_id: 0, departure_time: 29400, arrival_time: 29700, route_id: 0, transfer_distance_m: 150, is_transfer: true },
          { board_stop_id: 151, exit_stop_id: 207, trip_id: 2, departure_time: 29700, arrival_time: 31200, route_id: 4, transfer_distance_m: 0, is_transfer: false },
        ];
        const RealWorker = window.Worker;
        window.Worker = function (url, opts) {
          if (String(url).includes('routing.worker')) {
            const handlers = {};
            return {
              postMessage(msg) {
                setTimeout(() => {
                  if (msg.type === 'INIT') handlers.message?.({ data: { type: 'READY', loadTimeMs: 90 } });
                  else if (msg.type === 'ROUTE') handlers.message?.({ data: { type: 'RESULT', queryId: msg.queryId, segments: CANNED, profile: msg.profile, flags: msg.flags } });
                }, 30);
              },
              set onmessage(fn) { handlers.message = fn; },
              get onmessage() { return handlers.message; },
              set onerror(fn) { handlers.error = fn; },
              addEventListener(t, fn) { handlers[t] = fn; },
              removeEventListener(t) { delete handlers[t]; },
              terminate() {},
            };
          }
          return new RealWorker(url, opts);
        };
        window.Worker.prototype = RealWorker.prototype;
      });

      console.log('[Harness Planner] Navigating to http://127.0.0.1:4173/...');
      await mobilePage.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded' });
      await mobilePage.addStyleTag({ content: '.map-state-overlay { display: none !important; }' });
      await mobilePage.waitForSelector('.engine-status-ready', { timeout: 30000 });
      console.log('[Harness Planner] Engine ready (stubbed). Expanding sheet...');

      await mobilePage.evaluate(() => {
        document.querySelector('.bottom-sheet').style.height = '90dvh';
      });
      await new Promise((r) => setTimeout(r, 600));

      await mobilePage.click('.quick-preset-btn');
      await new Promise((r) => setTimeout(r, 400));
      await mobilePage.click('.trip-route-btn');
      console.log('[Harness Planner] Routing trip...');
      await mobilePage.waitForFunction(() => {
        const c = document.querySelector('.itinerary-results-container');
        return c && c.children.length > 0;
      }, { timeout: 15000 });
      await new Promise((r) => setTimeout(r, 800));
      console.log('[Harness Planner] Cards rendered. Dispatching swipe gesture...');

      const gesture = await mobilePage.evaluate(() => {
        let prevented = false;
        const origPrevent = TouchEvent.prototype.preventDefault;
        TouchEvent.prototype.preventDefault = function () { prevented = true; return origPrevent.call(this); };

        const card = document.querySelector('.trip-planner-card');
        const sheet = document.querySelector('.bottom-sheet');
        const sheetHeightBefore = sheet.style.height;

        const mkTouch = (y) => new Touch({ identifier: 1, target: card, clientX: 195, clientY: y });
        const fire = (type, y) => {
          const t = mkTouch(y);
          card.dispatchEvent(new TouchEvent(type, {
            touches: type === 'touchend' ? [] : [t],
            targetTouches: type === 'touchend' ? [] : [t],
            changedTouches: [t],
            bubbles: true, cancelable: true,
          }));
        };
        let lastY = 700;
        fire('touchstart', 700);
        for (let i = 1; i <= 12; i++) {
          const curY = 700 - i * 25;
          const t = mkTouch(curY);
          const notCancelled = card.dispatchEvent(new TouchEvent('touchmove', {
            touches: [t],
            targetTouches: [t],
            changedTouches: [t],
            bubbles: true, cancelable: true,
          }));
          if (!notCancelled) {
            prevented = true;
          } else {
            card.scrollTop += (lastY - curY);
          }
          lastY = curY;
        }
        fire('touchend', 400);

        TouchEvent.prototype.preventDefault = origPrevent;
        return {
          prevented,
          sheetHeightBefore,
          sheetHeightAfter: sheet.style.height,
          cardScrollable: card.scrollHeight > card.clientHeight,
          cardScrollTopBefore: 0,
          cardScrollTopAfter: card.scrollTop,
        };
      });

      console.log('[Harness Planner] GESTURE RESULT:', JSON.stringify(gesture));
      if (!gesture.cardScrollable) {
        throw new Error('TripPlanner card is not scrollable (scrollHeight <= clientHeight)');
      }
      if (gesture.prevented) {
        throw new Error('TripPlanner card swipe was intercepted by preventDefault()!');
      }
      if (gesture.cardScrollTopAfter <= gesture.cardScrollTopBefore) {
        throw new Error(`TripPlanner card failed to scroll (scrollTop stayed ${gesture.cardScrollTopAfter})`);
      }
      if (gesture.sheetHeightBefore !== gesture.sheetHeightAfter) {
        throw new Error(`Sheet height changed from ${gesture.sheetHeightBefore} to ${gesture.sheetHeightAfter}`);
      }
      console.log('[Harness Planner] SUCCESS: Cards scrolled natively without sheet hijacking or detent change!');
      await takeScreenshot(mobilePage, 'trip-cards-scrolled.png');
    } catch (err) {
      await takeScreenshot(mobilePage, 'trip-cards-scrolled-failed.png').catch(() => {});
      throw err;
    } finally {
      await mobileContext.close();
    }
  });

  // SCENARIO 5: No raw route IDs in leg badges
  await recordScenario('No raw route IDs in leg badges', 'trip planning', async ({ takeScreenshot }) => {
    console.log('\n[Harness] --- TESTING ROUTE BADGE LEAK REGRESSION (FC-2) ---');
    const badgeContext = await browser.newContext({
      viewport: { width: 390, height: 844 },
      hasTouch: true,
      isMobile: true,
    });
    const badgePage = await badgeContext.newPage();

    try {
      await badgePage.route(/\/api\/.*/, (route) => {
        const pathname = new URL(route.request().url()).pathname;
        if (pathname === '/api/me') {
          return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'test@example.com' }) });
        }
        if (pathname === '/api/basemap') {
          return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/vnd.pmtiles' }, body: basemapBuffer });
        }
        return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: '{}' });
      });

      await badgePage.addInitScript(() => {
        localStorage.setItem('derivee_pack_nyc', JSON.stringify({
          isInstalled: true, slug: 'nyc', version: '3',
          files: ['city_config.json', 'transit.sqlite', 'transit-lines.geojson', 'ultra_transfers.csr', 'timetable.bin', 'walk_graph.bin', 'patterns.json'].map((name) => ({ name, size: 1000 })),
          totalBytes: 7000,
        }));

        const REQUIRED = ['city_config.json', 'transit.sqlite', 'transit-lines.geojson', 'ultra_transfers.csr', 'timetable.bin', 'walk_graph.bin', 'patterns.json'];
        const fakeFile = { size: 1000, async arrayBuffer() { return new ArrayBuffer(8); } };
        
        const patternsArray = new Array(200).fill(null);
        patternsArray[36] = { route_id: "J" };
        patternsArray[167] = { route_id: "L" };
        const patternsFile = { size: 1000, async text() { return JSON.stringify(patternsArray); } };

        const fakeDir = {
          async getFileHandle(name) {
            if (!REQUIRED.includes(name)) throw new DOMException('nf', 'NotFoundError');
            if (name === 'patterns.json') return { async getFile() { return patternsFile; } };
            return { async getFile() { return fakeFile; } };
          },
        };
        Object.defineProperty(navigator, 'storage', {
          value: {
            async getDirectory() {
              return { async getDirectoryHandle(name) { if (name === 'nyc') return fakeDir; throw new DOMException('nf', 'NotFoundError'); } };
            },
          },
          configurable: true,
        });

        // Real engine-shaped segments: route_id as uint16 RAPTOR pattern index (e.g. 167, 36)
        // One leg with route_id undefined (missing route info)
        // One transfer leg
        const REAL_SHAPED_SEGMENTS = [
          { board_stop_id: 72, exit_stop_id: 150, trip_id: 1045, departure_time: 28800, arrival_time: 29400, route_id: 167, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 150, exit_stop_id: 151, trip_id: 0, departure_time: 29400, arrival_time: 29700, route_id: 0, transfer_distance_m: 150, is_transfer: true },
          { board_stop_id: 151, exit_stop_id: 180, trip_id: 2099, departure_time: 29700, arrival_time: 30300, route_id: 36, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 180, exit_stop_id: 207, trip_id: 3144, departure_time: 30300, arrival_time: 31200, route_id: undefined, transfer_distance_m: 0, is_transfer: false },
        ];
        const RealWorker = window.Worker;
        window.Worker = function (url, opts) {
          if (String(url).includes('routing.worker')) {
            const handlers = {};
            return {
              postMessage(msg) {
                setTimeout(() => {
                  if (msg.type === 'INIT') handlers.message?.({ data: { type: 'READY', loadTimeMs: 90, patterns: patternsArray } });
                  else if (msg.type === 'ROUTE') handlers.message?.({ data: { type: 'RESULT', queryId: msg.queryId, segments: REAL_SHAPED_SEGMENTS, profile: msg.profile, flags: msg.flags } });
                }, 30);
              },
              set onmessage(fn) { handlers.message = fn; },
              get onmessage() { return handlers.message; },
              set onerror(fn) { handlers.error = fn; },
              addEventListener(t, fn) { handlers[t] = fn; },
              removeEventListener(t) { delete handlers[t]; },
              terminate() {},
            };
          }
          return new RealWorker(url, opts);
        };
        window.Worker.prototype = RealWorker.prototype;
      });

      console.log('[Harness Badges] Navigating to http://127.0.0.1:4173/...');
      await badgePage.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded' });
      await badgePage.addStyleTag({ content: '.map-state-overlay { display: none !important; }' });
      await badgePage.waitForSelector('.engine-status-ready', { timeout: 30000 });

      await badgePage.evaluate(() => {
        document.querySelector('.bottom-sheet').style.height = '90dvh';
      });
      await new Promise((r) => setTimeout(r, 600));

      await badgePage.click('.quick-preset-btn');
      await new Promise((r) => setTimeout(r, 400));
      await badgePage.click('.trip-route-btn');
      console.log('[Harness Badges] Routing trip with real engine-shaped segments...');
      await badgePage.waitForFunction(() => {
        const c = document.querySelector('.itinerary-results-container');
        return c && c.children.length > 0;
      }, { timeout: 15000 });
      await new Promise((r) => setTimeout(r, 800));

      const badgeAudit = await badgePage.evaluate(() => {
        const routePills = Array.from(document.querySelectorAll('.route-pill-badge'));
        const badgeTexts = routePills.map((el) => (el.textContent || '').trim());
        const transferPills = Array.from(document.querySelectorAll('.leg-mode-pill.mode-pill-walk'));
        const transferTexts = transferPills.map((el) => (el.textContent || '').trim());
        const allCopy = document.querySelector('.itinerary-results-container')?.textContent || '';

        // Check for raw internal IDs
        const rawIdsFound = badgeTexts.filter((txt) => /^\d{2,}$/.test(txt) || txt === '0' || txt === '167' || txt === '36');

        return {
          badgeCount: routePills.length,
          badgeTexts,
          transferCount: transferPills.length,
          transferTexts,
          rawIdsFound,
          hasNumericTripLeaks: /trip[_\s]?id|#\d{4,}/i.test(allCopy),
        };
      });

      console.log('[Harness Badges] Route Badge Audit Result:', JSON.stringify(badgeAudit));
      await takeScreenshot(badgePage, 'leg-badges.png');

      if (badgeAudit.badgeCount === 0) {
        throw new Error('Expected at least one route badge pill to be rendered, found none');
      }
      const hasL = badgeAudit.badgeTexts.some((txt) => txt === 'L');
      const hasJ = badgeAudit.badgeTexts.some((txt) => txt === 'J');
      if (!hasL || !hasJ) {
        throw new Error(`Expected leg badges to contain real line names "L" and "J", got: ${JSON.stringify(badgeAudit.badgeTexts)}`);
      }

      if (badgeAudit.rawIdsFound.length > 0) {
        throw new Error(
          `Raw internal route IDs leaked into leg badges: ${JSON.stringify(badgeAudit.rawIdsFound)}. All badge texts: ${JSON.stringify(badgeAudit.badgeTexts)}`
        );
      }
      if (badgeAudit.badgeTexts.some((txt) => /^\d{2,}$/.test(txt))) {
        throw new Error(`Harness regression: found leg badge matching /^\\d{2,}$/: ${JSON.stringify(badgeAudit.badgeTexts)}`);
      }
      if (badgeAudit.transferCount === 0) {
        throw new Error('Expected transfer legs to render walk/transfer UI pill (.mode-pill-walk)');
      }
      console.log('[Harness Badges] SUCCESS: Zero raw internal route IDs leaked into leg badges!');
    } catch (err) {
      await takeScreenshot(badgePage, 'leg-badges-failed.png').catch(() => {});
      throw err;
    } finally {
      await badgeContext.close();
    }
  });

  await recordScenario('Itinerary legs group by ride', 'trip planning', async ({ takeScreenshot }) => {
    const groupContext = await browser.newContext({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true,
    });
    const groupPage = await groupContext.newPage();

    try {
      await groupPage.route(/\/api\/.*/, (route) => {
        const url = new URL(route.request().url());
        const pathname = url.pathname;
        if (pathname === '/api/cities') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify([{ id: 'nyc', name: 'New York City', slug: 'nyc', isInstalled: true }]),
          });
        }
        if (pathname === '/api/me') {
          return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'test@example.com' }) });
        }
        if (pathname === '/api/basemap') {
          return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/vnd.pmtiles' }, body: basemapBuffer });
        }
        return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: '{}' });
      });

      await groupPage.addInitScript(() => {
        localStorage.setItem('derivee_pack_nyc', JSON.stringify({
          isInstalled: true, slug: 'nyc', version: '3',
          files: ['city_config.json', 'transit.sqlite', 'transit-lines.geojson', 'ultra_transfers.csr', 'timetable.bin', 'walk_graph.bin'].map((name) => ({ name, size: 1000 })),
          totalBytes: 6000,
        }));

        const REQUIRED = ['city_config.json', 'transit.sqlite', 'transit-lines.geojson', 'ultra_transfers.csr', 'timetable.bin', 'walk_graph.bin'];
        const fakeFile = { size: 1000, async arrayBuffer() { return new ArrayBuffer(8); } };
        const fakeDir = {
          async getFileHandle(name) {
            if (!REQUIRED.includes(name)) throw new DOMException('nf', 'NotFoundError');
            return { async getFile() { return fakeFile; } };
          },
        };
        Object.defineProperty(navigator, 'storage', {
          value: {
            async getDirectory() {
              return { async getDirectoryHandle(name) { if (name === 'nyc') return fakeDir; throw new DOMException('nf', 'NotFoundError'); } };
            },
          },
          configurable: true,
        });

        // Bowery -> 59 St-Columbus Circle real engine-shaped segments:
        // Seg 0: Bowery -> Bowery (origin stub, 2s, dist 2m)
        // Seg 1: Bowery -> Canal St (J train, trip 20615, 90s)
        // Seg 2: Canal St -> Canal St (transfer walk, 57s, dist 74m)
        // Seg 3: Canal St -> 34 St-Herald Sq (Q train, trip 18522, 390s)
        // Seg 4: 34 St-Herald Sq -> 34 St-Penn Station (transfer walk, 91s, dist 118m)
        // Seg 5: 34 St-Penn Station -> 59 St-Columbus Circle (1 train, trip 89, 330s)
        // Seg 6: 59 St-Columbus Circle -> 59 St-Columbus Circle (destination stub, 8s, dist 10m)
        const BOWERY_COLUMBUS_SEGMENTS = [
          { board_stop_id: 1246, exit_stop_id: 1247, trip_id: 0, departure_time: 28800, arrival_time: 28802, route_id: 0, transfer_distance_m: 2, is_transfer: false },
          { board_stop_id: 1247, exit_stop_id: 1250, trip_id: 20615, departure_time: 28920, arrival_time: 29010, route_id: 217, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 1250, exit_stop_id: 1288, trip_id: 0, departure_time: 29010, arrival_time: 29067, route_id: 0, transfer_distance_m: 74, is_transfer: false },
          { board_stop_id: 1288, exit_stop_id: 1336, trip_id: 18522, departure_time: 29130, arrival_time: 29520, route_id: 190, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 1336, exit_stop_id: 76, trip_id: 0, departure_time: 29520, arrival_time: 29611, route_id: 0, transfer_distance_m: 118, is_transfer: false },
          { board_stop_id: 76, exit_stop_id: 67, trip_id: 89, departure_time: 29700, arrival_time: 30030, route_id: 3, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 67, exit_stop_id: 66, trip_id: 0, departure_time: 30030, arrival_time: 30038, route_id: 0, transfer_distance_m: 10, is_transfer: false },
        ];
        const RealWorker = window.Worker;
        window.Worker = function (url, opts) {
          if (String(url).includes('routing.worker')) {
            const handlers = {};
            return {
              postMessage(msg) {
                setTimeout(() => {
                  if (msg.type === 'INIT') handlers.message?.({ data: { type: 'READY', loadTimeMs: 90 } });
                  else if (msg.type === 'ROUTE') handlers.message?.({ data: { type: 'RESULT', queryId: msg.queryId, segments: BOWERY_COLUMBUS_SEGMENTS, profile: msg.profile, flags: msg.flags } });
                }, 30);
              },
              set onmessage(fn) { handlers.message = fn; },
              get onmessage() { return handlers.message; },
              set onerror(fn) { handlers.error = fn; },
              addEventListener(t, fn) { handlers[t] = fn; },
              removeEventListener(t) { delete handlers[t]; },
              terminate() {},
            };
          }
          return new RealWorker(url, opts);
        };
        window.Worker.prototype = RealWorker.prototype;
      });

      console.log('[Harness Grouping] Navigating to http://127.0.0.1:4173/...');
      await groupPage.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded' });
      await groupPage.addStyleTag({ content: '.map-state-overlay { display: none !important; }' });
      await groupPage.waitForSelector('.engine-status-ready', { timeout: 30000 });

      await groupPage.evaluate(() => {
        document.querySelector('.bottom-sheet').style.height = '90dvh';
      });
      await new Promise((r) => setTimeout(r, 600));

      await groupPage.click('.quick-preset-btn');
      await new Promise((r) => setTimeout(r, 400));
      await groupPage.click('.trip-route-btn');
      console.log('[Harness Grouping] Routing trip Bowery -> Columbus Circle...');
      await groupPage.waitForFunction(() => {
        const c = document.querySelector('.itinerary-results-container');
        return c && c.children.length > 0;
      }, { timeout: 15000 });
      await new Promise((r) => setTimeout(r, 800));

      const itineraryAudit = await groupPage.evaluate(() => {
        const glanceTransfers = document.querySelector('.glance-transfers')?.textContent?.trim() || '';
        const legCards = Array.from(document.querySelectorAll('.itinerary-leg-card'));
        const legBadgeTexts = legCards.map((c) => c.querySelector('.leg-index-badge')?.textContent?.trim() || '');
        const connectorRows = Array.from(document.querySelectorAll('.itinerary-transfer-connector, .transfer-connector-row'));
        const connectorTexts = connectorRows.map((r) => r.textContent?.trim() || '');
        const startRows = Array.from(document.querySelectorAll('.itinerary-compact-start'));
        const arriveRows = Array.from(document.querySelectorAll('.itinerary-compact-arrive'));

        return {
          glanceTransfers,
          legCardCount: legCards.length,
          legBadgeTexts,
          connectorCount: connectorRows.length,
          connectorTexts,
          startRowCount: startRows.length,
          arriveRowCount: arriveRows.length,
        };
      });

      console.log('[Harness Grouping] Itinerary Audit Result:', JSON.stringify(itineraryAudit));
      await takeScreenshot(groupPage, 'itinerary-grouping.png');

      // Assertions
      if (itineraryAudit.glanceTransfers !== '2 transfers') {
        throw new Error(`Expected transfer count to be "2 transfers", got "${itineraryAudit.glanceTransfers}"`);
      }
      if (itineraryAudit.legCardCount !== 3) {
        throw new Error(`Expected exactly 3 transit ride leg cards, got ${itineraryAudit.legCardCount} (leg badges: ${JSON.stringify(itineraryAudit.legBadgeTexts)})`);
      }
      if (itineraryAudit.connectorCount !== 2) {
        throw new Error(`Expected exactly 2 transfer connector rows between ride legs, got ${itineraryAudit.connectorCount}`);
      }
      const hasCanalTransfer = itineraryAudit.connectorTexts.some((txt) => /change at canal/i.test(txt));
      if (!hasCanalTransfer) {
        throw new Error(`Expected a connector row with "Change at Canal St", got connectors: ${JSON.stringify(itineraryAudit.connectorTexts)}`);
      }
      console.log('[Harness Grouping] SUCCESS: Itinerary legs correctly grouped by ride and transfers rendered as connectors!');
    } catch (err) {
      await takeScreenshot(groupPage, 'itinerary-grouping-failed.png').catch(() => {});
      throw err;
    } finally {
      await groupContext.close();
    }
  });

  // ==========================================================================
  // Wave: Leg detail wave (T2): tap a ride leg → line shape, stops, times
  // Scenario: Tap leg → line shape + stops (flow: trip planning)
  // ==========================================================================
  await recordScenario('Tap leg → line shape + stops', 'trip planning', async ({ takeScreenshot }) => {
    console.log('\n[Harness Leg Detail] --- TESTING LEG DETAIL: TAP LEG → LINE SHAPE, STOPS, TIMES ---');
    const legContext = await browser.newContext({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true,
    });
    const legPage = await legContext.newPage();

    try {
      await legPage.route(/\/api\/.*/, (route) => {
        const url = new URL(route.request().url());
        const pathname = url.pathname;
        if (pathname === '/api/cities') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify([{ id: 'nyc', name: 'New York City', slug: 'nyc', isInstalled: true }]),
          });
        }
        if (pathname === '/api/me') {
          return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'test@example.com' }) });
        }
        if (pathname === '/api/basemap') {
          return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/vnd.pmtiles' }, body: basemapBuffer });
        }
        if (pathname === '/api/realtime/arrivals') {
          return route.fulfill({
            status: 503,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ error: 'kv_not_configured' }),
          });
        }
        return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: '{}' });
      });

      await legPage.addInitScript(async ({ geojsonText }) => {
        localStorage.setItem('derivee_pack_nyc', JSON.stringify({
          isInstalled: true,
          slug: 'nyc',
          version: '3',
          displayName: 'New York City',
          seasonLabel: 'Summer 2026 Timetable',
          installedAt: '2026-10-01T00:00:00.000Z',
          totalBytes: 29684406,
          files: [
            { name: 'city_config.json', size: 3401 },
            { name: 'transit.sqlite', size: 9744384 },
            { name: 'transit-lines.geojson', size: 407221 },
            { name: 'ultra_transfers.csr', size: 582906 },
            { name: 'timetable.bin', size: 7184128 },
            { name: 'walk_graph.bin', size: 47426176 },
            { name: 'patterns.json', size: 1000 },
          ],
        }));

        const patternsArray = new Array(250).fill(null);
        patternsArray[217] = { route_id: 'J', headsign: 'Broad St' };
        patternsArray[190] = { route_id: 'Q', headsign: '96 St' };
        patternsArray[3] = { route_id: '1', headsign: 'Van Cortlandt Park' };

        if (navigator.storage && typeof navigator.storage.getDirectory === 'function') {
          const root = await navigator.storage.getDirectory();
          const nycDir = await root.getDirectoryHandle('nyc', { create: true });
          const geoHandle = await nycDir.getFileHandle('transit-lines.geojson', { create: true });
          const geoWritable = await geoHandle.createWritable();
          await geoWritable.write(geojsonText);
          await geoWritable.close();

          for (const fname of ['city_config.json', 'transit.sqlite', 'ultra_transfers.csr', 'timetable.bin', 'walk_graph.bin', 'patterns.json']) {
            const fh = await nycDir.getFileHandle(fname, { create: true });
            const w = await fh.createWritable();
            if (fname === 'city_config.json') {
              await w.write(JSON.stringify({ version: 3, displayName: 'New York City' }));
            } else if (fname === 'patterns.json') {
              await w.write(JSON.stringify(patternsArray));
            } else {
              await w.write(new Uint8Array([1, 2, 3, 4]));
            }
            await w.close();
          }
        }

        // Multi-hop transit segments with intermediate stops along Q train (trip 18522, route 190):
        // Seg 0: Bowery stub
        // Seg 1: J train Bowery -> Canal St
        // Seg 2: Transfer walk Canal St -> Canal St
        // Seg 3: Q train Canal St (1288) -> 14 St-Union Sq (444)
        // Seg 4: Q train 14 St-Union Sq (444) -> 23 St (81)
        // Seg 5: Q train 23 St (81) -> 34 St-Herald Sq (1336)
        // Seg 6: Transfer walk 34 St-Herald Sq -> 34 St-Penn Station
        // Seg 7: 1 train 34 St-Penn Station -> 59 St-Columbus Circle
        // Seg 8: Columbus Circle dest stub
        const MULTIHOP_SEGMENTS = [
          { board_stop_id: 1246, exit_stop_id: 1247, trip_id: 0, departure_time: 28800, arrival_time: 28802, route_id: 0, transfer_distance_m: 2, is_transfer: false },
          { board_stop_id: 1247, exit_stop_id: 1250, trip_id: 20615, departure_time: 28920, arrival_time: 29010, route_id: 217, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 1250, exit_stop_id: 1288, trip_id: 0, departure_time: 29010, arrival_time: 29067, route_id: 0, transfer_distance_m: 74, is_transfer: false },
          { board_stop_id: 1288, exit_stop_id: 444, trip_id: 18522, departure_time: 29130, arrival_time: 29280, route_id: 190, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 444, exit_stop_id: 81, trip_id: 18522, departure_time: 29280, arrival_time: 29400, route_id: 190, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 81, exit_stop_id: 1336, trip_id: 18522, departure_time: 29400, arrival_time: 29520, route_id: 190, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 1336, exit_stop_id: 76, trip_id: 0, departure_time: 29520, arrival_time: 29611, route_id: 0, transfer_distance_m: 118, is_transfer: false },
          { board_stop_id: 76, exit_stop_id: 67, trip_id: 89, departure_time: 29700, arrival_time: 30030, route_id: 3, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 67, exit_stop_id: 66, trip_id: 0, departure_time: 30030, arrival_time: 30038, route_id: 0, transfer_distance_m: 10, is_transfer: false },
        ];

        const RealWorker = window.Worker;
        window.Worker = function (url, opts) {
          if (String(url).includes('routing.worker')) {
            const handlers = {};
            return {
              postMessage(msg) {
                setTimeout(() => {
                  if (msg.type === 'INIT') {
                    handlers.message?.({ data: { type: 'READY', loadTimeMs: 90, patterns: patternsArray } });
                  } else if (msg.type === 'ROUTE') {
                    handlers.message?.({ data: { type: 'RESULT', queryId: msg.queryId, segments: MULTIHOP_SEGMENTS, profile: msg.profile, flags: msg.flags } });
                  }
                }, 30);
              },
              set onmessage(fn) { handlers.message = fn; },
              get onmessage() { return handlers.message; },
              set onerror(fn) { handlers.error = fn; },
              addEventListener(t, fn) { handlers[t] = fn; },
              removeEventListener(t) { delete handlers[t]; },
              terminate() {},
            };
          }
          return new RealWorker(url, opts);
        };
        window.Worker.prototype = RealWorker.prototype;
      }, { geojsonText: transitLinesGeojsonText });

      console.log('[Harness Leg Detail] Navigating to http://127.0.0.1:4173/...');
      await legPage.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded' });
      await legPage.addStyleTag({ content: '.map-state-overlay { display: none !important; }' });
      await legPage.waitForSelector('.engine-status-ready', { timeout: 30000 });

      await legPage.evaluate(() => {
        document.querySelector('.bottom-sheet').style.height = '90dvh';
      });
      await new Promise((r) => setTimeout(r, 600));

      await legPage.click('.quick-preset-btn');
      await new Promise((r) => setTimeout(r, 400));
      await legPage.click('.trip-route-btn');
      console.log('[Harness Leg Detail] Routing multi-hop trip...');
      await legPage.waitForFunction(() => {
        const c = document.querySelector('.itinerary-results-container');
        return c && c.children.length > 0;
      }, { timeout: 15000 });
      await new Promise((r) => setTimeout(r, 800));

      // 1. Assert initial state: all transit leg cards are tappable and no route is highlighted on map
      const initialAudit = await legPage.evaluate(() => {
        const mapContainer = document.querySelector('.maplibregl-map');
        const highlightedRoute = mapContainer?.getAttribute('data-highlighted-route') || null;
        const tappableCards = Array.from(document.querySelectorAll('.itinerary-leg-card-tappable'));
        const chevrons = Array.from(document.querySelectorAll('.leg-card-chevron'));
        return {
          highlightedRoute,
          tappableCardsCount: tappableCards.length,
          chevronsCount: chevrons.length,
        };
      });

      console.log('[Harness Leg Detail] Initial audit:', JSON.stringify(initialAudit));
      if (initialAudit.highlightedRoute !== null) {
        throw new Error(`Expected data-highlighted-route to be null initially, got "${initialAudit.highlightedRoute}"`);
      }
      if (initialAudit.tappableCardsCount < 3) {
        throw new Error(`Expected at least 3 tappable leg cards, got ${initialAudit.tappableCardsCount}`);
      }

      // 2. Tap the Q train leg card (Leg 2: Canal St -> 34 St-Herald Sq)
      console.log('[Harness Leg Detail] Tapping Q train leg card...');
      const tappedLeg = await legPage.evaluate(() => {
        const cards = Array.from(document.querySelectorAll('.itinerary-leg-card'));
        const qCard = cards.find((c) => c.textContent && c.textContent.includes('Canal St') && c.textContent.includes('34 St-Herald Sq'));
        if (qCard) {
          qCard.click();
          return true;
        }
        return false;
      });

      if (!tappedLeg) {
        throw new Error('Could not find Q train leg card to tap');
      }

      await legPage.waitForSelector('.leg-detail-container', { timeout: 5000 });
      await new Promise((r) => setTimeout(r, 600));

      // 3. Audit Leg Detail View
      const detailAudit = await legPage.evaluate(() => {
        const mapContainer = document.querySelector('.maplibregl-map');
        const highlightedRoute = mapContainer?.getAttribute('data-highlighted-route') || null;

        const headsign = document.querySelector('.leg-detail-headsign')?.textContent?.trim() || '';
        const routeBadge = document.querySelector('.leg-detail-route-badge')?.textContent?.trim() || '';
        const stopItems = Array.from(document.querySelectorAll('.leg-stop-item'));
        const stopNames = stopItems.map((el) => el.querySelector('.leg-stop-name')?.textContent?.trim() || '');
        const stopTimes = stopItems.map((el) => el.querySelector('.leg-stop-time')?.textContent?.trim() || '');
        const roleBadges = stopItems.map((el) => el.querySelector('.leg-stop-role-badge')?.textContent?.trim() || '');

        const detailAllText = document.querySelector('.leg-detail-container')?.textContent || '';
        const rawIdsFound = /18522|trip_id|#\d{3,}/i.test(detailAllText);

        return {
          highlightedRoute,
          headsign,
          routeBadge,
          stopCount: stopItems.length,
          stopNames,
          stopTimes,
          roleBadges,
          rawIdsFound,
        };
      });

      console.log('[Harness Leg Detail] Detail Audit Result:', JSON.stringify(detailAudit));
      await takeScreenshot(legPage, 'tap-leg-shape-stops.png');

      // Assertions on Leg Detail
      if (detailAudit.highlightedRoute !== 'Q') {
        throw new Error(`Expected data-highlighted-route to be "Q", got "${detailAudit.highlightedRoute}"`);
      }
      if (detailAudit.routeBadge !== 'Q') {
        throw new Error(`Expected route badge in leg detail to be "Q", got "${detailAudit.routeBadge}"`);
      }
      if (!/To 96 St/i.test(detailAudit.headsign)) {
        throw new Error(`Expected headsign to be "To 96 St", got "${detailAudit.headsign}"`);
      }
      if (detailAudit.stopCount !== 4) {
        throw new Error(`Expected 4 stops in ladder (board, 2 interim, alight), got ${detailAudit.stopCount}: ${JSON.stringify(detailAudit.stopNames)}`);
      }
      if (detailAudit.stopNames[0] !== 'Canal St' || detailAudit.stopNames[3] !== '34 St-Herald Sq') {
        throw new Error(`Expected stops from Canal St to 34 St-Herald Sq, got ${JSON.stringify(detailAudit.stopNames)}`);
      }
      if (!detailAudit.roleBadges[0].includes('Board')) {
        throw new Error(`Expected first stop role badge to be "Board", got "${detailAudit.roleBadges[0]}"`);
      }
      if (!detailAudit.roleBadges[3].includes('Alight')) {
        throw new Error(`Expected last stop role badge to be "Alight", got "${detailAudit.roleBadges[3]}"`);
      }
      if (detailAudit.stopTimes.some((t) => !t || t.length === 0)) {
        throw new Error(`Expected scheduled times for all stops, got ${JSON.stringify(detailAudit.stopTimes)}`);
      }
      if (detailAudit.rawIdsFound) {
        throw new Error('FC-2 regression: raw internal IDs found in leg detail view copy');
      }

      // 4. Test Back button returns to itinerary and restores map overlay
      console.log('[Harness Leg Detail] Clicking Back to routes button...');
      await legPage.click('.leg-detail-back-btn');
      await legPage.waitForSelector('.itinerary-results-container', { timeout: 5000 });
      await new Promise((r) => setTimeout(r, 600));

      const backAudit = await legPage.evaluate(() => {
        const mapContainer = document.querySelector('.maplibregl-map');
        const highlightedRoute = mapContainer?.getAttribute('data-highlighted-route') || null;
        const detailPresent = Boolean(document.querySelector('.leg-detail-container'));
        const itineraryPresent = Boolean(document.querySelector('.itinerary-results-container'));
        return {
          highlightedRoute,
          detailPresent,
          itineraryPresent,
        };
      });

      console.log('[Harness Leg Detail] Back Audit Result:', JSON.stringify(backAudit));
      await takeScreenshot(legPage, 'tap-leg-back-restored.png');

      if (backAudit.highlightedRoute !== null) {
        throw new Error(`Expected data-highlighted-route to be cleared (restoring full overlay), got "${backAudit.highlightedRoute}"`);
      }
      if (backAudit.detailPresent) {
        throw new Error('Expected leg detail container to be unmounted after clicking Back');
      }
      if (!backAudit.itineraryPresent) {
        throw new Error('Expected itinerary results container to be visible after clicking Back');
      }

      console.log('[Harness Leg Detail] SUCCESS: Tap leg → route shape highlighted, stop ladder rendered with times, Back restored overlay & itinerary!');
    } catch (err) {
      await takeScreenshot(legPage, 'tap-leg-failed.png').catch(() => {});
      throw err;
    } finally {
      await legContext.close();
    }
  });

  // ==========================================================================
  // Wave: Pack updates (T1): version check + update affordance
  // Scenario: Pack update available → installed (flow: pack management)
  // ==========================================================================
  await recordScenario('Pack update available → installed', 'pack management', async ({ takeScreenshot }) => {
    console.log('\n[Harness Pack Update] --- TESTING PACK UPDATE AFFORDANCE & INSTALLATION ---');
    const updateContext = await browser.newContext({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true,
    });
    const updatePage = await updateContext.newPage();

    try {
      // Mock Cloudflare Access auth
      await updatePage.route('**/api/me', (route) => {
        return route.fulfill({
          status: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: 'test@example.com' }),
        });
      });

      // Mock /api/pack-info returning newer v4 pack
      await updatePage.route('**/api/pack-info*', (route) => {
        return route.fulfill({
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
          body: JSON.stringify({
            version: 4,
            size: 29684406,
            updated_at: '2026-10-03T12:00:00.000Z',
          }),
        });
      });

      // Set initial installed pack state at v3 in OPFS / localStorage
      await updatePage.addInitScript(() => {
        localStorage.setItem('derivee_pack_nyc', JSON.stringify({
          isInstalled: true,
          slug: 'nyc',
          version: 3,
          displayName: 'New York City',
          seasonLabel: 'Summer 2026 Timetable',
          installedAt: '2026-10-01T00:00:00.000Z',
          totalBytes: 29684406,
          files: [
            { name: 'city_config.json', size: 3401 },
            { name: 'transit.sqlite', size: 9744384 },
            { name: 'transit-lines.geojson', size: 407221 },
            { name: 'ultra_transfers.csr', size: 582906 },
            { name: 'timetable.bin', size: 7184128 },
            { name: 'walk_graph.bin', size: 47426176 },
          ],
        }));

        const fakeFile = {
          size: 1000,
          async arrayBuffer() { return new ArrayBuffer(8); },
          async text() {
            return JSON.stringify({
              version: 3,
              slug: 'nyc',
              displayName: 'New York City',
              routing: { timetableBinFile: 't', walkGraphFile: 'w', ultraCsrFile: 'u' },
            });
          },
        };
        const fakeDir = {
          async getFileHandle() { return { async getFile() { return fakeFile; } }; },
          async getDirectoryHandle() { return this; },
          async removeEntry() {},
        };
        Object.defineProperty(navigator, 'storage', {
          value: {
            async getDirectory() {
              return { async getDirectoryHandle() { return fakeDir; } };
            },
          },
          configurable: true,
        });

        // Intercept worker instantiation for pack-installer.worker.ts to simulate downloading -> SUCCESS v4
        const OrigWorker = window.Worker;
        window.Worker = function (url, opts) {
          if (String(url).includes('pack-installer.worker')) {
            const handlers = {};
            const fakeWorker = {
              postMessage(msg) {
                if (msg.type === 'START_INSTALL') {
                  // Simulate progress stages
                  setTimeout(() => {
                    handlers.message?.({
                      data: {
                        type: 'PROGRESS',
                        stage: 'downloading',
                        loadedBytes: 14842203,
                        totalBytes: 29684406,
                        percent: 50,
                      },
                    });
                  }, 50);

                  setTimeout(() => {
                    handlers.message?.({
                      data: {
                        type: 'PROGRESS',
                        stage: 'verifying',
                        percent: 100,
                        message: 'Verifying integrity...',
                      },
                    });
                  }, 120);

                  setTimeout(() => {
                    handlers.message?.({
                      data: {
                        type: 'SUCCESS',
                        packState: {
                          isInstalled: true,
                          slug: 'nyc',
                          version: 4,
                          displayName: 'New York City',
                          seasonLabel: 'Summer 2026 Timetable',
                          installedAt: new Date().toISOString(),
                          totalBytes: 29684406,
                          files: [
                            { name: 'city_config.json', size: 3401 },
                            { name: 'transit.sqlite', size: 9744384 },
                            { name: 'transit-lines.geojson', size: 407221 },
                            { name: 'ultra_transfers.csr', size: 582906 },
                            { name: 'timetable.bin', size: 7184128 },
                            { name: 'walk_graph.bin', size: 47426176 },
                            { name: 'patterns.json', size: 19650 },
                          ],
                        },
                      },
                    });
                  }, 200);
                }
              },
              set onmessage(fn) { handlers.message = fn; },
              set onerror(fn) { handlers.error = fn; },
              terminate() {},
            };
            return fakeWorker;
          }
          return new OrigWorker(url, opts);
        };
      });

      console.log('[Harness Pack Update] Navigating to http://127.0.0.1:4173/...');
      await updatePage.goto('http://127.0.0.1:4173/');
      await updatePage.addStyleTag({ content: '.map-state-overlay { display: none !important; }' });

      // 1. Wait for update row affordance to appear
      console.log('[Harness Pack Update] Waiting for update affordance row...');
      await updatePage.waitForSelector('.pack-update-row', { timeout: 8000 });
      const updateRowText = await updatePage.$eval('.pack-update-row', (el) => el.textContent?.trim() || '');
      console.log(`[Harness Pack Update] Update row text: "${updateRowText}"`);

      if (!updateRowText.includes('v4 available') || !updateRowText.includes('Update')) {
        throw new Error(`Expected update row to state v4 available and have Update button, got: "${updateRowText}"`);
      }

      await takeScreenshot(updatePage, 'pack-update-available.png');

      // 2. Tap Update button
      console.log('[Harness Pack Update] Tapping Update button...');
      await updatePage.click('.pack-update-btn');

      // 3. Assert downloading state appears
      console.log('[Harness Pack Update] Asserting downloading progress appears...');
      await updatePage.waitForSelector('.installing-card', { timeout: 3000 });
      const stageBadgeText = await updatePage.$eval('.installer-stage-badge', (el) => el.textContent?.trim() || '');
      console.log(`[Harness Pack Update] Progress stage: "${stageBadgeText}"`);

      // 4. Wait for install to complete and update row to disappear
      console.log('[Harness Pack Update] Waiting for installation to complete and pack card to settle...');
      await updatePage.waitForSelector('.pack-installed-banner', { timeout: 8000 });
      await updatePage.waitForSelector('.pack-update-row', { state: 'detached', timeout: 5000 });

      // 5. Expand details to verify v4 is now installed
      console.log('[Harness Pack Update] Expanding details to verify installed version...');
      await updatePage.click('.pack-details-btn');
      await updatePage.waitForSelector('.pack-expanded-card', { timeout: 3000 });
      const cardTitle = await updatePage.$eval('.installer-card-title', (el) => el.textContent?.trim() || '');
      console.log(`[Harness Pack Update] Expanded card title: "${cardTitle}"`);

      if (!cardTitle.includes('v4')) {
        throw new Error(`Expected pack card title to show v4, got: "${cardTitle}"`);
      }

      await takeScreenshot(updatePage, 'pack-update-installed.png');
      console.log('[Harness Pack Update] SUCCESS: Pack update affordance verified, updated to v4, and state settled!');
    } catch (err) {
      await takeScreenshot(updatePage, 'pack-update-failed.png').catch(() => {});
      throw err;
    } finally {
      await updateContext.close();
    }
  });

  // ==========================================================================
  // Wave: Aesthetic polish (T2): world-class transit app finish
  // Scenario: Planner and cards match visual spec (flow: trip planning)
  // ==========================================================================
  await recordScenario('Planner and cards match visual spec', 'trip planning', async ({ takeScreenshot }) => {
    console.log('\n[Harness Visual Spec] --- TESTING PLANNER AND CARDS VISUAL SPEC ---');
    const visualContext = await browser.newContext({
      viewport: { width: 390, height: 844 },
      hasTouch: true,
      isMobile: true,
    });
    const visualPage = await visualContext.newPage();

    try {
      await visualPage.route(/\/api\/.*/, (route) => {
        const url = new URL(route.request().url());
        const pathname = url.pathname;
        if (pathname === '/api/cities') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify([{ id: 'nyc', name: 'New York City', slug: 'nyc', isInstalled: true }]),
          });
        }
        if (pathname === '/api/me') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email: 'test@example.com' }),
          });
        }
        if (pathname === '/api/basemap') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/vnd.pmtiles' },
            body: basemapBuffer,
          });
        }
        if (pathname === '/api/pack-info') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
            body: JSON.stringify({
              version: 4,
              size: 29800000,
              updated_at: '2026-10-04T00:00:00.000Z',
            }),
          });
        }
        return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: '{}' });
      });

      await visualPage.addInitScript(() => {
        localStorage.setItem('derivee_theme', 'dark');
        localStorage.setItem('derivee_pack_nyc', JSON.stringify({
          isInstalled: true,
          slug: 'nyc',
          version: 3,
          displayName: 'New York City',
          seasonLabel: 'Summer 2026 Timetable',
          installedAt: '2026-10-01T00:00:00.000Z',
          totalBytes: 29684406,
          files: [
            { name: 'city_config.json', size: 3401 },
            { name: 'transit.sqlite', size: 9744384 },
            { name: 'transit-lines.geojson', size: 407221 },
            { name: 'ultra_transfers.csr', size: 582906 },
            { name: 'timetable.bin', size: 7184128 },
            { name: 'walk_graph.bin', size: 47426176 },
            { name: 'patterns.json', size: 1000 },
          ],
        }));

        const REQUIRED = ['city_config.json', 'transit.sqlite', 'transit-lines.geojson', 'ultra_transfers.csr', 'timetable.bin', 'walk_graph.bin', 'patterns.json'];
        const fakeFile = { size: 1000, async arrayBuffer() { return new ArrayBuffer(8); } };

        const patternsArray = new Array(200).fill(null);
        patternsArray[36] = { route_id: "J" };
        patternsArray[167] = { route_id: "L" };
        const patternsFile = { size: 1000, async text() { return JSON.stringify(patternsArray); } };

        const fakeDir = {
          async getFileHandle(name) {
            if (!REQUIRED.includes(name)) throw new DOMException('nf', 'NotFoundError');
            if (name === 'patterns.json') return { async getFile() { return patternsFile; } };
            return { async getFile() { return fakeFile; } };
          },
        };
        Object.defineProperty(navigator, 'storage', {
          value: {
            async getDirectory() {
              return { async getDirectoryHandle(name) { if (name === 'nyc') return fakeDir; throw new DOMException('nf', 'NotFoundError'); } };
            },
          },
          configurable: true,
        });

        const REAL_SHAPED_SEGMENTS = [
          { board_stop_id: 72, exit_stop_id: 150, trip_id: 1045, departure_time: 28800, arrival_time: 29400, route_id: 167, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 150, exit_stop_id: 151, trip_id: 0, departure_time: 29400, arrival_time: 29700, route_id: 0, transfer_distance_m: 150, is_transfer: true },
          { board_stop_id: 151, exit_stop_id: 207, trip_id: 2099, departure_time: 29700, arrival_time: 30600, route_id: 36, transfer_distance_m: 0, is_transfer: false },
        ];

        window.__workerMode = 'normal';

        const RealWorker = window.Worker;
        window.Worker = function (url, opts) {
          if (String(url).includes('routing.worker')) {
            const handlers = {};
            return {
              postMessage(msg) {
                if (msg.type === 'INIT') {
                  setTimeout(() => {
                    handlers.message?.({ data: { type: 'READY', loadTimeMs: 45, patterns: patternsArray } });
                  }, 30);
                } else if (msg.type === 'ROUTE') {
                  setTimeout(() => {
                    if (window.__workerMode === 'empty') {
                      handlers.message?.({ data: { type: 'RESULT', queryId: msg.queryId, segments: [], profile: msg.profile, flags: msg.flags } });
                    } else if (window.__workerMode === 'error') {
                      handlers.message?.({ data: { type: 'ERROR', queryId: msg.queryId, message: 'Routing engine calculation timeout' } });
                    } else {
                      handlers.message?.({ data: { type: 'RESULT', queryId: msg.queryId, segments: REAL_SHAPED_SEGMENTS, profile: msg.profile, flags: msg.flags } });
                    }
                  }, 450);
                }
              },
              set onmessage(fn) { handlers.message = fn; },
              get onmessage() { return handlers.message; },
              set onerror(fn) { handlers.error = fn; },
              addEventListener(t, fn) { handlers[t] = fn; },
              removeEventListener(t) { delete handlers[t]; },
              terminate() {},
            };
          }
          return new RealWorker(url, opts);
        };
        window.Worker.prototype = RealWorker.prototype;
      });

      console.log('[Harness Visual Spec] Navigating to http://127.0.0.1:4173/...');
      await visualPage.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded' });
      await visualPage.addStyleTag({ content: '.map-state-overlay { display: none !important; }' });
      await visualPage.waitForSelector('.engine-status-ready', { timeout: 30000 });

      const captureDualTheme = async (page, darkName, lightName) => {
        await takeScreenshot(page, darkName);
        await page.click('.theme-toggle-light').catch(() => null);
        await new Promise((r) => setTimeout(r, 250));
        await takeScreenshot(page, lightName);
        await page.click('.theme-toggle-dark').catch(() => null);
        await new Promise((r) => setTimeout(r, 250));
      };

      // State 1: Sheet collapsed (peek detent 15dvh), brand lockup, offline ready indicator
      console.log('[Harness Visual Spec] Capturing State: Planner Idle (Collapsed Sheet 15dvh)...');
      await captureDualTheme(visualPage, 'visual-spec-planner-idle.png', 'visual-spec-light-planner-idle.png');

      // State 2: Sheet Half Detent (50dvh)
      console.log('[Harness Visual Spec] Expanding sheet to half detent (50dvh)...');
      await visualPage.evaluate(() => {
        document.querySelector('.bottom-sheet').style.height = '50dvh';
      });
      await new Promise((r) => setTimeout(r, 400));
      await captureDualTheme(visualPage, 'visual-spec-sheet-half.png', 'visual-spec-light-sheet-half.png');

      // State 3: Sheet Full Detent (90dvh) & Pack update row
      console.log('[Harness Visual Spec] Expanding sheet to full detent (90dvh)...');
      await visualPage.evaluate(() => {
        document.querySelector('.bottom-sheet').style.height = '90dvh';
      });
      await new Promise((r) => setTimeout(r, 400));

      // Check Pack card update-available affordance
      await visualPage.waitForSelector('.pack-update-row', { timeout: 5000 }).catch(() => null);
      await captureDualTheme(visualPage, 'visual-spec-pack-update-available.png', 'visual-spec-light-pack-update-available.png');

      // State 4: Departure Mode Segmented Control
      console.log('[Harness Visual Spec] Testing departure mode toggle...');
      await visualPage.click('.dep-mode-depart-at');
      await new Promise((r) => setTimeout(r, 300));
      const timeVisible = await visualPage.evaluate(() => {
        const timeGroup = document.querySelector('.trip-time-selector');
        return timeGroup && window.getComputedStyle(timeGroup).display !== 'none';
      });
      if (!timeVisible) {
        throw new Error('Expected departure time input to be visible when "Depart at" is active');
      }

      await visualPage.click('.dep-mode-now');
      await new Promise((r) => setTimeout(r, 300));
      await captureDualTheme(visualPage, 'visual-spec-departure-modes.png', 'visual-spec-light-departure-modes.png');

      // State 5: Routing State (Skeleton)
      console.log('[Harness Visual Spec] Triggering route to capture shimmering skeleton state...');
      await visualPage.click('.quick-preset-btn');
      await new Promise((r) => setTimeout(r, 400));

      // Click route button and quickly capture skeleton
      await visualPage.click('.trip-route-btn');
      await visualPage.waitForSelector('.itinerary-skeleton-card', { timeout: 4000 });
      console.log('[Harness Visual Spec] Shimmering skeleton card detected.');
      await takeScreenshot(visualPage, 'visual-spec-routing-skeleton.png');

      // State 6: Itinerary Results & Hero Arrival
      console.log('[Harness Visual Spec] Waiting for itinerary results to render...');
      await visualPage.waitForSelector('.itinerary-results-container', { timeout: 10000 });
      await new Promise((r) => setTimeout(r, 600));

      const itineraryAudit = await visualPage.evaluate(() => {
        const arrivalHero = document.querySelector('.arrival-time-hero');
        const heroText = arrivalHero?.textContent?.trim() || '';
        const cards = document.querySelectorAll('.itinerary-ranked-card');
        const connectors = document.querySelectorAll('.transfer-connector-row, .itinerary-transfer-connector');
        const legCards = document.querySelectorAll('.itinerary-leg-card');
        const badges = Array.from(document.querySelectorAll('.route-pill-badge')).map((b) => b.textContent?.trim());

        return {
          hasArrivalHero: Boolean(arrivalHero),
          heroText,
          cardCount: cards.length,
          connectorCount: connectors.length,
          legCount: legCards.length,
          badgeLabels: badges,
        };
      });

      console.log('[Harness Visual Spec] Itinerary Audit:', JSON.stringify(itineraryAudit));
      if (!itineraryAudit.hasArrivalHero || !itineraryAudit.heroText) {
        throw new Error('Expected arrival time hero element with formatted time, found none');
      }
      if (itineraryAudit.cardCount === 0) {
        throw new Error('Expected at least 1 itinerary card rendered');
      }
      if (itineraryAudit.connectorCount === 0) {
        throw new Error('Expected transfer connector row between legs');
      }
      await captureDualTheme(visualPage, 'visual-spec-itinerary-hero-arrival.png', 'visual-spec-light-itinerary-hero-arrival.png');

      // State 7: Connectivity: online / offline
      console.log('[Harness Visual Spec] Testing offline connectivity transition...');
      await visualContext.setOffline(true);
      await visualPage.evaluate(() => window.dispatchEvent(new Event('offline')));
      await new Promise((r) => setTimeout(r, 400));
      await captureDualTheme(visualPage, 'visual-spec-connectivity-offline.png', 'visual-spec-light-connectivity-offline.png');

      // Restore online
      await visualContext.setOffline(false);
      await visualPage.evaluate(() => window.dispatchEvent(new Event('online')));
      await new Promise((r) => setTimeout(r, 400));

      // State 8: Empty State (calm brand voice)
      console.log('[Harness Visual Spec] Testing empty state (no routes)...');
      await visualPage.evaluate(() => {
        window.__workerMode = 'empty';
      });
      await visualPage.click('.trip-route-btn');
      await visualPage.waitForSelector('.route-comparison-empty', { timeout: 6000 });
      const emptyStateAudit = await visualPage.evaluate(() => {
        const title = document.querySelector('.empty-title')?.textContent?.trim() || '';
        const subtitle = document.querySelector('.empty-subtitle')?.textContent?.trim() || '';
        return { title, subtitle };
      });
      console.log('[Harness Visual Spec] Empty state audit:', JSON.stringify(emptyStateAudit));
      if (!emptyStateAudit.title.includes('No direct transit route found')) {
        throw new Error(`Expected calm empty title "No direct transit route found", got: ${emptyStateAudit.title}`);
      }
      await captureDualTheme(visualPage, 'visual-spec-empty-state.png', 'visual-spec-light-empty-state.png');

      // State 9: Error State (calm recoverable error)
      console.log('[Harness Visual Spec] Testing recoverable error state...');
      await visualPage.evaluate(() => {
        window.__workerMode = 'error';
      });
      await visualPage.click('.trip-route-btn');
      await visualPage.waitForSelector('.itinerary-error-box', { timeout: 6000 });
      const errorAudit = await visualPage.evaluate(() => {
        const title = document.querySelector('.error-title')?.textContent?.trim() || '';
        const desc = document.querySelector('.error-description')?.textContent?.trim() || '';
        return { title, desc };
      });
      console.log('[Harness Visual Spec] Error state audit:', JSON.stringify(errorAudit));
      if (!errorAudit.title.includes('Routing Unavailable')) {
        throw new Error(`Expected error title "Routing Unavailable", got: ${errorAudit.title}`);
      }
      await captureDualTheme(visualPage, 'visual-spec-error-state.png', 'visual-spec-light-error-state.png');

      console.log('[Harness Visual Spec] SUCCESS: All states and transitions verified against visual spec in both themes!');
    } catch (err) {
      await takeScreenshot(visualPage, 'visual-spec-failed.png').catch(() => {});
      throw err;
    } finally {
      await visualContext.close();
    }
  });

  // ==========================================================================
  // SCENARIO 9: Light theme matches visual spec
  // ==========================================================================
  await recordScenario('Light theme matches visual spec', 'trip planning', async ({ takeScreenshot }) => {
    console.log('\n[Harness Light Spec] --- TESTING LIGHT THEME VISUAL SPEC & CONTRAST ---');
    const lightContext = await browser.newContext({
      viewport: { width: 390, height: 844 },
      hasTouch: true,
      isMobile: true,
    });
    const lightPage = await lightContext.newPage();

    try {
      await lightPage.route(/\/api\/.*/, (route) => {
        const url = new URL(route.request().url());
        const pathname = url.pathname;
        if (pathname === '/api/cities') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify([{ id: 'nyc', name: 'New York City', slug: 'nyc', isInstalled: true }]),
          });
        }
        if (pathname === '/api/me') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email: 'test@example.com' }),
          });
        }
        if (pathname === '/api/basemap') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/vnd.pmtiles' },
            body: basemapBuffer,
          });
        }
        if (pathname === '/api/pack-info') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
            body: JSON.stringify({
              version: 4,
              size: 29800000,
              updated_at: '2026-10-04T00:00:00.000Z',
            }),
          });
        }
        return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: '{}' });
      });

      await lightPage.addInitScript(() => {
        localStorage.setItem('derivee_theme', 'light');
        localStorage.setItem('derivee_pack_nyc', JSON.stringify({
          isInstalled: true,
          slug: 'nyc',
          version: 3,
          displayName: 'New York City',
          seasonLabel: 'Summer 2026 Timetable',
          installedAt: '2026-10-01T00:00:00.000Z',
          totalBytes: 29684406,
          files: [
            { name: 'city_config.json', size: 3401 },
            { name: 'transit.sqlite', size: 9744384 },
            { name: 'transit-lines.geojson', size: 407221 },
            { name: 'ultra_transfers.csr', size: 582906 },
            { name: 'timetable.bin', size: 7184128 },
            { name: 'walk_graph.bin', size: 47426176 },
            { name: 'patterns.json', size: 1000 },
          ],
        }));

        const REQUIRED = ['city_config.json', 'transit.sqlite', 'transit-lines.geojson', 'ultra_transfers.csr', 'timetable.bin', 'walk_graph.bin', 'patterns.json'];
        const fakeFile = { size: 1000, async arrayBuffer() { return new ArrayBuffer(8); } };

        const patternsArray = new Array(200).fill(null);
        patternsArray[36] = { route_id: "J" };
        patternsArray[167] = { route_id: "L" };
        const patternsFile = { size: 1000, async text() { return JSON.stringify(patternsArray); } };

        const fakeDir = {
          async getFileHandle(name) {
            if (!REQUIRED.includes(name)) throw new DOMException('nf', 'NotFoundError');
            if (name === 'patterns.json') return { async getFile() { return patternsFile; } };
            return { async getFile() { return fakeFile; } };
          },
        };
        Object.defineProperty(navigator, 'storage', {
          value: {
            async getDirectory() {
              return { async getDirectoryHandle(name) { if (name === 'nyc') return fakeDir; throw new DOMException('nf', 'NotFoundError'); } };
            },
          },
          configurable: true,
        });

        const REAL_SHAPED_SEGMENTS = [
          { board_stop_id: 72, exit_stop_id: 150, trip_id: 1045, departure_time: 28800, arrival_time: 29400, route_id: 167, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 150, exit_stop_id: 151, trip_id: 0, departure_time: 29400, arrival_time: 29700, route_id: 0, transfer_distance_m: 150, is_transfer: true },
          { board_stop_id: 151, exit_stop_id: 207, trip_id: 2099, departure_time: 29700, arrival_time: 30600, route_id: 36, transfer_distance_m: 0, is_transfer: false },
        ];

        window.__workerMode = 'normal';

        const RealWorker = window.Worker;
        window.Worker = function (url, opts) {
          if (String(url).includes('routing.worker')) {
            const handlers = {};
            return {
              postMessage(msg) {
                if (msg.type === 'INIT') {
                  setTimeout(() => {
                    handlers.message?.({ data: { type: 'READY', loadTimeMs: 45, patterns: patternsArray } });
                  }, 30);
                } else if (msg.type === 'ROUTE') {
                  setTimeout(() => {
                    if (window.__workerMode === 'empty') {
                      handlers.message?.({ data: { type: 'RESULT', queryId: msg.queryId, segments: [], profile: msg.profile, flags: msg.flags } });
                    } else if (window.__workerMode === 'error') {
                      handlers.message?.({ data: { type: 'ERROR', queryId: msg.queryId, message: 'Routing engine calculation timeout' } });
                    } else {
                      handlers.message?.({ data: { type: 'RESULT', queryId: msg.queryId, segments: REAL_SHAPED_SEGMENTS, profile: msg.profile, flags: msg.flags } });
                    }
                  }, 450);
                }
              },
              set onmessage(fn) { handlers.message = fn; },
              get onmessage() { return handlers.message; },
              set onerror(fn) { handlers.error = fn; },
            };
          }
          return new RealWorker(url, opts);
        };
        window.Worker.prototype = RealWorker.prototype;
      });

      console.log('[Harness Light Spec] Navigating to http://127.0.0.1:4173/...');
      await lightPage.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded' });
      await lightPage.addStyleTag({ content: '.map-state-overlay { display: none !important; }' });
      await lightPage.waitForSelector('.engine-status-ready', { timeout: 30000 });

      // Verify theme attribute is light
      const currentTheme = await lightPage.evaluate(() => document.documentElement.getAttribute('data-theme'));
      if (currentTheme !== 'light') {
        throw new Error(`Expected [data-theme="light"], got: ${currentTheme}`);
      }
      console.log('[Harness Light Spec] Verified data-theme="light" attribute.');

      // State 1: Planner Idle (Collapsed 15dvh)
      await takeScreenshot(lightPage, 'visual-spec-light-planner-idle.png');

      // State 2: Sheet Half Detent (50dvh)
      await lightPage.evaluate(() => {
        document.querySelector('.bottom-sheet').style.height = '50dvh';
      });
      await new Promise((r) => setTimeout(r, 400));
      await takeScreenshot(lightPage, 'visual-spec-light-sheet-half.png');

      // State 3: Sheet Full Detent (90dvh) & Pack update
      await lightPage.evaluate(() => {
        document.querySelector('.bottom-sheet').style.height = '90dvh';
      });
      await new Promise((r) => setTimeout(r, 400));
      await lightPage.waitForSelector('.pack-update-row', { timeout: 5000 }).catch(() => null);
      await takeScreenshot(lightPage, 'visual-spec-light-pack-update-available.png');

      // State 4: Departure Mode Segmented Control
      await lightPage.click('.dep-mode-depart-at');
      await new Promise((r) => setTimeout(r, 300));
      await lightPage.click('.dep-mode-now');
      await new Promise((r) => setTimeout(r, 300));
      await takeScreenshot(lightPage, 'visual-spec-light-departure-modes.png');

      // State 5: Routing State (Skeleton Shimmer)
      await lightPage.click('.quick-preset-btn');
      await new Promise((r) => setTimeout(r, 400));
      await lightPage.click('.trip-route-btn');
      await lightPage.waitForSelector('.itinerary-skeleton-card', { timeout: 4000 });
      await takeScreenshot(lightPage, 'visual-spec-light-routing-skeleton.png');

      // State 6: Itinerary Results & Hero Arrival & Contrast Check
      await lightPage.waitForSelector('.itinerary-results-container', { timeout: 10000 });
      await new Promise((r) => setTimeout(r, 600));

      const lightAudit = await lightPage.evaluate(() => {
        const arrivalHero = document.querySelector('.arrival-time-hero');
        const heroColor = arrivalHero ? window.getComputedStyle(arrivalHero).color : '';
        const badges = Array.from(document.querySelectorAll('.route-pill-badge'));
        const badgeColors = badges.map((b) => ({
          text: b.textContent?.trim(),
          color: window.getComputedStyle(b).color,
          bg: window.getComputedStyle(b).backgroundColor,
        }));
        return {
          heroColor,
          badgeColors,
        };
      });
      console.log('[Harness Light Spec] Light Audit:', JSON.stringify(lightAudit));
      await takeScreenshot(lightPage, 'visual-spec-light-itinerary-hero-arrival.png');

      // State 7: Connectivity offline
      await lightContext.setOffline(true);
      await lightPage.evaluate(() => window.dispatchEvent(new Event('offline')));
      await new Promise((r) => setTimeout(r, 400));
      await takeScreenshot(lightPage, 'visual-spec-light-connectivity-offline.png');
      await lightContext.setOffline(false);
      await lightPage.evaluate(() => window.dispatchEvent(new Event('online')));
      await new Promise((r) => setTimeout(r, 400));

      // State 8: Empty state
      await lightPage.evaluate(() => { window.__workerMode = 'empty'; });
      await lightPage.click('.trip-route-btn');
      await lightPage.waitForSelector('.route-comparison-empty', { timeout: 6000 });
      await takeScreenshot(lightPage, 'visual-spec-light-empty-state.png');

      // State 9: Error state
      await lightPage.evaluate(() => { window.__workerMode = 'error'; });
      await lightPage.click('.trip-route-btn');
      await lightPage.waitForSelector('.itinerary-error-box', { timeout: 6000 });
      await takeScreenshot(lightPage, 'visual-spec-light-error-state.png');

      // Theme toggle verification (Theme switches Dark -> Light without camera jump)
      console.log('[Harness Light Spec] Testing live toggle to Dark and back to Light...');

      const initialMapInfo = await lightPage.evaluate(() => {
        const map = window.__mapInstance;
        if (!map) return null;
        const center = map.getCenter();
        return {
          center: { lng: center.lng, lat: center.lat },
          zoom: map.getZoom(),
          pitch: map.getPitch(),
          bearing: map.getBearing(),
        };
      });

      // Tap Dark
      await lightPage.click('.theme-toggle-dark');
      await new Promise((r) => setTimeout(r, 600));
      const darkThemeAttr = await lightPage.evaluate(() => document.documentElement.getAttribute('data-theme'));
      if (darkThemeAttr !== 'dark') throw new Error(`Expected data-theme="dark", got: ${darkThemeAttr}`);

      const darkMapState = await lightPage.evaluate(() => {
        const map = window.__mapInstance;
        if (!map) return null;
        const style = map.getStyle();
        const bgLayer = style?.layers?.find((l) => l.id === 'background');
        return {
          bgColor: bgLayer?.paint?.['background-color'],
        };
      });
      if (darkMapState?.bgColor && darkMapState.bgColor.toLowerCase() === '#ffffff') {
        throw new Error(`Expected dark map restyle, but map background is still white: ${darkMapState.bgColor}`);
      }

      // Tap Light
      await lightPage.click('.theme-toggle-light');
      await new Promise((r) => setTimeout(r, 600));
      const lightThemeAttr = await lightPage.evaluate(() => document.documentElement.getAttribute('data-theme'));
      if (lightThemeAttr !== 'light') throw new Error(`Expected data-theme="light", got: ${lightThemeAttr}`);

      const lightMapState = await lightPage.evaluate(() => {
        const map = window.__mapInstance;
        if (!map) return null;
        const center = map.getCenter();
        const style = map.getStyle();
        const bgLayer = style?.layers?.find((l) => l.id === 'background');
        return {
          center: { lng: center.lng, lat: center.lat },
          zoom: map.getZoom(),
          pitch: map.getPitch(),
          bearing: map.getBearing(),
          bgColor: bgLayer?.paint?.['background-color'],
        };
      });
      if (lightMapState?.bgColor && lightMapState.bgColor.toLowerCase() !== '#ffffff') {
        throw new Error(`Expected porcelain light map background #ffffff, got: ${lightMapState.bgColor}`);
      }

      if (initialMapInfo && lightMapState) {
        const deltaLng = Math.abs(initialMapInfo.center.lng - lightMapState.center.lng);
        const deltaLat = Math.abs(initialMapInfo.center.lat - lightMapState.center.lat);
        const deltaZoom = Math.abs(initialMapInfo.zoom - lightMapState.zoom);
        if (deltaLng > 0.0001 || deltaLat > 0.0001 || deltaZoom > 0.01) {
          throw new Error(`Camera jump detected across theme toggle! Initial: ${JSON.stringify(initialMapInfo)}, Current: ${JSON.stringify(lightMapState)}`);
        }
      }

      console.log('[Harness Light Spec] SUCCESS: Light theme and transitions verified against visual spec!');
    } catch (err) {
      await takeScreenshot(lightPage, 'visual-spec-light-failed.png').catch(() => {});
      throw err;
    } finally {
      await lightContext.close();
    }
  });

  // ==========================================================================
  // SCENARIO 10: Device visual defects (light theme + map)
  // ==========================================================================
  await recordScenario('Device visual defects (light theme + map)', 'visual spec', async ({ takeScreenshot }) => {
    console.log('\n[Harness Device Visuals] --- TESTING DEVICE-REPORTED VISUAL DEFECTS (LIGHT THEME + MAP) ---');
    const deviceContext = await browser.newContext({
      viewport: { width: 390, height: 844 },
      hasTouch: true,
      isMobile: true,
    });
    const page = await deviceContext.newPage();
    page.on('console', (msg) => console.log(`[Scenario10 Console ${msg.type()}]`, msg.text()));
    page.on('pageerror', (err) => console.log(`[Scenario10 PageError]`, err.message));

    try {
      await page.route(/\/api\/.*/, (route) => {
        const url = new URL(route.request().url());
        const pathname = url.pathname;
        if (pathname === '/api/cities') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify([{ id: 'nyc', name: 'New York City', slug: 'nyc', isInstalled: true }]),
          });
        }
        if (pathname === '/api/me') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email: 'test@example.com' }),
          });
        }
        if (pathname === '/api/basemap') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/vnd.pmtiles' },
            body: basemapBuffer,
          });
        }
        if (pathname === '/api/pack-info') {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
            body: JSON.stringify({
              version: 4,
              size: 29800000,
              updated_at: '2026-10-04T00:00:00.000Z',
            }),
          });
        }
        return route.fulfill({ status: 200, headers: { 'Content-Type': 'application/json' }, body: '{}' });
      });

      await page.route(/\/data\/stops\.json/, (route) => {
        const stopsPath = path.join(DIST_DIR, 'data/stops.json');
        if (fs.existsSync(stopsPath)) {
          return route.fulfill({
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: fs.readFileSync(stopsPath),
          });
        }
        return route.continue();
      });

      await page.addInitScript(async ({ geojsonText }) => {
        localStorage.setItem('derivee_theme', 'light');
        localStorage.setItem('derivee_pack_nyc', JSON.stringify({
          isInstalled: true,
          slug: 'nyc',
          version: 3,
          displayName: 'New York City',
          seasonLabel: 'Summer 2026 Timetable',
          installedAt: '2026-10-01T00:00:00.000Z',
          totalBytes: 29684406,
          files: [
            { name: 'city_config.json', size: 3401 },
            { name: 'transit.sqlite', size: 9744384 },
            { name: 'transit-lines.geojson', size: 407221 },
            { name: 'ultra_transfers.csr', size: 582906 },
            { name: 'timetable.bin', size: 7184128 },
            { name: 'walk_graph.bin', size: 47426176 },
            { name: 'patterns.json', size: 1000 },
          ],
        }));

        const patternsArray = new Array(200).fill(null);
        patternsArray[36] = { route_id: 'J' };
        patternsArray[167] = { route_id: 'L' };

        // Write minimal transit-lines.geojson and required pack files to real OPFS before app loads
        if (navigator.storage && typeof navigator.storage.getDirectory === 'function') {
          const root = await navigator.storage.getDirectory();
          const nycDir = await root.getDirectoryHandle('nyc', { create: true });
          const geoHandle = await nycDir.getFileHandle('transit-lines.geojson', { create: true });
          const geoWritable = await geoHandle.createWritable();
          await geoWritable.write(geojsonText);
          await geoWritable.close();

          for (const fname of ['city_config.json', 'transit.sqlite', 'ultra_transfers.csr', 'timetable.bin', 'walk_graph.bin', 'patterns.json']) {
            const fh = await nycDir.getFileHandle(fname, { create: true });
            const w = await fh.createWritable();
            if (fname === 'city_config.json') {
              await w.write(JSON.stringify({ version: 3, displayName: 'New York City' }));
            } else if (fname === 'patterns.json') {
              await w.write(JSON.stringify(patternsArray));
            } else {
              await w.write(new Uint8Array([1, 2, 3, 4]));
            }
            await w.close();
          }
        }

        const REAL_SHAPED_SEGMENTS = [
          { board_stop_id: 72, exit_stop_id: 150, trip_id: 1045, departure_time: 28800, arrival_time: 29400, route_id: 167, transfer_distance_m: 0, is_transfer: false },
          { board_stop_id: 150, exit_stop_id: 151, trip_id: 0, departure_time: 29400, arrival_time: 29700, route_id: 0, transfer_distance_m: 150, is_transfer: true },
          { board_stop_id: 151, exit_stop_id: 207, trip_id: 2099, departure_time: 29700, arrival_time: 30600, route_id: 36, transfer_distance_m: 0, is_transfer: false },
        ];

        window.__workerMode = 'normal';

        const OrigWorker = window.Worker;
        window.Worker = function (url, opts) {
          if (String(url).includes('pack-installer.worker')) {
            const handlers = {};
            return {
              postMessage(msg) {
                if (msg.type === 'START_INSTALL') {
                  setTimeout(() => {
                    handlers.message?.({
                      data: {
                        type: 'PROGRESS',
                        stage: 'downloading',
                        loadedBytes: 14842203,
                        totalBytes: 29684406,
                        percent: 50,
                      },
                    });
                  }, 50);
                  setTimeout(() => {
                    handlers.message?.({
                      data: {
                        type: 'PROGRESS',
                        stage: 'verifying',
                        percent: 100,
                        message: 'Validating headers & SQLite signatures...',
                      },
                    });
                  }, 500);
                  setTimeout(() => {
                    handlers.message?.({
                      data: {
                        type: 'SUCCESS',
                        packState: {
                          isInstalled: true,
                          slug: 'nyc',
                          version: 4,
                          displayName: 'New York City (v4)',
                          seasonLabel: 'Fall 2026 Timetable',
                          installedAt: new Date().toISOString(),
                          totalBytes: 29800000,
                          files: [],
                        },
                      },
                    });
                  }, 1200);
                }
              },
              terminate() {},
              set onmessage(fn) { handlers.message = fn; },
              get onmessage() { return handlers.message; },
              set onerror(fn) { handlers.error = fn; },
            };
          }
          if (String(url).includes('routing.worker')) {
            const handlers = {};
            return {
              postMessage(msg) {
                if (msg.type === 'INIT') {
                  setTimeout(() => {
                    handlers.message?.({ data: { type: 'READY', loadTimeMs: 45, patterns: patternsArray } });
                  }, 30);
                } else if (msg.type === 'ROUTE') {
                  setTimeout(() => {
                    handlers.message?.({ data: { type: 'RESULT', queryId: msg.queryId, segments: REAL_SHAPED_SEGMENTS, profile: msg.profile, flags: msg.flags } });
                  }, 300);
                }
              },
              set onmessage(fn) { handlers.message = fn; },
              get onmessage() { return handlers.message; },
              set onerror(fn) { handlers.error = fn; },
            };
          }
          return new OrigWorker(url, opts);
        };
        window.Worker.prototype = OrigWorker.prototype;
      }, { geojsonText: transitLinesGeojsonText });

      console.log('[Harness Device Visuals] Navigating to http://127.0.0.1:4173/...');
      await page.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded' });
      await page.addStyleTag({ content: '.map-state-overlay { display: none !important; }' });
      await page.waitForSelector('.engine-status-ready', { timeout: 30000 });

      // ------------------------------------------------------------------------
      // CHECK 1: Zoomed-out map (z≈10–11, Midtown): parallel lines separable by eye
      // ------------------------------------------------------------------------
      console.log('[Harness Device Visuals] Check 1: Zoomed-out map line separation in Midtown...');
      const debugInfo = await page.evaluate(() => {
        const map = window.__mapInstance;
        return {
          hasMapInstance: Boolean(map),
          mapLoaded: map ? map.loaded() : false,
          layerIds: map && map.getStyle() ? map.getStyle().layers.map(l => l.id) : [],
          localStorageKeys: Object.keys(localStorage),
          packKey: localStorage.getItem('derivee_pack_nyc'),
        };
      });
      console.log('[Harness Debug Info]', JSON.stringify(debugInfo));
      await page.waitForFunction(() => {
        const map = window.__mapInstance;
        return map && map.getLayer('transit-lines-layer') != null && map.getLayer('transit-lines-casing') != null;
      }, { timeout: 20000 });

      await page.evaluate(() => {
        const map = window.__mapInstance;
        if (map) {
          map.jumpTo({ center: [-73.985, 40.758], zoom: 10.8 });
        }
      });
      await new Promise((r) => setTimeout(r, 800));

      const mapLayerAudit = await page.evaluate(() => {
        const map = window.__mapInstance;
        if (!map) return { hasMap: false };
        const style = map.getStyle();
        const casingLayer = style?.layers?.find((l) => l.id === 'transit-lines-casing');
        const ribbonLayer = style?.layers?.find((l) => l.id === 'transit-lines-layer');
        return {
          hasMap: true,
          hasCasingLayer: Boolean(casingLayer),
          casingColor: casingLayer?.paint?.['line-color'],
          hasRibbonLayer: Boolean(ribbonLayer),
          ribbonOffset: ribbonLayer?.paint?.['line-offset'],
        };
      });

      if (!mapLayerAudit.hasCasingLayer) {
        throw new Error('Check 1 Failed: Missing transit-lines-casing layer in MapLibre style');
      }
      if (!mapLayerAudit.hasRibbonLayer || !mapLayerAudit.ribbonOffset) {
        throw new Error('Check 1 Failed: Missing line-offset expression on transit-lines-layer');
      }
      console.log('[Harness Device Visuals] Map layer audit verified:', JSON.stringify(mapLayerAudit));

      // Collapse sheet to reveal full map view in Midtown
      await page.evaluate(() => {
        const sheet = document.querySelector('.bottom-sheet');
        if (sheet) sheet.style.height = '12dvh';
      });
      await new Promise((r) => setTimeout(r, 400));
      await takeScreenshot(page, 'parallel-lines-midtown-z11.png');

      // ------------------------------------------------------------------------
      // CHECK 2: Header wordmark legible in light AND dark
      // ------------------------------------------------------------------------
      console.log('[Harness Device Visuals] Check 2: Header wordmark legibility in light AND dark...');
      const wordmarkLightAudit = await page.evaluate(() => {
        const titleEl = document.querySelector('.app-title');
        const headerEl = document.querySelector('.app-header');
        if (!titleEl || !headerEl) return null;
        return {
          titleColor: window.getComputedStyle(titleEl).color,
          headerBg: window.getComputedStyle(headerEl).backgroundColor,
        };
      });

      console.log('[Harness Device Visuals] Light Wordmark Audit:', JSON.stringify(wordmarkLightAudit));
      if (!wordmarkLightAudit || wordmarkLightAudit.titleColor === 'rgb(241, 245, 249)' || wordmarkLightAudit.titleColor === 'rgb(255, 255, 255)') {
        throw new Error(`Check 2 Failed: Wordmark washed out in light mode: ${wordmarkLightAudit?.titleColor}`);
      }
      await takeScreenshot(page, 'header-wordmark-light.png');

      // Switch to dark theme
      await page.click('.theme-toggle-dark');
      await new Promise((r) => setTimeout(r, 500));

      const wordmarkDarkAudit = await page.evaluate(() => {
        const titleEl = document.querySelector('.app-title');
        const headerEl = document.querySelector('.app-header');
        if (!titleEl || !headerEl) return null;
        return {
          titleColor: window.getComputedStyle(titleEl).color,
          headerBg: window.getComputedStyle(headerEl).backgroundColor,
        };
      });
      console.log('[Harness Device Visuals] Dark Wordmark Audit:', JSON.stringify(wordmarkDarkAudit));
      if (!wordmarkDarkAudit || wordmarkDarkAudit.titleColor === 'rgb(10, 15, 22)' || wordmarkDarkAudit.titleColor === 'rgb(0, 0, 0)') {
        throw new Error(`Check 2 Failed: Wordmark dark on dark background: ${wordmarkDarkAudit?.titleColor}`);
      }
      await takeScreenshot(page, 'header-wordmark-dark.png');

      // Switch back to light theme for remaining checks
      await page.click('.theme-toggle-light');
      await new Promise((r) => setTimeout(r, 500));

      // ------------------------------------------------------------------------
      // CHECK 3: Pack install card: spinner arc follows icon square
      // ------------------------------------------------------------------------
      console.log('[Harness Device Visuals] Check 3: Pack install card spinner tracking icon square...');
      await page.evaluate(() => {
        const sheet = document.querySelector('.bottom-sheet');
        if (sheet) sheet.style.height = '90dvh';
      });
      await new Promise((r) => setTimeout(r, 400));

      await page.waitForSelector('.pack-update-btn', { timeout: 5000 });
      await page.click('.pack-update-btn');
      await page.waitForSelector('.installing-beacon', { timeout: 5000 });
      await new Promise((r) => setTimeout(r, 200));

      const spinnerAudit = await page.evaluate(() => {
        const beacon = document.querySelector('.installing-beacon');
        const spinner = beacon ? beacon.querySelector('.spinner-ring') : null;
        const arc = spinner ? spinner.querySelector('.spinner-arc') : null;
        if (!spinner || !arc) return null;
        const spinnerStyle = window.getComputedStyle(spinner);
        return {
          isSvg: spinner.tagName.toLowerCase() === 'svg',
          viewBox: spinner.getAttribute('viewBox'),
          hasArc: Boolean(arc),
          pathLength: arc.getAttribute('pathLength'),
          rx: arc.getAttribute('rx'),
          transform: spinnerStyle.transform,
        };
      });

      console.log('[Harness Device Visuals] Spinner Audit:', JSON.stringify(spinnerAudit));
      if (!spinnerAudit || !spinnerAudit.isSvg || spinnerAudit.pathLength !== '100') {
        throw new Error(`Check 3 Failed: Spinner does not conform to concentric contour tracking: ${JSON.stringify(spinnerAudit)}`);
      }
      await takeScreenshot(page, 'pack-install-spinner-tracking.png');

      // Wait for pack install to settle
      await page.waitForSelector('.installed-badge, .badge-installed, .pack-update-row', { timeout: 5000 }).catch(() => null);
      await new Promise((r) => setTimeout(r, 600));

      // ------------------------------------------------------------------------
      // CHECK 4: LEG 1 card: station names and connector line visible in light AND dark
      // ------------------------------------------------------------------------
      console.log('[Harness Device Visuals] Check 4: LEG 1 card station names and connector line in light AND dark...');
      await page.click('.quick-preset-btn');
      await new Promise((r) => setTimeout(r, 400));
      await page.click('.trip-route-btn');
      await page.waitForSelector('.itinerary-results-container', { timeout: 10000 });
      await new Promise((r) => setTimeout(r, 600));

      // Light theme audit
      const legLightAudit = await page.evaluate(() => {
        const legCard = document.querySelector('.itinerary-leg-card');
        const stationName = document.querySelector('.leg-stop-name');
        const connector = document.querySelector('.leg-connector-line');
        if (!stationName || !connector) return null;
        return {
          cardBg: legCard ? window.getComputedStyle(legCard).backgroundColor : '',
          stationNameColor: window.getComputedStyle(stationName).color,
          stationNameText: stationName.textContent?.trim(),
          connectorColor: window.getComputedStyle(connector).backgroundColor,
        };
      });

      console.log('[Harness Device Visuals] Light LEG 1 Audit:', JSON.stringify(legLightAudit));
      if (!legLightAudit || legLightAudit.stationNameColor === 'rgb(241, 245, 249)' || legLightAudit.stationNameColor === 'rgb(255, 255, 255)') {
        throw new Error(`Check 4 Failed: Leg station name white-on-white in light mode: ${legLightAudit?.stationNameColor}`);
      }
      if (legLightAudit.connectorColor === 'rgba(0, 0, 0, 0)' || legLightAudit.connectorColor === 'rgb(203, 213, 225)') {
        throw new Error(`Check 4 Failed: Leg connector line invisible in light mode: ${legLightAudit?.connectorColor}`);
      }
      await takeScreenshot(page, 'leg1-card-detail-light.png');

      // Dark theme audit
      await page.click('.theme-toggle-dark');
      await new Promise((r) => setTimeout(r, 500));

      const legDarkAudit = await page.evaluate(() => {
        const legCard = document.querySelector('.itinerary-leg-card');
        const stationName = document.querySelector('.leg-stop-name');
        const connector = document.querySelector('.leg-connector-line');
        if (!stationName || !connector) return null;
        return {
          cardBg: legCard ? window.getComputedStyle(legCard).backgroundColor : '',
          stationNameColor: window.getComputedStyle(stationName).color,
          stationNameText: stationName.textContent?.trim(),
          connectorColor: window.getComputedStyle(connector).backgroundColor,
        };
      });

      console.log('[Harness Device Visuals] Dark LEG 1 Audit:', JSON.stringify(legDarkAudit));
      if (!legDarkAudit || legDarkAudit.stationNameColor === 'rgb(10, 15, 22)' || legDarkAudit.stationNameColor === 'rgb(0, 0, 0)') {
        throw new Error(`Check 4 Failed: Leg station name dark in dark mode: ${legDarkAudit?.stationNameColor}`);
      }
      await takeScreenshot(page, 'leg1-card-detail-dark.png');

      console.log('[Harness Device Visuals] SUCCESS: All 4 device visual defects verified fixed!');
    } catch (err) {
      await takeScreenshot(page, 'device-visual-defects-failed.png').catch(() => {});
      throw err;
    } finally {
      await deviceContext.close();
    }
  });

} finally {
  if (browser) await browser.close();
  server.close();
  if (xvfbProc) {
    xvfbProc.kill();
  }

  // Generate Reports
  const reportData = {
    runId,
    commit,
    timestamp: new Date().toISOString(),
    stats: {
      total: scenarioResults.length,
      passed: scenarioResults.filter((s) => s.status === 'passed').length,
      failed: scenarioResults.filter((s) => s.status === 'failed').length,
      durationMs: scenarioResults.reduce((acc, s) => acc + s.durationMs, 0),
    },
    reportPath: path.join(reportDir, 'index.html'),
    scenarios: scenarioResults,
    suites: [
      {
        title: 'Diagnostic Harness',
        specs: scenarioResults.map((s) => ({
          title: s.name,
          ok: s.status === 'passed',
          tests: [
            {
              timeout: 60000,
              annotations: [{ type: 'flow', description: s.flow }],
              expectedStatus: 'passed',
              status: s.status === 'passed' ? 'expected' : 'unexpected',
              results: [
                {
                  status: s.status,
                  duration: s.durationMs,
                  errors: s.error ? [s.error] : [],
                  attachments: s.screenshots.map((shot) => ({
                    name: 'screenshot',
                    contentType: 'image/png',
                    path: shot,
                  })),
                },
              ],
            },
          ],
        })),
      },
    ],
  };

  const jsonReportPath = path.join(reportDir, 'report.json');
  fs.writeFileSync(jsonReportPath, JSON.stringify(reportData, null, 2), 'utf8');
  console.log(`[Harness] Wrote JSON report to: ${jsonReportPath}`);

  const htmlReport = generateHtmlReport(reportData);
  const htmlReportPath = path.join(reportDir, 'index.html');
  fs.writeFileSync(htmlReportPath, htmlReport, 'utf8');
  console.log(`[Harness] Wrote HTML report to: ${htmlReportPath}`);

  if (scenarioResults.some((s) => s.status === 'failed')) {
    process.exitCode = 1;
  }
}
