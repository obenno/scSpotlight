import { defineConfig } from "@playwright/test";

const port = Number(process.env.SCSPOTLIGHT_E2E_PORT || 8899);

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 120_000,
  expect: {
    timeout: 30_000,
  },
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    headless: true,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  webServer: {
    command: "pixi run Rscript tests/e2e/run-analysis-app.R",
    url: `http://127.0.0.1:${port}`,
    timeout: 120_000,
    reuseExistingServer: false,
    env: {
      ...process.env,
      SCSPOTLIGHT_E2E_PORT: String(port),
    },
  },
});
