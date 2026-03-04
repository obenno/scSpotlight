import { defineConfig } from 'vite';

export default defineConfig({
  define: {
    global: 'globalThis',
  },
  build: {
    lib: {
      entry: 'srcjs/index.js',
      name: 'scSpotlight',
      formats: ['umd'],
      fileName: () => 'index.js',
    },
    outDir: 'inst/app/www',
    emptyOutDir: false,
    sourcemap: true,
    minify: 'terser',
    rollupOptions: {
      external: ['shiny', 'jquery', 'waiter'],
      output: {
        intro: 'globalThis.process = globalThis.process || { env: {} }; globalThis.process.env = globalThis.process.env || {}; globalThis.process.env.NODE_ENV = globalThis.process.env.NODE_ENV || "production"; var process = globalThis.process; var global = globalThis;',
        globals: {
          shiny: 'Shiny',
          jquery: 'jQuery',
          waiter: 'waiter',
        },
      },
    },
  },
  server: {
    host: true,
    port: 5173,
  },
});
