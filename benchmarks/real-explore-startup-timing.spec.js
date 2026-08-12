import fs from "node:fs";
import path from "node:path";
import { expect, test } from "@playwright/test";

const archiveFile = process.env.SCSPOTLIGHT_REAL_EXPLORE_TIMING_ARCHIVE_FILE;
const descriptorFile = process.env.SCSPOTLIGHT_REAL_EXPLORE_TIMING_DESCRIPTOR_FILE;
const resultsFile = process.env.SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_RESULTS_FILE;
const serverEventFile = process.env.SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_EVENT_FILE;
const inputMode = process.env.SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_INPUT_MODE || "server_data_dir";

if (!archiveFile || !descriptorFile || !resultsFile || !serverEventFile) {
  throw new Error("Explore startup timing paths must be configured.");
}

const readJsonLines = (file) => {
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
};

const waitForServerEvent = async (phase, state = "end") => {
  await expect.poll(
    () => readJsonLines(serverEventFile).some((event) => (
      event.phase === phase && event.state === state
    )),
    { timeout: 60 * 60 * 1000 },
  ).toBe(true);
  return readJsonLines(serverEventFile).find((event) => (
    event.phase === phase && event.state === state
  ));
};

const phaseDurations = (events) => events
  .filter((event) => Number.isFinite(event.elapsedMs))
  .map((event) => ({
    source: event.source,
    phase: event.phase,
    state: event.state,
    elapsed_ms: Math.round(event.elapsedMs),
    output_bytes: Number.isFinite(event.outputBytes) ? event.outputBytes : null,
    reduction_name: event.reductionName ?? null,
  }));

test("real Explore startup records phase-level timing", async ({ page }) => {
  test.setTimeout(75 * 60 * 1000);
  const descriptor = JSON.parse(fs.readFileSync(descriptorFile, "utf8"));
  const browserEvents = [];
  const pageNavigationStarted = Date.now();

  await page.addInitScript(() => {
    globalThis.SCSPOTLIGHT_BENCHMARK_STARTUP_TIMING = true;
    globalThis.scspotlightBenchmarkStartupTimings = [];
  });
  await page.goto("/");

  const inputReadyAt = Date.now();
  let archiveSelectionStartedAt;
  if (inputMode === "browser_upload") {
    const uploadStarted = Date.now();
    await page.locator("#dataInput-dataInput").setInputFiles(archiveFile);
    archiveSelectionStartedAt = uploadStarted;
    browserEvents.push({
      source: "browser",
      phase: "browser_upload_input_dispatch",
      state: "end",
      elapsedMs: Date.now() - uploadStarted,
      outputBytes: fs.statSync(archiveFile).size,
    });
  } else {
    await expect(page.locator("#dataInput-dataDirFile-selectized")).toBeAttached();
    const dataSelect = page.locator("#dataInput-dataDirFile-selectized");
    await dataSelect.click();
    await dataSelect.fill(descriptor.archive_filename);
    const archiveOption = page
      .locator(".selectize-dropdown:visible .option")
      .filter({ hasText: descriptor.archive_filename });
    await expect(archiveOption).toBeVisible();
    archiveSelectionStartedAt = Date.now();
    await archiveOption.click();
  }

  const datasetLoadStarted = await waitForServerEvent("server_dataset_load", "start");
  const archiveSelectionToServerLoadStartMs = (
    datasetLoadStarted.serverTimestampEpochMs - archiveSelectionStartedAt
  );
  if (inputMode === "browser_upload") {
    browserEvents.push({
      source: "browser",
      phase: "browser_upload_to_server_dataset_load_start",
      state: "end",
      elapsedMs: archiveSelectionToServerLoadStartMs,
      outputBytes: fs.statSync(archiveFile).size,
    });
  }
  await expect(page.locator("#cellCount .cell-count-total")).toHaveText(
    new Intl.NumberFormat().format(descriptor.cell_count),
    { timeout: 60 * 60 * 1000 },
  );
  await expect.poll(
    () => page.evaluate(() => (
      globalThis.scspotlightBenchmarkStartupTimings || []
    ).some((event) => event.phase === "browser_initial_plot_ready")),
    { timeout: 60 * 60 * 1000 },
  ).toBe(true);
  await expect(page.locator(".waiter-overlay.waiter-fullscreen")).toBeHidden();
  await waitForServerEvent("server_metadata_ipc", "end");
  await waitForServerEvent("server_reductions_ipc", "end");

  const firstViewSettledAt = Date.now();
  const capturedBrowserEvents = await page.evaluate(() => (
    globalThis.scspotlightBenchmarkStartupTimings || []
  ));
  const serverEvents = readJsonLines(serverEventFile);
  const browserTimingEvents = [
    ...browserEvents,
    ...capturedBrowserEvents.filter((event) => event.source === "browser"),
  ];
  const initialPlotReady = capturedBrowserEvents.find((event) => (
    event.source === "browser" && event.phase === "browser_initial_plot_ready"
  ));
  if (!initialPlotReady) {
    throw new Error("The browser did not record initial plot readiness.");
  }
  const result = {
    schema_version: 2,
    command: "pixi run benchmark-real-explore-startup-timing",
    input_mode: inputMode,
    archive: {
      filename: descriptor.archive_filename,
      bytes: fs.statSync(archiveFile).size,
      cell_count: descriptor.cell_count,
      feature_count: descriptor.feature_count,
    },
    timing: {
      page_to_input_ready_ms: inputReadyAt - pageNavigationStarted,
      archive_selection_to_server_dataset_load_start_ms: archiveSelectionToServerLoadStartMs,
      initial_plot_ready_after_archive_selection_ms: (
        initialPlotReady.browserTimestampEpochMs - archiveSelectionStartedAt
      ),
      initial_plot_ready_after_page_navigation_ms: (
        initialPlotReady.browserTimestampEpochMs - pageNavigationStarted
      ),
      first_view_settled_after_archive_selection_ms: (
        firstViewSettledAt - archiveSelectionStartedAt
      ),
      first_view_settled_after_page_navigation_ms: (
        firstViewSettledAt - pageNavigationStarted
      ),
      phase_durations: phaseDurations([...serverEvents, ...browserTimingEvents]),
      server_events: serverEvents,
      browser_events: browserTimingEvents,
    },
  };
  fs.mkdirSync(path.dirname(resultsFile), { recursive: true });
  fs.writeFileSync(resultsFile, `${JSON.stringify(result, null, 2)}\n`);
});
