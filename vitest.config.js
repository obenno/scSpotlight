import { fileURLToPath } from 'node:url';
import { configDefaults, defineConfig } from 'vitest/config';
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
    exclude: [...configDefaults.exclude, 'tests/e2e/**', 'benchmarks/**'],
  },
});
