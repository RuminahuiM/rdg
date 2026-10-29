/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// `--mode mock` serves the app with the in-browser mock API (src/mocks); the normal build
// talks to /api on the Static Web App. The local Functions host (tools/Start-ApiLocal.ps1)
// listens on 7071; `npm run dev` proxies /api there.
export default defineConfig(({ mode }) => ({
  plugins: [react()],
  // The mock service worker is served only in mock mode, never in the deployed app.
  publicDir: mode === 'mock' ? 'mock-public' : 'public',
  server: {
    port: 5173,
    proxy: { '/api': 'http://localhost:7071' },
  },
  build: {
    sourcemap: true,
    chunkSizeWarningLimit: 1500,
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
    css: false,
    env: { TZ: 'UTC' },
  },
}));
