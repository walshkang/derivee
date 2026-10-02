import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';
import { VitePWA } from 'vite-plugin-pwa';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function getGitCommitHash(): string {
  if (process.env.CF_PAGES_COMMIT_SHA) {
    return process.env.CF_PAGES_COMMIT_SHA.slice(0, 7);
  }
  if (process.env.VITE_COMMIT_HASH) {
    return process.env.VITE_COMMIT_HASH.slice(0, 7);
  }
  if (process.env.COMMIT_HASH) {
    return process.env.COMMIT_HASH.slice(0, 7);
  }
  try {
    return execSync('git rev-parse --short HEAD', { encoding: 'utf8' }).trim();
  } catch {
    return 'unknown';
  }
}

function getBuildTimestamp(): string {
  if (process.env.VITE_BUILD_TIME) {
    return process.env.VITE_BUILD_TIME;
  }
  if (process.env.BUILD_TIME) {
    return process.env.BUILD_TIME;
  }
  return new Date().toISOString();
}

const buildCommitHash = getGitCommitHash();
const buildTimestamp = getBuildTimestamp();


function basemapDevMiddleware() {
  return {
    name: 'basemap-dev-middleware',
    configureServer(server: any) {
      server.middlewares.use('/api/basemap', (req: any, res: any) => {
        const filePath = path.resolve(__dirname, '../DeriveeNative/Derivee/basemap-nyc.pmtiles');
        if (!fs.existsSync(filePath)) {
          res.statusCode = 404;
          res.end(JSON.stringify({ error: 'not_found' }));
          return;
        }
        const stat = fs.statSync(filePath);
        const totalSize = stat.size;
        const range = req.headers.range;

        res.setHeader('Content-Type', 'application/vnd.pmtiles');
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Expose-Headers', 'Content-Length, Content-Range, ETag');

        if (range) {
          const parts = range.replace(/bytes=/, '').split('-');
          const start = parseInt(parts[0], 10);
          const end = parts[1] ? parseInt(parts[1], 10) : totalSize - 1;
          const chunksize = (end - start) + 1;
          res.statusCode = 206;
          res.setHeader('Content-Range', `bytes ${start}-${end}/${totalSize}`);
          res.setHeader('Content-Length', chunksize);
          const stream = fs.createReadStream(filePath, { start, end });
          stream.pipe(res);
        } else {
          res.statusCode = 200;
          res.setHeader('Content-Length', totalSize);
          const stream = fs.createReadStream(filePath);
          stream.pipe(res);
        }
      });
    }
  };
}

export const workboxConfig = {
  // Precache only app shell assets (including zstd.wasm and stops.json)
  globPatterns: [
    '**/*.{js,css,html,ico,pbf,woff,woff2,wasm,json}'
  ],
  // Explicitly exclude any data packs, binary archives, or large data payloads
  globIgnores: [
    '**/*.pack*',
    '**/*.zst',
    '**/*.pmtiles',
    '**/*.bin',
    '**/*.sqlite*',
    '**/*.csr',
    '**/*.tar',
    '**/package.json',
    '**/README.md'
  ],
  navigateFallback: null,
  runtimeCaching: [
    {
      urlPattern: ({ request, url }: { request: Request; url?: URL }) =>
        request.mode === 'navigate' && !url?.pathname.startsWith('/api'),
      handler: 'NetworkFirst' as const,
      options: {
        cacheName: 'navigations',
        networkTimeoutSeconds: 3,
        expiration: {
          maxEntries: 50,
          maxAgeSeconds: 24 * 60 * 60
        }
      }
    }
  ],
  cleanupOutdatedCaches: true
};

export default defineConfig({
  root: __dirname,
  define: {
    __BUILD_HASH__: JSON.stringify(buildCommitHash),
    __BUILD_TIME__: JSON.stringify(buildTimestamp),
  },
  esbuild: {
    tsconfigRaw: JSON.stringify({
      compilerOptions: {
        target: 'es2022',
        jsx: 'react-jsx',
        jsxImportSource: 'preact'
      }
    })
  },
  worker: {
    format: 'es'
  },
  optimizeDeps: {
    exclude: ['@bokuweb/zstd-wasm']
  },
  plugins: [
    preact(),
    basemapDevMiddleware(),
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      manifestFilename: 'manifest.webmanifest',
      manifest: {
        name: 'Dérivée',
        short_name: 'Dérivée',
        description: 'Offline-first NYC transit routing & fog-of-war exploration',
        start_url: '/',
        display: 'standalone',
        orientation: 'portrait',
        background_color: '#090d13',
        theme_color: '#0d1117',
        categories: ['navigation', 'travel'],
        icons: [
          {
            src: '/icons/icon-192.png',
            sizes: '192x192',
            type: 'image/png'
          },
          {
            src: '/icons/icon-512.png',
            sizes: '512x512',
            type: 'image/png'
          },
          {
            src: '/icons/icon-512-maskable.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable'
          },
          {
            src: '/apple-touch-icon.png',
            sizes: '180x180',
            type: 'image/png'
          },
          {
            src: '/icons/apple-touch-icon.png',
            sizes: '180x180',
            type: 'image/png'
          },
          {
            src: '/icons/icon.svg',
            sizes: 'any',
            type: 'image/svg+xml'
          },
          {
            src: '/favicon.svg',
            sizes: 'any',
            type: 'image/svg+xml'
          }
        ]
      },
      workbox: workboxConfig
    })
  ]
});
