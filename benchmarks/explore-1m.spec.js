import fs from "node:fs";
import path from "node:path";
import { expect, test } from "@playwright/test";

const benchmarkRoot = process.env.SCSPOTLIGHT_BENCHMARK_ROOT || "benchmarks/.tmp/explore-1m";
const resultsFile = process.env.SCSPOTLIGHT_BENCHMARK_RESULTS_FILE ||
  path.join(benchmarkRoot, "results.json");
const pidFile = process.env.SCSPOTLIGHT_BENCHMARK_PID_FILE ||
  path.join(benchmarkRoot, "shiny-server.pid");
const archiveName = "scspotlight-explore-1m.explore-parquet.zip";

const parseProcStatus = (pid) => {
  const statusPath = `/proc/${pid}/status`;
  if (!fs.existsSync(statusPath)) {
    return { rssKb: null, hwmKb: null };
  }
  const status = fs.readFileSync(statusPath, "utf8");
  const parseKb = (label) => {
    const match = status.match(new RegExp(`^${label}:\\s+(\\d+)`, "m"));
    return match ? Number(match[1]) : null;
  };

  return { rssKb: parseKb("VmRSS"), hwmKb: parseKb("VmHWM") };
};

const readServerPid = () => Number(fs.readFileSync(pidFile, "utf8").trim());

const readShinyInputValue = (page, inputId) => page.evaluate((id) => {
  const value = window.Shiny?.shinyapp?.$inputValues?.[id];
  return value == null ? value : JSON.parse(JSON.stringify(value));
}, inputId);

const getBrowserMemory = async (page) => {
  const session = await page.context().newCDPSession(page);
  await session.send("Performance.enable");
  const metrics = await session.send("Performance.getMetrics");
  const dom = await session.send("Memory.getDOMCounters").catch(() => null);
  const heap = await session.send("Runtime.getHeapUsage").catch(() => null);
  const metricMap = Object.fromEntries(metrics.metrics.map(({ name, value }) => [name, value]));
  const performanceMemory = await page.evaluate(() => {
    const memory = performance.memory;
    return memory
      ? {
        usedJsHeapSize: memory.usedJSHeapSize,
        totalJsHeapSize: memory.totalJSHeapSize,
        jsHeapSizeLimit: memory.jsHeapSizeLimit,
      }
      : null;
  });

  return {
    renderer_js_heap_used_bytes: metricMap.JSHeapUsedSize ?? null,
    renderer_js_heap_total_bytes: metricMap.JSHeapTotalSize ?? null,
    runtime_heap_used_bytes: heap?.usedSize ?? null,
    runtime_heap_total_bytes: heap?.totalSize ?? null,
    dom_nodes: dom?.nodes ?? null,
    dom_documents: dom?.documents ?? null,
    performance_memory: performanceMemory,
  };
};

test("1M Explore workload records first View, selected-gene, RSS, and browser memory", async ({ page, browser }) => {
  test.setTimeout(10 * 60 * 1000);
  await expect.poll(() => fs.existsSync(resultsFile)).toBe(true);
  await expect.poll(() => fs.existsSync(pidFile)).toBe(true);

  const serverPid = readServerPid();
  const rssSamples = [parseProcStatus(serverPid)];
  const sampler = setInterval(() => {
    try {
      rssSamples.push(parseProcStatus(serverPid));
    } catch {
      // The final sample is captured before results are written.
    }
  }, 100);

  try {
    await page.goto("/");
    await expect(page.locator("#dataInput-dataDirFile-selectized")).toBeAttached();

    const dataSelect = page.locator("#dataInput-dataDirFile-selectized");
    const initialReadyBeforeLoad = await readShinyInputValue(page, "initialPlotReady");
    await dataSelect.click();
    await dataSelect.fill(archiveName);
    const archiveOption = page
      .locator(".selectize-dropdown:visible .option")
      .filter({ hasText: archiveName });
    await expect(archiveOption).toBeVisible();
    const firstViewStarted = Date.now();
    await archiveOption.click();
    await expect(page.locator("#cellCount .cell-count-total")).toHaveText("1,000,000", {
      timeout: 8 * 60 * 1000,
    });
    await expect.poll(() => readShinyInputValue(page, "initialPlotReady")).not.toBe(
      initialReadyBeforeLoad,
    );
    await expect(page.locator(".waiter-overlay.waiter-fullscreen")).toBeHidden();
    const firstViewLatencyMs = Date.now() - firstViewStarted;

    const featureSelect = page.locator("#inputFeatures-features-selectized");
    await expect(featureSelect).toBeAttached();
    const expressionStarted = performance.now();
    await featureSelect.click();
    await featureSelect.fill("BENCHMARK_GENE");
    await page
      .locator(".selectize-dropdown:visible .option")
      .filter({ hasText: "BENCHMARK_GENE" })
      .click();
    await expect(page.locator("#featureSparkLine .featureSparkLine")).toHaveCount(1, {
      timeout: 3 * 60 * 1000,
    });
    await expect(page.locator("#featureSparkLine .featureSparkLine")).toHaveAttribute(
      "data-status",
      "ready",
    );
    const expressionLatencyMs = Math.round(performance.now() - expressionStarted);

    await page.waitForTimeout(1000);
    rssSamples.push(parseProcStatus(serverPid));
    const browserMemory = await getBrowserMemory(page);
    const result = JSON.parse(fs.readFileSync(resultsFile, "utf8"));
    const rssValues = rssSamples.map((sample) => sample.rssKb).filter(Number.isFinite);
    const hwmValues = rssSamples.map((sample) => sample.hwmKb).filter(Number.isFinite);

    result.browser = {
      method: {
        first_view: "Elapsed wall time from selecting the local Explore archive to the rendered 1,000,000-cell count.",
        selected_gene: "Elapsed wall time from selecting BENCHMARK_GENE to the received client sparkline.",
        server_rss: "Linux /proc sampled every 100 ms for the single-threaded R Shiny process.",
        browser_memory: "Chromium renderer JS heap and DOM counters after a one-second settled period.",
      },
      first_view_latency_ms: firstViewLatencyMs,
      selected_gene_expression_end_to_end_latency_ms: expressionLatencyMs,
      server_rss: {
        pid: serverPid,
        baseline_rss_kb: rssValues[0] ?? null,
        peak_sampled_rss_kb: rssValues.length ? Math.max(...rssValues) : null,
        peak_process_hwm_kb: hwmValues.length ? Math.max(...hwmValues) : null,
        sample_interval_ms: 100,
        sample_count: rssSamples.length,
      },
      browser_memory: browserMemory,
      environment: {
        browser_version: browser.version(),
        user_agent: await page.evaluate(() => navigator.userAgent),
        viewport: page.viewportSize(),
      },
    };
    fs.writeFileSync(resultsFile, `${JSON.stringify(result, null, 2)}\n`);
  } finally {
    clearInterval(sampler);
  }
});
