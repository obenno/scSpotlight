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

// init webR instance for reading reduction and expr data
// It seems put two async webr jobs in the same instance might cause data processing conflicts
// We found this when reading reduction and meta data with just one instance
let webR;
let shelter;

// global variables to store spinners
let vlnPlotSpinner;
let dotPlotSpinner;
let featurePlotSpinner;
let mainPlotSpinner;

const ipcCache = {
  reductions: new Map(),
  expr: new Map(),
  reductionVersion: null,
  exprVersion: null,
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
  if (ipcCache.reductionVersion !== version) {
    ipcCache.reductions.clear();
    ipcCache.reductionVersion = version;
    updateReductionCacheKeys();
  }
};

const ensureExprCacheVersion = (version) => {
  if (ipcCache.exprVersion !== version) {
    ipcCache.expr.clear();
    ipcCache.exprVersion = version;
    updateExprCacheKeys();
  }
};

const makeReductionCacheKey = (version, reductionName) =>
  `${version}::${reductionName}`;

const makeExprCacheKey = (version, assay, geneName) =>
  `${version}::${assay}::${geneName}`;

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
      webR = await initWebRInstance();
      shelter = await initShelter(webR);
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

    syncVlnPlotPanelState();
    syncDotPlotPanelState();
    syncFeaturePlotPanelState();
    syncElbowPlotPanelState();

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
  const storedFeatures = sparkLineArray.map((e) => {
    // select the first span element
    return e.querySelector("span").innerHTML;
  });
  // remember to add shiny module id as prefix
  Shiny.setInputValue("inputFeatures-storedFeatures", storedFeatures);
});

Shiny.addCustomMessageHandler("reduction_ready", (msg) => {
  try {
    const reductionURL =
      window.location.origin + "/data/reduction/" + msg.reductionFile;
    (async () => {
      // show spinner
      if (mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }

      ensureReductionCacheVersion(msg.reductionVersion);
      const cacheKey = makeReductionCacheKey(
        msg.reductionVersion,
        msg.reductionName,
      );
      const buffer = await fetchArrowIPCBuffer(reductionURL);
      ipcCache.reductions.set(cacheKey, buffer);
      updateReductionCacheKeys();

      const table = decodeArrowIPC(buffer);
      const df = {
        X: getFloat32Column(table, "X"),
        Y: getFloat32Column(table, "Y"),
      };
      reglElementData.updateReductionData(df);
      Shiny.setInputValue("reductionProcessed", true, { priority: "event" });
      console.log("reduction", df);

      // do not hide the spinner, since it will trigger the reglScatter_plot immediately
    })().catch((error) => {
      console.error("There was a problem:", error);
      mainPlotSpinner.style.display = "none";
    });
  } catch (error) {
    console.error("There was a problem:", error);
    mainPlotSpinner.style.display = "none";
  }
});

Shiny.addCustomMessageHandler("reduction_cached", (msg) => {
  try {
    (async () => {
      if (mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }

      ensureReductionCacheVersion(msg.reductionVersion);
      const cacheKey = makeReductionCacheKey(
        msg.reductionVersion,
        msg.reductionName,
      );
      const buffer = ipcCache.reductions.get(cacheKey);
      if (!buffer) {
        throw new Error(`Cached reduction IPC missing for ${cacheKey}`);
      }

      const table = decodeArrowIPC(buffer);
      const df = {
        X: getFloat32Column(table, "X"),
        Y: getFloat32Column(table, "Y"),
      };
      reglElementData.updateReductionData(df);
      Shiny.setInputValue("reductionProcessed", true, { priority: "event" });
    })().catch((error) => {
      console.error("There was a problem:", error);
      mainPlotSpinner.style.display = "none";
    });
  } catch (error) {
    console.error("There was a problem:", error);
    mainPlotSpinner.style.display = "none";
  }
});

Shiny.addCustomMessageHandler("pca_ready", (msg) => {
  try {
    (async () => {
      if (!msg?.stdevFile) {
        reglElementData.updatePcaStdev(null);
        syncElbowPlotPanelState();
        requestFloatingPlotRefresh(["floatingElbowPlot"]);
        return;
      }

      const stdevURL = `${window.location.origin}/data/reduction/${msg.stdevFile}`;
      const table = await readArrowIPC(stdevURL);
      const stdevArray = getFloat32Column(table, "stdev");
      reglElementData.updatePcaStdev(stdevArray);
      syncElbowPlotPanelState();
      requestFloatingPlotRefresh(["floatingElbowPlot"]);
    })().catch((error) => {
      console.error("There was a problem:", error);
    });
  } catch (error) {
    console.error("There was a problem:", error);
  }
});

const syncMetaUiAfterUpdate = ({ fullTransfer = false } = {}) => {
  const nonNumericCols = getNonNumericCols(reglElementData);

  emptyDropOptions(vlnDropDownId);
  updateDropOptions(vlnDropDownId);

  markVlnPlotDirty();
  markDotPlotDirty();
  markFeaturePlotDirty();
  requestFloatingPlotRefresh([
    "floatingVlnPlot",
    "floatingDotPlot",
    "floatingFeaturePlot",
  ]);

  Shiny.setInputValue("metaCols", nonNumericCols);
  if (fullTransfer) {
    Shiny.setInputValue("metaProcessed", true, { priority: "event" });
  } else {
    Shiny.setInputValue(
      "metaPatchProcessed",
      { timestamp: Date.now() },
      { priority: "event" },
    );
  }
};

Shiny.addCustomMessageHandler("meta_ready", (msg) => {
  try {
    const metaURL = window.location.origin + "/data/meta/" + msg.metaFile;
    (async () => {
      // show main plot spinner
      if (mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }
      const table = await readArrowIPC(metaURL);
      const out = parseMetaFromArrow(table);
      console.log("metaData", out);
      reglElementData.updateCellMetaData(out);
      syncMetaUiAfterUpdate({ fullTransfer: true });

      // do not hide the spinner, since it will trigger the reglScatter_plot immediately
    })().catch((error) => {
      console.error("There was a problem:", error);
      mainPlotSpinner.style.display = "none";
    });
  } catch (error) {
    console.error("There was a problem:", error);
    mainPlotSpinner.style.display = "none";
  }
});

Shiny.addCustomMessageHandler("meta_patch_ready", (msg) => {
  try {
    const metaURL = window.location.origin + "/data/meta/" + msg.metaFile;
    (async () => {
      if (mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }

      const table = await readArrowIPC(metaURL);
      const out = parseMetaFromArrow(table);
      console.log("metaPatch", out);
      reglElementData.updateCellMetaDataPatch(out);
      syncMetaUiAfterUpdate({ fullTransfer: false });
    })().catch((error) => {
      console.error("There was a problem:", error);
      mainPlotSpinner.style.display = "none";
    });
  } catch (error) {
    console.error("There was a problem:", error);
    mainPlotSpinner.style.display = "none";
  }
});

Shiny.addCustomMessageHandler("expr_ready", (msg) => {
  try {
    const exprURL = window.location.origin + "/data/expr/" + msg.exprFile;
    (async () => {
      ensureExprCacheVersion(msg.exprVersion);
      const cacheKey = makeExprCacheKey(msg.exprVersion, msg.assay, msg.geneName);
      const buffer = await fetchArrowIPCBuffer(exprURL);
      ipcCache.expr.set(cacheKey, buffer);
      updateExprCacheKeys();

      const table = decodeArrowIPC(buffer);
      const expr = {};
      expr[msg.geneName] = getFloat32Column(table, "expr");
      reglElementData.updateExpressionData(expr);
      console.log("exprData", reglElementData.origData.expressionData);
      const feature = Object.keys(expr)[0];
      const sparkLine = document
        .getElementById("featureSparkLine")
        .querySelectorAll(".featureSparkLine");
      const sparkLineArray = [...sparkLine];
      sparkLineArray.forEach((e) => {
        if (e.querySelector("span").innerHTML == feature) {
          updateSparkLine(e, reglElementData);
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
    })();
  } catch (error) {
    console.error("There was a problem:", error);
  }
});

Shiny.addCustomMessageHandler("expr_cached", (msg) => {
  try {
    (async () => {
      ensureExprCacheVersion(msg.exprVersion);
      const cacheKey = makeExprCacheKey(msg.exprVersion, msg.assay, msg.geneName);
      const buffer = ipcCache.expr.get(cacheKey);
      if (!buffer) {
        throw new Error(`Cached expression IPC missing for ${cacheKey}`);
      }

      const table = decodeArrowIPC(buffer);
      const expr = {};
      expr[msg.geneName] = getFloat32Column(table, "expr");
      reglElementData.updateExpressionData(expr);
      console.log("exprData", reglElementData.origData.expressionData);
      const feature = Object.keys(expr)[0];
      const sparkLine = document
        .getElementById("featureSparkLine")
        .querySelectorAll(".featureSparkLine");
      const sparkLineArray = [...sparkLine];
      sparkLineArray.forEach((e) => {
        if (e.querySelector("span").innerHTML == feature) {
          updateSparkLine(e, reglElementData);
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
    });
  } catch (error) {
    console.error("There was a problem:", error);
  }
});

Shiny.addCustomMessageHandler("clear_expr", (msg) => {
  // purge exprssion data
  reglElementData.origData.expressionData = {};
  reglElementData.plotMetaData.selectedFeatures = [];
  // remember to add shiny module id as prefix
  Shiny.setInputValue("inputFeatures-storedFeatures", [], {
    priority: "event",
  });
  Shiny.setInputValue("selectedFeatures", [], { priority: "event" });

  // remove all sparkline
  document.getElementById("featureSparkLine").innerHTML = "";

  markVlnPlotDirty();
  refreshVlnDropOptions();
  markDotPlotDirty();
  markFeaturePlotDirty();
  requestFloatingPlotRefresh([
    "floatingDotPlot",
    "floatingFeaturePlot",
  ]);
});

Shiny.addCustomMessageHandler("selectPointsByCategory", (msg) => {
  // handler for selecting cells by category
  const groupBy = msg.groupBy;
  const splitBy = msg.splitBy;
  const selectedGroupBy = msg.selectedGroupBy;
  const selectedSplitBy = msg.selectedSplitBy;
  const selectedCells = [];
  const groupByArray = groupBy
    ? expandMeta(reglElementData.origData.cellMetaData[groupBy])
    : [];
  const splitByArray = splitBy
    ? expandMeta(reglElementData.origData.cellMetaData[splitBy])
    : [];
  const colNames = Object.keys(reglElementData.origData.cellMetaData);
  const cellsArray = colNames.includes("cells")
    ? expandMeta(reglElementData.origData.cellMetaData["cells"])
    : [];
  if (groupBy && selectedGroupBy) {
    if (!splitBy) {
      groupByArray.forEach((e, i) => {
        const currentCell = cellsArray[i];
        if (selectedGroupBy.includes(e)) {
          selectedCells.push(currentCell);
        }
      });
    } else {
      groupByArray.forEach((e, i) => {
        const currentSplitBy = splitByArray[i];
        const currentCell = cellsArray[i];
        if (
          selectedGroupBy.includes(e) &&
          selectedSplitBy.includes(currentSplitBy)
        ) {
          selectedCells.push(currentCell);
        }
      });
    }
  }
  if (selectedCells.length > 0) {
    // update selectedCells in reglElementData
    reglElementData.plotData.selectedCells = selectedCells;
    Shiny.setInputValue("categorySelectedCells", selectedCells, {
      priority: "event",
    });
  }
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
  }
  console.log({
    [newMetaCol]: expandMeta(reglElementData.origData.cellMetaData[newMetaCol]),
  });

  const nonNumericCols = Object.keys(
    reglElementData.origData.cellMetaData,
  ).reduce((acc, val, _) => {
    if (reglElementData.origData.cellMetaData[val].type === "category") {
      acc.push(val);
    }
    return acc;
  }, []);
  console.log("nonNumericCols", nonNumericCols);
  Shiny.setInputValue("metaCols", nonNumericCols);
  // send the newMetaCol data to R
  Shiny.setInputValue(
    "newMetaColData",
    {
      [newMetaCol]: expandMeta(
        reglElementData.origData.cellMetaData[newMetaCol],
      ),
    },
    { priority: "event" },
  );
  // deselct points
  reglElementData.deselectAll();
  // reset selectedCells
  Shiny.setInputValue("categorySelectedCells", null, { priority: "event" });
});

Shiny.addCustomMessageHandler("reglScatter_plot", (msg) => {
  // first remove spinner if exists
  if (mainPlotSpinner.style.display === "none") {
    // show spinners for the plot
    console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
    mainPlotSpinner.style.display = "flex";
    console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
  }
  const parentDiv = document.getElementById(mainPlotElId);
  reglElementData.plotEl.style.display = "none";

  // clear reglScatterCanvas data including plotMetaData
  console.log("msg: ", msg);
  const group_by = msg.group_by;
  const split_by = msg.split_by;
  const moduleScore = msg.moduleScore;

  // update group_by levels to server side
  let groupByLevels = group_by
    ? new Set(expandMeta(reglElementData.origData.cellMetaData[group_by]))
    : null;
  groupByLevels = group_by ? [...groupByLevels].sort() : null;
  // when split_by == null, this will return a set with size 0
  //     // update split_by levels to server side
  let splitByLevels = split_by
    ? new Set(expandMeta(reglElementData.origData.cellMetaData[split_by]))
    : null;
  splitByLevels = split_by ? [...splitByLevels].sort() : null;
  Shiny.setInputValue("metaColLevels", {
    groupBy: groupByLevels,
    splitBy: splitByLevels,
  });

  reglElementData.clear();
  // update plotMetaData with previous one
  reglElementData.updatePlotMetaData(group_by, split_by, moduleScore);
  // then update with new msg, in case msg is empty
  //reglElementData.updatePlotMetaData(msg);
  console.log("reglElementData.plotMetaData: ", reglElementData.plotMetaData);

  console.log("Generating plotEl");
  // regenerate plot elements
  console.profile("Generating plotEl");
  reglElementData.generatePlotEl();
  console.profileEnd("Generating plotEl");
  console.log("reglElementData :", reglElementData);
  // update legend elements
  parentDiv.appendChild(reglElementData.plotEl);
  // create deck instance after plot element is mounted in DOM
  reglElementData.mountDeck();
  const accordions = document.querySelectorAll(".accordion-item");
  const category_accordion = [...accordions].filter((e) => {
    if (e.dataset.value == "analysis_category") {
      return e;
    }
  });
  const category_accordion_body =
    category_accordion[0].querySelector(".accordion-body");
  category_accordion_body.appendChild(reglElementData.catLegendEl);
  category_accordion_body.appendChild(reglElementData.expLegendEl);

  // return selected points to server side
  reglElementData.setSelectionHandlers({
    onSelect: ({ selectedCells }) => {
      console.log("selectedCells: ", selectedCells);
      Shiny.setInputValue("selectedPoints", selectedCells, {
        priority: "event",
      });
    },
    onDeselect: () => {
      Shiny.setInputValue("selectedPoints", null);
    },
  });

  reglElementData.plotEl.style.display = "flex";

  // hide spinner
  if (mainPlotSpinner.style.display !== "none") {
    console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
    mainPlotSpinner.style.display = "none";
    console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
  }
  //featurePlot().then({});
  markVlnPlotDirty();
  markDotPlotDirty();
  markFeaturePlotDirty();
  requestFloatingPlotRefresh([
    "floatingVlnPlot",
    "floatingDotPlot",
    "floatingFeaturePlot",
  ]);
});

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
  if (!stdev || stdev.length === 0) {
    statusEl.textContent = "No PCA standard deviation data available.";
    return;
  }

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
    a.innerHTML = `${option.label} <span class="text-muted">(${option.type})</span>`;
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
