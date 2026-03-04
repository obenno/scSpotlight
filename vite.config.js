import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    lib: {
      entry: 'srcjs/index.js',
      name: 'scSpotlight',
      formats: ['umd'],
      fileName: () => 'index.js',
    },
    outDir: 'inst/app/www',
    sourcemap: true,
    minify: 'terser',
    rollupOptions: {
      external: ['shiny', 'jquery', 'waiter'],
      output: {
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
