import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';
import { VitePWA } from 'vite-plugin-pwa';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  root: __dirname,
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
      workbox: {
        // Precache only app shell assets (including zstd.wasm)
        globPatterns: [
          '**/*.{js,css,html,ico,pbf,woff,woff2,wasm}'
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
          '**/README.md'
        ],
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api/],
        cleanupOutdatedCaches: true
      }
    })
  ]
});
