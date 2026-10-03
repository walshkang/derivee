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
                  if (msg.type === 'INIT') handlers.message?.({ data: { type: 'READY', loadTimeMs: 90 } });
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
