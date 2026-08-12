import { defineConfig } from "@playwright/test";

const port = Number(process.env.SCSPOTLIGHT_BENCHMARK_PORT || 8900);
const appCommand = process.env.SCSPOTLIGHT_BENCHMARK_APP_COMMAND ||
  "pixi run Rscript benchmarks/run_explore_1m_app.R";
const testMatch = process.env.SCSPOTLIGHT_BENCHMARK_TEST_MATCH || "explore-1m.spec.js";
const outputDir = process.env.SCSPOTLIGHT_PLAYWRIGHT_OUTPUT_DIR || "test-results";

export default defineConfig({
  testDir: "./benchmarks",
  testMatch,
  timeout: 45 * 60 * 1000,
  outputDir,
  expect: {
    timeout: 8 * 60 * 1000,
  },
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  reporter: "list",
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    headless: true,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  webServer: {
    command: appCommand,
    url: `http://127.0.0.1:${port}`,
    timeout: 5 * 60 * 1000,
    reuseExistingServer: false,
    env: {
      ...process.env,
      SCSPOTLIGHT_BENCHMARK_PORT: String(port),
    },
  },
});
