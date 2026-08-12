import fs from "node:fs";
import path from "node:path";
import { expect, test } from "@playwright/test";

const scratchRoot = process.env.SCSPOTLIGHT_REAL_EXPLORE_ROOT ||
  path.join(process.env.SCSPOTLIGHT_TEMP_ROOT || "benchmarks/.tmp", "cellxgene-explore");
const runId = process.env.SCSPOTLIGHT_REAL_EXPLORE_RUN_ID || "latest";
const runRoot = path.join(scratchRoot, "runs", runId);
const resultsFile = path.join(runRoot, "results.json");
const descriptorFile = path.join(runRoot, "artifact.json");
const pidFile = path.join(runRoot, "shiny-server.pid");
const maxRssLimitBytes = 6_000_000_000;
const rssLimitBytes = Number(process.env.SCSPOTLIGHT_RSS_LIMIT_BYTES || String(maxRssLimitBytes));

if (!Number.isFinite(rssLimitBytes) || rssLimitBytes <= 0 || rssLimitBytes > maxRssLimitBytes) {
  throw new Error(`SCSPOTLIGHT_RSS_LIMIT_BYTES must be a positive value no greater than ${maxRssLimitBytes}.`);
}

const parseProcStatus = (pid) => {
  const statusPath = `/proc/${pid}/status`;
  if (!fs.existsSync(statusPath)) {
    return { pid, rssKb: null, hwmKb: null };
  }
  const status = fs.readFileSync(statusPath, "utf8");
  const parseKb = (label) => {
    const match = status.match(new RegExp(`^${label}:\\s+(\\d+)`, "m"));
    return match ? Number(match[1]) : null;
  };

  return { pid, rssKb: parseKb("VmRSS"), hwmKb: parseKb("VmHWM") };
};

const kbToBytes = (value) => Number.isFinite(value) ? value * 1024 : null;

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

const getChromiumProcessMemory = async (browserSession) => {
  const info = await browserSession.send("SystemInfo.getProcessInfo");
  const trackedTypes = new Set(["browser", "renderer", "gpu", "GPU", "utility"]);
  const processes = info.processInfo
    .filter((process) => trackedTypes.has(process.type))
    .map((process) => ({
      type: process.type,
      ...parseProcStatus(process.id),
    }));
  const rssValues = processes.map((process) => process.rssKb).filter(Number.isFinite);
  const hwmValues = processes.map((process) => process.hwmKb).filter(Number.isFinite);

  return {
    processes,
    aggregateRssKb: rssValues.length ? rssValues.reduce((total, value) => total + value, 0) : null,
    aggregateHwmKb: hwmValues.length ? hwmValues.reduce((total, value) => total + value, 0) : null,
  };
};

test("real CellxGene Explore archive records first View, selected gene, and RSS gates", async ({ page, browser }) => {
  test.setTimeout(75 * 60 * 1000);
  await expect.poll(() => fs.existsSync(resultsFile), { timeout: 60_000 }).toBe(true);
  await expect.poll(() => fs.existsSync(descriptorFile), { timeout: 60_000 }).toBe(true);
  await expect.poll(() => fs.existsSync(pidFile), { timeout: 5 * 60 * 1000 }).toBe(true);

  const descriptor = JSON.parse(fs.readFileSync(descriptorFile, "utf8"));
  const serverPid = readServerPid();
  const serverSamples = [parseProcStatus(serverPid)];
  const browserSession = await browser.newBrowserCDPSession();
  const chromiumSamples = [];
  let samplingChromium = false;
  const sampleChromium = async () => {
    if (samplingChromium) return;
    samplingChromium = true;
    try {
      chromiumSamples.push(await getChromiumProcessMemory(browserSession));
    } finally {
      samplingChromium = false;
    }
  };

  await sampleChromium();
  const sampler = setInterval(() => {
    try {
      serverSamples.push(parseProcStatus(serverPid));
      void sampleChromium();
    } catch {
      // The final sample is captured before raw results are written.
    }
  }, 100);

  try {
    await page.goto("/");
    await expect(page.locator("#dataInput-dataDirFile-selectized")).toBeAttached();

    const dataSelect = page.locator("#dataInput-dataDirFile-selectized");
    const initialReadyBeforeLoad = await readShinyInputValue(page, "initialPlotReady");
    await dataSelect.click();
    await dataSelect.fill(descriptor.archive_filename);
    const archiveOption = page
      .locator(".selectize-dropdown:visible .option")
      .filter({ hasText: descriptor.archive_filename });
    await expect(archiveOption).toBeVisible();
    const firstViewStarted = Date.now();
    await archiveOption.click();
    await expect(page.locator("#cellCount .cell-count-total")).toHaveText(
      new Intl.NumberFormat().format(descriptor.cell_count),
      { timeout: 60 * 60 * 1000 },
    );
    await expect.poll(() => readShinyInputValue(page, "initialPlotReady"), {
      timeout: 60 * 60 * 1000,
    }).not.toBe(initialReadyBeforeLoad);
    await expect(page.locator(".waiter-overlay.waiter-fullscreen")).toBeHidden();
    const firstViewLatencyMs = Date.now() - firstViewStarted;

    const featureSelect = page.locator("#inputFeatures-features-selectized");
    await expect(featureSelect).toBeAttached();
    const expressionStarted = performance.now();
    await featureSelect.click();
    await featureSelect.fill(descriptor.selected_gene);
    await page
      .locator(".selectize-dropdown:visible .option")
      .filter({ hasText: descriptor.selected_gene })
      .click();
    await expect(page.locator("#featureSparkLine .featureSparkLine")).toHaveCount(1, {
      timeout: 10 * 60 * 1000,
    });
    await expect(page.locator("#featureSparkLine .featureSparkLine")).toHaveAttribute(
      "data-status",
      "ready",
    );
    const expressionLatencyMs = Math.round(performance.now() - expressionStarted);

    await page.waitForTimeout(1000);
    serverSamples.push(parseProcStatus(serverPid));
    await sampleChromium();
    const browserMemory = await getBrowserMemory(page);
    const result = JSON.parse(fs.readFileSync(resultsFile, "utf8"));
    const serverRssValues = serverSamples.map((sample) => sample.rssKb).filter(Number.isFinite);
    const serverHwmValues = serverSamples.map((sample) => sample.hwmKb).filter(Number.isFinite);
    const chromiumRssValues = chromiumSamples
      .map((sample) => sample.aggregateRssKb)
      .filter(Number.isFinite);
    const chromiumHwmValues = chromiumSamples
      .map((sample) => sample.aggregateHwmKb)
      .filter(Number.isFinite);
    const serverPeakHwmBytes = kbToBytes(
      serverHwmValues.length ? Math.max(...serverHwmValues) : null,
    );
    const chromiumPeakHwmBytes = kbToBytes(
      chromiumHwmValues.length ? Math.max(...chromiumHwmValues) : null,
    );
    const serverGatePassed = Number.isFinite(serverPeakHwmBytes) && serverPeakHwmBytes < rssLimitBytes;
    const chromiumGatePassed = Number.isFinite(chromiumPeakHwmBytes) &&
      chromiumPeakHwmBytes < rssLimitBytes;

    result.browser = {
      method: {
        first_view: "Elapsed wall time from selecting the full real Explore archive to a rendered real cell count.",
        selected_gene: "Elapsed wall time from selecting the recorded real-artifact gene to the received client sparkline.",
        server_rss: "Linux /proc sampled every 100 ms for the single-threaded Explore Mode R Shiny process, including archive extraction and browser transfers.",
        chromium_rss: "Linux /proc sampled every 100 ms for Chromium browser, renderer, GPU, and utility processes discovered through CDP.",
        browser_memory: "Chromium renderer JS heap and DOM counters after a one-second settled period.",
      },
      first_view_latency_ms: firstViewLatencyMs,
      selected_gene_expression_end_to_end_latency_ms: expressionLatencyMs,
      server_rss: {
        pid: serverPid,
        baseline_rss_kb: serverRssValues[0] ?? null,
        peak_sampled_rss_kb: serverRssValues.length ? Math.max(...serverRssValues) : null,
        peak_process_hwm_kb: serverHwmValues.length ? Math.max(...serverHwmValues) : null,
        peak_process_hwm_bytes: serverPeakHwmBytes,
        sample_interval_ms: 100,
        sample_count: serverSamples.length,
      },
      chromium_rss: {
        peak_sampled_aggregate_rss_kb: chromiumRssValues.length ? Math.max(...chromiumRssValues) : null,
        peak_aggregate_hwm_kb: chromiumHwmValues.length ? Math.max(...chromiumHwmValues) : null,
        peak_aggregate_hwm_bytes: chromiumPeakHwmBytes,
        sample_interval_ms: 100,
        sample_count: chromiumSamples.length,
        final_processes: chromiumSamples.at(-1)?.processes ?? [],
      },
      browser_memory: browserMemory,
      environment: {
        browser_version: browser.version(),
        user_agent: await page.evaluate(() => navigator.userAgent),
        viewport: page.viewportSize(),
      },
    };
    result.acceptance = {
      ...result.acceptance,
      rss_limit_bytes: rssLimitBytes,
      browser_visualization_rss_under_limit: serverGatePassed && chromiumGatePassed,
      browser_server_rss_under_limit: serverGatePassed,
      chromium_rss_under_limit: chromiumGatePassed,
      real_explore_evidence_status: result.acceptance.processing_rss_under_limit &&
        serverGatePassed && chromiumGatePassed
        ? "passed"
        : "failed_rss_gate",
    };
    fs.writeFileSync(resultsFile, `${JSON.stringify(result, null, 2)}\n`);

    expect(serverGatePassed).toBe(true);
    expect(chromiumGatePassed).toBe(true);
  } finally {
    clearInterval(sampler);
    await browserSession.detach().catch(() => {});
  }
});
