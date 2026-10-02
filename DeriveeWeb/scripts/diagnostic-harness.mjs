import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
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
      // Security check
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

// 3. Launch Firefox and run test
let browser;
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

  const allRequests = [];
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
    allRequests.push(info);
    console.log(`[Request Finished] ${info}`);
  });

  page.on('requestfailed', (req) => {
    const failure = req.failure()?.errorText || 'Unknown failure';
    const entry = {
      url: req.url(),
      method: req.method(),
      error: failure,
    };
    failedRequests.push(entry);
    pendingRequests.delete(req);
    console.warn(`[Request Failed] ${req.method()} ${req.url()}: ${failure}`);
  });

  // Load basemap fixture buffer
  if (!fs.existsSync(FIXTURE_PATH)) {
    throw new Error(`PMTiles fixture not found at: ${FIXTURE_PATH}`);
  }
  const basemapBuffer = fs.readFileSync(FIXTURE_PATH);
  console.log(`[Harness] Loaded PMTiles fixture (${basemapBuffer.length} bytes)`);

  // Route mocking: Mocks EVERY /api/* request
  await page.route(/\/api\/.*/, (route) => {
    const req = route.request();
    const parsed = new URL(req.url());
    if (parsed.pathname === '/api/basemap') {
      console.log(`[Route Intercept] Serving /api/basemap (${basemapBuffer.length} bytes)`);
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
      console.log('[Route Intercept] Serving /api/cities');
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
      console.log('[Route Intercept] Serving /api/me');
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
      console.warn(`[Route Intercept UNEXPECTED] ${req.method()} ${req.url()}`);
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

  console.log('[Harness] Navigating to http://127.0.0.1:4173/...');
  await page.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded' });

  console.log('[Harness] Page loaded. Watching for basemap download and mount...');

  // Check WebGL in page
  const webglStatus = await page.evaluate(() => {
    const canvas = document.createElement('canvas');
    const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
    if (!gl) return { ok: false, error: 'No WebGL context' };
    return { ok: true, renderer: gl.getParameter(gl.RENDERER) };
  });
  console.log('[Harness] In-page WebGL check:', webglStatus);

  // Check if Retry button exists (if already in error state)
  const retryBtn = page.locator('.map-retry-btn');
  if (await retryBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
    console.log('[Harness] Retry button visible. Clicking it...');
    await retryBtn.click();
  }

  // Poll for state change up to 60 seconds
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

      const screenshotPath = '/tmp/map-ready.png';
      await page.screenshot({ path: screenshotPath });
      console.log(`[Harness] Saved screenshot to ${screenshotPath}`);

      // Wait a moment for any background tile loading or rendering
      await new Promise((r) => setTimeout(r, 2000));

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
          break;
        }
        if (cur.state === 'map-error') {
          console.log(`[Harness Reload] FAILURE: Cached basemap entered map-error!`);
          console.log(`[Harness Reload] Details: ${cur.details}`);
          break;
        }
        await new Promise((r) => setTimeout(r, 500));
      }

      console.log('\n[Harness] --- TESTING TRIP PLANNER CARD SCROLL GESTURE REGRESSION ---');
      const mobileContext = await browser.newContext({
        viewport: { width: 390, height: 844 },
        hasTouch: true,
        isMobile: true,
      });
      const mobilePage = await mobileContext.newPage();

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
      await mobileContext.close();

      break;
    }

    if (state.state === 'map-error') {
      settled = true;
      errorDesc = state.desc;
      errorDetails = state.details;
      console.log(`[Harness] FAILURE: Basemap entered map-error state!`);
      console.log(`[Harness] Error Desc: ${errorDesc}`);
      console.log(`[Harness] Error Details:\n${errorDetails}`);
      break;
    }

    await new Promise((r) => setTimeout(r, 500));
  }

  if (!settled) {
    console.log('[Harness] TIMEOUT: 60s elapsed without reaching map-ready or map-error.');
  }

  // Report pending requests
  console.log('\n--- PENDING REQUESTS AT SETTLE/TIMEOUT ---');
  if (pendingRequests.size === 0) {
    console.log('None.');
  } else {
    for (const [, info] of pendingRequests) {
      console.log(`- ${info.method} ${info.url} (pending for ${Date.now() - info.startTime}ms)`);
    }
  }

  console.log('\n--- FAILED REQUESTS ---');
  if (failedRequests.length === 0) {
    console.log('None.');
  } else {
    for (const f of failedRequests) {
      console.log(`- ${f.method} ${f.url}: ${f.error}`);
    }
  }

  console.log('\n--- PAGE ERRORS ---');
  if (pageErrors.length === 0) {
    console.log('None.');
  } else {
    for (const pe of pageErrors) {
      console.log(`- ${pe}`);
    }
  }

  console.log('\n--- HARNESS COMPLETE ---');
} finally {
  if (browser) await browser.close();
  server.close();
  if (xvfbProc) {
    xvfbProc.kill();
  }
}
