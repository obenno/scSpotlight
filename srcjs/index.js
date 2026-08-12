import "shiny";
// not sure why waiter was not exposed as library
// cannot import even added it to externals config
// seems nothing wrong in the webpack config
// https://github.com/JohnCoene/waiter/blob/776f9f3ccd27aa3322d6c6d37c47b3d7b1f393e6/webpack.common.js#L64
// https://webpack.js.org/configuration/output/#outputlibrary
// exporting not tested, remove import temporarily
// import "waiter";

import {
  initFullScreenSpinner,
  removeFullScreenSpinner,
  addOverlaySpinner,
} from "./modules/spinner.js";

import {
  initFloatingPlots,
  requestFloatingPlotRefresh,
} from "./modules/floatingPlots.js";

//import bootstrap-icons
import "bootstrap-icons/font/bootstrap-icons.css";

import {
  reglScatterCanvas,
  expandMeta,
  getMetaLevels,
  invalidateMetaCache,
  sortStringArray,
} from "./modules/deckScatter.js";

import {
  initShelter,
  featurePlot,
  vlnPlot,
  dotPlot,
  initWebRInstance,
} from "./modules/webr.js";

import {
  readArrowIPC,
  fetchArrowIPCBuffer,
  decodeArrowIPC,
  getFloat32Column,
  parseMetaFromArrow,
} from "./modules/arrowReader.js";

import {
  createSparkLine,
  updateSparkLine,
} from "./modules/featureSparkLine.js";

//import './modules/virtualSelect.js'

// keep global variables as small as possible
// query elements inside functions when necessary

// id of the mainClusterPlot parent div
const mainPlotElId = "mainClusterPlot-clusterPlot";
// featurePlot canvas id
const featurePlotElId = "featurePlotCanvas";
const renameClusterIds = {
  title: "renameCluster-selectCellFromCat",
  chosenGroup: "renameCluster-chosenGroup",
  chosenSplit: "renameCluster-chosenSplit",
  selectedCellsText: "renameCluster-selectedCellsText",
  assign: "renameCluster-assign",
  selectedCellsPayload: "renameCluster-selectedCellsPayload",
  categorySelectionContext: "renameCluster-categorySelectionContext",
  assignmentIntent: "renameCluster-assignmentIntent",
};
const renameSelectionState = {
  lastGroupBy: null,
  lastSplitBy: null,
};
// vlnSelect widget id
const vlnDropDownId = "vlnDropDown";
// vlnPlot canvas id
const vlnPlotElId = "VlnPlot";
// dotPlot canvas id
const dotPlotElId = "DotPlot";
const vlnPlotStatusId = "floatingVlnPlotStatus";
const dotPlotActionId = "floatingDotPlotAction";
const dotPlotStatusId = "floatingDotPlotStatus";
const dotPlotOrderListId = "floatingDotPlotOrderList";
const dotPlotOrderModeId = "floatingDotPlotOrderMode";
const dotPlotOrderResetId = "floatingDotPlotOrderReset";
const featurePlotActionId = "floatingFeaturePlotAction";
const featurePlotStatusId = "floatingFeaturePlotStatus";
const featurePlotNcolId = "floatingFeaturePlotNcol";
const elbowPlotElId = "elbowPlotCanvas";
const elbowPlotStatusId = "floatingElbowPlotStatus";

// R waiter package spinners
// keep the style exactly the same with R function

var reglElementData = new reglScatterCanvas("reglScatter");

// init webR instance for browser-side plotting helpers
// keep a dedicated shelter because concurrent plot jobs can otherwise step on shared state
let webR;
let shelter;

// global variables to store spinners
let vlnPlotSpinner;
let dotPlotSpinner;
let featurePlotSpinner;
let mainPlotSpinner;
let initialPlotRequestSeq = 0;
let pendingInitialPlotRequestId = 0;
let renderedInitialPlotRequestId = 0;
let activeMetaRequestSeq = 0;
let activeMetaRequest = null;
let activeMetaVersion = null;
let activeReductionRequestSeq = 0;
let activeReductionRequest = null;
let activeReductionVersion = null;
let activePcaRequestSeq = 0;
let activePcaRequest = null;
let activePcaVersion = null;
let pcaTransferFailed = false;
const startupTimingEnabled = () => globalThis.SCSPOTLIGHT_BENCHMARK_STARTUP_TIMING === true;

const recordStartupTiming = (phase, state = "mark", details = {}) => {
  if (!startupTimingEnabled()) return;
  const event = {
    source: "browser",
    phase,
    state,
    browserTimestampMs: performance.now(),
    browserTimestampEpochMs: Date.now(),
    ...details,
  };
  globalThis.scspotlightBenchmarkStartupTimings = [
    ...(globalThis.scspotlightBenchmarkStartupTimings || []),
    event,
  ];
};

const recordServerStartupTiming = (event = {}) => {
  if (!startupTimingEnabled()) return;
  globalThis.scspotlightBenchmarkStartupTimings = [
    ...(globalThis.scspotlightBenchmarkStartupTimings || []),
    {
      ...event,
      browserReceivedTimestampMs: performance.now(),
      browserReceivedTimestampEpochMs: Date.now(),
    },
  ];
};

const measureStartupTiming = (phase, fn, details = {}) => {
  if (!startupTimingEnabled()) {
    return fn();
  }
  const started = performance.now();
  recordStartupTiming(phase, "start", details);
  try {
    const value = fn();
    recordStartupTiming(phase, "end", {
      ...details,
      elapsedMs: performance.now() - started,
    });
    return value;
  } catch (error) {
    recordStartupTiming(phase, "error", {
      ...details,
      elapsedMs: performance.now() - started,
    });
    throw error;
  }
};

const notifyInitialPlotReady = (requestId) => {
  if (
    requestId !== pendingInitialPlotRequestId ||
    requestId !== renderedInitialPlotRequestId
  ) {
    return;
  }
  pendingInitialPlotRequestId = 0;
  recordStartupTiming("browser_initial_plot_ready", "mark", { requestId });
  Shiny.setInputValue("initialPlotReady", Date.now(), { priority: "event" });
};

const notifyInitialPlotSettled = (requestId) => {
  if (requestId !== pendingInitialPlotRequestId) {
    return;
  }
  pendingInitialPlotRequestId = 0;
  Shiny.setInputValue("initialPlotReady", Date.now(), { priority: "event" });
};

const safelyRunStartupSync = (label, fn) => {
  try {
    fn();
  } catch (error) {
    console.error(`Startup sync failed: ${label}`, error);
  }
};

const ipcCache = {
  reductions: new Map(),
  expr: new Map(),
  reductionVersion: null,
  exprVersion: null,
  exprAssay: null,
  invalidatedExprVersion: null,
  exprGeneration: 0,
};

const REDUCTION_CACHE_LIMIT = 5;
const EXPR_CACHE_LIMIT = 100;
const CACHE_KEY_DELIMITER = "::";

const touchCacheEntry = (cacheMap, key) => {
  if (!cacheMap.has(key)) return null;
  const value = cacheMap.get(key);
  cacheMap.delete(key);
  cacheMap.set(key, value);
  return value;
};

const setCacheEntry = (cacheMap, key, value, limit) => {
  if (cacheMap.has(key)) {
    cacheMap.delete(key);
  }
  cacheMap.set(key, value);
  while (cacheMap.size > limit) {
    const oldestKey = cacheMap.keys().next().value;
    cacheMap.delete(oldestKey);
  }
};

const updateReductionCacheKeys = () => {
  Shiny.setInputValue(
    "updateReduction-cachedReductionKeys",
    Array.from(ipcCache.reductions.keys()),
    { priority: "event" },
  );
};

const updateExprCacheKeys = () => {
  Shiny.setInputValue(
    "inputFeatures-cachedExprKeys",
    Array.from(ipcCache.expr.keys()),
    { priority: "event" },
  );
};

const ensureReductionCacheVersion = (version) => {
  if (
    ipcCache.reductionVersion !== null &&
    Number(version) < Number(ipcCache.reductionVersion)
  ) {
    return false;
  }

  if (ipcCache.reductionVersion !== version) {
    ipcCache.reductions.clear();
    ipcCache.reductionVersion = version;
    updateReductionCacheKeys();
  }

  return true;
};

const ensureExprCacheVersion = (version, assay = null) => {
  if (ipcCache.exprVersion !== null && Number(version) < Number(ipcCache.exprVersion)) {
    return false;
  }

  if (
    ipcCache.invalidatedExprVersion !== null &&
    version !== null &&
    Number(version) <= Number(ipcCache.invalidatedExprVersion)
  ) {
    return false;
  }

  if (ipcCache.exprVersion !== version || ipcCache.exprAssay !== assay) {
    ipcCache.expr.clear();
    ipcCache.exprVersion = version;
    ipcCache.exprAssay = assay;
    if (
      ipcCache.invalidatedExprVersion !== null &&
      version !== null &&
      Number(version) > Number(ipcCache.invalidatedExprVersion)
    ) {
      ipcCache.invalidatedExprVersion = null;
    }
    updateExprCacheKeys();
  }

  return true;
};

const isCurrentExprCacheIdentity = (version, assay) => (
  ipcCache.exprVersion === version && ipcCache.exprAssay === assay
);

const makeReductionCacheKey = (version, reductionName) =>
  `${version}${CACHE_KEY_DELIMITER}${reductionName}`;

const makeExprCacheKey = (version, assay, geneName) =>
  `${version}${CACHE_KEY_DELIMITER}${assay}${CACHE_KEY_DELIMITER}${geneName}`;

const getFeatureSparkLineGene = (containerEl) => (
  containerEl?.querySelector(".feature-gene-symbol")?.textContent ||
  containerEl?.querySelector("span")?.textContent ||
  ""
);

const getFeatureSparkLineElements = () => [
  ...(document.getElementById("featureSparkLine")?.querySelectorAll(".featureSparkLine") || []),
];

const isExpressionFeatureActive = (geneName) => {
  if (!geneName) {
    return true;
  }
  const sparkLines = getFeatureSparkLineElements();
  return sparkLines.some((sparkLine) => getFeatureSparkLineGene(sparkLine) === geneName);
};

const isCurrentExpressionPayload = (msg) => (
  isCurrentExprCacheIdentity(msg.exprVersion, msg.assay) &&
  isExpressionFeatureActive(msg.geneName)
);

const isCurrentExpressionRequest = (msg, generation) => (
  generation === ipcCache.exprGeneration &&
  isCurrentExpressionPayload(msg)
);

const getCurrentReductionName = () => {
  const el = document.getElementById("updateReduction-reduction");
  return el?.value && el.value !== "None" ? el.value : null;
};

const resolveActiveReduction = (reductions, activeReductionName) => {
  if (!Array.isArray(reductions) || reductions.length === 0) {
    return null;
  }

  const findByName = (name) => reductions.find(
    (reduction) => reduction.reductionName === name,
  );

  return (
    findByName(activeReductionName) ||
    findByName(getCurrentReductionName()) ||
    reductions[0]
  );
};

const startMetaRequest = (version) => {
  if (
    activeMetaVersion != null &&
    version != null &&
    Number(version) < Number(activeMetaVersion)
  ) {
    return { stale: true, version };
  }

  activeMetaRequestSeq += 1;
  activeMetaVersion = version;
  activeMetaRequest = {
    id: activeMetaRequestSeq,
    version,
  };
  return activeMetaRequest;
};

const isCurrentMetaRequest = (request) => (
  request &&
  !request.stale &&
  activeMetaRequest &&
  request.id === activeMetaRequest.id &&
  request.version === activeMetaRequest.version &&
  request.version === activeMetaVersion
);

const isCurrentMetaVersion = (version) => (
  activeMetaVersion == null || Number(version) >= Number(activeMetaVersion)
);

const startReductionRequest = (version, reductionName = null) => {
  if (
    activeReductionVersion != null &&
    version != null &&
    Number(version) < Number(activeReductionVersion)
  ) {
    return { stale: true, version, reductionName };
  }

  activeReductionRequestSeq += 1;
  activeReductionVersion = version;
  activeReductionRequest = {
    id: activeReductionRequestSeq,
    version,
    reductionName,
  };
  return activeReductionRequest;
};

const isCurrentReductionRequest = (request) => (
  request &&
  !request.stale &&
  activeReductionRequest &&
  request.id === activeReductionRequest.id &&
  request.version === activeReductionRequest.version &&
  request.version === activeReductionVersion &&
  request.reductionName === activeReductionRequest.reductionName
);

const isCurrentReductionVersion = (version) => (
  activeReductionVersion == null || Number(version) >= Number(activeReductionVersion)
);

const startPcaRequest = (version) => {
  if (
    activePcaVersion != null &&
    version != null &&
    Number(version) < Number(activePcaVersion)
  ) {
    return { stale: true, version };
  }

  activePcaRequestSeq += 1;
  activePcaVersion = version;
  activePcaRequest = {
    id: activePcaRequestSeq,
    version,
  };
  return activePcaRequest;
};

const isCurrentPcaRequest = (request) => (
  request &&
  !request.stale &&
  activePcaRequest &&
  request.id === activePcaRequest.id &&
  request.version === activePcaRequest.version &&
  request.version === activePcaVersion
);

const isCurrentPcaVersion = (version) => (
  version == null || activePcaVersion == null || Number(version) >= Number(activePcaVersion)
);

const formatPlotTransferError = (payload = {}) => {
  const payloadType = payload.payloadType || payload.type;
  if (payloadType === "metadata_patch") {
    const cols = normalizeChangedMetaCols(payload.cols);
    const colLabel = cols.length > 0 ? cols.join(", ") : "the requested columns";
    return {
      heading: "Metadata update could not apply",
      body: `The update for \`${colLabel}\` could not be applied. Existing metadata is still shown. Retry the action or reload the dataset.`,
    };
  }

  if (payloadType === "metadata") {
    return {
      heading: "Metadata could not load",
      body: "Could not load metadata for this dataset. Retry transfer, or reload the dataset.",
    };
  }

  if (payloadType === "expression") {
    const geneName = payload.geneName || "the selected gene";
    const assay = payload.assay || "the selected assay";
    return {
      heading: "Expression could not load",
      body: `Could not load expression for \`${geneName}\` in \`${assay}\`. The category scatter remains available. Retry transfer or choose another gene.`,
    };
  }

  if (payloadType === "reductions") {
    return {
      heading: "Scatter could not initialize",
      body: "No active reduction finished rendering. Retry transfer, or reload the dataset.",
    };
  }

  if (payloadType === "reduction") {
    const reductionName = payload.reductionName || payload.activeReduction;
    return {
      heading: "Reduction could not load",
      body: reductionName
        ? `Could not load \`${reductionName}\`. Try switching reductions, retry transfer, or reload the dataset.`
        : "Could not load the selected reduction. Try switching reductions, retry transfer, or reload the dataset.",
    };
  }

  return {
    heading: "Scatter could not initialize",
    body: "No active reduction finished rendering. Retry transfer, or reload the dataset.",
  };
};

const showPlotTransferError = (payloadOrMessage) => {
  const parentDiv = document.getElementById(mainPlotElId);
  if (!parentDiv) return;

  const formatted = typeof payloadOrMessage === "string"
    ? { heading: payloadOrMessage, body: "" }
    : formatPlotTransferError(payloadOrMessage);

  let errorEl = parentDiv.querySelector("#plot-transfer-error");
  if (!errorEl) {
    errorEl = document.createElement("div");
    errorEl.id = "plot-transfer-error";
    errorEl.setAttribute("role", "alert");
    errorEl.setAttribute("aria-live", "assertive");
    errorEl.style.position = "absolute";
    errorEl.style.inset = "1rem auto auto 1rem";
    errorEl.style.zIndex = "10";
    errorEl.style.maxWidth = "min(34rem, calc(100% - 2rem))";
    errorEl.style.padding = "0.75rem 1rem";
    errorEl.style.borderRadius = "0.5rem";
    errorEl.style.background = "#fff3cd";
    errorEl.style.border = "1px solid #ffecb5";
    errorEl.style.color = "#664d03";
    parentDiv.appendChild(errorEl);
  }

  errorEl.textContent = formatted.body
    ? `${formatted.heading}\n${formatted.body}`
    : formatted.heading;
};

const clearPlotTransferError = () => {
  document.getElementById("plot-transfer-error")?.remove();
};

const showPcaTransferError = () => {
  reglElementData.updatePcaStdev(null);
  const statusEl = document.getElementById(elbowPlotStatusId);
  if (statusEl) {
    statusEl.textContent = "PCA summary unavailable. The main scatter can still load.";
  }
  requestFloatingPlotRefresh(["floatingElbowPlot"]);
};

const handlePlotTransferError = (error, requestId, payloadOrMessage) => {
  console.error("There was a problem:", error);
  if (mainPlotSpinner) {
    mainPlotSpinner.style.display = "none";
  }
  showPlotTransferError(payloadOrMessage);
  if (requestId) {
    notifyInitialPlotSettled(requestId);
  }
};

const decodeReductionBuffer = (buffer) => {
  const table = decodeArrowIPC(buffer);
  return {
    X: getFloat32Column(table, "X"),
    Y: getFloat32Column(table, "Y"),
  };
};

const resolveDataResourceUrl = (resourcePrefix, kind, fileName) => {
  if (!resourcePrefix || typeof resourcePrefix !== "string") {
    throw new Error("Missing session resource prefix for IPC fetch");
  }
  if (!/^(meta|reduction|expr)$/.test(kind)) {
    throw new Error(`Invalid IPC resource kind: ${kind}`);
  }
  if (!fileName || typeof fileName !== "string") {
    throw new Error("Missing IPC resource file name");
  }

  const basename = fileName.split(/[\\/]/).pop();
  if (basename !== fileName || basename === "." || basename === "..") {
    throw new Error("IPC resource file names must be basenames");
  }

  const normalizedPrefix = resourcePrefix.replace(/^\/+|\/+$/g, "");
  if (!normalizedPrefix || normalizedPrefix === "data" || normalizedPrefix.includes("/")) {
    throw new Error("Invalid session resource prefix for IPC fetch");
  }

  return `${window.location.origin}/${encodeURIComponent(normalizedPrefix)}/${kind}/${encodeURIComponent(basename)}`;
};

const plotReductionBuffer = (
  buffer,
  shouldMutate = () => true,
  timingDetails = {},
) => {
  const reductionData = measureStartupTiming(
    "browser_active_reduction_decode",
    () => decodeReductionBuffer(buffer),
    timingDetails,
  );
  if (!shouldMutate()) {
    return;
  }
  measureStartupTiming(
    "browser_active_reduction_apply",
    () => {
      clearPlotTransferError();
      reglElementData.updateReductionData(reductionData);
      Shiny.setInputValue("reductionProcessed", true, { priority: "event" });
    },
    timingDetails,
  );
};

// init normal shelter for webR to gain better control of the r objects
//const shelterInstance = await initShelter(plotWebR);
// code below will ensure the functions were invoked after all the shiny content loaded
// thus here init scatterplot instance
document.addEventListener(
  "DOMContentLoaded",
  function () {
    // Add full screen spinner
    (async () => {
      const fullScreenSpinner = initFullScreenSpinner("App Loading...");
      document.body.prepend(fullScreenSpinner);
      recordStartupTiming("browser_webr_initialize", "start");
      const webRStarted = performance.now();
      webR = await initWebRInstance();
      shelter = await initShelter(webR);
      recordStartupTiming("browser_webr_initialize", "end", {
        elapsedMs: performance.now() - webRStarted,
      });
      removeFullScreenSpinner();
    })();

    // Add floating plot spinners
    vlnPlotSpinner = addOverlaySpinner("floatingVlnPlotBody");
    dotPlotSpinner = addOverlaySpinner("floatingDotPlotCanvasWrap");
    featurePlotSpinner = addOverlaySpinner("floatingFeaturePlotCanvasWrap");
    // Add main plot spinner
    mainPlotSpinner = addOverlaySpinner(mainPlotElId);

    initFloatingPlots({
      hostId: "plotFloatingHost",
      railId: "plotRail",
      leftSidebarId: "leftSidebar",
      leftSidebarRailId: "leftSidebarRail",
      mainBoundsId: mainPlotElId,
      panelConfigs: [
        {
          id: "floatingVlnPlot",
          refresh: () => {
            const canvas = document.getElementById(vlnPlotElId);
            if (canvas) updateVlnPlot(canvas);
          },
        },
        {
          id: "floatingDotPlot",
          refresh: () => {
            syncDotPlotPanelState();
          },
        },
        {
          id: "floatingFeaturePlot",
          refresh: () => {
            syncFeaturePlotPanelState();
          },
        },
        {
          id: "floatingElbowPlot",
          refresh: () => {
            const canvas = document.getElementById(elbowPlotElId);
            if (canvas) updateElbowPlot(canvas);
          },
          onResize: debounce(() => {
            const canvas = document.getElementById(elbowPlotElId);
            if (canvas) updateElbowPlot(canvas);
          }, 120),
        },
      ],
      debounce,
    });

    safelyRunStartupSync("vln", syncVlnPlotPanelState);
    safelyRunStartupSync("dot", syncDotPlotPanelState);
    safelyRunStartupSync("feature", syncFeaturePlotPanelState);
    safelyRunStartupSync("elbow", syncElbowPlotPanelState);

    const dotPlotActionButton = document.getElementById(dotPlotActionId);
    if (dotPlotActionButton) {
      dotPlotActionButton.addEventListener("click", (event) => {
        event.preventDefault();
        const canvas = document.getElementById(dotPlotElId);
        if (canvas) updateDotPlot(canvas);
      });
    }

    const featurePlotActionButton = document.getElementById(featurePlotActionId);
    if (featurePlotActionButton) {
      featurePlotActionButton.addEventListener("click", (event) => {
        event.preventDefault();
        const canvas = document.getElementById(featurePlotElId);
        if (canvas) updateFeaturePlot(canvas);
      });
    }

    const featurePlotNcolInput = document.getElementById(featurePlotNcolId);
    if (featurePlotNcolInput) {
      featurePlotNcolInput.addEventListener("change", () => {
        normalizeFeaturePlotNcol();
        markFeaturePlotDirty();
        syncFeaturePlotPanelState();
      });
    }

    const dotPlotOrderList = document.getElementById(dotPlotOrderListId);
    const dotPlotOrderReset = document.getElementById(dotPlotOrderResetId);
    if (dotPlotOrderList) {
      dotPlotOrderList.addEventListener("dragstart", (event) => {
        const item = event.target.closest(".plot-floating-order-item");
        if (!item) return;
        item.classList.add("dragging");
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("text/plain", item.dataset.value || "");
      });

      dotPlotOrderList.addEventListener("dragover", (event) => {
        event.preventDefault();
        const target = event.target.closest(".plot-floating-order-item");
        dotPlotOrderList.querySelectorAll(".drop-target").forEach((node) => {
          node.classList.remove("drop-target");
        });
        if (target && !target.classList.contains("dragging")) {
          target.classList.add("drop-target");
        }
      });

      dotPlotOrderList.addEventListener("drop", (event) => {
        event.preventDefault();
        const draggedValue = event.dataTransfer.getData("text/plain");
        const target = event.target.closest(".plot-floating-order-item");
        if (!draggedValue || !target || target.dataset.value === draggedValue) {
          clearDotPlotOrderDragState();
          return;
        }

        const currentOrder = getRenderedDotPlotOrder();
        const nextOrder = currentOrder.filter((value) => value !== draggedValue);
        const targetIndex = nextOrder.indexOf(target.dataset.value);
        nextOrder.splice(targetIndex, 0, draggedValue);
        setDotPlotGroupOrder(nextOrder, true);
        markDotPlotDirty();
        syncDotPlotPanelState();
      });

      dotPlotOrderList.addEventListener("dragend", () => {
        clearDotPlotOrderDragState();
      });
    }

    if (dotPlotOrderReset) {
      dotPlotOrderReset.addEventListener("click", () => {
        setDotPlotGroupOrder([], false);
        clearDotPlotOrderDragState();
        markDotPlotDirty();
        syncDotPlotPanelState();
      });
    }

    window.addEventListener("scspotlight:featurePlotSelectionChanged", () => {
      markVlnPlotDirty();
      refreshVlnDropOptions();
      syncVlnPlotPanelState();
      markDotPlotDirty();
      markFeaturePlotDirty();
      syncDotPlotPanelState();
      syncFeaturePlotPanelState();
    });

    // add select widget to vlnplot box
    const vlnDropDown = createVlnDropend(vlnDropDownId);
    const vlnContainer = document.getElementById(vlnPlotElId).parentElement;
    vlnContainer.prepend(vlnDropDown);

    // Adjust widget elements on scroll
    document.getElementById(mainPlotElId).addEventListener("scroll", () => {
      const containerEl = document.getElementById(mainPlotElId);

      const noteEl = containerEl.querySelector("#scatterPlotNote");

      noteEl.style.bottom = "2%";
      noteEl.style.bottom = `calc(${noteEl.style.bottom} - ${containerEl.scrollTop}px)`;

      const infoEl = containerEl.querySelector("#info");

      infoEl.style.bottom = "1%";
      infoEl.style.bottom = `calc(${infoEl.style.bottom} - ${containerEl.scrollTop}px)`;

      const sliderEl = containerEl.querySelector(".label-slider");
      sliderEl.style.bottom = "1%";
      sliderEl.style.bottom = `calc(${sliderEl.style.bottom} - ${containerEl.scrollTop}px)`;

      const downloadEl = containerEl.querySelector("#downloadIcon");
      downloadEl.style.bottom = "1%";
      downloadEl.style.bottom = `calc(${downloadEl.style.bottom} - ${containerEl.scrollTop}px)`;
    });

    // auto update vlnPlot when resizing
    // Create ResizeObserver instance
    const featurePlotCanvas = document.getElementById(featurePlotElId);
    const vlnPlotCanvas = document.getElementById(vlnPlotElId);
    const dotPlotCanvas = document.getElementById(dotPlotElId);
    const resizeObserver = new ResizeObserver(
      debounce((entries) => {
        for (const entry of entries) {
          if (
            shelter &&
            //shelter2 &&
            Object.keys(reglElementData.origData.cellMetaData).length > 0
          ) {
            // ensure shelter was initiated and reglElementData was populated
            if (entry.target === vlnPlotCanvas && isElementVisible(entry.target)) {
              const vlnPlotPanel = document.getElementById("floatingVlnPlot");
              if (
                !document
                  .getElementById(vlnDropDownId)
                  .querySelector("button")
                  .classList.contains("show")
              ) {
                if (vlnPlotPanel?.dataset.plotRendered === "true") {
                  console.log("resized vlnplot...");
                  updateVlnPlot(vlnPlotCanvas);
                } else {
                  markVlnPlotDirty();
                  syncVlnPlotPanelState();
                }
              }
            }
            if (entry.target === dotPlotCanvas && isElementVisible(entry.target)) {
              console.log("resized dotplot...");
              const dotPlotPanel = document.getElementById("floatingDotPlot");
              if (dotPlotPanel?.dataset.plotRendered === "true") {
                updateDotPlot(dotPlotCanvas);
              } else {
                markDotPlotDirty();
                syncDotPlotPanelState();
              }
            }
            if (
              entry.target === featurePlotCanvas &&
              isElementVisible(entry.target)
            ) {
              console.log("resized featureplot...");
              const featurePlotPanel = document.getElementById("floatingFeaturePlot");
              if (featurePlotPanel?.dataset.featurePlotRendered === "true") {
                updateFeaturePlot(featurePlotCanvas);
              } else {
                markFeaturePlotDirty();
                syncFeaturePlotPanelState();
              }
            }
          }
        }
      }, 250),
    );

    // start observer
    resizeObserver.observe(featurePlotCanvas);
    resizeObserver.observe(vlnPlotCanvas);
    resizeObserver.observe(dotPlotCanvas);
  },
  false,
);

Shiny.addCustomMessageHandler("createSparkLine", (feature) => {
  const sparkLineEl = createSparkLine(feature);
  const sparkLineContainer = document.getElementById("featureSparkLine");
  sparkLineContainer.appendChild(sparkLineEl);

  const sparkLineArray = [
    ...sparkLineContainer.querySelectorAll(".featureSparkLine"),
  ];
  // notify server that gene expression stored has been changed
  // set the value when start transferring data
  const storedFeatures = sparkLineArray.map((e) => getFeatureSparkLineGene(e));
  // remember to add shiny module id as prefix
  Shiny.setInputValue("inputFeatures-storedFeatures", storedFeatures);
});

Shiny.addCustomMessageHandler("await_initial_plot_ready", (_msg) => {
  initialPlotRequestSeq += 1;
  pendingInitialPlotRequestId = initialPlotRequestSeq;
  renderedInitialPlotRequestId = 0;
  recordStartupTiming("browser_initial_plot_wait", "mark", {
    requestId: pendingInitialPlotRequestId,
  });
  notifyInitialPlotReady(pendingInitialPlotRequestId);
});

Shiny.addCustomMessageHandler("benchmark_timing", (event) => {
  recordServerStartupTiming(event);
});

Shiny.addCustomMessageHandler("reduction_ready", (msg) => {
  const requestId = pendingInitialPlotRequestId;
  const transferRequest = startReductionRequest(
    msg.reductionVersion,
    msg.reductionName,
  );
  try {
    const reductionURL =
      resolveDataResourceUrl(msg.resourcePrefix, "reduction", msg.reductionFile);
    (async () => {
      // show spinner
      if (mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }

      if (!ensureReductionCacheVersion(msg.reductionVersion)) {
        return;
      }
      if (!isCurrentReductionRequest(transferRequest)) {
        return;
      }
      const cacheKey = makeReductionCacheKey(
        msg.reductionVersion,
        msg.reductionName,
      );
      const buffer = await fetchArrowIPCBuffer(reductionURL);
      if (!isCurrentReductionRequest(transferRequest)) {
        return;
      }
      setCacheEntry(
        ipcCache.reductions,
        cacheKey,
        buffer,
        REDUCTION_CACHE_LIMIT,
      );
      updateReductionCacheKeys();

      plotReductionBuffer(buffer, () => isCurrentReductionRequest(transferRequest));
      console.log("reduction", msg.reductionName);

      // do not hide the spinner, since it will trigger the reglScatter_plot immediately
    })().catch((error) => {
      if (!isCurrentReductionRequest(transferRequest)) {
        return;
      }
      handlePlotTransferError(
        error,
        requestId,
        {
          payloadType: "reduction",
          reasonCode: "fetch_failed",
          version: msg.reductionVersion,
          reductionName: msg.reductionName,
        },
      );
    });
  } catch (error) {
    if (!isCurrentReductionRequest(transferRequest)) {
      return;
    }
    handlePlotTransferError(
      error,
      requestId,
      {
        payloadType: "reduction",
        reasonCode: "fetch_failed",
        version: msg.reductionVersion,
        reductionName: msg.reductionName,
      },
    );
  }
});

Shiny.addCustomMessageHandler("reductions_ready", (msg) => {
  const requestId = pendingInitialPlotRequestId;
  const transferRequest = startReductionRequest(
    msg.reductionVersion,
    msg.activeReduction || null,
  );
  try {
    (async () => {
      if (!ensureReductionCacheVersion(msg.reductionVersion)) {
        return;
      }
      if (!isCurrentReductionRequest(transferRequest)) {
        return;
      }

      if (mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }

      const reductions = Array.isArray(msg.reductions) ? msg.reductions : [];
      const activeReduction = resolveActiveReduction(reductions, msg.activeReduction);
      if (!activeReduction) {
        throw new Error("No reductions were provided for plotting");
      }
      const inactiveReductions = reductions.filter(
        (reduction) => reduction.reductionName !== activeReduction.reductionName,
      );

      const activeURL =
        resolveDataResourceUrl(
          activeReduction.resourcePrefix || msg.resourcePrefix,
          "reduction",
          activeReduction.reductionFile,
        );
      recordStartupTiming("browser_active_reduction_fetch", "start", {
        reductionName: activeReduction.reductionName,
      });
      const activeFetchStarted = performance.now();
      const activeBuffer = await fetchArrowIPCBuffer(activeURL);
      recordStartupTiming("browser_active_reduction_fetch", "end", {
        reductionName: activeReduction.reductionName,
        elapsedMs: performance.now() - activeFetchStarted,
        outputBytes: activeBuffer.byteLength,
      });
      if (!isCurrentReductionRequest(transferRequest)) {
        return;
      }
      setCacheEntry(
        ipcCache.reductions,
        makeReductionCacheKey(msg.reductionVersion, activeReduction.reductionName),
        activeBuffer,
        REDUCTION_CACHE_LIMIT,
      );
      updateReductionCacheKeys();
      plotReductionBuffer(
        activeBuffer,
        () => isCurrentReductionRequest(transferRequest),
        { reductionName: activeReduction.reductionName },
      );

      await Promise.all(
        inactiveReductions.map(async (reduction) => {
          if (!isCurrentReductionRequest(transferRequest)) {
            return;
          }
          const reductionURL =
            resolveDataResourceUrl(
              reduction.resourcePrefix || msg.resourcePrefix,
              "reduction",
              reduction.reductionFile,
            );
          const buffer = await fetchArrowIPCBuffer(reductionURL);
          if (!isCurrentReductionRequest(transferRequest)) {
            return;
          }
          setCacheEntry(
            ipcCache.reductions,
            makeReductionCacheKey(msg.reductionVersion, reduction.reductionName),
            buffer,
            REDUCTION_CACHE_LIMIT,
          );
        }),
      );
      if (!isCurrentReductionRequest(transferRequest)) {
        return;
      }
      updateReductionCacheKeys();
    })().catch((error) => {
      if (!isCurrentReductionRequest(transferRequest)) {
        return;
      }
      handlePlotTransferError(
        error,
        requestId,
        {
          payloadType: "reductions",
          reasonCode: "fetch_failed",
          version: msg.reductionVersion,
          activeReduction: msg.activeReduction,
        },
      );
      Shiny.setInputValue("reductionProcessed", false, { priority: "event" });
    });
  } catch (error) {
    if (!isCurrentReductionRequest(transferRequest)) {
      return;
    }
    handlePlotTransferError(
      error,
      requestId,
      {
        payloadType: "reductions",
        reasonCode: "fetch_failed",
        version: msg.reductionVersion,
        activeReduction: msg.activeReduction,
      },
    );
  }
});

Shiny.addCustomMessageHandler("reduction_cached", (msg) => {
  try {
    (async () => {
      if (mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }

      if (!ensureReductionCacheVersion(msg.reductionVersion)) {
        return;
      }
      const cacheKey = makeReductionCacheKey(
        msg.reductionVersion,
        msg.reductionName,
      );
      const buffer = touchCacheEntry(ipcCache.reductions, cacheKey);
      if (!buffer) {
        updateReductionCacheKeys();
        Shiny.setInputValue(
          "updateReduction-cacheMissReduction",
          msg.reductionName,
          { priority: "event" },
        );
        return;
      }

      plotReductionBuffer(buffer);
    })().catch((error) => {
      handlePlotTransferError(
        error,
        pendingInitialPlotRequestId,
        "Cached reduction data failed to load. Fetching a fresh copy may resolve this.",
      );
      Shiny.setInputValue("reductionProcessed", false, { priority: "event" });
    });
  } catch (error) {
    handlePlotTransferError(
      error,
      pendingInitialPlotRequestId,
      "Cached reduction data failed to load. Fetching a fresh copy may resolve this.",
    );
  }
});

Shiny.addCustomMessageHandler("pca_ready", (msg) => {
  const transferRequest = startPcaRequest(msg.reductionVersion);
  try {
    (async () => {
      if (!isCurrentPcaRequest(transferRequest)) {
        return;
      }

      if (!msg?.stdevFile) {
        pcaTransferFailed = false;
        reglElementData.updatePcaStdev(null);
        syncElbowPlotPanelState();
        requestFloatingPlotRefresh(["floatingElbowPlot"]);
        return;
      }

      const stdevURL = resolveDataResourceUrl(
        msg.resourcePrefix,
        "reduction",
        msg.stdevFile,
      );
      const table = await readArrowIPC(stdevURL);
      if (!isCurrentPcaRequest(transferRequest)) {
        return;
      }
      const stdevArray = getFloat32Column(table, "stdev");
      if (!isCurrentPcaRequest(transferRequest)) {
        return;
      }
      pcaTransferFailed = false;
      reglElementData.updatePcaStdev(stdevArray);
      syncElbowPlotPanelState();
      requestFloatingPlotRefresh(["floatingElbowPlot"]);
    })().catch((error) => {
      if (!isCurrentPcaRequest(transferRequest)) {
        return;
      }
      console.error("There was a problem:", error);
      pcaTransferFailed = true;
      showPcaTransferError();
    });
  } catch (error) {
    if (!isCurrentPcaRequest(transferRequest)) {
      return;
    }
    console.error("There was a problem:", error);
    pcaTransferFailed = true;
    showPcaTransferError();
  }
});

Shiny.addCustomMessageHandler("transfer_error", (msg) => {
  const payload = msg || {};
  const payloadType = payload.payloadType;
  const version = payload.version;

  if (payloadType === "pca") {
    if (!isCurrentPcaVersion(version)) {
      return;
    }
    if (version != null) {
      activePcaVersion = version;
    }
    activePcaRequest = null;
    pcaTransferFailed = true;
    showPcaTransferError();
    return;
  }

  if (payloadType === "expression") {
    if (
      ipcCache.invalidatedExprVersion !== null &&
      version != null &&
      Number(version) <= Number(ipcCache.invalidatedExprVersion)
    ) {
      return;
    }
    const staleVersion = ipcCache.exprVersion !== null && Number(version) < Number(ipcCache.exprVersion);
    const staleAssay =
      ipcCache.exprVersion !== null &&
      Number(version) === Number(ipcCache.exprVersion) &&
      ipcCache.exprAssay !== null &&
      Boolean(payload.assay) &&
      payload.assay !== ipcCache.exprAssay;
    if (staleVersion || staleAssay || !isExpressionFeatureActive(payload.geneName)) {
      return;
    }
  }

  if (
    (payloadType === "metadata" || payloadType === "metadata_patch") &&
    !isCurrentMetaVersion(version)
  ) {
    return;
  }
  if (payloadType === "metadata" || payloadType === "metadata_patch") {
    activeMetaVersion = version;
    activeMetaRequest = null;
  }

  if (
    (payloadType === "reduction" || payloadType === "reductions") &&
    !isCurrentReductionVersion(version)
  ) {
    return;
  }
  if (payloadType === "reduction" || payloadType === "reductions") {
    activeReductionVersion = version;
    activeReductionRequest = null;
  }

  if (mainPlotSpinner) {
    mainPlotSpinner.style.display = "none";
  }
  showPlotTransferError(payload);
  if (
    payloadType === "metadata" ||
    payloadType === "metadata_patch" ||
    payloadType === "reduction" ||
    payloadType === "reductions"
  ) {
    notifyInitialPlotSettled(pendingInitialPlotRequestId);
  }
});

const normalizeChangedMetaCols = (cols = []) => {
  if (!Array.isArray(cols)) return [];
  return cols.filter((col) => typeof col === "string" && col.length > 0 && col !== "None");
};

const metaColsAffectMainPlot = (changedCols = []) => {
  const activeCols = [
    reglElementData.plotMetaData.group_by,
    reglElementData.plotMetaData.split_by,
  ].filter((col) => typeof col === "string" && col.length > 0);

  return changedCols.some((col) => activeCols.includes(col));
};

const metaColsAffectDotPlot = (changedCols = []) => {
  const groupBy = reglElementData.plotMetaData.group_by;
  return Boolean(groupBy) && changedCols.includes(groupBy);
};

const metaColsAffectVlnPlot = (changedCols = []) => {
  const activeCols = [];
  const groupBy = reglElementData.plotMetaData.group_by;
  if (groupBy) {
    activeCols.push(groupBy);
  }

  const { selectedOption } = normalizeVlnSelection();
  if (selectedOption?.type === "meta") {
    activeCols.push(selectedOption.label);
  }

  return changedCols.some((col) => activeCols.includes(col));
};

const getSidebarMetaState = () => {
  const metaData = reglElementData.origData.cellMetaData || {};
  const cols = getNonNumericCols(reglElementData);
  const groupBy = reglElementData.plotMetaData.group_by;
  const splitBy = reglElementData.plotMetaData.split_by;

  return {
    cols,
    groupBy,
    splitBy,
    groupByLevels: groupBy ? getMetaLevels(metaData[groupBy]) : null,
    splitByLevels: splitBy ? getMetaLevels(metaData[splitBy]) : null,
    metaVersion: activeMetaVersion,
    timestamp: Date.now(),
  };
};

const pushSidebarMetaState = () => {
  Shiny.setInputValue("metaSidebarState", getSidebarMetaState(), {
    priority: "event",
  });
};

const getRenameSelectEl = (id) => document.getElementById(id);

const getRenameSelectize = (id) => {
  const el = getRenameSelectEl(id);
  if (!el) return null;
  return el.selectize || null;
};

const getRenameSelectedValues = (id) => {
  const selectize = getRenameSelectize(id);
  if (selectize) {
    const value = selectize.getValue();
    return Array.isArray(value) ? value : value ? [value] : [];
  }
  const el = getRenameSelectEl(id);
  if (!el) return [];
  return [...el.selectedOptions].map((option) => option.value).filter(Boolean);
};

const setRenameSelectChoices = (id, choices = [], { preserveSelection = true } = {}) => {
  const normalizedChoices = [...new Set(
    (choices || [])
      .filter((value) => value != null)
      .map((value) => String(value))
      .filter((value) => value.length > 0 && value !== "undefined"),
  )];
  const selectize = getRenameSelectize(id);
  if (selectize) {
    const previous = preserveSelection ? getRenameSelectedValues(id) : [];
    selectize.clear(true);
    selectize.clearOptions();
    normalizedChoices.forEach((value) => {
      selectize.addOption({ value, text: value });
    });
    selectize.refreshItems();
    selectize.refreshOptions(false);
    const next = previous.filter((value) => normalizedChoices.includes(value));
    if (next.length > 0) {
      selectize.setValue(next, true);
    }
    if (normalizedChoices.length > 0) {
      selectize.enable();
    } else {
      selectize.disable();
    }
    return;
  }

  const el = getRenameSelectEl(id);
  if (!el) return;
  const previous = preserveSelection ? getRenameSelectedValues(id) : [];
  el.innerHTML = "";
  normalizedChoices.forEach((value) => {
    const option = document.createElement("option");
    option.value = value;
    option.textContent = value;
    option.selected = previous.includes(value);
    el.appendChild(option);
  });
  el.disabled = normalizedChoices.length === 0;
  el.size = Math.min(Math.max(normalizedChoices.length, 1), 8);
};

const clearRenameCategorySelectionUi = () => {
  [renameClusterIds.chosenGroup, renameClusterIds.chosenSplit].forEach((id) => {
    const selectize = getRenameSelectize(id);
    if (selectize) {
      selectize.clear(true);
      return;
    }
    const el = getRenameSelectEl(id);
    if (!el) return;
    [...el.options].forEach((option) => {
      option.selected = false;
    });
  });
};

const toggleRenameControl = (id, show) => {
  const el = getRenameSelectEl(id) || document.getElementById(id);
  if (!el) return;
  const container = el.closest(".form-group, .shiny-input-container") || el;
  container.style.display = show ? "" : "none";
};

const updateRenameSelectedCellsText = (count = 0) => {
  const el = document.getElementById(renameClusterIds.selectedCellsText);
  if (!el) return;
  el.textContent = `${new Intl.NumberFormat().format(Math.max(0, Number(count) || 0))} Cells Selected`;
};

const setRenameAssignmentFeedback = (message) => {
  const el = document.getElementById(renameClusterIds.selectedCellsText);
  if (!el || !message) return;
  el.textContent = message;
};

const clearRenameAssignmentTransportState = () => {
  if (!globalThis.Shiny?.setInputValue) return;
  Shiny.setInputValue(renameClusterIds.selectedCellsPayload, null, { priority: "event" });
  Shiny.setInputValue(renameClusterIds.categorySelectionContext, null, { priority: "event" });
  Shiny.setInputValue(renameClusterIds.assignmentIntent, null, { priority: "event" });
};

const normalizePlotContextValue = (value) => (
  value == null || value === "" ? "None" : String(value)
);

const currentRenameContext = () => ({
  groupBy: normalizePlotContextValue(reglElementData.plotMetaData.group_by),
  splitBy: normalizePlotContextValue(reglElementData.plotMetaData.split_by),
  metaVersion: activeMetaVersion,
  viewFilterVersion: reglElementData.plotMetaData.viewFilterVersion,
});

const currentAnalysisSelectionContext = () => ({
  metaVersion: activeMetaVersion,
  analysisVersion: reglElementData.plotMetaData.analysisVersion,
  analysisLineageId: reglElementData.plotMetaData.analysisLineageId,
  viewFilterVersion: reglElementData.plotMetaData.viewFilterVersion,
});

const getCurrentCellIds = () => {
  const metaData = reglElementData.origData.cellMetaData || {};
  const metaCells = expandMeta(metaData.cells) || [];
  if (metaCells.length > 0) {
    return Array.from(metaCells, (cell) => (cell == null ? null : String(cell)));
  }
  const plotCells = reglElementData.plotData.cells || [];
  return plotCells.flat
    ? plotCells.flat().map((cell) => (cell == null ? null : String(cell)))
    : [];
};

const cellIdOrderChanged = (previousCellIds, nextCellIds) => (
  previousCellIds.length !== nextCellIds.length ||
  previousCellIds.some((cell, index) => cell !== nextCellIds[index])
);

const validateMetadataPatchCellIds = (patchMeta) => {
  const currentCellIds = getCurrentCellIds();
  const patchCellIds = expandMeta(patchMeta?.cells) || [];
  const normalizedPatchCellIds = Array.from(
    patchCellIds,
    (cell) => (cell == null ? null : String(cell)),
  );

  if (currentCellIds.length === 0 || cellIdOrderChanged(currentCellIds, normalizedPatchCellIds)) {
    throw new Error("Metadata patch Cell IDs do not match the active Analysis");
  }
};

const clearExpressionState = ({
  refreshPanels = true,
  invalidateVersion = false,
} = {}) => {
  const invalidationVersions = [];
  if (typeof invalidateVersion === "number" && Number.isFinite(invalidateVersion)) {
    invalidationVersions.push(invalidateVersion);
  }
  if (invalidateVersion === true && ipcCache.exprVersion !== null) {
    const cachedVersion = Number(ipcCache.exprVersion);
    if (Number.isFinite(cachedVersion)) {
      invalidationVersions.push(cachedVersion);
    }
  }
  if (invalidationVersions.length > 0) {
    const invalidationVersion = Math.max(...invalidationVersions);
    ipcCache.invalidatedExprVersion = ipcCache.invalidatedExprVersion === null
      ? invalidationVersion
      : Math.max(
        Number(ipcCache.invalidatedExprVersion),
        invalidationVersion,
      );
  }
  ipcCache.exprGeneration += 1;
  ipcCache.expr.clear();
  ipcCache.exprVersion = null;
  ipcCache.exprAssay = null;
  updateExprCacheKeys();

  reglElementData.origData.expressionData = {};
  reglElementData.plotMetaData.selectedFeatures = [];
  Shiny.setInputValue("inputFeatures-storedFeatures", [], {
    priority: "event",
  });
  Shiny.setInputValue("selectedFeatures", [], { priority: "event" });

  const sparkLineContainer = document.getElementById("featureSparkLine");
  if (sparkLineContainer) {
    sparkLineContainer.innerHTML = "";
  }

  if (!refreshPanels) {
    return;
  }

  markVlnPlotDirty();
  refreshVlnDropOptions();
  markDotPlotDirty();
  markFeaturePlotDirty();
  requestFloatingPlotRefresh([
    "floatingDotPlot",
    "floatingFeaturePlot",
  ]);
};

const clearSelectionTransportAfterScatterReplacement = () => {
  clearRenameCategorySelectionUi();
  clearRenameAssignmentTransportState();
  updateRenameSelectedCellsText(0);
};

const clearSelectedCellsAfterSelectionInvalidation = () => {
  reglElementData.setSelectedCells([], { source: null });
  reglElementData.interactions?.clearLasso?.();
  clearSelectionTransportAfterScatterReplacement();
};

const handleFullObjectReplacementState = () => {
  clearExpressionState({ refreshPanels: false, invalidateVersion: true });
  clearSelectedCellsAfterSelectionInvalidation();
  renameSelectionState.lastGroupBy = null;
  renameSelectionState.lastSplitBy = null;
};

const isSafeAssignmentColumnName = (value) => (
  /^[A-Za-z][A-Za-z0-9_.]*$/.test(String(value || ""))
);

const buildRenameAssignmentIntent = () => {
  const newMetaCol = document.getElementById("renameCluster-newMeta")?.value?.trim() || "";
  const assignAs = document.getElementById("renameCluster-assignAs")?.value?.trim() || "";
  if (!isSafeAssignmentColumnName(newMetaCol)) {
    setRenameAssignmentFeedback("Enter a valid metadata column name before assigning.");
    return null;
  }
  if (!assignAs) {
    setRenameAssignmentFeedback("Enter a label before assigning selected cells.");
    return null;
  }

  const context = currentRenameContext();
  const knownCellSet = new Set(getCurrentCellIds());
  const selectedCells = (reglElementData.plotData.selectedCells || [])
    .map((cell) => String(cell))
    .filter((cell) => cell.length > 0);
  const hasManualSelection =
    reglElementData.selectionSource === "lasso" && selectedCells.length > 0;

  if (hasManualSelection) {
    const uniqueCells = [...new Set(selectedCells)];
    if (
      uniqueCells.length !== selectedCells.length ||
      uniqueCells.some((cell) => !knownCellSet.has(cell))
    ) {
      setRenameAssignmentFeedback("Selected cells are no longer valid for the current plot.");
      return null;
    }
    return {
      type: "selected_cells",
      newMetaCol,
      assignAs,
      selectedCells: uniqueCells,
      context,
    };
  }

  const groupBy = context.groupBy;
  const splitBy = context.splitBy;
  const groupContextMatches =
    normalizePlotContextValue(renameSelectionState.lastGroupBy) === groupBy &&
    normalizePlotContextValue(renameSelectionState.lastSplitBy) === splitBy;
  const selectedGroupLevels = getRenameSelectedValues(renameClusterIds.chosenGroup);
  const selectedSplitLevels = splitBy !== "None"
    ? getRenameSelectedValues(renameClusterIds.chosenSplit)
    : [];
  const metaData = reglElementData.origData.cellMetaData || {};

  if (!groupContextMatches || groupBy === "None" || selectedGroupLevels.length === 0) {
    setRenameAssignmentFeedback("Select cells in the current plot context before assigning.");
    return null;
  }
  if ((reglElementData.plotData.selectedCells || []).length === 0) {
    setRenameAssignmentFeedback("Selected category levels are not visible in the current View.");
    return null;
  }
  const validGroupLevels = new Set(getMetaLevels(metaData[groupBy]));
  if (selectedGroupLevels.some((level) => !validGroupLevels.has(level))) {
    setRenameAssignmentFeedback("Selected group levels are no longer available.");
    return null;
  }
  if (splitBy !== "None") {
    const validSplitLevels = new Set(getMetaLevels(metaData[splitBy]));
    if (
      selectedSplitLevels.length === 0 ||
      selectedSplitLevels.some((level) => !validSplitLevels.has(level))
    ) {
      setRenameAssignmentFeedback("Selected split levels are no longer available.");
      return null;
    }
  }

  return {
    type: "category_context",
    newMetaCol,
    assignAs,
    context,
    category: {
      groupBy,
      groupLevels: selectedGroupLevels,
      splitBy,
      splitLevels: selectedSplitLevels,
    },
  };
};

const pushRenameAssignmentIntent = (event) => {
  if (event?.type === "click" && renameSelectionState.pointerAssignmentHandled) {
    renameSelectionState.pointerAssignmentHandled = false;
    return;
  }
  if (event?.type === "pointerdown") {
    renameSelectionState.pointerAssignmentHandled = true;
  }
  const intent = buildRenameAssignmentIntent();
  if (!intent) return;
  Shiny.setInputValue(renameClusterIds.assignmentIntent, intent, { priority: "event" });
};

const computeRenameCategorySelectedCells = () => {
  const groupBy = reglElementData.plotMetaData.group_by;
  const splitBy = reglElementData.plotMetaData.split_by;
  const metaData = reglElementData.origData.cellMetaData || {};
  if (!groupBy || groupBy === "None") {
    return [];
  }

  const selectedGroup = getRenameSelectedValues(renameClusterIds.chosenGroup);
  if (selectedGroup.length === 0) {
    return [];
  }
  const selectedGroupSet = new Set(selectedGroup);
  const selectedSplit = splitBy && splitBy !== "None"
    ? getRenameSelectedValues(renameClusterIds.chosenSplit)
    : [];
  const selectedSplitSet = new Set(selectedSplit);

  if (splitBy && splitBy !== "None" && selectedSplitSet.size === 0) {
    return [];
  }

  const groupValues = expandMeta(metaData[groupBy]) || [];
  const splitValues = splitBy && splitBy !== "None" ? expandMeta(metaData[splitBy]) || [] : [];
  const cells = expandMeta(metaData.cells) || [];
  const selectedCells = [];

  for (let i = 0; i < cells.length; i++) {
    if (!selectedGroupSet.has(groupValues[i])) continue;
    if (splitBy && splitBy !== "None" && !selectedSplitSet.has(splitValues[i])) continue;
    selectedCells.push(cells[i]);
  }
  return selectedCells;
};

const getRenameCategorySelectionContext = () => {
  const groupBy = normalizePlotContextValue(reglElementData.plotMetaData.group_by);
  const splitBy = normalizePlotContextValue(reglElementData.plotMetaData.split_by);
  const groupLevels = getRenameSelectedValues(renameClusterIds.chosenGroup);
  const splitLevels = splitBy === "None"
    ? []
    : getRenameSelectedValues(renameClusterIds.chosenSplit);

  if (
    groupBy === "None" ||
    groupLevels.length === 0 ||
    (splitBy !== "None" && splitLevels.length === 0)
  ) {
    return null;
  }

  return {
    context: { groupBy, splitBy },
    category: { groupBy, groupLevels, splitBy, splitLevels },
    ...currentAnalysisSelectionContext(),
  };
};

const applyRenameCategorySelection = () => {
  if (reglElementData.selectionSource === "lasso" && reglElementData.plotData.selectedCells.length > 0) {
    Shiny.setInputValue(renameClusterIds.categorySelectionContext, null, { priority: "event" });
    updateRenameSelectedCellsText(reglElementData.plotData.selectedCells.length);
    return;
  }
  const categoryContext = getRenameCategorySelectionContext();
  const selectedCells = computeRenameCategorySelectedCells();
  reglElementData.setSelectedCells(selectedCells, { source: selectedCells.length > 0 ? "category" : null });
  const visibleSelectedCells = reglElementData.plotData.selectedCells || [];
  Shiny.setInputValue(renameClusterIds.selectedCellsPayload, null, { priority: "event" });
  Shiny.setInputValue(
    renameClusterIds.categorySelectionContext,
    visibleSelectedCells.length > 0 ? categoryContext : null,
    { priority: "event" },
  );
  updateRenameSelectedCellsText(visibleSelectedCells.length);
};

const syncRenameClusterSelectionUi = () => {
  const groupBy = reglElementData.plotMetaData.group_by;
  const splitBy = reglElementData.plotMetaData.split_by;
  const metaData = reglElementData.origData.cellMetaData || {};
  const groupingChanged =
    renameSelectionState.lastGroupBy !== groupBy ||
    renameSelectionState.lastSplitBy !== splitBy;
  const hadPriorRenameContext =
    renameSelectionState.lastGroupBy !== null || renameSelectionState.lastSplitBy !== null;
  const previousGroupSelection = getRenameSelectedValues(renameClusterIds.chosenGroup);
  const previousSplitSelection = getRenameSelectedValues(renameClusterIds.chosenSplit);
  const hasManualSelection =
    reglElementData.selectionSource === "lasso" && reglElementData.plotData.selectedCells.length > 0;
  const showCategoryControls = Boolean(groupBy) && groupBy !== "None" && !hasManualSelection;

  toggleRenameControl(renameClusterIds.title, showCategoryControls);
  toggleRenameControl(renameClusterIds.chosenGroup, showCategoryControls);
  toggleRenameControl(
    renameClusterIds.chosenSplit,
    showCategoryControls && Boolean(splitBy) && splitBy !== "None",
  );

  if (showCategoryControls) {
    setRenameSelectChoices(renameClusterIds.chosenGroup, getMetaLevels(metaData[groupBy]), {
      preserveSelection: !groupingChanged,
    });
    if (splitBy && splitBy !== "None") {
      setRenameSelectChoices(renameClusterIds.chosenSplit, getMetaLevels(metaData[splitBy]), {
        preserveSelection: !groupingChanged,
      });
    } else {
      setRenameSelectChoices(renameClusterIds.chosenSplit, []);
    }
  }

  const nextGroupSelection = getRenameSelectedValues(renameClusterIds.chosenGroup);
  const nextSplitSelection = getRenameSelectedValues(renameClusterIds.chosenSplit);
  const selectionInvalidated =
    previousGroupSelection.length !== nextGroupSelection.length ||
    previousGroupSelection.some((value) => !nextGroupSelection.includes(value)) ||
    previousSplitSelection.length !== nextSplitSelection.length ||
    previousSplitSelection.some((value) => !nextSplitSelection.includes(value));
  const hasRenameSelectionToClear =
    previousGroupSelection.length > 0 ||
    previousSplitSelection.length > 0 ||
    (reglElementData.plotData.selectedCells || []).length > 0;

  if (
    hasRenameSelectionToClear &&
    ((hadPriorRenameContext && groupingChanged) || selectionInvalidated)
  ) {
    clearRenameAssignmentTransportState();
  }

  renameSelectionState.lastGroupBy = groupBy;
  renameSelectionState.lastSplitBy = splitBy;

  if (hasManualSelection) {
    updateRenameSelectedCellsText(reglElementData.plotData.selectedCells.length);
    return;
  }

  applyRenameCategorySelection();
};

const initRenameClusterClientSelection = () => {
  [renameClusterIds.chosenGroup, renameClusterIds.chosenSplit].forEach((id) => {
    const el = getRenameSelectEl(id);
    if (!el || el.dataset.renameClusterBound === "true") return;
    el.dataset.renameClusterBound = "true";
    el.addEventListener("change", () => {
      applyRenameCategorySelection();
    });
  });

  const assignBtn = document.getElementById(renameClusterIds.assign);
  if (assignBtn && assignBtn.dataset.renameClusterBound !== "true") {
    assignBtn.dataset.renameClusterBound = "true";
    assignBtn.addEventListener("pointerdown", pushRenameAssignmentIntent);
    assignBtn.addEventListener("click", pushRenameAssignmentIntent);
  }

  syncRenameClusterSelectionUi();
};

const syncMetaUiAfterUpdate = ({
  fullTransfer = false,
  changedCols = [],
  notifyServer = true,
} = {}) => {
  const normalizedChangedCols = normalizeChangedMetaCols(changedCols);
  const refreshMainPlot = fullTransfer || metaColsAffectMainPlot(normalizedChangedCols);
  const panelsToRefresh = [];

  emptyDropOptions(vlnDropDownId);
  updateDropOptions(vlnDropDownId);

  if (fullTransfer || metaColsAffectVlnPlot(normalizedChangedCols)) {
    markVlnPlotDirty();
    panelsToRefresh.push("floatingVlnPlot");
  }

  if (fullTransfer || metaColsAffectDotPlot(normalizedChangedCols)) {
    markDotPlotDirty();
    panelsToRefresh.push("floatingDotPlot");
  }

  if (fullTransfer) {
    markFeaturePlotDirty();
    panelsToRefresh.push("floatingFeaturePlot");
  }

  if (panelsToRefresh.length > 0) {
    requestFloatingPlotRefresh(panelsToRefresh);
  }

  pushSidebarMetaState();
  syncRenameClusterSelectionUi();

  if (notifyServer) {
    if (fullTransfer) {
      Shiny.setInputValue("metaProcessed", true, { priority: "event" });
    } else {
      Shiny.setInputValue(
        "metaPatchProcessed",
        {
          cols: normalizedChangedCols,
          refreshMainPlot,
          timestamp: Date.now(),
        },
        { priority: "event" },
      );
    }
  }

  return { refreshMainPlot };
};

Shiny.addCustomMessageHandler("meta_ready", (msg) => {
  const requestId = pendingInitialPlotRequestId;
  const transferRequest = startMetaRequest(msg.metaVersion);
  try {
    const metaURL = resolveDataResourceUrl(msg.resourcePrefix, "meta", msg.metaFile);
    (async () => {
      // show main plot spinner
      if (mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }
      const table = await readArrowIPC(metaURL, {
        onFetch: (event) => recordStartupTiming("browser_metadata_fetch", event.state, event),
        onDecode: (event) => recordStartupTiming("browser_metadata_decode", event.state, event),
      });
      const out = measureStartupTiming(
        "browser_metadata_parse",
        () => parseMetaFromArrow(table),
      );
      if (!isCurrentMetaRequest(transferRequest)) {
        return;
      }
      console.log("metaData", out);
      measureStartupTiming("browser_metadata_apply_and_ui", () => {
        const previousCellIds = getCurrentCellIds();
        clearPlotTransferError();
        reglElementData.updateCellMetaData(out);
        if (cellIdOrderChanged(previousCellIds, getCurrentCellIds())) {
          handleFullObjectReplacementState();
        }
        syncMetaUiAfterUpdate({ fullTransfer: true });
      });

      // do not hide the spinner, since it will trigger the reglScatter_plot immediately
    })().catch((error) => {
      if (!isCurrentMetaRequest(transferRequest)) {
        return;
      }
      handlePlotTransferError(
        error,
        requestId,
        {
          payloadType: "metadata",
          reasonCode: "fetch_failed",
          version: msg.metaVersion,
        },
      );
    });
  } catch (error) {
    if (!isCurrentMetaRequest(transferRequest)) {
      return;
    }
    handlePlotTransferError(
      error,
      requestId,
      {
        payloadType: "metadata",
        reasonCode: "fetch_failed",
        version: msg.metaVersion,
      },
    );
  }
});

Shiny.addCustomMessageHandler("meta_patch_ready", (msg) => {
  const patchVersion = msg.metaVersion || msg.version;
  const transferRequest = patchVersion == null ? null : startMetaRequest(patchVersion);
  const isCurrentPatchRequest = () =>
    patchVersion == null || isCurrentMetaRequest(transferRequest);
  try {
    if (!isCurrentPatchRequest()) {
      return;
    }
    const changedCols = normalizeChangedMetaCols(msg.cols);
    if (changedCols.length === 0) {
      throw new Error("Metadata patch did not include column scope");
    }
    const metaURL = resolveDataResourceUrl(msg.resourcePrefix, "meta", msg.metaFile);
    (async () => {
      const refreshMainPlot = metaColsAffectMainPlot(changedCols);

      if (refreshMainPlot && mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }

      const table = await readArrowIPC(metaURL);
      if (!isCurrentPatchRequest()) {
        return;
      }
      const out = parseMetaFromArrow(table);
      validateMetadataPatchCellIds(out);
      const patch = {};
      changedCols.forEach((col) => {
        if (!out[col]) {
          throw new Error(`Metadata patch payload is missing column ${col}`);
        }
        patch[col] = out[col];
      });
      console.log("metaPatch", out);
      reglElementData.updateCellMetaDataPatch(patch);
      clearSelectedCellsAfterSelectionInvalidation();
      const syncResult = syncMetaUiAfterUpdate({
        fullTransfer: false,
        changedCols,
      });

      if (!syncResult.refreshMainPlot) {
        mainPlotSpinner.style.display = "none";
      }
    })().catch((error) => {
      if (!isCurrentPatchRequest()) {
        return;
      }
      console.error("There was a problem:", error);
      mainPlotSpinner.style.display = "none";
      showPlotTransferError({
        payloadType: "metadata_patch",
        reasonCode: "fetch_failed",
        version: patchVersion,
        cols: changedCols,
      });
    });
  } catch (error) {
    console.error("There was a problem:", error);
    mainPlotSpinner.style.display = "none";
    if (isCurrentPatchRequest()) {
      showPlotTransferError({
        payloadType: "metadata_patch",
        reasonCode: "fetch_failed",
        version: patchVersion,
        cols: normalizeChangedMetaCols(msg.cols),
      });
    }
  }
});

Shiny.addCustomMessageHandler("expr_ready", (msg) => {
  const generation = ipcCache.exprGeneration;
  if (!isExpressionFeatureActive(msg.geneName)) {
    return;
  }
  try {
    const exprURL = resolveDataResourceUrl(msg.resourcePrefix, "expr", msg.exprFile);
    (async () => {
      if (!ensureExprCacheVersion(msg.exprVersion, msg.assay)) {
        return;
      }
      if (!isCurrentExpressionRequest(msg, generation)) {
        return;
      }
      const cacheKey = makeExprCacheKey(msg.exprVersion, msg.assay, msg.geneName);
      const buffer = await fetchArrowIPCBuffer(exprURL);
      if (!isCurrentExpressionRequest(msg, generation)) {
        return;
      }
      setCacheEntry(ipcCache.expr, cacheKey, buffer, EXPR_CACHE_LIMIT);
      updateExprCacheKeys();

      const table = decodeArrowIPC(buffer);
      if (!isCurrentExpressionRequest(msg, generation)) {
        return;
      }
      const expr = {};
      expr[msg.geneName] = getFloat32Column(table, "expr");
      if (!isCurrentExpressionRequest(msg, generation)) {
        return;
      }
      reglElementData.updateExpressionData(expr);
      console.log("exprData", reglElementData.origData.expressionData);
      const feature = Object.keys(expr)[0];
      const sparkLineArray = getFeatureSparkLineElements();
      sparkLineArray.forEach((e) => {
        if (getFeatureSparkLineGene(e) == feature) {
          updateSparkLine(e, () => reglElementData);
        }
      });
      markVlnPlotDirty();
      refreshVlnDropOptions();
      markDotPlotDirty();
      markFeaturePlotDirty();
      requestFloatingPlotRefresh([
        "floatingDotPlot",
        "floatingFeaturePlot",
      ]);
    })().catch((error) => {
      console.error("There was a problem:", error);
      if (isCurrentExpressionRequest(msg, generation)) {
        showPlotTransferError({
          payloadType: "expression",
          reasonCode: "fetch_failed",
          version: msg.exprVersion,
          geneName: msg.geneName,
          assay: msg.assay,
        });
      }
    });
  } catch (error) {
    console.error("There was a problem:", error);
    if (isCurrentExpressionRequest(msg, generation)) {
      showPlotTransferError({
        payloadType: "expression",
        reasonCode: "fetch_failed",
        version: msg.exprVersion,
        geneName: msg.geneName,
        assay: msg.assay,
      });
    }
  }
});

Shiny.addCustomMessageHandler("expr_cached", (msg) => {
  const generation = ipcCache.exprGeneration;
  if (!isExpressionFeatureActive(msg.geneName)) {
    return;
  }
  try {
    (async () => {
      if (!ensureExprCacheVersion(msg.exprVersion, msg.assay)) {
        return;
      }
      if (!isCurrentExpressionRequest(msg, generation)) {
        return;
      }
      const cacheKey = makeExprCacheKey(msg.exprVersion, msg.assay, msg.geneName);
      const buffer = touchCacheEntry(ipcCache.expr, cacheKey);
      if (!buffer) {
        updateExprCacheKeys();
        Shiny.setInputValue("inputFeatures-cacheMissFeature", msg.geneName, {
          priority: "event",
        });
        return;
      }

      const table = decodeArrowIPC(buffer);
      if (!isCurrentExpressionRequest(msg, generation)) {
        return;
      }
      const expr = {};
      expr[msg.geneName] = getFloat32Column(table, "expr");
      if (!isCurrentExpressionRequest(msg, generation)) {
        return;
      }
      reglElementData.updateExpressionData(expr);
      console.log("exprData", reglElementData.origData.expressionData);
      const feature = Object.keys(expr)[0];
      const sparkLineArray = getFeatureSparkLineElements();
      sparkLineArray.forEach((e) => {
        if (getFeatureSparkLineGene(e) == feature) {
          updateSparkLine(e, () => reglElementData);
        }
      });
      markVlnPlotDirty();
      refreshVlnDropOptions();
      markDotPlotDirty();
      markFeaturePlotDirty();
      requestFloatingPlotRefresh([
        "floatingDotPlot",
        "floatingFeaturePlot",
      ]);
    })().catch((error) => {
      console.error("There was a problem:", error);
      if (isCurrentExpressionRequest(msg, generation)) {
        showPlotTransferError({
          payloadType: "expression",
          reasonCode: "decode_failed",
          version: msg.exprVersion,
          geneName: msg.geneName,
          assay: msg.assay,
        });
      }
    });
  } catch (error) {
    console.error("There was a problem:", error);
    if (isCurrentExpressionRequest(msg, generation)) {
      showPlotTransferError({
        payloadType: "expression",
        reasonCode: "decode_failed",
        version: msg.exprVersion,
        geneName: msg.geneName,
        assay: msg.assay,
      });
    }
  }
});

Shiny.addCustomMessageHandler("clear_expr", (msg) => {
  // purge expression data and associated client cache/state
  clearExpressionState({ invalidateVersion: msg?.invalidateVersion });
});

Shiny.addCustomMessageHandler("selectPointsByCategory", (msg) => {
  applyRenameCategorySelection();
});

Shiny.addCustomMessageHandler("addNewMeta", (msg) => {
  const newMetaCol = msg.colName;
  const assignAs = msg.colValue;
  console.log("newMetaCol:", newMetaCol);
  console.log("assignAs:", assignAs);
  const metaData = reglElementData.origData.cellMetaData;
  // selectedCells records manually selected points by lasso
  // or category selected cells updated by selectPointsByCategory
  const selectedCells = reglElementData.plotData.selectedCells;
  const colNames = Object.keys(metaData);
  if (colNames.length > 0 && selectedCells.length > 0) {
    const nCells = expandMeta(metaData[Object.keys(metaData)[0]]).length;
    //console.log(Object.keys(metaData).includes(newMetaCol));
    //console.log(!Object.keys(metaData).includes(newMetaCol));
    if (!colNames.includes(newMetaCol)) {
      reglElementData.origData.cellMetaData[newMetaCol] = {
        type: "category",
        value: {
          unknown: Array(nCells)
            .fill(0)
            .map((_, i) => i),
        },
      };
      //console.log(reglElementData.origData.cellMetaData[newMetaCol]);
    }
    const idx = selectedCells.map((e) =>
      expandMeta(metaData["cells"]).indexOf(e),
    );
    console.log("idx", idx);
    //idx.forEach((e) => {
    //  reglElementData.origData.cellMetaData
    //    .getChild(newMetaCol)
    //    .gset(e, assignAs);
    //});
    //
    // arrow vector set function has a bug, the same value will
    // all be replaced by one set() operation, no matter the index
    // parameter used.
    //
    // thus convert to array and replace the value
    //

    let nn = expandMeta(reglElementData.origData.cellMetaData[newMetaCol]);
    console.log("nn", nn);
    idx.forEach((e) => {
      nn[e] = assignAs;
    });
    const result = nn.reduce((acc, val, index) => {
      (acc[val] = acc[val] || []).push(index);
      return acc;
    }, {});
    reglElementData.origData.cellMetaData[newMetaCol].value = result;
    invalidateMetaCache(reglElementData.origData.cellMetaData[newMetaCol]);
  }
  console.log({
    [newMetaCol]: expandMeta(reglElementData.origData.cellMetaData[newMetaCol]),
  });

  syncMetaUiAfterUpdate({
    fullTransfer: false,
    changedCols: [newMetaCol],
    notifyServer: false,
  });

  // deselct points
  reglElementData.deselectAll();
  clearRenameCategorySelectionUi();
  clearRenameAssignmentTransportState();
  syncRenameClusterSelectionUi();
  // reset selectedCells
  Shiny.setInputValue("categorySelectedCells", null, { priority: "event" });
});

Shiny.addCustomMessageHandler("reglScatter_plot", (msg) => {
  const requestId = pendingInitialPlotRequestId;
  const scatterRenderStarted = performance.now();
  recordStartupTiming("browser_scatter_render", "start", { requestId });
  const previousReglElementData = reglElementData;
  const previousPlotEl = previousReglElementData.plotEl;
  const previousCatLegendEl = previousReglElementData.catLegendEl;
  const previousExpLegendEl = previousReglElementData.expLegendEl;
  const previousPlotMetaData = { ...previousReglElementData.plotMetaData };
  const previousSelectedCells = [...(previousReglElementData.plotData.selectedCells || [])];
  const previousSelectionSource = previousReglElementData.selectionSource;
  const isViewFilterRender = msg.viewFilterOnly === true;
  const nextReglElementData = previousReglElementData.createRenderReplacement();
  const parentDiv = document.getElementById(mainPlotElId);
  const replacesRenderedScatter = previousPlotEl?.parentNode === parentDiv;
  const categoryAccordionBody = document.querySelector(
    '.accordion-item[data-value="analysis_category"] .accordion-body',
  );
  try {
    // first remove spinner if exists
    if (mainPlotSpinner.style.display === "none") {
      // show spinners for the plot
      console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
      mainPlotSpinner.style.display = "flex";
      console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
    }

    // clear reglScatterCanvas data including plotMetaData
    console.log("msg: ", msg);
    const group_by = msg.group_by;
    const split_by = msg.split_by;
    const moduleScore = msg.moduleScore;

    nextReglElementData.updatePlotMetaData(group_by, split_by, moduleScore);
    nextReglElementData.plotMetaData.viewFilter = msg.viewFilter || null;
    nextReglElementData.plotMetaData.viewFilterVersion = msg.viewFilterVersion ?? 0;
    nextReglElementData.plotMetaData.analysisVersion = msg.analysisVersion;
    nextReglElementData.plotMetaData.analysisLineageId = msg.analysisLineageId;
    console.log("reglElementData.plotMetaData: ", nextReglElementData.plotMetaData);

    console.log("Generating plotEl");
    const renderDetails = { requestId };
    // regenerate plot elements
    console.profile("Generating plotEl");
    measureStartupTiming(
      "browser_scatter_model_and_dom",
      () => nextReglElementData.generatePlotEl(),
      renderDetails,
    );
    console.profileEnd("Generating plotEl");
    console.log("reglElementData :", nextReglElementData);
    const nextPlotEl = nextReglElementData.plotEl;
    const nextCatLegendEl = nextReglElementData.catLegendEl;
    const nextExpLegendEl = nextReglElementData.expLegendEl;

    if (!parentDiv || !categoryAccordionBody) {
      throw new Error("Plot containers are not available");
    }

    // update legend elements
    if (previousPlotEl?.parentNode === parentDiv) {
      parentDiv.removeChild(previousPlotEl);
    }
    parentDiv.appendChild(nextPlotEl);
    // create deck instance after plot element is mounted in DOM
    measureStartupTiming(
      "browser_deck_create",
      () => nextReglElementData.mountDeck(),
      renderDetails,
    );
    if (previousCatLegendEl?.parentNode === categoryAccordionBody) {
      categoryAccordionBody.removeChild(previousCatLegendEl);
    }
    if (previousExpLegendEl?.parentNode === categoryAccordionBody) {
      categoryAccordionBody.removeChild(previousExpLegendEl);
    }
    categoryAccordionBody.appendChild(nextCatLegendEl);
    categoryAccordionBody.appendChild(nextExpLegendEl);

    reglElementData = nextReglElementData;
    if (replacesRenderedScatter && !isViewFilterRender) {
      // Render replacements do not retain lasso geometry. Clear the matching
      // server transport so a visually cleared lasso cannot mutate later state.
      clearSelectedCellsAfterSelectionInvalidation();
    }
    pushSidebarMetaState();

    // return selected points to server side
    reglElementData.setSelectionHandlers({
      onSelect: ({ selectedCells }) => {
        console.log("selectedCells: ", selectedCells);
        clearRenameCategorySelectionUi();
        Shiny.setInputValue(renameClusterIds.categorySelectionContext, null, {
          priority: "event",
        });
        updateRenameSelectedCellsText(selectedCells.length);
        syncRenameClusterSelectionUi();
        Shiny.setInputValue(renameClusterIds.selectedCellsPayload, {
          cells: selectedCells,
          ...currentAnalysisSelectionContext(),
        }, {
          priority: "event",
        });
      },
      onDeselect: () => {
        clearRenameCategorySelectionUi();
        clearRenameAssignmentTransportState();
        syncRenameClusterSelectionUi();
      },
    });

    initRenameClusterClientSelection();
    if (isViewFilterRender && previousSelectionSource === "lasso") {
      reglElementData.setSelectedCells(previousSelectedCells, { source: "lasso" });
      const reconciledCells = reglElementData.plotData.selectedCells;
      if (reconciledCells.length > 0) {
        reglElementData.selectionHandlers.onSelect({ selectedCells: reconciledCells });
      } else {
        reglElementData.selectionHandlers.onDeselect();
      }
    }

    nextPlotEl.style.display = "flex";
    previousReglElementData.destroy();

    // hide spinner
    if (mainPlotSpinner.style.display !== "none") {
      console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
      mainPlotSpinner.style.display = "none";
      console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
    }
    renderedInitialPlotRequestId = requestId;
    recordStartupTiming("browser_scatter_render", "end", {
      requestId,
      elapsedMs: performance.now() - scatterRenderStarted,
    });
    notifyInitialPlotReady(requestId);
    //featurePlot().then({});
    markVlnPlotDirty();
    markDotPlotDirty();
    markFeaturePlotDirty();
    requestFloatingPlotRefresh([
      "floatingVlnPlot",
      "floatingDotPlot",
      "floatingFeaturePlot",
    ]);
  } catch (error) {
    console.error("There was a problem:", error);
    if (
      nextReglElementData.plotEl?.parentNode === parentDiv &&
      nextReglElementData.plotEl !== previousPlotEl
    ) {
      parentDiv.removeChild(nextReglElementData.plotEl);
    }
    if (previousPlotEl && previousPlotEl.parentNode !== parentDiv) {
      parentDiv?.appendChild(previousPlotEl);
    }
    if (
      nextReglElementData.catLegendEl?.parentNode === categoryAccordionBody &&
      nextReglElementData.catLegendEl !== previousCatLegendEl
    ) {
      categoryAccordionBody.removeChild(nextReglElementData.catLegendEl);
    }
    if (
      nextReglElementData.expLegendEl?.parentNode === categoryAccordionBody &&
      nextReglElementData.expLegendEl !== previousExpLegendEl
    ) {
      categoryAccordionBody.removeChild(nextReglElementData.expLegendEl);
    }
    if (previousCatLegendEl && previousCatLegendEl.parentNode !== categoryAccordionBody) {
      categoryAccordionBody?.appendChild(previousCatLegendEl);
    }
    if (previousExpLegendEl && previousExpLegendEl.parentNode !== categoryAccordionBody) {
      categoryAccordionBody?.appendChild(previousExpLegendEl);
    }
    nextReglElementData.destroy();
    reglElementData = previousReglElementData;
    reglElementData.plotMetaData = previousPlotMetaData;
    mainPlotSpinner.style.display = "none";
    recordStartupTiming("browser_scatter_render", "error", {
      requestId,
      elapsedMs: performance.now() - scatterRenderStarted,
    });
    notifyInitialPlotSettled(requestId);
  }
});

Shiny.addCustomMessageHandler("selected_cells_count", (msg) => {
  reglElementData.updateCellCount({ selectedCount: msg?.selected ?? 0 });
});

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => {
    initRenameClusterClientSelection();
  });
} else {
  initRenameClusterClientSelection();
}

const updateFeaturePlot = (canvas) => {
  if (!canvas || !featurePlotSpinner) return;

  const hideSpinner = () => {
    featurePlotSpinner.style.display = "none";
  };
  const showSpinner = () => {
    featurePlotSpinner.style.display = "flex";
  };

  hideSpinner();

  const container = canvas.parentElement;
  if (!container) {
    hideSpinner();
    return;
  }
  const rect = container.getBoundingClientRect();
  const containerPadding = getPadding(container);
  const canvasWidth =
    rect.width - containerPadding.left - containerPadding.right;
  const canvasHeight =
    rect.height - containerPadding.top - containerPadding.bottom;
  canvas.width = canvasWidth * 2;
  canvas.height = canvasHeight * 2;
  canvas.style.width = "100%";
  canvas.style.height = "100%";

  const ctx = canvas.getContext("2d");
  if (canvasWidth <= 0 || canvasHeight <= 0) {
    hideSpinner();
    return;
  }

  const renderMessage = (message) => {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.font = "30px Arial";
    ctx.fillStyle = "#636363";
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillText(message, 10, 10);
    hideSpinner();
  };

  const features = reglElementData.plotMetaData.selectedFeatures || [];
  if (features.length <= 1 || reglElementData.plotMetaData.moduleScore) {
    renderMessage("Please select at least two features");
    syncFeaturePlotPanelState();
    return;
  }

  const missingExpr = features.some(
    (feature) => !reglElementData.origData.expressionData[feature],
  );
  if (missingExpr) {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    hideSpinner();
    syncFeaturePlotPanelState();
    return;
  }

  const colNames = Object.keys(reglElementData.origData.reductionData);
  if (colNames.length === 0) {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    hideSpinner();
    syncFeaturePlotPanelState();
    return;
  }

  const expressionInput = {};
  for (const feature of features) {
    expressionInput[feature] = Array.from(
      reglElementData.origData.expressionData[feature],
    );
  }

  const drInput = {};
  for (const colName of colNames) {
    drInput[colName] = Array.from(reglElementData.origData.reductionData[colName]);
  }

  const ncol = normalizeFeaturePlotNcol();
  setFeaturePlotControlsDisabled(true);
  showSpinner();
  featurePlot(shelter, canvasWidth, canvasHeight, drInput, expressionInput, ncol)
    .then((res) => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const img = res.images[0];
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      const featurePlotPanel = document.getElementById("floatingFeaturePlot");
      if (featurePlotPanel) {
        featurePlotPanel.dataset.featurePlotRendered = "true";
        featurePlotPanel.dataset.featurePlotStale = "false";
      }
    })
    .catch((error) => {
      console.error("Failed to update featurePlot:", error);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
    })
    .finally(() => {
      hideSpinner();
      setFeaturePlotControlsDisabled(false);
      syncFeaturePlotPanelState();
      shelter.purge();
    });
};

const syncFeaturePlotPanelState = () => {
  const featurePlotPanel = document.getElementById("floatingFeaturePlot");
  const statusEl = document.getElementById(featurePlotStatusId);
  const actionButton = document.getElementById(featurePlotActionId);
  const ncolInput = document.getElementById(featurePlotNcolId);

  if (!featurePlotPanel || !statusEl || !actionButton || !ncolInput) return;

  const selectedFeatures = reglElementData.plotMetaData.selectedFeatures || [];
  const moduleScoreActive = Boolean(reglElementData.plotMetaData.moduleScore);
  const hasRendered = featurePlotPanel.dataset.featurePlotRendered === "true";
  const isStale = featurePlotPanel.dataset.featurePlotStale === "true";
  const isBusy = featurePlotSpinner?.style.display !== "none";
  const icon = actionButton.querySelector("i");
  const ncol = normalizeFeaturePlotNcol();
  ncolInput.disabled = moduleScoreActive || isBusy;

  if (moduleScoreActive) {
    statusEl.textContent = "FeaturePlot is unavailable while module score coloring is active.";
    actionButton.disabled = true;
    actionButton.title = "Plot unavailable";
    if (icon) {
      icon.className = "bi bi-slash-circle";
    }
    return;
  }

  if (selectedFeatures.length === 0) {
    statusEl.textContent = "No genes selected. Select at least two genes, choose columns, then click plot.";
    actionButton.disabled = true;
    actionButton.title = "Select genes first";
    if (icon) {
      icon.className = "bi bi-play-circle";
    }
    return;
  }

  if (selectedFeatures.length === 1) {
    statusEl.textContent = `Selected gene(s): ${selectedFeatures[0]}. Select at least one more gene, then click plot.`;
    actionButton.disabled = true;
    actionButton.title = "Select one more gene";
    if (icon) {
      icon.className = "bi bi-play-circle";
    }
    return;
  }

  statusEl.textContent = `Selected gene(s): ${selectedFeatures.join(", ")} | ncol: ${ncol}`;
  actionButton.disabled = isBusy || selectedFeatures.length <= 1;
  actionButton.title = hasRendered || isStale ? "Update plot" : "Plot";
  if (icon) {
    icon.className = hasRendered || isStale ? "bi bi-arrow-repeat" : "bi bi-play-circle";
  }
};

const syncElbowPlotPanelState = () => {
  const statusEl = document.getElementById(elbowPlotStatusId);
  if (!statusEl) return;

  const stdev = reglElementData.origData.pcaStdev;
  if (pcaTransferFailed) {
    statusEl.textContent = "PCA summary unavailable. The main scatter can still load.";
    return;
  }

  if (!stdev || stdev.length === 0) {
    statusEl.textContent = "No PCA standard deviation data available.";
    return;
  }

  pcaTransferFailed = false;
  statusEl.textContent = `PCA standard deviations | ${stdev.length} PCs`;
};

const updateElbowPlot = (canvas) => {
  if (!canvas) return;

  const container = canvas.parentElement;
  const ctx = canvas.getContext("2d");
  if (!container || !ctx) return;

  const rect = container.getBoundingClientRect();
  const padding = getPadding(container);
  const width = rect.width - padding.left - padding.right;
  const height = rect.height - padding.top - padding.bottom;
  const dpr = Math.max(window.devicePixelRatio || 1, 300 / 96);

  canvas.width = Math.max(1, Math.floor(width * dpr));
  canvas.height = Math.max(1, Math.floor(height * dpr));
  canvas.style.width = "100%";
  canvas.style.height = "100%";
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, Math.max(1, width), Math.max(1, height));

  const stdev = reglElementData.origData.pcaStdev;
  if (!stdev || stdev.length === 0) {
    syncElbowPlotPanelState();
    return;
  }

  if (width <= 0 || height <= 0) {
    syncElbowPlotPanelState();
    return;
  }

  const margins = { top: 20, right: 18, bottom: 54, left: 64 };
  const plotWidth = Math.max(1, width - margins.left - margins.right);
  const plotHeight = Math.max(1, height - margins.top - margins.bottom);
  const values = Array.from(stdev);
  const maxValue = Math.max(...values);
  const minValue = Math.min(...values);
  const yMin = Math.min(0, minValue);
  const yMax = maxValue <= yMin ? yMin + 1 : maxValue;
  const xCount = values.length;

  const getX = (index) => {
    if (xCount === 1) return margins.left + plotWidth / 2;
    return margins.left + (index / (xCount - 1)) * plotWidth;
  };

  const getY = (value) => margins.top + ((yMax - value) / (yMax - yMin)) * plotHeight;

  ctx.strokeStyle = "rgba(0, 0, 0, 0.2)";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(margins.left, margins.top);
  ctx.lineTo(margins.left, margins.top + plotHeight);
  ctx.lineTo(margins.left + plotWidth, margins.top + plotHeight);
  ctx.stroke();

  const tickCount = Math.min(5, xCount);
  ctx.fillStyle = "rgba(0, 0, 0, 0.62)";
  ctx.font = "12px Arial";
  ctx.textAlign = "center";
  ctx.textBaseline = "top";
  for (let i = 0; i < tickCount; i += 1) {
    const idx = tickCount === 1 ? 0 : Math.round((i / (tickCount - 1)) * (xCount - 1));
    const x = getX(idx);
    ctx.beginPath();
    ctx.moveTo(x, margins.top + plotHeight);
    ctx.lineTo(x, margins.top + plotHeight + 6);
    ctx.stroke();
    ctx.fillText(String(idx + 1), x, margins.top + plotHeight + 8);
  }

  const yTickCount = 5;
  ctx.textAlign = "right";
  ctx.textBaseline = "middle";
  for (let i = 0; i < yTickCount; i += 1) {
    const value = yMin + ((yMax - yMin) * i) / (yTickCount - 1);
    const y = getY(value);
    ctx.strokeStyle = "rgba(0, 0, 0, 0.08)";
    ctx.beginPath();
    ctx.moveTo(margins.left, y);
    ctx.lineTo(margins.left + plotWidth, y);
    ctx.stroke();

    ctx.strokeStyle = "rgba(0, 0, 0, 0.2)";
    ctx.beginPath();
    ctx.moveTo(margins.left - 6, y);
    ctx.lineTo(margins.left, y);
    ctx.stroke();
    ctx.fillStyle = "rgba(0, 0, 0, 0.62)";
    ctx.fillText(value.toFixed(2), margins.left - 10, y);
  }

  ctx.strokeStyle = "#2a6f9e";
  ctx.lineWidth = 2;
  ctx.beginPath();
  values.forEach((value, index) => {
    const x = getX(index);
    const y = getY(value);
    if (index === 0) {
      ctx.moveTo(x, y);
    } else {
      ctx.lineTo(x, y);
    }
  });
  ctx.stroke();

  ctx.fillStyle = "#1c4e70";
  values.forEach((value, index) => {
    const x = getX(index);
    const y = getY(value);
    ctx.beginPath();
    ctx.arc(x, y, 3, 0, Math.PI * 2);
    ctx.fill();
  });

  ctx.save();
  ctx.fillStyle = "rgba(0, 0, 0, 0.72)";
  ctx.font = "12px Arial";
  ctx.textAlign = "center";
  ctx.fillText("Principal Component", margins.left + plotWidth / 2, height - 10);
  ctx.translate(10, margins.top + plotHeight / 2);
  ctx.rotate(-Math.PI / 2);
  ctx.fillText("Standard Deviation", 0, 0);
  ctx.restore();

  syncElbowPlotPanelState();
};

const normalizeFeaturePlotNcol = () => {
  const input = document.getElementById(featurePlotNcolId);
  if (!input) return 3;

  const parsed = Number.parseInt(input.value, 10);
  const normalized = Number.isNaN(parsed) ? 3 : Math.min(6, Math.max(1, parsed));
  input.value = String(normalized);
  return normalized;
};

const markFeaturePlotDirty = () => {
  const featurePlotPanel = document.getElementById("floatingFeaturePlot");
  if (!featurePlotPanel) return;

  if (featurePlotPanel.dataset.featurePlotRendered !== "true") {
    featurePlotPanel.dataset.featurePlotStale = "false";
    return;
  }

  featurePlotPanel.dataset.featurePlotStale = "true";
};

const markDotPlotDirty = () => {
  const panel = document.getElementById("floatingDotPlot");
  if (!panel) return;

  panel.dataset.plotStale = panel.dataset.plotRendered === "true" ? "true" : "false";
};

const getDotPlotGroupMeta = (groupBy = reglElementData.plotMetaData.group_by) => {
  if (!groupBy) return null;

  const groupMeta = reglElementData.origData.cellMetaData[groupBy];
  if (!groupMeta || groupMeta.type !== "category" || !groupMeta.value) {
    return null;
  }

  return groupMeta;
};

const getDotPlotGroupLevels = (groupMeta = null) => {
  const resolvedGroupMeta = groupMeta || getDotPlotGroupMeta();
  if (!resolvedGroupMeta) return [];

  return Object.keys(resolvedGroupMeta.value);
};

const setDotPlotControlsDisabled = (disabled) => {
  const actionButton = document.getElementById(dotPlotActionId);
  const orderList = document.getElementById(dotPlotOrderListId);
  const orderReset = document.getElementById(dotPlotOrderResetId);

  if (actionButton) {
    actionButton.disabled = disabled;
  }
  if (orderList) {
    orderList.setAttribute("aria-disabled", disabled ? "true" : "false");
  }
  if (orderReset) {
    orderReset.dataset.busyDisabled = disabled ? "true" : "false";
  }
};

const setFeaturePlotControlsDisabled = (disabled) => {
  const actionButton = document.getElementById(featurePlotActionId);
  const ncolInput = document.getElementById(featurePlotNcolId);

  if (actionButton) {
    actionButton.disabled = disabled;
  }
  if (ncolInput) {
    ncolInput.disabled = disabled || Boolean(reglElementData.plotMetaData.moduleScore);
  }
};

const markVlnPlotDirty = () => {
  const panel = document.getElementById("floatingVlnPlot");
  if (!panel) return;

  panel.dataset.plotStale = panel.dataset.plotRendered === "true" ? "true" : "false";
};

const syncVlnPlotPanelState = () => {
  const panel = document.getElementById("floatingVlnPlot");
  const statusEl = document.getElementById(vlnPlotStatusId);
  if (!panel || !statusEl) return;

  const groupBy = reglElementData.plotMetaData.group_by;
  const { selectedOption, options } = normalizeVlnSelection();

  if (!groupBy || !reglElementData.origData.cellMetaData[groupBy]) {
    statusEl.textContent = "No grouping metadata available for VlnPlot.";
    return;
  }

  if (!selectedOption || options.length === 0) {
    statusEl.textContent = `Group: ${groupBy} | No numeric metadata or selected genes available`;
    return;
  }

  const modeLabel = selectedOption.type === "feature"
    ? `Feature: ${selectedOption.label}`
    : `Meta: ${selectedOption.label}`;

  statusEl.textContent = `Group: ${groupBy} | ${modeLabel}`;
};

const clearDotPlotOrderDragState = () => {
  const list = document.getElementById(dotPlotOrderListId);
  if (!list) return;
  list.querySelectorAll(".dragging, .drop-target").forEach((node) => {
    node.classList.remove("dragging", "drop-target");
  });
};

const getDefaultDotPlotGroupOrder = (groupLevels = []) => {
  if (!Array.isArray(groupLevels) || groupLevels.length === 0) return [];
  return [...groupLevels].sort(sortStringArray);
};

const getStoredDotPlotGroupOrder = () => {
  const panel = document.getElementById("floatingDotPlot");
  if (!panel) {
    return { isCustom: false, order: [] };
  }

  const isCustom = panel.dataset.dotPlotOrderCustom === "true";
  let order = [];
  if (panel.dataset.dotPlotOrder) {
    try {
      order = JSON.parse(panel.dataset.dotPlotOrder);
    } catch (_) {
      order = [];
    }
  }

  return {
    isCustom,
    order: Array.isArray(order) ? order : [],
  };
};

const setDotPlotGroupOrder = (order = [], isCustom = false) => {
  const panel = document.getElementById("floatingDotPlot");
  if (!panel) return;

  panel.dataset.dotPlotOrder = JSON.stringify(order);
  panel.dataset.dotPlotOrderCustom = isCustom ? "true" : "false";
};

const getRenderedDotPlotOrder = () => {
  const list = document.getElementById(dotPlotOrderListId);
  if (!list) return [];
  return [...list.querySelectorAll(".plot-floating-order-item")].map(
    (item) => item.dataset.value,
  );
};

const resolveDotPlotGroupOrder = (groupLevels = []) => {
  const defaultOrder = getDefaultDotPlotGroupOrder(groupLevels);
  const stored = getStoredDotPlotGroupOrder();
  if (!stored.isCustom) {
    return {
      order: defaultOrder,
      isCustom: false,
    };
  }

  const included = stored.order.filter((value) => defaultOrder.includes(value));
  const remaining = defaultOrder.filter((value) => !included.includes(value));
  return {
    order: [...included, ...remaining],
    isCustom: true,
  };
};

const renderDotPlotOrderList = (groupLevels = []) => {
  const list = document.getElementById(dotPlotOrderListId);
  const mode = document.getElementById(dotPlotOrderModeId);
  const reset = document.getElementById(dotPlotOrderResetId);
  if (!list || !mode || !reset) return { order: [], isCustom: false };

  const { order, isCustom } = resolveDotPlotGroupOrder(groupLevels);
  setDotPlotGroupOrder(isCustom ? order : [], isCustom);

  list.innerHTML = "";
  order.forEach((value) => {
    const item = document.createElement("div");
    item.className = "plot-floating-order-item";
    item.draggable = true;
    item.dataset.value = value;

    const handle = document.createElement("span");
    handle.className = "plot-floating-order-handle";
    handle.innerHTML = '<i class="bi bi-grip-vertical"></i>';

    const label = document.createElement("span");
    label.className = "plot-floating-order-label";
    label.textContent = value;

    item.append(handle, label);
    list.appendChild(item);
  });

  mode.textContent = isCustom ? "Custom order" : "Default order";
  reset.disabled = !isCustom;

  return { order, isCustom };
};

const syncDotPlotPanelState = () => {
  const panel = document.getElementById("floatingDotPlot");
  const statusEl = document.getElementById(dotPlotStatusId);
  const actionButton = document.getElementById(dotPlotActionId);
  const orderList = document.getElementById(dotPlotOrderListId);
  const orderReset = document.getElementById(dotPlotOrderResetId);
  if (!panel || !statusEl || !actionButton || !orderList || !orderReset) return;

  const icon = actionButton.querySelector("i");
  const hasRendered = panel.dataset.plotRendered === "true";
  const isStale = panel.dataset.plotStale === "true";
  const isBusy = dotPlotSpinner?.style.display !== "none";
  const groupBy = reglElementData.plotMetaData.group_by;
  const selectedFeatures = reglElementData.plotMetaData.selectedFeatures || [];
  const groupMeta = getDotPlotGroupMeta(groupBy);
  const groupLevels = getDotPlotGroupLevels(groupMeta);
  const { order: groupOrder, isCustom: hasCustomOrder } = renderDotPlotOrderList(groupLevels);

  if (!groupBy || !groupMeta || groupLevels.length === 0) {
    statusEl.textContent = "No grouping metadata available for DotPlot.";
    actionButton.disabled = true;
    orderList.innerHTML = "";
    orderList.setAttribute("aria-disabled", "true");
    orderReset.disabled = true;
    orderReset.dataset.busyDisabled = "false";
    actionButton.title = "Plot unavailable";
    if (icon) icon.className = "bi bi-slash-circle";
    return;
  }

  orderList.setAttribute("aria-disabled", "false");

  if (selectedFeatures.length <= 1) {
    statusEl.textContent = "Select at least two genes to plot DotPlot.";
    actionButton.disabled = true;
    orderReset.disabled = !hasCustomOrder;
    actionButton.title = "Select more genes";
    if (icon) icon.className = "bi bi-play-circle";
    return;
  }

  const orderLabel = hasCustomOrder
    ? groupOrder.join(" > ")
    : "default";
  statusEl.textContent = `Group: ${groupBy} | genes: ${selectedFeatures.join(", ")} | order: ${orderLabel}`;
  actionButton.disabled = isBusy;
  orderList.setAttribute("aria-disabled", isBusy ? "true" : "false");
  orderReset.disabled = isBusy || !hasCustomOrder;
  actionButton.title = hasRendered || isStale ? "Update plot" : "Plot";
  if (icon) {
    icon.className = hasRendered || isStale ? "bi bi-arrow-repeat" : "bi bi-play-circle";
  }
};

Shiny.addCustomMessageHandler("reglScatter_deselect", (msg) => {
  console.log("Deselect points...");
  reglElementData.deselectAll();
  clearRenameCategorySelectionUi();
  clearRenameAssignmentTransportState();
  syncRenameClusterSelectionUi();
});

function getPadding(element) {
  const style = element.currentStyle || window.getComputedStyle(element);
  return {
    top: parseInt(style.paddingTop, 10),
    right: parseInt(style.paddingRight, 10),
    bottom: parseInt(style.paddingBottom, 10),
    left: parseInt(style.paddingLeft, 10),
  };
}

const updateVlnPlot = (canvas) => {
  // ensure the infobox panel selected vlnplot
  // id was defined in R's nav_panel() title argument
  //if(infoPanelActive(btmBoxListId) !== "VlnPlot") return false
  if (!canvas || !vlnPlotSpinner) return;

  const hideSpinner = () => {
    vlnPlotSpinner.style.display = "none";
  };
  const showSpinner = () => {
    vlnPlotSpinner.style.display = "flex";
  };

  const container = canvas.parentElement;
  if (!container) {
    hideSpinner();
    return;
  }
  const rect = container.getBoundingClientRect();
  const containerPadding = getPadding(container);
  const canvasWidth =
    rect.width - containerPadding.left - containerPadding.right;
  const canvasHeight =
    rect.height - containerPadding.top - containerPadding.bottom;
  canvas.width = canvasWidth * 2;
  canvas.height = canvasHeight * 2;
  canvas.style.width = "100%";
  canvas.style.height = "100%";

  const ctx = canvas.getContext("2d");
  if (canvasWidth <= 0 || canvasHeight <= 0) {
    hideSpinner();
    return;
  }

  const groupBy = reglElementData.plotMetaData.group_by;
  const vlnPlotPanel = document.getElementById("floatingVlnPlot");
  const groupMeta = groupBy
    ? reglElementData.origData.cellMetaData[groupBy]
    : null;

  if (!groupMeta) {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    hideSpinner();
    syncVlnPlotPanelState();
    return;
  }

  console.log("Updating vlnplot...");
  showSpinner();

  // It seems that webR does not support typedArray
  const expressionInput = {};
  const metaInput = {};
  let expr = false;

  const { selectedOption } = normalizeVlnSelection();
  if (!selectedOption) {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    hideSpinner();
    syncVlnPlotPanelState();
    return;
  }

  if (selectedOption.type === "feature") {
    const f = selectedOption.label;
    const exprVec = reglElementData.origData.expressionData[f];
    if (!exprVec) {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      hideSpinner();
      syncVlnPlotPanelState();
      return;
    }
    expressionInput[f] = Array.from(exprVec);
    expr = f;
  } else {
    const selectedMetaCol = selectedOption.label;
    if (!reglElementData.origData.cellMetaData[selectedMetaCol]) {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      hideSpinner();
      syncVlnPlotPanelState();
      return;
    }
    metaInput[selectedMetaCol] = expandMeta(
      reglElementData.origData.cellMetaData[selectedMetaCol],
    );
  }

  const groupInput = {};
  groupInput[groupBy] = expandMeta(groupMeta);
  const groupOrder = [...new Set(groupInput[groupBy])].sort(sortStringArray);
  const dfInput = { ...groupInput, ...metaInput, ...expressionInput };
  for (const k of Object.keys(dfInput)) {
    // webr dataframe convertion doesn't support typed array
    dfInput[k] = Array.from(dfInput[k]);
  }
  console.log("vlnPlot inputs: ", dfInput, groupBy, groupOrder, expr);
  vlnPlot(
    shelter,
    canvasWidth,
    canvasHeight,
    dfInput,
    groupBy,
    groupOrder,
    (expr = expr),
    reglElementData.plotMetaData.catColors,
  )
    .then((res) => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const img = res.images[0];
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      if (vlnPlotPanel) {
        vlnPlotPanel.dataset.plotRendered = "true";
        vlnPlotPanel.dataset.plotStale = "false";
      }
    })
    .catch((error) => {
      console.error("Failed to update vlnPlot:", error);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
    })
    .finally(() => {
      hideSpinner();
      syncVlnPlotPanelState();
      shelter.purge();
    });
};

const updateDotPlot = (canvas) => {
  // ensure the infobox panel selected vlnplot
  // id was defined in R's nav_panel() title argument
  //if(infoPanelActive(btmBoxListId) !== "DotPlot") return false
  if (!canvas || !dotPlotSpinner) return;

  const hideSpinner = () => {
    dotPlotSpinner.style.display = "none";
  };
  const showSpinner = () => {
    dotPlotSpinner.style.display = "flex";
  };

  hideSpinner();

  const container = canvas.parentElement;
  if (!container) {
    hideSpinner();
    return;
  }
  const rect = container.getBoundingClientRect();
  const containerPadding = getPadding(container);
  const canvasWidth =
    rect.width - containerPadding.left - containerPadding.right;
  const canvasHeight =
    rect.height - containerPadding.top - containerPadding.bottom;

  canvas.width = canvasWidth * 2;
  canvas.height = canvasHeight * 2;
  canvas.style.width = "100%";
  canvas.style.height = "100%";

  const dotPlotPanel = document.getElementById("floatingDotPlot");
  const ctx = canvas.getContext("2d");
  if (canvasWidth <= 0 || canvasHeight <= 0) {
    hideSpinner();
    return;
  }

  const renderMessage = (message) => {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.font = "30px Arial";
    ctx.fillStyle = "#636363";
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillText(message, 10, 10);
    hideSpinner();
  };

  const features = reglElementData.plotMetaData.selectedFeatures || [];
  // dotPlot only be rendered when there are more than one selected genes
  if (features.length > 1) {
    const expressionInput = {};
    const missingExpr = features.some(
      (f) => !reglElementData.origData.expressionData[f],
    );
    if (missingExpr) {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      hideSpinner();
      syncDotPlotPanelState();
      return;
    }

    for (const f of features) {
      expressionInput[f] = Array.from(reglElementData.origData.expressionData[f]);
    }

    const groupBy = reglElementData.plotMetaData.group_by;
    const groupMeta = groupBy
      ? reglElementData.origData.cellMetaData[groupBy]
      : null;
    if (!groupMeta) {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      hideSpinner();
      syncDotPlotPanelState();
      return;
    }

    const groupValues = expandMeta(groupMeta);
    const { order: groupOrder } = resolveDotPlotGroupOrder(groupValues);
    const groupInput = {};
    groupInput[groupBy] = groupValues;
    const dfInput = { ...groupInput, ...expressionInput };

    setDotPlotControlsDisabled(true);
    showSpinner();
    dotPlot(shelter, canvasWidth, canvasHeight, dfInput, groupBy, groupOrder)
      .then((res) => {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        const img = res.images[0];
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        if (dotPlotPanel) {
          dotPlotPanel.dataset.plotRendered = "true";
          dotPlotPanel.dataset.plotStale = "false";
        }
      })
      .catch((error) => {
        console.error("Failed to update dotPlot:", error);
        ctx.clearRect(0, 0, canvas.width, canvas.height);
      })
      .finally(() => {
        hideSpinner();
        setDotPlotControlsDisabled(false);
        syncDotPlotPanelState();
        shelter.purge();
      });
  } else {
    renderMessage("Please select at least two features");
    syncDotPlotPanelState();
  }
};

// Debounce helper function
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

const isElementVisible = (el) => !!(el && el.offsetParent !== null);

// function to replace column with new Vector to simulate mutate operation
// if colName already exists in the table, the child/column will be
// replaced by the new vector; if colName doesn't exist, it will be
// appended to the table as the last column
const tableMutateCol = (table, colName, arrowVector) => {
  const vec = {};
  for (let i = 0; i < table.numCols; i++) {
    const field = table.schema.fields[i].name;
    vec[field] = table.getChildAt(i);
  }
  // replace the old one
  vec[colName] = arrowVector;
  return new Table(vec);
};

// function to create vlnplot dropend button
const createVlnDropend = (Id) => {
  const el = document.createElement("div");
  el.id = Id;
  el.classList.add("btn-group", "dropend");
  el.style.width = "2rem";
  el.style.position = "absolute";
  el.style.zIndex = 1;
  el.style.top = "0.2rem";
  el.style.left = "0.2rem";
  el.style.padding = "0";

  el.style.display = "flex";
  el.style.justifyContent = "center";
  el.style.alignItems = "center";

  const bt = document.createElement("button");
  bt.classList.add("btn", "dropdown-toggle", "p-0");
  bt.type = "button";
  bt.setAttribute("data-bs-toggle", "dropdown");
  bt.setAttribute("aria-expanded", "false");
  const icon = document.createElement("i");
  icon.classList.add("bi", "bi-columns");
  icon.style.fontSize = "1.2rem";
  bt.appendChild(icon);

  const ul = document.createElement("ul");
  ul.classList.add("dropdown-menu");

  const listHeader = document.createElement("li");
  const h = document.createElement("h6");
  h.classList.add("dropdown-header");
  h.innerHTML = "Select VlnPlot term";
  h.style.color = "var(--bs-primary)";
  listHeader.appendChild(h);
  ul.appendChild(listHeader);

  el.appendChild(bt);
  el.appendChild(ul);

  // add listener
  el.addEventListener("click", function (e) {
    const item = e.target.closest(".dropdown-item");
    if (item) {
      e.preventDefault();
      reglElementData.plotMetaData.selectedMeta = item.dataset.optionId || null;
      console.log("reglElementData.plotMetaData", reglElementData.plotMetaData);
      markVlnPlotDirty();
      refreshVlnDropOptions();
      const vlnPlotCanvas = document.getElementById(vlnPlotElId);
      if (vlnPlotCanvas && isElementVisible(vlnPlotCanvas)) {
        updateVlnPlot(vlnPlotCanvas);
      } else {
        syncVlnPlotPanelState();
      }
    }
  });

  return el;
};

const getVlnPlotTermOptions = () => {
  const metaOptions = getNumericCols(reglElementData).map((label) => ({
    id: `meta:${label}`,
    label,
    type: "meta",
  }));
  const featureOptions = (reglElementData.plotMetaData.selectedFeatures || [])
    .filter((feature) => Boolean(reglElementData.origData.expressionData[feature]))
    .map((feature) => ({
      id: `feature:${feature}`,
      label: feature,
      type: "feature",
    }));

  return [...metaOptions, ...featureOptions];
};

const normalizeVlnSelection = () => {
  const options = getVlnPlotTermOptions();
  const currentId = reglElementData.plotMetaData.selectedMeta;
  let selectedOption = options.find((option) => option.id === currentId) || null;

  if (!selectedOption) {
    selectedOption = options.find((option) => option.type === "meta") || options[0] || null;
  }

  return {
    options,
    selectedOption,
  };
};

// function to update menu options of the dropend button
const updateDropOptions = (btId) => {
  const bt = document.getElementById(btId);
  if (!bt) return;

  const menu = bt.querySelector(".dropdown-menu");
  if (!menu) return;

  const { options, selectedOption } = normalizeVlnSelection();

  const listHeader = document.createElement("li");
  const h = document.createElement("h6");
  h.classList.add("dropdown-header");
  h.innerHTML = "Select VlnPlot term";
  h.style.color = "var(--bs-primary)";
  listHeader.appendChild(h);
  menu.appendChild(listHeader);

  if (options.length === 0) {
    const emptyItem = document.createElement("li");
    emptyItem.classList.add("dropdown-item-text", "text-muted");
    emptyItem.textContent = "No numeric metadata or selected genes available";
    menu.appendChild(emptyItem);
    return;
  }

  options.forEach((option) => {
    const item = document.createElement("li");
    const a = document.createElement("a");
    a.classList.add("dropdown-item");
    if (selectedOption?.id === option.id) {
      a.classList.add("active");
    }
    a.setAttribute("href", "#");
    a.dataset.optionId = option.id;
    a.style.fontSize = "0.9rem";
    const typeLabel = document.createElement("span");
    typeLabel.classList.add("text-muted");
    typeLabel.textContent = ` (${option.type})`;
    a.replaceChildren(document.createTextNode(option.label), typeLabel);
    item.appendChild(a);
    menu.appendChild(item);
  });
};

const refreshVlnDropOptions = () => {
  emptyDropOptions(vlnDropDownId);
  updateDropOptions(vlnDropDownId);
};

const emptyDropOptions = (btId) => {
  const bt = document.getElementById(btId);
  if (!bt) return;
  const menu = bt.querySelector(".dropdown-menu");
  if (!menu) return;
  reglScatterCanvas.removeAllChildNodes(menu);
};

// extract numeric meta columns
const getNumericCols = (reglElementData) => {
  const cols = [];
  Object.keys(reglElementData.origData.cellMetaData).forEach((key) => {
    if (
      reglElementData.origData.cellMetaData[key].type === "number" &&
      key !== "cells"
    ) {
      cols.push(key);
    }
  });
  return cols;
};

// extrac nonNumeric meta columns
const getNonNumericCols = (reglElementData) => {
  const cols = [];
  Object.keys(reglElementData.origData.cellMetaData).forEach((key) => {
    if (
      reglElementData.origData.cellMetaData[key].type === "category" &&
      key !== "cells"
    ) {
      cols.push(key);
    }
  });
  return cols;
};
