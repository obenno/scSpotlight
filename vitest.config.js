import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';
import viteConfig from './vite.config.js';

const shinyStub = fileURLToPath(new URL('./srcjs/test/shinyStub.js', import.meta.url));

export default defineConfig({
  ...viteConfig,
  resolve: {
    ...(viteConfig.resolve || {}),
    alias: {
      ...(viteConfig.resolve?.alias || {}),
      shiny: shinyStub,
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: [],
  },
});
