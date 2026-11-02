/**
 * @vitest-environment jsdom
 */

import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import payloadContracts from "../inst/protocol/browser-payload-contracts.json";

const testState = vi.hoisted(() => ({
  handlers: {},
  inputs: [],
  reglInstance: null,
  spinners: {},
}));

const TEST_RESOURCE_PREFIX = "data-test-session";
const TEST_CELL_IDENTITY = "0123456789abcdef0123456789abcdef";

vi.mock("shiny", () => ({}), { virtual: true });

vi.mock("./modules/spinner.js", () => ({
  initFullScreenSpinner: () => document.createElement("div"),
  removeFullScreenSpinner: vi.fn(),
  addOverlaySpinner: (id) => {
    const el = document.createElement("div");
    el.style.display = "none";
    testState.spinners[id] = el;
    return el;
  },
}));

vi.mock("./modules/floatingPlots.js", () => ({
  initFloatingPlots: vi.fn(),
  requestFloatingPlotRefresh: vi.fn(),
}));

vi.mock("./modules/webr.js", () => ({
  initShelter: vi.fn().mockResolvedValue({ purge: vi.fn() }),
  featurePlot: vi.fn(),
  vlnPlot: vi.fn(),
  dotPlot: vi.fn(),
  initWebRInstance: vi.fn().mockResolvedValue({}),
}));

vi.mock("./modules/arrowReader.js", () => ({
  readArrowIPC: vi.fn(),
  fetchArrowIPCBuffer: vi.fn(),
  decodeArrowIPC: vi.fn(),
  getFloat32Column: vi.fn(),
  parseMetaFromArrow: vi.fn(),
}));

vi.mock("./modules/featureSparkLine.js", () => ({
  createSparkLine: vi.fn(),
  updateSparkLine: vi.fn(),
}));

vi.mock("./modules/deckScatter.js", () => {
  const expandMeta = (meta) => {
    if (!meta) return [];
    if (Array.isArray(meta)) return meta;
    if (Array.isArray(meta.value)) return meta.value;
    if (ArrayBuffer.isView(meta.value)) return meta.value;
    if (meta.type === "cell_id" && meta.value) return meta.value;
    if (meta.type === "category" && meta.value && typeof meta.value === "object") {
      const entries = Object.entries(meta.value);
      const size = entries.reduce((max, [, indices]) => {
        const last = Math.max(...indices, -1);
        return Math.max(max, last + 1);
      }, 0);
      const expanded = Array(size).fill(undefined);
      entries.forEach(([label, indices]) => {
        indices.forEach((index) => {
          expanded[index] = label;
        });
      });
      return expanded;
    }
    return [];
  };

  class MockReglScatterCanvas {
    static removeAllChildNodes(node) {
      while (node.firstChild) {
        node.removeChild(node.firstChild);
      }
    }

    constructor() {
      this.plotMetaData = {
        group_by: null,
        split_by: null,
        moduleScore: null,
        selectedFeatures: [],
        viewFilter: null,
        viewFilterVersion: 0,
        cellIdentity: TEST_CELL_IDENTITY,
      };
      this.plotData = {
        selectedCells: [],
        cells: [["c1", "c2", "c3"]],
        visibleCellCount: 3,
      };
      this.origData = {
        cellMetaData: {},
        expressionData: {},
        reductionData: { umap: [1] },
      };
      this.plotEl = document.createElement("div");
      this.catLegendEl = document.createElement("div");
      this.expLegendEl = document.createElement("div");
      this.selectionSource = null;
      this.interactions = { clearLasso: vi.fn() };
      this.updateCellMetaDataPatchCalls = [];
      this.updateExpressionDataCalls = [];
      testState.reglInstance = this;
    }

    clear() {
      this.selectionSource = null;
      this.plotData.selectedCells = [];
      this.plotEl = document.createElement("div");
      this.catLegendEl = document.createElement("div");
      this.expLegendEl = document.createElement("div");
    }

    updatePlotMetaData(groupBy, splitBy, moduleScore) {
      this.plotMetaData.group_by = groupBy;
      this.plotMetaData.split_by = splitBy;
      this.plotMetaData.moduleScore = moduleScore;
    }

    generatePlotEl() {
      const cells = this.origData.cellMetaData.cells?.value || ["c1", "c2", "c3"];
      const nFeature = this.origData.cellMetaData.nFeature_RNA?.value || [];
      const percentMt = this.origData.cellMetaData.percent_mt?.value || [];
      const filter = this.plotMetaData.viewFilter;
      const visibleCells = !filter
        ? cells
        : cells.filter((cell, index) => {
          const nFeatureValue = Number(nFeature[index]);
          const percentMtValue = Number(percentMt[index]);
          return Number.isFinite(nFeatureValue) &&
            Number.isFinite(percentMtValue) &&
            nFeatureValue > Number(filter.nFeature?.min) &&
            nFeatureValue < Number(filter.nFeature?.max) &&
            percentMtValue < Number(filter.percentMt?.max);
        });
      this.plotData.cells = [visibleCells];
      this.plotData.visibleCellCount = visibleCells.length;
    }

    mountDeck() {}

    createRenderReplacement() {
      const replacement = new MockReglScatterCanvas();
      replacement.plotMetaData = {
        ...this.plotMetaData,
        selectedFeatures: [...(this.plotMetaData.selectedFeatures || [])],
      };
      replacement.plotData = {
        ...this.plotData,
        selectedCells: [...(this.plotData.selectedCells || [])],
      };
      replacement.origData = this.origData;
      return replacement;
    }

    destroy() {}

    updateCellCount() {}

    updateReductionData(reductionData) {
      this.origData.reductionData = reductionData;
    }

    updateCellMetaData(cellMetaData) {
      this.origData.cellMetaData = cellMetaData;
    }

    updateCellMetaDataPatch(cellMetaDataPatch) {
      const existingMeta = this.origData.cellMetaData || {};
      const expectedLength = existingMeta.cells ? expandMeta(existingMeta.cells).length : null;
      Object.entries(cellMetaDataPatch).forEach(([key, value]) => {
        if (!value || value.type === undefined || value.value === undefined) {
          throw new Error(`Invalid metadata patch payload for column ${key}`);
        }
        if (expectedLength !== null && expandMeta(value).length !== expectedLength) {
          throw new Error(`Metadata patch length mismatch for ${key}`);
        }
        if (existingMeta[key]?.type !== undefined && existingMeta[key].type !== value.type) {
          throw new Error(`Metadata patch type mismatch for ${key}`);
        }
      });
      this.updateCellMetaDataPatchCalls.push(cellMetaDataPatch);
      this.origData.cellMetaData = {
        ...this.origData.cellMetaData,
        ...cellMetaDataPatch,
      };
    }

    updateExpressionData(expressionData) {
      this.updateExpressionDataCalls.push(expressionData);
      Object.entries(expressionData).forEach(([feature, values]) => {
        this.origData.expressionData[feature] = new Float32Array(values);
      });
    }

    updatePcaStdev(pcaStdev) {
      this.origData.pcaStdev = pcaStdev ? new Float32Array(pcaStdev) : null;
    }

    clearHighlight() {}

    setSelectedCells(selectedCells = [], { source = null } = {}) {
      this.selectionSource = source;
      const visibleCells = new Set((this.plotData.cells || []).flat());
      this.plotData.selectedCells = [...new Set(selectedCells)]
        .filter((cell) => visibleCells.has(cell));
    }

    setSelectionHandlers(handlers) {
      this.selectionHandlers = handlers;
    }

    deselectAll() {
      this.setSelectedCells([], { source: null });
      if (this.selectionHandlers?.onDeselect) {
        this.selectionHandlers.onDeselect();
      }
    }
  }

  return {
    reglScatterCanvas: MockReglScatterCanvas,
    expandMeta,
    getMetaLevels: (meta) => Object.keys(meta?.value || {}).sort(),
    invalidateMetaCache: vi.fn(),
    sortStringArray: (values) => [...values].sort(),
  };
});

const buildDom = () => {
  document.body.innerHTML = `
    <div id="mainClusterPlot-clusterPlot">
      <div id="scatterPlotNote"></div>
      <div id="info"></div>
      <div class="label-slider"></div>
      <div id="downloadIcon"></div>
    </div>
    <div><canvas id="VlnPlot"></canvas></div>
    <div><canvas id="featurePlotCanvas"></canvas></div>
    <div><canvas id="DotPlot"></canvas></div>
    <div id="featureSparkLine"></div>
    <div id="renameCluster-selectCellFromCat"></div>
    <select id="renameCluster-chosenGroup" multiple></select>
    <select id="renameCluster-chosenSplit" multiple></select>
    <div id="renameCluster-selectedCellsText"></div>
    <input id="renameCluster-newMeta" />
    <input id="renameCluster-assignAs" />
    <button id="renameCluster-assign"></button>
    <select id="updateReduction-reduction"><option value="umap" selected>umap</option></select>
    <div id="floatingVlnPlot"></div>
    <div id="floatingElbowPlot">
      <div id="floatingElbowPlotStatus"></div>
      <canvas id="elbowPlotCanvas"></canvas>
    </div>
    <div id="floatingFeaturePlot">
      <button id="floatingFeaturePlotAction"><i class="bi bi-play-circle"></i></button>
      <div id="floatingFeaturePlotStatus"></div>
      <input id="floatingFeaturePlotNcol" value="3" />
    </div>
    <div id="floatingDotPlot">
      <button id="floatingDotPlotAction"><i class="bi bi-play-circle"></i></button>
      <div id="floatingDotPlotStatus"></div>
      <div id="floatingDotPlotOrderList"></div>
      <button id="floatingDotPlotOrderReset"></button>
      <span id="floatingDotPlotOrderMode"></span>
    </div>
    <div class="accordion-item" data-value="analysis_category">
      <div class="accordion-body"></div>
    </div>
  `;
};

const installShiny = () => {
  const resourceBackedMessages = new Set([
    "meta_ready",
    "meta_patch_ready",
    "reduction_ready",
    "reductions_ready",
    "pca_ready",
    "expr_ready",
  ]);
  globalThis.Shiny = {
    addCustomMessageHandler: (name, handler) => {
      testState.handlers[name] = resourceBackedMessages.has(name)
        ? (msg) => handler({
          resourcePrefix: TEST_RESOURCE_PREFIX,
          ...((name === "meta_ready" || name === "meta_patch_ready")
            ? { cellIdentity: TEST_CELL_IDENTITY }
            : {}),
          ...msg,
        })
        : handler;
    },
    setInputValue: (...args) => {
      testState.inputs.push(args);
    },
  };
};

const loadIndex = async () => {
  await import("./index.js");
  document.dispatchEvent(new Event("DOMContentLoaded"));
  await Promise.resolve();
};

const resetReglInstance = () => {
  if (!testState.reglInstance) return;
  testState.reglInstance.plotMetaData = {
    group_by: null,
    split_by: null,
    moduleScore: null,
    selectedFeatures: [],
    viewFilter: null,
    viewFilterVersion: 0,
    cellIdentity: TEST_CELL_IDENTITY,
  };
  testState.reglInstance.plotData = {
    selectedCells: [],
    cells: [["c1", "c2", "c3"]],
    visibleCellCount: 3,
  };
  testState.reglInstance.origData = {
    cellMetaData: {},
    expressionData: {},
    reductionData: { umap: [1] },
    pcaStdev: null,
  };
  testState.reglInstance.plotEl = document.createElement("div");
  testState.reglInstance.catLegendEl = document.createElement("div");
  testState.reglInstance.expLegendEl = document.createElement("div");
  testState.reglInstance.selectionSource = null;
  testState.reglInstance.selectionHandlers = null;
  testState.reglInstance.interactions = { clearLasso: vi.fn() };
  testState.reglInstance.updateCellMetaDataPatchCalls = [];
  testState.reglInstance.updateExpressionDataCalls = [];
  testState.reglInstance.createRenderReplacement = Object.getPrototypeOf(
    testState.reglInstance,
  ).createRenderReplacement;
  testState.reglInstance.destroy = Object.getPrototypeOf(
    testState.reglInstance,
  ).destroy;
  testState.reglInstance.setSelectionHandlers = Object.getPrototypeOf(
    testState.reglInstance,
  ).setSelectionHandlers;
};

const setCategoryMeta = (columnName, mapping) => {
  testState.reglInstance.origData.cellMetaData.cells = {
    type: "cell_id",
    value: ["c1", "c2", "c3"],
  };
  testState.reglInstance.origData.cellMetaData[columnName] = {
    type: "category",
    value: mapping,
  };
};

const setAssignmentInputs = ({ colName = "assignedCluster", value = "T cell" } = {}) => {
  document.getElementById("renameCluster-newMeta").value = colName;
  document.getElementById("renameCluster-assignAs").value = value;
};

const clickAssign = () => {
  const assignButton = document.getElementById("renameCluster-assign");
  assignButton.dispatchEvent(new Event("pointerdown", { bubbles: true }));
  assignButton.click();
};

const selectValues = (id, values) => {
  const el = document.getElementById(id);
  [...el.options].forEach((option) => {
    option.selected = values.includes(option.value);
  });
  el.dispatchEvent(new Event("change"));
};

const browserContractMessageNames = [
  "meta_ready",
  "meta_patch_ready",
  "reduction_ready",
  "reductions_ready",
  "pca_ready",
  "expr_ready",
  "reduction_cached",
  "expr_cached",
  "clear_expr",
  "transfer_error",
];

const latestInputValue = (name) => {
  const found = [...testState.inputs].reverse().find(([inputName]) => inputName === name);
  return found?.[1];
};

const encodeLabelBuffer = (label) => new TextEncoder().encode(label).buffer;

const decodeLabelBuffer = (buffer) => new TextDecoder().decode(buffer);

const addFeatureSparkLine = (feature) => {
  const container = document.createElement("span");
  container.className = "featureSparkLine";
  const label = document.createElement("span");
  label.className = "feature-gene-symbol";
  label.textContent = feature;
  container.appendChild(label);
  const sparkLine = document.createElement("span");
  sparkLine.className = "sparkLine";
  const progress = document.createElement("span");
  sparkLine.appendChild(progress);
  container.appendChild(sparkLine);
  const icon = document.createElement("span");
  icon.className = "icon-container";
  icon.appendChild(document.createElement("span"));
  container.appendChild(icon);
  document.getElementById("featureSparkLine").appendChild(container);
  return container;
};

const resetArrowReaderMocks = async () => {
  const arrowReader = await import("./modules/arrowReader.js");
  arrowReader.readArrowIPC.mockReset();
  arrowReader.fetchArrowIPCBuffer.mockReset();
  arrowReader.decodeArrowIPC.mockReset();
  arrowReader.getFloat32Column.mockReset();
  arrowReader.parseMetaFromArrow.mockReset();
  return arrowReader;
};

const expectResourceUrl = (url, kind, basename) => {
  expect(url).toBe(`${window.location.origin}/${TEST_RESOURCE_PREFIX}/${kind}/${basename}`);
  expect(url).not.toBe(`${window.location.origin}/data/${kind}/${basename}`);
  expect(url).not.toMatch(/filePath|output_file|matrix_dir|\/tmp|[A-Za-z]:\\/);
};

const expectSessionResourceUrl = (url, resourcePrefix, kind, basename) => {
  expect(url).toBe(`${window.location.origin}/${resourcePrefix}/${kind}/${basename}`);
  expect(url).not.toBe(`${window.location.origin}/data/${kind}/${basename}`);
  expect(url).not.toMatch(/filePath|output_file|matrix_dir|\/tmp|[A-Za-z]:\\/);
};

const numericValueFromResourceUrl = (url) => {
  const match = /v(\d+)/.exec(url);
  return match ? Number(match[1]) : 0;
};

const createDeferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((promiseResolve, promiseReject) => {
    resolve = promiseResolve;
    reject = promiseReject;
  });
  return { promise, resolve, reject };
};

const getPlotTransferError = () => document.getElementById("plot-transfer-error");

const expectPlotTransferError = ({ heading, body }) => {
  const overlay = getPlotTransferError();
  expect(overlay).toBeTruthy();
  expect(overlay.getAttribute("role")).toBe("alert");
  expect(overlay.getAttribute("aria-live")).toBe("assertive");
  expect(overlay.textContent).toContain(heading);
  expect(overlay.textContent).toContain(body);
};

describe("browser message handlers", () => {
  beforeAll(async () => {
    console.profile = console.profile || vi.fn();
    console.profileEnd = console.profileEnd || vi.fn();
    globalThis.ResizeObserver = class {
      observe() {}
      disconnect() {}
      unobserve() {}
    };
    buildDom();
    installShiny();
    await loadIndex();
  });

  beforeEach(() => {
    testState.inputs = [];
    testState.spinners = {};
    buildDom();
    resetReglInstance();
    document.dispatchEvent(new Event("DOMContentLoaded"));
  });

  it("clears chosen categories when grouping fields change", () => {
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });

    selectValues("renameCluster-chosenGroup", ["A"]);
    expect(testState.reglInstance.plotData.selectedCells).toEqual(["c1", "c2"]);
    expect(testState.reglInstance.selectionSource).toBe("category");

    setCategoryMeta("clusterB", { A: [2], C: [0, 1] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterB",
      split_by: "None",
      moduleScore: null,
    });

    expect(document.getElementById("renameCluster-chosenGroup").selectedOptions).toHaveLength(0);
    expect(testState.reglInstance.plotData.selectedCells).toEqual([]);
    expect(testState.reglInstance.selectionSource).toBe(null);
  });

  it("keeps category selection cleared after assigning metadata", () => {
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });

    selectValues("renameCluster-chosenGroup", ["A"]);
    expect(testState.reglInstance.plotData.selectedCells).toEqual(["c1", "c2"]);

    testState.handlers.addNewMeta({
      colName: "renamed",
      colValue: "selected",
    });

    expect(document.getElementById("renameCluster-chosenGroup").selectedOptions).toHaveLength(0);
    expect(testState.reglInstance.plotData.selectedCells).toEqual([]);
    expect(testState.reglInstance.selectionSource).toBe(null);
    expect(testState.reglInstance.origData.cellMetaData.renamed.value).toEqual({
      selected: [0, 1],
      unknown: [2],
    });
  });

  it("renders and selects prototype-named category levels", () => {
    const categoryMap = Object.create(null);
    categoryMap["__proto__"] = [0];
    categoryMap.constructor = [1];
    categoryMap.prototype = [2];
    setCategoryMeta("clusterA", categoryMap);
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });

    expect([...document.getElementById("renameCluster-chosenGroup").options]
      .map((option) => option.value)).toEqual([
      "__proto__",
      "constructor",
      "prototype",
    ]);

    selectValues("renameCluster-chosenGroup", ["__proto__"]);
    expect(testState.reglInstance.plotData.selectedCells).toEqual(["c1"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      category: { groupLevels: ["__proto__"] },
    });

    selectValues("renameCluster-chosenGroup", ["constructor"]);
    expect(testState.reglInstance.plotData.selectedCells).toEqual(["c2"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      category: { groupLevels: ["constructor"] },
    });

    selectValues("renameCluster-chosenGroup", ["prototype"]);
    expect(testState.reglInstance.plotData.selectedCells).toEqual(["c3"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      category: { groupLevels: ["prototype"] },
    });
  });

  it("keeps prototype-named labels in legacy assignment category buckets", () => {
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });
    testState.reglInstance.setSelectedCells(["c1", "c2", "c3"], { source: "lasso" });

    testState.handlers.addNewMeta({
      colName: "renamed",
      colValue: "__proto__",
    });

    const firstCategoryMap = testState.reglInstance.origData.cellMetaData.renamed.value;
    expect(Object.getPrototypeOf(firstCategoryMap)).toBeNull();
    expect(Object.keys(firstCategoryMap)).toEqual(["__proto__"]);
    expect(firstCategoryMap["__proto__"]).toEqual([0, 1, 2]);

    testState.reglInstance.setSelectedCells(["c1"], { source: "lasso" });
    testState.handlers.addNewMeta({
      colName: "renamed",
      colValue: "constructor",
    });

    const categoryMap = testState.reglInstance.origData.cellMetaData.renamed.value;
    expect(Object.getPrototypeOf(categoryMap)).toBeNull();
    expect(Object.keys(categoryMap)).toEqual(["constructor", "__proto__"]);
    expect(categoryMap.constructor).toEqual([0]);
    expect(categoryMap["__proto__"]).toEqual([1, 2]);

    testState.reglInstance.setSelectedCells(["c2"], { source: "lasso" });
    testState.handlers.addNewMeta({
      colName: "renamed",
      colValue: "prototype",
    });

    const finalCategoryMap = testState.reglInstance.origData.cellMetaData.renamed.value;
    expect(Object.getPrototypeOf(finalCategoryMap)).toBeNull();
    expect(Object.keys(finalCategoryMap)).toEqual([
      "constructor",
      "prototype",
      "__proto__",
    ]);
    expect(finalCategoryMap.constructor).toEqual([0]);
    expect(finalCategoryMap.prototype).toEqual([1]);
    expect(finalCategoryMap["__proto__"]).toEqual([2]);
    expect(Object.prototype.polluted).toBeUndefined();
  });

  it("sends a versioned lasso selection payload and bounded assignment intent", () => {
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    setCategoryMeta("batch", { batch1: [0, 2], batch2: [1] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "batch",
      moduleScore: null,
      analysisVersion: 17,
      analysisLineageId: 4,
    });

    selectValues("renameCluster-chosenGroup", ["A"]);
    selectValues("renameCluster-chosenSplit", ["batch1"]);
    expect(testState.reglInstance.plotData.selectedCells).toEqual(["c1"]);

    testState.reglInstance.setSelectedCells(["c2", "c3"], { source: "lasso" });
    testState.reglInstance.selectionHandlers.onSelect({ selectedCells: ["c2", "c3"] });
    setAssignmentInputs({ colName: "safe_assignment", value: "manual selection" });
    clickAssign();

    expect(latestInputValue("renameCluster-selectedCellsPayload")).toMatchObject({
      cells: ["c2", "c3"],
      metaVersion: null,
      analysisVersion: 17,
      analysisLineageId: 4,
    });
    expect(latestInputValue("renameCluster-categorySelectionContext")).toBeNull();

    expect(latestInputValue("renameCluster-assignmentIntent")).toMatchObject({
      type: "selected_cells",
      newMetaCol: "safe_assignment",
      assignAs: "manual selection",
      selectedCells: ["c2", "c3"],
      context: {
        groupBy: "clusterA",
        splitBy: "batch",
      },
    });
    expect(latestInputValue("newMetaColData")).toBeUndefined();
  });

  it("publishes bounded category subset context without derived Cell IDs", () => {
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    setCategoryMeta("batch", { batch1: [0, 2], batch2: [1] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "batch",
      moduleScore: null,
      analysisVersion: 17,
      analysisLineageId: 4,
    });

    selectValues("renameCluster-chosenGroup", ["A"]);
    selectValues("renameCluster-chosenSplit", ["batch1"]);

    expect(testState.reglInstance.plotData.selectedCells).toEqual(["c1"]);
    expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
    expect(latestInputValue("renameCluster-categorySelectionContext")).toEqual({
      context: { groupBy: "clusterA", splitBy: "batch" },
      category: {
        groupBy: "clusterA",
        groupLevels: ["A"],
        splitBy: "batch",
        splitLevels: ["batch1"],
      },
      metaVersion: null,
      analysisVersion: 17,
      analysisLineageId: 4,
      viewFilterVersion: 0,
    });
    expect(latestInputValue("renameCluster-categorySelectionContext")).not.toHaveProperty("cells");
  });

  it("emits one assignment intent for a normal assignment activation", () => {
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });

    testState.reglInstance.setSelectedCells(["c1", "c3"], { source: "lasso" });
    setAssignmentInputs({ colName: "single_activation", value: "manual" });

    clickAssign();

    const assignmentEvents = testState.inputs.filter(
      ([inputName]) => inputName === "renameCluster-assignmentIntent",
    );
    expect(assignmentEvents).toHaveLength(1);
    expect(assignmentEvents[0][1]).toMatchObject({
      type: "selected_cells",
      selectedCells: ["c1", "c3"],
      newMetaCol: "single_activation",
      assignAs: "manual",
    });
  });

  it("reconciles a lasso selection to the visible View without changing Analysis identity", () => {
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["c1", "c2", "c3"] },
      clusterA: { type: "category", value: { A: [0, 1], B: [2] } },
      nFeature_RNA: { type: "number", value: [100, 250, 400] },
      percent_mt: { type: "number", value: [5, 10, 20] },
    };
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
      analysisVersion: 17,
      analysisLineageId: 4,
      viewFilterVersion: 0,
    });
    const originalAnalysisVersion = testState.reglInstance.plotMetaData.analysisVersion;
    testState.reglInstance.setSelectedCells(["c1", "c2"], { source: "lasso" });
    testState.reglInstance.selectionHandlers.onSelect({ selectedCells: ["c1", "c2"] });

    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
      analysisVersion: 17,
      analysisLineageId: 4,
      viewFilterVersion: 1,
      viewFilterOnly: true,
      viewFilter: {
        nFeature: { column: "nFeature_RNA", min: 150, max: 350 },
        percentMt: { column: "percent_mt", max: 15 },
      },
    });

    expect(testState.reglInstance.plotData.cells[0]).toEqual(["c2"]);
    expect(testState.reglInstance.plotData.selectedCells).toEqual(["c2"]);
    expect(testState.reglInstance.plotMetaData.analysisVersion).toBe(originalAnalysisVersion);
    expect(latestInputValue("renameCluster-selectedCellsPayload")).toMatchObject({
      cells: ["c2"],
      analysisVersion: 17,
      analysisLineageId: 4,
      viewFilterVersion: 1,
    });
  });

  it("sends bounded category assignment intent only for the current group and split context", () => {
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    setCategoryMeta("batch", { batch1: [0, 2], batch2: [1] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "batch",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["A"]);
    selectValues("renameCluster-chosenSplit", ["batch1"]);
    setAssignmentInputs({ colName: "safe_assignment", value: "category selection" });

    clickAssign();

    expect(latestInputValue("renameCluster-assignmentIntent")).toMatchObject({
      type: "category_context",
      newMetaCol: "safe_assignment",
      assignAs: "category selection",
      context: {
        groupBy: "clusterA",
        splitBy: "batch",
      },
      category: {
        groupBy: "clusterA",
        groupLevels: ["A"],
        splitBy: "batch",
        splitLevels: ["batch1"],
      },
    });
    expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
    expect(latestInputValue("newMetaColData")).toBeUndefined();
  });

  it("clears rename selection payloads on split changes, patch invalidation, assignment completion, and deselect", async () => {
    const arrowReader = await resetArrowReaderMocks();
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    setCategoryMeta("batchA", { batch1: [0, 2], batch2: [1] });
    arrowReader.readArrowIPC.mockResolvedValue({ table: "baseline-meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue(
      testState.reglInstance.origData.cellMetaData,
    );
    testState.handlers.meta_ready({
      metaFile: "baseline-meta-ipc",
      metaVersion: 0,
    });
    await vi.waitFor(() => {
      expect(latestInputValue("metaProcessed")).toBe(true);
    });

    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "batchA",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["A"]);
    selectValues("renameCluster-chosenSplit", ["batch1"]);
    setAssignmentInputs({ colName: "safe_assignment", value: "category selection" });
    clickAssign();
    expect(latestInputValue("renameCluster-assignmentIntent")).toBeTruthy();

    setCategoryMeta("batchB", { other1: [0, 1], other2: [2] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "batchB",
      moduleScore: null,
    });
    expect(document.getElementById("renameCluster-chosenGroup").selectedOptions).toHaveLength(0);
    expect(document.getElementById("renameCluster-chosenSplit").selectedOptions).toHaveLength(0);
    expect(testState.reglInstance.plotData.selectedCells).toEqual([]);
    expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
    expect(latestInputValue("renameCluster-assignmentIntent")).toBeNull();

    selectValues("renameCluster-chosenGroup", ["A"]);
    selectValues("renameCluster-chosenSplit", ["other1"]);
    arrowReader.readArrowIPC.mockResolvedValue({ table: "patch" });
    arrowReader.parseMetaFromArrow.mockReturnValue({
      cells: { type: "cell_id", value: ["c1", "c2", "c3"] },
      clusterA: { type: "category", value: { C: [0, 1], D: [2] } },
    });
    testState.handlers.meta_patch_ready({
      metaFile: "cluster-patch-ipc",
      metaVersion: 1,
      cols: ["clusterA"],
    });
    await vi.waitFor(() => {
      expect(document.getElementById("renameCluster-chosenGroup").selectedOptions).toHaveLength(0);
      expect(testState.reglInstance.plotData.selectedCells).toEqual([]);
      expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
      expect(latestInputValue("renameCluster-categorySelectionContext")).toBeNull();
      expect(latestInputValue("renameCluster-assignmentIntent")).toBeNull();
    });

    testState.reglInstance.setSelectedCells(["c1"], { source: "lasso" });
    testState.reglInstance.selectionHandlers.onSelect({ selectedCells: ["c1"] });
    setAssignmentInputs({ colName: "safe_assignment", value: "manual selection" });
    clickAssign();
    expect(latestInputValue("renameCluster-selectedCellsPayload")).toMatchObject({
      cells: ["c1"],
      metaVersion: 1,
    });

    arrowReader.readArrowIPC.mockResolvedValue({ table: "assignment-patch" });
    arrowReader.parseMetaFromArrow.mockReturnValue({
      cells: { type: "cell_id", value: ["c1", "c2", "c3"] },
      safe_assignment: { type: "category", value: { "manual selection": [0], unknown: [1, 2] } },
    });
    testState.handlers.meta_patch_ready({
      metaFile: "assignment-patch-ipc",
      metaVersion: 2,
      cols: ["safe_assignment"],
    });

    await vi.waitFor(() => {
      expect(testState.reglInstance.plotData.selectedCells).toEqual([]);
      expect(testState.reglInstance.selectionSource).toBe(null);
      expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
      expect(latestInputValue("renameCluster-categorySelectionContext")).toBeNull();
      expect(latestInputValue("renameCluster-assignmentIntent")).toBeNull();
    });

    testState.reglInstance.setSelectedCells(["c2"], { source: "lasso" });
    testState.reglInstance.selectionHandlers.onSelect({ selectedCells: ["c2"] });
    clickAssign();
    testState.handlers.reglScatter_deselect({});
    expect(testState.reglInstance.plotData.selectedCells).toEqual([]);
    expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
    expect(latestInputValue("renameCluster-assignmentIntent")).toBeNull();
  });

  it("clears subset-stale browser state on full object replacement", async () => {
    const arrowReader = await resetArrowReaderMocks();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["c1", "c2", "c3"] },
      clusterA: { type: "category", value: { A: [0, 1], B: [2] } },
    };
    testState.reglInstance.origData.expressionData = {
      GeneA: new Float32Array([1, 2, 3]),
    };
    testState.reglInstance.plotData.selectedCells = ["c1", "c3"];
    testState.reglInstance.selectionSource = "lasso";
    testState.reglInstance.plotMetaData.selectedFeatures = ["GeneA"];
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["A"]);
    setAssignmentInputs({ colName: "safe_assignment", value: "selected" });
    clickAssign();
    expect(latestInputValue("renameCluster-assignmentIntent")).toBeTruthy();

    arrowReader.readArrowIPC.mockResolvedValue({ table: "subset-meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue({
      cells: { type: "cell_id", value: ["c2", "c4"] },
      clusterB: { type: "category", value: { C: [0], D: [1] } },
    });

    testState.handlers.meta_ready({ metaFile: "subset-meta-ipc", metaVersion: 2 });

    await vi.waitFor(() => {
      expect(testState.reglInstance.plotData.selectedCells).toEqual([]);
      expect(testState.reglInstance.selectionSource).toBeNull();
      expect(document.getElementById("renameCluster-chosenGroup").selectedOptions).toHaveLength(0);
      expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
      expect(latestInputValue("renameCluster-categorySelectionContext")).toBeNull();
      expect(latestInputValue("renameCluster-assignmentIntent")).toBeNull();
      expect(testState.reglInstance.origData.expressionData).toEqual({});
      expect(testState.reglInstance.plotMetaData.selectedFeatures).toEqual([]);
      expect(latestInputValue("inputFeatures-cachedExprKeys")).toEqual([]);
    });
  });

  it("clears lasso selection after an object replacement", async () => {
    const arrowReader = await resetArrowReaderMocks();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["c1", "c2", "c3"] },
      clusterA: { type: "category", value: { A: [0, 1], B: [2] } },
    };
    testState.reglInstance.setSelectedCells(["c1", "c2", "c3"], { source: "lasso" });
    arrowReader.readArrowIPC.mockResolvedValue({ table: "restore-meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue({
      cells: { type: "cell_id", value: ["c2", "c4"] },
      clusterA: { type: "category", value: { A: [0], C: [1] } },
    });

    testState.handlers.meta_ready({ metaFile: "restore-meta-ipc", metaVersion: 3 });

    await vi.waitFor(() => {
      expect(testState.reglInstance.plotData.selectedCells).toEqual([]);
      expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
      expect(latestInputValue("renameCluster-categorySelectionContext")).toBeNull();
      expect(latestInputValue("renameCluster-assignmentIntent")).toBeNull();
    });
  });

  it("clears server selection transport when a replacement keeps the same Cell IDs", () => {
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });
    testState.reglInstance.setSelectedCells(["c1", "c3"], { source: "lasso" });

    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });

    expect(testState.reglInstance.plotData.selectedCells).toEqual([]);
    expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
    expect(latestInputValue("renameCluster-categorySelectionContext")).toBeNull();
    expect(document.getElementById("renameCluster-chosenGroup").selectedOptions).toHaveLength(0);
  });

  it("keeps existing transfer_error and stale gates unchanged during subset refreshes", async () => {
    const arrowReader = await resetArrowReaderMocks();
    arrowReader.readArrowIPC.mockResolvedValue({ table: "current" });
    arrowReader.parseMetaFromArrow.mockReturnValue({
      cells: { type: "cell_id", value: ["c1"] },
    });

    testState.handlers.meta_ready({ metaFile: "meta-v4", metaVersion: 4 });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cells.value).toEqual(["c1"]);
    });

    testState.handlers.transfer_error({
      payloadType: "metadata",
      reasonCode: "write_failed",
      version: 3,
    });

    expect(getPlotTransferError()).toBeNull();
    expect(Object.keys(testState.handlers)).not.toContain("subset_restore_ready");
  });

  it("ignores stale expression errors after object replacement clears expression state", async () => {
    const arrowReader = await resetArrowReaderMocks();
    addFeatureSparkLine("GeneA");
    arrowReader.fetchArrowIPCBuffer.mockResolvedValueOnce(encodeLabelBuffer("gene-a-v12"));
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      label: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockReturnValue(new Float32Array([12]));

    testState.handlers.expr_ready({
      exprFile: "gene-a-v12",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 12,
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.expressionData.GeneA).toBeDefined();
    });

    arrowReader.readArrowIPC.mockResolvedValue({ table: "replacement-meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue({
      cells: { type: "cell_id", value: ["c2"] },
    });
    testState.handlers.meta_ready({ metaFile: "replacement-meta", metaVersion: 4 });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.expressionData).toEqual({});
    });

    testState.handlers.transfer_error({
      payloadType: "expression",
      reasonCode: "write_failed",
      version: 12,
      geneName: "GeneA",
      assay: "RNA",
    });

    expect(getPlotTransferError()).toBeNull();
  });

  it("rejects invalid assignment inputs before sending Shiny assignment intent", () => {
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });
    // Simulate a stale lasso payload that survives outside the renderer.
    testState.reglInstance.selectionSource = "lasso";
    testState.reglInstance.plotData.selectedCells = ["c1", "missing-cell"];
    setAssignmentInputs({ colName: "", value: "manual selection" });

    clickAssign();

    expect(latestInputValue("renameCluster-assignmentIntent")).toBeUndefined();
    expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
    expect(latestInputValue("newMetaColData")).toBeUndefined();

    setAssignmentInputs({ colName: "safe_assignment", value: "" });
    clickAssign();
    expect(latestInputValue("renameCluster-assignmentIntent")).toBeUndefined();
    expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();

    setAssignmentInputs({ colName: "safe_assignment", value: "manual selection" });
    clickAssign();
    expect(latestInputValue("renameCluster-assignmentIntent")).toBeUndefined();
    expect(latestInputValue("renameCluster-selectedCellsPayload")).toBeNull();
  });

  it("prefetches reduction buffers and plots only the selected reduction", async () => {
    const arrowReader = await import("./modules/arrowReader.js");
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) =>
      Promise.resolve(new TextEncoder().encode(url).buffer),
    );
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({ buffer }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const url = new TextDecoder().decode(table.buffer);
      const value = url.includes("umap") ? 1 : 2;
      return new Float32Array([colName === "X" ? value : value + 10]);
    });

    document.getElementById("updateReduction-reduction").innerHTML = `
      <option value="stale" selected>stale</option>
    `;

    await testState.handlers.reductions_ready({
      reductionVersion: 1,
      activeReduction: "umap",
      reductions: [
        { reductionName: "umap", reductionFile: "umap-ipc" },
        { reductionName: "pca", reductionFile: "pca-ipc" },
      ],
    });

    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.reductionData.X).toEqual(
        new Float32Array([1]),
      );
      expect(testState.inputs).toContainEqual([
        "updateReduction-cachedReductionKeys",
        ["1::umap", "1::pca"],
        { priority: "event" },
      ]);
    });
  });

  it("falls back to first prefetched reduction when active reduction is absent", async () => {
    const arrowReader = await import("./modules/arrowReader.js");
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) =>
      Promise.resolve(new TextEncoder().encode(url).buffer),
    );
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({ buffer }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const url = new TextDecoder().decode(table.buffer);
      const value = url.includes("pca") ? 3 : 4;
      return new Float32Array([colName === "X" ? value : value + 10]);
    });
    document.getElementById("updateReduction-reduction").innerHTML = `
      <option value="stale" selected>stale</option>
    `;

    await testState.handlers.reductions_ready({
      reductionVersion: 2,
      activeReduction: "missing",
      reductions: [
        { reductionName: "pca", reductionFile: "pca-ipc" },
        { reductionName: "umap", reductionFile: "umap-ipc" },
      ],
    });

    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.reductionData.X).toEqual(
        new Float32Array([3]),
      );
    });
  });

  it("settles initial plot readiness when reduction loading fails", async () => {
    const arrowReader = await import("./modules/arrowReader.js");
    arrowReader.fetchArrowIPCBuffer.mockRejectedValueOnce(new Error("network failed"));

    testState.handlers.await_initial_plot_ready({});
    testState.handlers.reduction_ready({
      reductionFile: "broken-ipc",
      reductionVersion: 3,
      reductionName: "umap",
    });

    await vi.waitFor(() => {
      expect(testState.inputs).toContainEqual([
        "initialPlotReady",
        expect.any(Number),
        { priority: "event" },
      ]);
      expect(document.getElementById("plot-transfer-error")?.textContent).toMatch(
        /Reduction could not load/,
      );
    });
  });

  it("shows accessible metadata transfer failures and preserves prior scatter state", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const previousReductionData = testState.reglInstance.origData.reductionData;
    arrowReader.readArrowIPC.mockRejectedValueOnce(new Error("fetch /tmp/meta.arrow failed"));

    testState.handlers.await_initial_plot_ready({});
    testState.handlers.meta_ready({ metaFile: "meta-v4", metaVersion: 4 });

    await vi.waitFor(() => {
      expectPlotTransferError({
        heading: "Metadata could not load",
        body: "Could not load metadata for this dataset. Retry transfer, or reload the dataset.",
      });
      expect(testState.spinners["mainClusterPlot-clusterPlot"].style.display).toBe("none");
      expect(testState.reglInstance.origData.reductionData).toBe(previousReductionData);
      expect(latestInputValue("initialPlotReady")).toEqual(expect.any(Number));
    });
  });

  it("shows reduction-specific transfer failures without clearing previous scatter", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const previousReductionData = { X: new Float32Array([99]), Y: new Float32Array([100]) };
    testState.reglInstance.origData.reductionData = previousReductionData;
    arrowReader.fetchArrowIPCBuffer.mockResolvedValueOnce(encodeLabelBuffer("umap-v401"));
    arrowReader.decodeArrowIPC.mockImplementation(() => {
      throw new Error("decode failed");
    });

    testState.handlers.await_initial_plot_ready({});
    testState.handlers.reduction_ready({
      reductionFile: "umap-v5",
      reductionName: "umap",
      reductionVersion: 5,
    });

    await vi.waitFor(() => {
      expectPlotTransferError({
        heading: "Reduction could not load",
        body: "Could not load `umap`. Try switching reductions, retry transfer, or reload the dataset.",
      });
      expect(testState.reglInstance.origData.reductionData).toBe(previousReductionData);
      expect(latestInputValue("initialPlotReady")).toEqual(expect.any(Number));
    });
  });

  it("shows scatter initialization copy when no active batched reduction renders", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const previousReductionData = { X: new Float32Array([42]), Y: new Float32Array([43]) };
    testState.reglInstance.origData.reductionData = previousReductionData;
    arrowReader.fetchArrowIPCBuffer.mockRejectedValueOnce(new Error("network failed"));

    testState.handlers.await_initial_plot_ready({});
    testState.handlers.reductions_ready({
      reductionVersion: 6,
      activeReduction: "umap",
      reductions: [
        { reductionFile: "umap-v6", reductionName: "umap", reductionVersion: 6 },
      ],
    });

    await vi.waitFor(() => {
      expectPlotTransferError({
        heading: "Scatter could not initialize",
        body: "No active reduction finished rendering. Retry transfer, or reload the dataset.",
      });
      expect(testState.reglInstance.origData.reductionData).toBe(previousReductionData);
      expect(latestInputValue("initialPlotReady")).toEqual(expect.any(Number));
    });
  });

  it("ignores stale metadata and reduction results after asynchronous work completes", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const staleMeta = createDeferred();
    const currentMeta = createDeferred();
    const staleReduction = createDeferred();
    const currentReduction = createDeferred();

    arrowReader.readArrowIPC.mockImplementation((url) => {
      if (url.includes("meta-v7")) return staleMeta.promise;
      if (url.includes("meta-v8")) return currentMeta.promise;
      throw new Error(`Unexpected metadata URL ${url}`);
    });
    arrowReader.parseMetaFromArrow.mockImplementation((table) => table);

    testState.handlers.meta_ready({ metaFile: "meta-v7", metaVersion: 7 });
    testState.handlers.meta_ready({ metaFile: "meta-v8", metaVersion: 8 });
    currentMeta.resolve({ cells: { type: "cell_id", value: ["c1", "c2"] } });

    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cells.value).toEqual(["c1", "c2"]);
    });

    staleMeta.resolve({ cells: { type: "cell_id", value: ["stale1", "stale2"] } });
    await Promise.resolve();
    await Promise.resolve();
    expect(testState.reglInstance.origData.cellMetaData.cells.value).toEqual(["c1", "c2"]);

    arrowReader.readArrowIPC.mockReset();
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) => {
      if (url.includes("umap-v9")) return staleReduction.promise;
      if (url.includes("pca-v10")) return currentReduction.promise;
      throw new Error(`Unexpected reduction URL ${url}`);
    });
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      label: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = table.label.includes("stale") ? 405 : 406;
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });

    testState.handlers.reduction_ready({
      reductionFile: "umap-v9",
      reductionName: "umap",
      reductionVersion: 9,
    });
    testState.handlers.reduction_ready({
      reductionFile: "pca-v10",
      reductionName: "pca",
      reductionVersion: 10,
    });
    currentReduction.resolve(encodeLabelBuffer("current"));

    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([406]);
    });

    staleReduction.resolve(encodeLabelBuffer("stale"));
    await Promise.resolve();
    await Promise.resolve();
    expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([406]);
  });

  it("routes PCA failures to the ElbowPlot status without settling main scatter readiness", async () => {
    const arrowReader = await resetArrowReaderMocks();
    arrowReader.readArrowIPC.mockRejectedValueOnce(new Error("pca /tmp/stdev.arrow failed"));

    testState.handlers.pca_ready({ stdevFile: "pca-v11", reductionVersion: 11 });

    await vi.waitFor(() => {
      expect(document.getElementById("floatingElbowPlotStatus").textContent).toContain(
        "PCA summary unavailable",
      );
    });
    expect(testState.inputs.filter(([name]) => name === "initialPlotReady")).toHaveLength(0);

    testState.handlers.transfer_error({
      payloadType: "pca",
      reasonCode: "write_failed",
      version: 12,
    });
    expect(document.getElementById("floatingElbowPlotStatus").textContent).toContain(
      "PCA summary unavailable",
    );
    expect(getPlotTransferError()).toBeNull();
  });

  it("ignores stale initial plot failures after a newer render wait starts", async () => {
    const arrowReader = await import("./modules/arrowReader.js");
    arrowReader.fetchArrowIPCBuffer.mockRejectedValueOnce(new Error("stale failure"));

    testState.handlers.await_initial_plot_ready({});
    testState.handlers.reduction_ready({
      reductionFile: "broken-ipc",
      reductionVersion: 1,
      reductionName: "umap",
    });
    testState.handlers.await_initial_plot_ready({});

    await Promise.resolve();
    await Promise.resolve();
    expect(
      testState.inputs.filter(([name]) => name === "initialPlotReady"),
    ).toHaveLength(0);

    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });

    expect(
      testState.inputs.filter(([name]) => name === "initialPlotReady"),
    ).toHaveLength(1);
  });

  it("restores previous plot DOM when plot generation fails", () => {
    const mainPlot = document.getElementById("mainClusterPlot-clusterPlot");
    const legendBody = document.querySelector(
      '.accordion-item[data-value="analysis_category"] .accordion-body',
    );
    const currentInstance = testState.reglInstance;
    const previousPlotEl = testState.reglInstance.plotEl;
    const previousCatLegendEl = testState.reglInstance.catLegendEl;
    const previousExpLegendEl = testState.reglInstance.expLegendEl;

    mainPlot.appendChild(previousPlotEl);
    legendBody.appendChild(previousCatLegendEl);
    legendBody.appendChild(previousExpLegendEl);
    const replacement = currentInstance.createRenderReplacement();
    replacement.generatePlotEl = vi.fn(() => {
      throw new Error("render failed");
    });
    currentInstance.createRenderReplacement = vi.fn(() => replacement);

    testState.handlers.await_initial_plot_ready({});
    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });

    expect(mainPlot.contains(previousPlotEl)).toBe(true);
    expect(legendBody.contains(previousCatLegendEl)).toBe(true);
    expect(legendBody.contains(previousExpLegendEl)).toBe(true);
    testState.reglInstance = currentInstance;
  });

  it("does not destroy previous plot before late render setup completes", () => {
    const mainPlot = document.getElementById("mainClusterPlot-clusterPlot");
    const legendBody = document.querySelector(
      '.accordion-item[data-value="analysis_category"] .accordion-body',
    );
    const currentInstance = testState.reglInstance;
    const previousPlotEl = testState.reglInstance.plotEl;
    const previousCatLegendEl = testState.reglInstance.catLegendEl;
    const previousExpLegendEl = testState.reglInstance.expLegendEl;

    mainPlot.appendChild(previousPlotEl);
    legendBody.appendChild(previousCatLegendEl);
    legendBody.appendChild(previousExpLegendEl);
    const replacement = currentInstance.createRenderReplacement();
    replacement.setSelectionHandlers = vi.fn(() => {
      throw new Error("late setup failed");
    });
    currentInstance.createRenderReplacement = vi.fn(() => replacement);
    currentInstance.destroy = vi.fn();

    testState.handlers.reglScatter_plot({
      group_by: "clusterA",
      split_by: "None",
      moduleScore: null,
    });

    expect(currentInstance.destroy).not.toHaveBeenCalled();
    expect(mainPlot.contains(previousPlotEl)).toBe(true);
    expect(legendBody.contains(previousCatLegendEl)).toBe(true);
    expect(legendBody.contains(previousExpLegendEl)).toBe(true);
    testState.reglInstance = currentInstance;
  });

  it("enables DotPlot and FeaturePlot actions after selected genes change", () => {
    setCategoryMeta("clusterA", { A: [0, 1], B: [2] });
    testState.reglInstance.plotMetaData.group_by = "clusterA";

    const dotAction = document.getElementById("floatingDotPlotAction");
    const featureAction = document.getElementById("floatingFeaturePlotAction");
    dotAction.disabled = true;
    featureAction.disabled = true;

    testState.reglInstance.plotMetaData.selectedFeatures = ["GeneA", "GeneB"];
    window.dispatchEvent(new CustomEvent("scspotlight:featurePlotSelectionChanged"));

    expect(dotAction.disabled).toBe(false);
    expect(featureAction.disabled).toBe(false);
    expect(document.getElementById("floatingDotPlotStatus").textContent).toContain(
      "GeneA, GeneB",
    );
    expect(document.getElementById("floatingFeaturePlotStatus").textContent).toContain(
      "GeneA, GeneB",
    );
  });

  it("registers custom message handlers for every browser payload contract", () => {
    expect(Object.keys(payloadContracts.messages)).toEqual(browserContractMessageNames);
    browserContractMessageNames.forEach((messageName) => {
      expect(testState.handlers[messageName]).toEqual(expect.any(Function));
    });
  });

  it("meta_ready fetches metaFile metadata and reports metaProcessed", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const parsedMeta = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { alpha: [0, 2], beta: [1] } },
      nCount: { type: "number", value: new Float32Array([1, 2, 3]) },
    };
    arrowReader.readArrowIPC.mockResolvedValue({ table: "meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue(parsedMeta);

    testState.handlers.meta_ready({ metaFile: "meta-ipc", metaVersion: 100 });

    await vi.waitFor(() => {
      expectResourceUrl(arrowReader.readArrowIPC.mock.calls[0][0], "meta", "meta-ipc");
      expect(arrowReader.parseMetaFromArrow).toHaveBeenCalledWith({ table: "meta" });
      expect(testState.reglInstance.origData.cellMetaData).toBe(parsedMeta);
      expect(latestInputValue("metaProcessed")).toBe(true);
    });
  });

  it("meta_ready builds fetch URLs from the session resourcePrefix", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const parsedMeta = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { alpha: [0, 2], beta: [1] } },
    };
    arrowReader.readArrowIPC.mockResolvedValue({ table: "prefixed-meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue(parsedMeta);

    testState.handlers.meta_ready({
      resourcePrefix: "data-session-abc123",
      metaFile: "meta-ipc",
      metaVersion: 100,
    });

    await vi.waitFor(() => {
      expectSessionResourceUrl(
        arrowReader.readArrowIPC.mock.calls[0][0],
        "data-session-abc123",
        "meta",
        "meta-ipc",
      );
      expect(testState.reglInstance.origData.cellMetaData).toBe(parsedMeta);
      expect(latestInputValue("metaProcessed")).toBe(true);
    });
  });

  it("keeps valid full metadata current after a malformed newer notification", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const validRead = createDeferred();
    const parsedMeta = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      batch: { type: "category", value: { A: [0], B: [1, 2] } },
    };
    arrowReader.readArrowIPC.mockImplementation((url) => {
      if (url.includes("valid-meta-ipc")) return validRead.promise;
      throw new Error(`Unexpected metadata URL ${url}`);
    });
    arrowReader.parseMetaFromArrow.mockReturnValue(parsedMeta);

    testState.handlers.await_initial_plot_ready({});
    testState.handlers.meta_ready({
      metaFile: "valid-meta-ipc",
      metaVersion: 100,
    });
    testState.handlers.meta_ready({
      metaFile: "malformed-meta-ipc",
      metaVersion: 9999,
      cellIdentity: null,
    });

    expect(arrowReader.readArrowIPC).toHaveBeenCalledTimes(1);
    expect(getPlotTransferError().textContent).toContain("Metadata could not load");
    expect(testState.spinners["mainClusterPlot-clusterPlot"].style.display).toBe("flex");
    expect(
      testState.inputs.filter(([name]) => name === "initialPlotReady"),
    ).toHaveLength(0);

    validRead.resolve({ table: "valid-meta" });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData).toBe(parsedMeta);
      expect(latestInputValue("metaProcessed")).toBe(true);
    });
    expect(
      testState.inputs.filter(([name]) => name === "initialPlotReady"),
    ).toHaveLength(0);

    testState.handlers.reglScatter_plot({
      group_by: "batch",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["A"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      metaVersion: 100,
    });
    expect(
      testState.inputs.filter(([name]) => name === "initialPlotReady"),
    ).toHaveLength(1);
  });

  it("meta_patch_ready fetches patch metadata and reports changed cols", async () => {
    const arrowReader = await resetArrowReaderMocks();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { old: [0, 1, 2] } },
      batch: { type: "category", value: { A: [0], B: [1, 2] } },
    };
    testState.reglInstance.plotMetaData.group_by = "cluster";
    const parsedPatch = {
      cluster: { type: "category", value: { alpha: [0, 2], beta: [1] } },
    };
    arrowReader.readArrowIPC.mockResolvedValue({ table: "patch" });
    arrowReader.parseMetaFromArrow.mockReturnValue(parsedPatch);

    testState.handlers.meta_patch_ready({
      metaFile: "meta-patch-ipc",
      metaVersion: 101,
      cols: ["cluster"],
    });

    await vi.waitFor(() => {
      expectResourceUrl(
        arrowReader.readArrowIPC.mock.calls[0][0],
        "meta",
        "meta-patch-ipc",
      );
      expect(testState.reglInstance.origData.cellMetaData.cluster).toBe(
        parsedPatch.cluster,
      );
      expect(testState.reglInstance.origData.cellMetaData.batch).toBeDefined();
      expect(latestInputValue("metaPatchProcessed")).toEqual({
        cols: ["cluster"],
        refreshMainPlot: true,
        timestamp: expect.any(Number),
      });
    });
  });

  it("meta_patch_ready applies only scoped columns and skips main scatter refresh for unrelated cols", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const existingCluster = { type: "category", value: { old: [0, 1, 2] } };
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: existingCluster,
      batch: { type: "category", value: { A: [0], B: [1, 2] } },
      score: { type: "number", value: new Float32Array([1, 2, 3]) },
    };
    testState.reglInstance.plotMetaData.group_by = "cluster";
    testState.reglInstance.plotMetaData.selectedMeta = "meta:score";
    arrowReader.readArrowIPC.mockResolvedValue({ table: "baseline-meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue(
      testState.reglInstance.origData.cellMetaData,
    );
    testState.handlers.meta_ready({
      metaFile: "baseline-meta-ipc",
      metaVersion: 409,
    });
    await vi.waitFor(() => {
      expect(latestInputValue("metaProcessed")).toBe(true);
    });
    testState.inputs = [];

    const parsedPatch = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { stale: [0, 1, 2] } },
      batch: { type: "category", value: { A: [0, 2], B: [1] } },
    };
    arrowReader.readArrowIPC.mockResolvedValue({ table: "patch" });
    arrowReader.parseMetaFromArrow.mockReturnValue(parsedPatch);

    testState.handlers.meta_patch_ready({
      metaFile: "meta-patch-batch-ipc",
      metaVersion: 410,
      cols: ["batch"],
    });

    await vi.waitFor(() => {
      expect(testState.reglInstance.updateCellMetaDataPatchCalls).toHaveLength(1);
      expect(Object.keys(testState.reglInstance.updateCellMetaDataPatchCalls[0])).toEqual([
        "batch",
      ]);
      expect(testState.reglInstance.origData.cellMetaData.batch).toBe(parsedPatch.batch);
      expect(testState.reglInstance.origData.cellMetaData.cluster).toBe(existingCluster);
      expect(latestInputValue("metaPatchProcessed")).toEqual({
        cols: ["batch"],
        refreshMainPlot: false,
        timestamp: expect.any(Number),
      });
      expect(latestInputValue("metaProcessed")).toBeUndefined();
    });
  });

  it("meta_patch_ready rejects malformed patches before mutating metadata", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const existingBatch = { type: "category", value: { A: [0], B: [1, 2] } };
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      batch: existingBatch,
    };
    arrowReader.readArrowIPC.mockResolvedValue({ table: "bad-patch" });
    arrowReader.parseMetaFromArrow.mockReturnValue({
      batch: { type: "category", value: { A: [0], B: [1] } },
    });

    testState.handlers.meta_patch_ready({
      metaFile: "bad-meta-patch-ipc",
      metaVersion: 411,
      cols: ["batch"],
    });

    await vi.waitFor(() => {
      expect(testState.reglInstance.updateCellMetaDataPatchCalls).toHaveLength(0);
      expect(testState.reglInstance.origData.cellMetaData.batch).toBe(existingBatch);
      const overlay = getPlotTransferError();
      expect(overlay).toBeTruthy();
      expect(overlay.textContent).toContain("Metadata update could not apply");
      expect(overlay.textContent).toContain("batch");
      expect(overlay.textContent).toContain("Existing metadata is still shown");
      expect(latestInputValue("metaPatchProcessed")).toBeUndefined();
    });

    testState.handlers.reglScatter_plot({
      group_by: "batch",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["A"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      metaVersion: 410,
    });
  });

  it("meta_patch_ready rejects a compact identity for the wrong Analysis order", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const existingBatch = { type: "category", value: { A: [0], B: [1, 2] } };
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      batch: existingBatch,
    };
    arrowReader.readArrowIPC.mockResolvedValue({ table: "current-meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue(
      testState.reglInstance.origData.cellMetaData,
    );
    testState.handlers.meta_ready({
      metaFile: "current-meta-ipc",
      metaVersion: 412,
    });
    await vi.waitFor(() => {
      expect(latestInputValue("metaProcessed")).toBe(true);
    });
    arrowReader.readArrowIPC.mockClear();

    testState.handlers.meta_patch_ready({
      metaFile: "reordered-meta-patch-ipc",
      metaVersion: 9999,
      cols: ["batch"],
      cellIdentity: "ffffffffffffffffffffffffffffffff",
    });

    await Promise.resolve();
    expect(arrowReader.readArrowIPC).not.toHaveBeenCalled();
    expect(testState.reglInstance.updateCellMetaDataPatchCalls).toHaveLength(0);
    expect(testState.reglInstance.origData.cellMetaData.batch).toBe(existingBatch);
    expect(getPlotTransferError().textContent).toContain("Metadata update could not apply");

    testState.handlers.reglScatter_plot({
      group_by: "batch",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["A"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      metaVersion: 412,
    });
  });

  it("defers a newer compact patch until its full metadata identity commits", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const fullRead = createDeferred();
    const nextCellIdentity = "11111111111111111111111111111111";
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      batch: { type: "category", value: { old: [0, 1, 2] } },
    };
    arrowReader.readArrowIPC.mockImplementation((url) => {
      if (url.includes("replacement-meta")) return fullRead.promise;
      if (url.includes("deferred-meta-patch")) return Promise.resolve({ kind: "patch" });
      throw new Error(`Unexpected metadata URL ${url}`);
    });
    arrowReader.parseMetaFromArrow.mockImplementation((table) => (
      table.kind === "full"
        ? {
          cells: { type: "cell_id", value: ["New1", "New2", "New3"] },
          batch: { type: "category", value: { full: [0, 1, 2] } },
        }
        : { batch: { type: "category", value: { patched: [0, 1, 2] } } }
    ));

    testState.handlers.meta_ready({
      metaFile: "replacement-meta-ipc",
      metaVersion: 413,
      cellIdentity: nextCellIdentity,
    });
    testState.handlers.meta_patch_ready({
      metaFile: "deferred-meta-patch-ipc",
      metaVersion: 414,
      cols: ["batch"],
      cellIdentity: nextCellIdentity,
    });

    await Promise.resolve();
    expect(arrowReader.readArrowIPC).toHaveBeenCalledTimes(1);

    fullRead.resolve({ kind: "full" });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cells.value).toEqual([
        "New1", "New2", "New3",
      ]);
      expect(testState.reglInstance.origData.cellMetaData.batch.value).toEqual({
        patched: [0, 1, 2],
      });
    });

    expect(arrowReader.readArrowIPC).toHaveBeenCalledTimes(2);
    expect(testState.reglInstance.plotMetaData.cellIdentity).toBe(nextCellIdentity);
    expect(testState.reglInstance.updateCellMetaDataPatchCalls).toHaveLength(1);
    expect(latestInputValue("metaProcessed")).toBe(true);
    expect(latestInputValue("metaPatchProcessed")).toEqual({
      cols: ["batch"],
      refreshMainPlot: false,
      timestamp: expect.any(Number),
    });
    expect(getPlotTransferError()).toBeNull();
  });

  it("keeps a full metadata transfer current after a newer patch write fails", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const fullRead = createDeferred();
    const nextCellIdentity = "22222222222222222222222222222222";
    arrowReader.readArrowIPC.mockReturnValue(fullRead.promise);
    arrowReader.parseMetaFromArrow.mockReturnValue({
      cells: { type: "cell_id", value: ["Next1", "Next2", "Next3"] },
      batch: { type: "category", value: { full: [0, 1, 2] } },
    });

    testState.handlers.meta_ready({
      metaFile: "full-after-patch-error-ipc",
      metaVersion: 415,
      cellIdentity: nextCellIdentity,
    });
    testState.handlers.transfer_error({
      payloadType: "metadata_patch",
      reasonCode: "write_failed",
      version: 416,
      cols: ["batch"],
    });
    fullRead.resolve({ kind: "full" });

    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cells.value).toEqual([
        "Next1", "Next2", "Next3",
      ]);
    });
    expect(testState.reglInstance.plotMetaData.cellIdentity).toBe(nextCellIdentity);
    expect(latestInputValue("metaProcessed")).toBe(true);
    expect(getPlotTransferError()).toBeNull();

    testState.handlers.reglScatter_plot({
      group_by: "batch",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["full"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      metaVersion: 415,
    });
  });

  it("replays a newer applied patch after an older same-identity full snapshot", async () => {
    const arrowReader = await resetArrowReaderMocks();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      batch: { type: "category", value: { old: [0, 1, 2] } },
    };
    arrowReader.readArrowIPC.mockImplementation((url) => (
      Promise.resolve({ kind: url.includes("meta-patch") ? "patch" : "full" })
    ));
    arrowReader.parseMetaFromArrow.mockImplementation((table) => (
      table.kind === "patch"
        ? { batch: { type: "category", value: { patched: [0, 1, 2] } } }
        : {
          cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
          cluster: { type: "category", value: { refreshed: [0, 1, 2] } },
          batch: { type: "category", value: { full: [0, 1, 2] } },
        }
    ));

    testState.handlers.meta_patch_ready({
      metaFile: "same-identity-meta-patch-ipc",
      metaVersion: 418,
      cols: ["batch"],
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.batch.value).toEqual({
        patched: [0, 1, 2],
      });
    });

    testState.handlers.meta_ready({
      metaFile: "older-same-identity-full-ipc",
      metaVersion: 417,
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
        refreshed: [0, 1, 2],
      });
      expect(testState.reglInstance.origData.cellMetaData.batch.value).toEqual({
        patched: [0, 1, 2],
      });
    });

    expect(testState.reglInstance.updateCellMetaDataPatchCalls).toHaveLength(2);
    expect(getPlotTransferError()).toBeNull();
  });

  it("delayed stale meta_patch_ready results are ignored after fetch", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const staleRead = createDeferred();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { old: [0, 1, 2] } },
    };
    testState.reglInstance.plotMetaData.group_by = "cluster";
    arrowReader.readArrowIPC.mockResolvedValue({ table: "baseline-meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue(
      testState.reglInstance.origData.cellMetaData,
    );
    testState.handlers.meta_ready({
      metaFile: "baseline-meta-ipc",
      metaVersion: 419,
    });
    await vi.waitFor(() => {
      expect(latestInputValue("metaProcessed")).toBe(true);
    });

    arrowReader.readArrowIPC
      .mockImplementationOnce(() => staleRead.promise)
      .mockResolvedValueOnce({ table: "current" });
    arrowReader.parseMetaFromArrow.mockImplementation((table) => ({
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: {
        type: "category",
        value: table.table === "current" ? { current: [0, 1, 2] } : { stale: [0, 1, 2] },
      },
    }));

    testState.handlers.meta_patch_ready({
      metaFile: "stale-meta-patch-ipc",
      metaVersion: 420,
      cols: ["cluster"],
    });
    testState.handlers.meta_patch_ready({
      metaFile: "current-meta-patch-ipc",
      metaVersion: 421,
      cols: ["cluster"],
    });

    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
        current: [0, 1, 2],
      });
      expect(latestInputValue("metaSidebarState")).toMatchObject({
        metaVersion: 421,
      });
    });

    staleRead.resolve({ table: "stale" });
    await Promise.resolve();
    await Promise.resolve();

    expect(testState.reglInstance.updateCellMetaDataPatchCalls).toHaveLength(1);
    expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
      current: [0, 1, 2],
    });
    expect(getPlotTransferError()).toBeNull();
  });

  it("applies out-of-order metadata patches for disjoint columns", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const phaseRead = createDeferred();
    const scoreRead = createDeferred();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      phase: { type: "category", value: { old: [0, 1, 2] } },
      score: { type: "number", value: new Float32Array([0, 0, 0]) },
    };
    arrowReader.readArrowIPC.mockImplementation((url) => {
      if (url.includes("phase")) return phaseRead.promise;
      if (url.includes("score")) return scoreRead.promise;
      throw new Error(`Unexpected metadata patch URL ${url}`);
    });
    arrowReader.parseMetaFromArrow.mockImplementation((table) => ({
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      ...(table.column === "phase"
        ? { phase: { type: "category", value: { G1: [0], S: [1], G2M: [2] } } }
        : { score: { type: "number", value: new Float32Array([1, 2, 3]) } }),
    }));

    testState.handlers.meta_patch_ready({
      metaFile: "phase-meta-patch-ipc",
      metaVersion: 422,
      cols: ["phase"],
    });
    testState.handlers.meta_patch_ready({
      metaFile: "score-meta-patch-ipc",
      metaVersion: 423,
      cols: ["score"],
    });

    scoreRead.resolve({ column: "score" });
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.cellMetaData.score.value)).toEqual([
        1, 2, 3,
      ]);
      expect(latestInputValue("metaSidebarState")).toMatchObject({
        metaVersion: 421,
      });
    });

    phaseRead.resolve({ column: "phase" });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.phase.value).toEqual({
        G1: [0],
        S: [1],
        G2M: [2],
      });
      expect(latestInputValue("metaSidebarState")).toMatchObject({
        metaVersion: 423,
      });
    });

    expect(testState.reglInstance.updateCellMetaDataPatchCalls).toHaveLength(2);
  });

  it("supersedes an older same-column metadata patch at the same version", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const staleRead = createDeferred();
    const currentRead = createDeferred();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { old: [0, 1, 2] } },
    };
    arrowReader.readArrowIPC
      .mockImplementationOnce(() => staleRead.promise)
      .mockImplementationOnce(() => currentRead.promise);
    arrowReader.parseMetaFromArrow.mockImplementation((table) => ({
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: {
        type: "category",
        value: table.request === "current" ? { current: [0, 1, 2] } : { stale: [0, 1, 2] },
      },
    }));

    testState.handlers.meta_patch_ready({
      metaFile: "cluster-stale-same-version-ipc",
      metaVersion: 424,
      cols: ["cluster"],
    });
    testState.handlers.meta_patch_ready({
      metaFile: "cluster-current-same-version-ipc",
      metaVersion: 424,
      cols: ["cluster"],
    });

    currentRead.resolve({ request: "current" });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
        current: [0, 1, 2],
      });
    });

    staleRead.resolve({ request: "stale" });
    await Promise.resolve();
    await Promise.resolve();

    expect(testState.reglInstance.updateCellMetaDataPatchCalls).toHaveLength(1);
    expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
      current: [0, 1, 2],
    });
  });

  it("scopes metadata patch errors to matching in-flight columns", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const phaseRead = createDeferred();
    const scoreRead = createDeferred();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      phase: { type: "category", value: { old: [0, 1, 2] } },
      score: { type: "number", value: new Float32Array([0, 0, 0]) },
    };
    arrowReader.readArrowIPC.mockImplementation((url) => {
      if (url.includes("phase")) return phaseRead.promise;
      if (url.includes("score")) return scoreRead.promise;
      throw new Error(`Unexpected metadata patch URL ${url}`);
    });
    arrowReader.parseMetaFromArrow.mockImplementation((table) => ({
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      ...(table.column === "phase"
        ? { phase: { type: "category", value: { current: [0, 1, 2] } } }
        : { score: { type: "number", value: new Float32Array([4, 5, 6]) } }),
    }));

    testState.handlers.meta_patch_ready({
      metaFile: "phase-error-meta-patch-ipc",
      metaVersion: 425,
      cols: ["phase"],
    });
    testState.handlers.meta_patch_ready({
      metaFile: "score-current-meta-patch-ipc",
      metaVersion: 426,
      cols: ["score"],
    });
    testState.handlers.transfer_error({
      payloadType: "metadata_patch",
      reasonCode: "write_failed",
      version: 425,
      cols: ["phase"],
    });

    phaseRead.resolve({ column: "phase" });
    scoreRead.resolve({ column: "score" });
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.cellMetaData.score.value)).toEqual([
        4, 5, 6,
      ]);
    });

    expect(testState.reglInstance.origData.cellMetaData.phase.value).toEqual({
      old: [0, 1, 2],
    });
    expect(testState.reglInstance.updateCellMetaDataPatchCalls).toHaveLength(1);
    expect(getPlotTransferError().textContent).toContain("phase");
    expect(latestInputValue("metaSidebarState")).toMatchObject({
      metaVersion: 424,
    });

    testState.handlers.meta_patch_ready({
      metaFile: "phase-recovery-meta-patch-ipc",
      metaVersion: 427,
      cols: ["phase"],
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.phase.value).toEqual({
        current: [0, 1, 2],
      });
      expect(latestInputValue("metaSidebarState")).toMatchObject({
        metaVersion: 427,
      });
    });
  });

  it("drops a deferred patch when a newer full identity supersedes its prerequisite", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const staleFullRead = createDeferred();
    const currentFullRead = createDeferred();
    const staleIdentity = "44444444444444444444444444444444";
    const currentIdentity = "55555555555555555555555555555555";
    arrowReader.readArrowIPC.mockImplementation((url) => {
      if (url.includes("stale-full")) return staleFullRead.promise;
      if (url.includes("current-full")) return currentFullRead.promise;
      if (url.includes("recovery-full")) {
        return Promise.resolve({
          cells: { type: "cell_id", value: ["Current1", "Current2", "Current3"] },
          batch: { type: "category", value: { recovered: [0, 1, 2] } },
        });
      }
      throw new Error(`Unexpected metadata URL ${url}`);
    });
    arrowReader.parseMetaFromArrow.mockImplementation((table) => table);

    testState.handlers.meta_ready({
      metaFile: "stale-full-ipc",
      metaVersion: 428,
      cellIdentity: staleIdentity,
    });
    testState.handlers.meta_patch_ready({
      metaFile: "stale-full-meta-patch-ipc",
      metaVersion: 430,
      cols: ["batch"],
      cellIdentity: staleIdentity,
    });
    testState.handlers.meta_ready({
      metaFile: "current-full-ipc",
      metaVersion: 429,
      cellIdentity: currentIdentity,
    });

    currentFullRead.resolve({
      cells: { type: "cell_id", value: ["Current1", "Current2", "Current3"] },
      batch: { type: "category", value: { current: [0, 1, 2] } },
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cells.value).toEqual([
        "Current1", "Current2", "Current3",
      ]);
    });

    staleFullRead.resolve({
      cells: { type: "cell_id", value: ["Stale1", "Stale2", "Stale3"] },
      batch: { type: "category", value: { stale: [0, 1, 2] } },
    });
    await Promise.resolve();
    await Promise.resolve();

    expect(arrowReader.readArrowIPC).toHaveBeenCalledTimes(2);
    expect(testState.reglInstance.origData.cellMetaData.batch.value).toEqual({
      current: [0, 1, 2],
    });
    expect(testState.reglInstance.plotMetaData.cellIdentity).toBe(currentIdentity);

    testState.handlers.transfer_error({
      payloadType: "metadata",
      reasonCode: "write_failed",
      version: 431,
    });
    testState.handlers.reglScatter_plot({
      group_by: "batch",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["current"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      metaVersion: 429,
    });

    testState.handlers.meta_ready({
      metaFile: "recovery-full-ipc",
      metaVersion: 432,
      cellIdentity: currentIdentity,
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.batch.value).toEqual({
        recovered: [0, 1, 2],
      });
    });
    testState.handlers.reglScatter_plot({
      group_by: "batch",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["recovered"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      metaVersion: 432,
    });
  });

  it("heals a late older same-column notification from the newer applied patch", async () => {
    const arrowReader = await resetArrowReaderMocks();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { old: [0, 1, 2] } },
    };
    arrowReader.readArrowIPC.mockImplementation((url) => {
      if (url.includes("baseline-meta")) return Promise.resolve({ table: "baseline" });
      if (url.includes("current-meta-patch")) return Promise.resolve({ table: "current" });
      throw new Error(`Unexpected metadata URL ${url}`);
    });
    arrowReader.parseMetaFromArrow.mockImplementation((table) => (
      table.table === "baseline"
        ? testState.reglInstance.origData.cellMetaData
        : { cluster: { type: "category", value: { current: [0, 1, 2] } } }
    ));
    testState.handlers.meta_ready({
      metaFile: "baseline-meta-ipc",
      metaVersion: 432,
    });
    await vi.waitFor(() => {
      expect(latestInputValue("metaProcessed")).toBe(true);
    });
    arrowReader.readArrowIPC.mockClear();

    testState.handlers.meta_patch_ready({
      metaFile: "current-meta-patch-ipc",
      metaVersion: 434,
      cols: ["cluster"],
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
        current: [0, 1, 2],
      });
      expect(latestInputValue("metaSidebarState")).toMatchObject({
        metaVersion: 432,
      });
    });

    testState.handlers.meta_patch_ready({
      metaFile: "late-stale-meta-patch-ipc",
      metaVersion: 433,
      cols: ["cluster"],
    });
    await Promise.resolve();

    testState.handlers.reglScatter_plot({
      group_by: "cluster",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["current"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      metaVersion: 434,
    });
    expect(arrowReader.readArrowIPC).toHaveBeenCalledTimes(1);
    expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
      current: [0, 1, 2],
    });
  });

  it("does not carry an old-identity patch version across full object replacement", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const replacementIdentity = "66666666666666666666666666666666";
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { old: [0, 1, 2] } },
    };
    arrowReader.readArrowIPC.mockImplementation((url) => {
      if (url.includes("old-identity-meta-patch")) {
        return Promise.resolve({ kind: "oldPatch" });
      }
      if (url.includes("replacement-full")) {
        return Promise.resolve({ kind: "replacementFull" });
      }
      if (url.includes("replacement-meta-patch")) {
        return Promise.resolve({ kind: "replacementPatch" });
      }
      if (url.includes("recovery-full")) {
        return Promise.resolve({ kind: "recoveryFull" });
      }
      throw new Error(`Unexpected metadata URL ${url}`);
    });
    arrowReader.parseMetaFromArrow.mockImplementation((table) => {
      if (table.kind === "oldPatch") {
        return { cluster: { type: "category", value: { patchedOld: [0, 1, 2] } } };
      }
      if (table.kind === "replacementPatch") {
        return { cluster: { type: "category", value: { patchedNew: [0, 1, 2] } } };
      }
      return {
          cells: { type: "cell_id", value: ["New1", "New2", "New3"] },
          cluster: {
            type: "category",
            value: table.kind === "recoveryFull"
              ? { recovered: [0, 1, 2] }
              : { replacement: [0, 1, 2] },
          },
        };
    });

    testState.handlers.meta_patch_ready({
      metaFile: "old-identity-meta-patch-ipc",
      metaVersion: 436,
      cols: ["cluster"],
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
        patchedOld: [0, 1, 2],
      });
    });

    testState.handlers.meta_ready({
      metaFile: "replacement-full-ipc",
      metaVersion: 435,
      cellIdentity: replacementIdentity,
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cells.value).toEqual([
        "New1", "New2", "New3",
      ]);
      expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
        replacement: [0, 1, 2],
      });
    });

    testState.handlers.reglScatter_plot({
      group_by: "cluster",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["replacement"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      metaVersion: 436,
    });
    expect(testState.reglInstance.plotMetaData.cellIdentity).toBe(replacementIdentity);

    testState.handlers.meta_patch_ready({
      metaFile: "replacement-meta-patch-ipc",
      metaVersion: 437,
      cols: ["cluster"],
      cellIdentity: replacementIdentity,
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
        patchedNew: [0, 1, 2],
      });
    });
    testState.handlers.reglScatter_plot({
      group_by: "cluster",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["patchedNew"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      metaVersion: 437,
    });

    testState.handlers.meta_ready({
      metaFile: "recovery-full-ipc",
      metaVersion: 438,
      cellIdentity: replacementIdentity,
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cluster.value).toEqual({
        recovered: [0, 1, 2],
      });
    });
    testState.handlers.reglScatter_plot({
      group_by: "cluster",
      split_by: "None",
      moduleScore: null,
    });
    selectValues("renameCluster-chosenGroup", ["recovered"]);
    expect(latestInputValue("renameCluster-categorySelectionContext")).toMatchObject({
      metaVersion: 438,
    });
  });

  it("pca_ready stores Float32Array stdev data and clears on null stdevFile", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const stdev = new Float32Array([4.5, 2.25, 1.125]);
    arrowReader.readArrowIPC.mockResolvedValue({ table: "pca" });
    arrowReader.getFloat32Column.mockReturnValue(stdev);

    testState.handlers.pca_ready({ stdevFile: "pca-stdev-ipc", reductionVersion: 102 });

    await vi.waitFor(() => {
      expectResourceUrl(
        arrowReader.readArrowIPC.mock.calls[0][0],
        "reduction",
        "pca-stdev-ipc",
      );
      expect(arrowReader.getFloat32Column).toHaveBeenCalledWith({ table: "pca" }, "stdev");
      expect(testState.reglInstance.origData.pcaStdev).toBeInstanceOf(Float32Array);
      expect(Array.from(testState.reglInstance.origData.pcaStdev)).toEqual([
        4.5,
        2.25,
        1.125,
      ]);
    });

    testState.handlers.pca_ready({ stdevFile: null, reductionVersion: 103 });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.pcaStdev).toBeNull();
    });
  });

  it("ignores stale PCA success and error payloads", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const stalePca = createDeferred();
    const currentPca = createDeferred();
    arrowReader.readArrowIPC.mockImplementation((url) => {
      if (url.includes("pca-v104")) return stalePca.promise;
      if (url.includes("pca-v105")) return currentPca.promise;
      throw new Error(`Unexpected PCA URL ${url}`);
    });
    arrowReader.getFloat32Column.mockImplementation((table) => table.stdev);

    testState.handlers.pca_ready({ stdevFile: "pca-v104", reductionVersion: 104 });
    testState.handlers.pca_ready({ stdevFile: "pca-v105", reductionVersion: 105 });
    currentPca.resolve({ stdev: new Float32Array([10, 5]) });

    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.pcaStdev)).toEqual([10, 5]);
    });

    stalePca.resolve({ stdev: new Float32Array([1, 1]) });
    await Promise.resolve();
    await Promise.resolve();
    expect(Array.from(testState.reglInstance.origData.pcaStdev)).toEqual([10, 5]);

    testState.handlers.transfer_error({
      payloadType: "pca",
      reasonCode: "write_failed",
      version: 104,
    });
    expect(Array.from(testState.reglInstance.origData.pcaStdev)).toEqual([10, 5]);

    testState.handlers.transfer_error({
      payloadType: "pca",
      reasonCode: "write_failed",
      version: 106,
    });
    expect(testState.reglInstance.origData.pcaStdev).toBeNull();
  });

  it("reports stored feature identities as text rather than escaped HTML", async () => {
    const { createSparkLine } = await import("./modules/featureSparkLine.js");
    createSparkLine.mockImplementationOnce((feature) => {
      const container = document.createElement("span");
      container.className = "featureSparkLine";
      const label = document.createElement("span");
      label.className = "feature-gene-symbol";
      label.textContent = feature;
      container.appendChild(label);
      return container;
    });

    testState.handlers.createSparkLine("Gene<A&B>");

    expect(document.querySelector(".feature-gene-symbol").innerHTML).toBe(
      "Gene&lt;A&amp;B&gt;",
    );
    expect(latestInputValue("inputFeatures-storedFeatures")).toEqual([
      "Gene<A&B>",
    ]);
  });

  it("renders VlnPlot dropdown labels as text nodes", () => {
    const maliciousLabel = '<img src=x onerror="window.__xss = true">';
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["c1"] },
      [maliciousLabel]: { type: "number", value: new Float32Array([1]) },
    };

    window.dispatchEvent(new CustomEvent("scspotlight:featurePlotSelectionChanged"));

    const menu = document.querySelector("#vlnDropDown .dropdown-menu");
    const item = menu.querySelector(".dropdown-item");
    expect(menu.querySelector("img")).toBeNull();
    expect(item.childNodes[0].nodeType).toBe(Node.TEXT_NODE);
    expect(item.textContent).toContain(maliciousLabel);
    expect(item.textContent).toContain("(meta)");
  });

  it("reduction_ready, reductions_ready, and reduction_cached honor versioned cache keys", async () => {
    const arrowReader = await resetArrowReaderMocks();
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) =>
      Promise.resolve(encodeLabelBuffer(url)),
    );
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = numericValueFromResourceUrl(table.url);
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });

    testState.handlers.reduction_ready({
      reductionFile: "umap-v200",
      reductionName: "umap",
      reductionVersion: 200,
    });
    await vi.waitFor(() => {
      expectResourceUrl(
        arrowReader.fetchArrowIPCBuffer.mock.calls.at(-1)[0],
        "reduction",
        "umap-v200",
      );
      expect(latestInputValue("updateReduction-cachedReductionKeys")).toEqual([
        "200::umap",
      ]);
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([
        200,
      ]);
    });

    document.getElementById("updateReduction-reduction").innerHTML = `
      <option value="pca" selected>pca</option>
    `;
    testState.handlers.reductions_ready({
      reductionVersion: 201,
      activeReduction: "pca",
      reductions: [
        { reductionFile: "umap-v201", reductionName: "umap", reductionVersion: 201 },
        { reductionFile: "pca-v201", reductionName: "pca", reductionVersion: 201 },
      ],
    });
    await vi.waitFor(() => {
      expect(latestInputValue("updateReduction-cachedReductionKeys")).toEqual([
        "201::pca",
        "201::umap",
      ]);
      expect(latestInputValue("updateReduction-cachedReductionKeys")).not.toContain(
        "200::umap",
      );
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([
        201,
      ]);
    });

    const fetchCountBeforeStale = arrowReader.fetchArrowIPCBuffer.mock.calls.length;
    testState.handlers.reduction_ready({
      reductionFile: "umap-v199",
      reductionName: "umap",
      reductionVersion: 199,
    });
    await Promise.resolve();
    await Promise.resolve();
    expect(arrowReader.fetchArrowIPCBuffer).toHaveBeenCalledTimes(fetchCountBeforeStale);
    expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([201]);

    testState.handlers.reduction_cached({
      reductionName: "missing",
      reductionVersion: 201,
    });
    await vi.waitFor(() => {
      expect(latestInputValue("updateReduction-cacheMissReduction")).toBe("missing");
    });
  });

  it("ignores stale reduction transfer errors after a newer reduction commits", async () => {
    const arrowReader = await resetArrowReaderMocks();
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) => (
      Promise.resolve(encodeLabelBuffer(url))
    ));
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = numericValueFromResourceUrl(table.url);
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });

    testState.handlers.reduction_ready({
      reductionFile: "umap-v202",
      reductionName: "umap",
      reductionVersion: 202,
    });
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([202]);
    });

    testState.handlers.reduction_ready({
      reductionFile: "pca-v203",
      reductionName: "pca",
      reductionVersion: 203,
    });
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([203]);
    });

    testState.handlers.transfer_error({
      payloadType: "reduction",
      reasonCode: "write_failed",
      version: 202,
      reductionName: "umap",
    });

    expect(getPlotTransferError()).toBeNull();
    expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([203]);
  });

  it("does not let a same-version error for another reduction cancel the active request", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const activeFetch = createDeferred();
    arrowReader.fetchArrowIPCBuffer.mockReturnValue(activeFetch.promise);
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = numericValueFromResourceUrl(table.url);
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });

    testState.handlers.reduction_ready({
      reductionFile: "pca-v204",
      reductionName: "pca",
      reductionVersion: 204,
    });
    testState.handlers.transfer_error({
      payloadType: "reduction",
      reasonCode: "write_failed",
      version: 204,
      reductionName: "umap",
    });

    expect(getPlotTransferError()).toBeNull();

    activeFetch.resolve(encodeLabelBuffer("pca-v204"));
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([204]);
    });
  });

  it("rejects an older same-version reduction attempt after a newer attempt starts", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const currentFetch = createDeferred();
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) => {
      if (url.includes("pca-attempt-2")) return currentFetch.promise;
      throw new Error(`Older same-version attempt should not fetch: ${url}`);
    });
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = table.url.includes("pca-attempt-2") ? 205 : -1;
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });

    testState.handlers.reduction_ready({
      reductionFile: "pca-attempt-2",
      reductionName: "pca",
      reductionVersion: 205,
      transferAttemptId: 2,
    });
    testState.handlers.reduction_ready({
      reductionFile: "umap-attempt-1",
      reductionName: "umap",
      reductionVersion: 205,
      transferAttemptId: 1,
    });

    currentFetch.resolve(encodeLabelBuffer("pca-attempt-2"));
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([205]);
    });
    expect(arrowReader.fetchArrowIPCBuffer).toHaveBeenCalledTimes(1);
  });

  it("keeps a cached reduction selected when an older same-version fetch resolves", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const staleFetch = createDeferred();
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) => {
      if (url.includes("pca-v206")) return Promise.resolve(encodeLabelBuffer("pca-v206"));
      if (url.includes("umap-v999")) return staleFetch.promise;
      throw new Error(`Unexpected reduction URL ${url}`);
    });
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = table.url.includes("pca-v206") ? 206 : 999;
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });

    testState.handlers.reduction_ready({
      reductionFile: "pca-v206",
      reductionName: "pca",
      reductionVersion: 206,
    });
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([206]);
    });

    testState.handlers.reduction_ready({
      reductionFile: "umap-v999",
      reductionName: "umap",
      reductionVersion: 206,
    });
    await vi.waitFor(() => {
      expect(arrowReader.fetchArrowIPCBuffer).toHaveBeenCalledTimes(2);
    });

    document.getElementById("updateReduction-reduction").innerHTML = `
      <option value="pca" selected>pca</option>
    `;
    testState.handlers.reduction_cached({
      reductionName: "pca",
      reductionVersion: 206,
    });
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([206]);
    });

    staleFetch.resolve(encodeLabelBuffer("umap-v999"));
    await Promise.resolve();
    await Promise.resolve();
    expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([206]);
  });

  it("rejects a delayed same-version transfer notification after a cache selection", async () => {
    const arrowReader = await resetArrowReaderMocks();
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) => {
      if (url.includes("pca-v208")) return Promise.resolve(encodeLabelBuffer("pca-v208"));
      throw new Error(`Delayed transfer should not fetch: ${url}`);
    });
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = table.url.includes("pca-v208") ? 208 : -1;
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });

    testState.handlers.reduction_ready({
      reductionFile: "pca-v208",
      reductionName: "pca",
      reductionVersion: 208,
    });
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([208]);
    });

    document.getElementById("updateReduction-reduction").innerHTML = `
      <option value="pca" selected>pca</option>
    `;
    testState.handlers.reduction_cached({
      reductionName: "pca",
      reductionVersion: 208,
    });
    testState.handlers.reduction_ready({
      reductionFile: "umap-delayed-v208",
      reductionName: "umap",
      reductionVersion: 208,
      transferAttemptId: 1,
    });
    await Promise.resolve();
    await Promise.resolve();

    expect(arrowReader.fetchArrowIPCBuffer).toHaveBeenCalledTimes(1);
    expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([208]);
  });

  it("does not re-open the spinner for a rejected older reduction attempt", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const currentFetch = createDeferred();
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) => {
      if (url.includes("pca-attempt-2")) return currentFetch.promise;
      throw new Error(`Older same-version attempt should not fetch: ${url}`);
    });
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = table.url.includes("pca-attempt-2") ? 209 : -1;
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });

    testState.handlers.reduction_ready({
      reductionFile: "pca-attempt-2",
      reductionName: "pca",
      reductionVersion: 209,
      transferAttemptId: 2,
    });
    await vi.waitFor(() => {
      expect(arrowReader.fetchArrowIPCBuffer).toHaveBeenCalledTimes(1);
    });
    const mainPlotSpinner = testState.spinners["mainClusterPlot-clusterPlot"];
    mainPlotSpinner.style.display = "none";

    testState.handlers.reduction_ready({
      reductionFile: "umap-attempt-1",
      reductionName: "umap",
      reductionVersion: 209,
      transferAttemptId: 1,
    });
    await Promise.resolve();
    await Promise.resolve();

    expect(mainPlotSpinner.style.display).toBe("none");
    expect(arrowReader.fetchArrowIPCBuffer).toHaveBeenCalledTimes(1);

    currentFetch.resolve(encodeLabelBuffer("pca-attempt-2"));
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([209]);
    });
  });

  it("keeps a cache-miss selection when a different same-version transfer arrives", async () => {
    const arrowReader = await resetArrowReaderMocks();
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) => {
      if (url.includes("pca-cache-miss-v210")) {
        return Promise.resolve(encodeLabelBuffer("pca-cache-miss-v210"));
      }
      throw new Error(`Delayed transfer should not fetch: ${url}`);
    });
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = table.url.includes("pca-cache-miss-v210") ? 210 : -1;
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });
    document.getElementById("updateReduction-reduction").innerHTML = `
      <option value="pca" selected>pca</option>
    `;

    testState.handlers.reduction_cached({
      reductionName: "pca",
      reductionVersion: 210,
    });
    await vi.waitFor(() => {
      expect(latestInputValue("updateReduction-cacheMissReduction")).toBe("pca");
    });

    testState.handlers.reduction_ready({
      reductionFile: "umap-delayed-v210",
      reductionName: "umap",
      reductionVersion: 210,
      transferAttemptId: 1,
    });
    await Promise.resolve();
    await Promise.resolve();
    expect(arrowReader.fetchArrowIPCBuffer).not.toHaveBeenCalled();

    testState.handlers.reduction_ready({
      reductionFile: "pca-cache-miss-v210",
      reductionName: "pca",
      reductionVersion: 210,
      transferAttemptId: 2,
    });
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([210]);
    });
  });

  it("prefers the current dropdown reduction over the stale prefetch selection", async () => {
    const arrowReader = await resetArrowReaderMocks();
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) => (
      Promise.resolve(encodeLabelBuffer(url))
    ));
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = table.url.includes("pca-v210") ? 210 : 211;
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });
    document.getElementById("updateReduction-reduction").innerHTML = `
      <option value="pca" selected>pca</option>
    `;

    testState.handlers.reductions_ready({
      reductionVersion: 210,
      activeReduction: "umap",
      reductions: [
        { reductionName: "umap", reductionFile: "umap-v210" },
        { reductionName: "pca", reductionFile: "pca-v210" },
      ],
    });

    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([210]);
    });
  });

  it("keeps the active scatter available when an inactive prefetch fails", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) => {
      if (url.includes("pca-v211")) return Promise.resolve(encodeLabelBuffer(url));
      if (url.includes("umap-v211")) return Promise.reject(new Error("prefetch failed"));
      throw new Error(`Unexpected reduction URL ${url}`);
    });
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = table.url.includes("pca-v211") ? 211 : -1;
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });
    document.getElementById("updateReduction-reduction").innerHTML = `
      <option value="pca" selected>pca</option>
    `;

    testState.handlers.reductions_ready({
      reductionVersion: 211,
      activeReduction: "pca",
      reductions: [
        { reductionName: "pca", reductionFile: "pca-v211" },
        { reductionName: "umap", reductionFile: "umap-v211" },
      ],
    });

    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([211]);
      expect(latestInputValue("reductionProcessed")).toBe(true);
    });
    await Promise.resolve();
    await Promise.resolve();

    expect(getPlotTransferError()).toBeNull();
    expect(latestInputValue("reductionProcessed")).toBe(true);
    expect(warn).toHaveBeenCalledWith(
      "Could not prefetch inactive reduction umap",
      expect.any(Error),
    );
    warn.mockRestore();
  });

  it("expr_ready and expr_cached honor assay/gene versioned cache keys", async () => {
    const arrowReader = await resetArrowReaderMocks();
    addFeatureSparkLine("GeneA");
    addFeatureSparkLine("GeneB");
    addFeatureSparkLine("MissingGene");
    arrowReader.fetchArrowIPCBuffer.mockImplementation((url) =>
      Promise.resolve(encodeLabelBuffer(url)),
    );
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table) => {
      const value = numericValueFromResourceUrl(table.url);
      return new Float32Array([value, value + 1]);
    });

    testState.handlers.expr_ready({
      exprFile: "gene-a-v300",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 300,
    });
    await vi.waitFor(() => {
      expectResourceUrl(
        arrowReader.fetchArrowIPCBuffer.mock.calls.at(-1)[0],
        "expr",
        "gene-a-v300",
      );
      expect(latestInputValue("inputFeatures-cachedExprKeys")).toEqual([
        "300::RNA::GeneA",
      ]);
      expect(Array.from(testState.reglInstance.origData.expressionData.GeneA)).toEqual([
        300,
        301,
      ]);
    });

    testState.handlers.expr_ready({
      exprFile: "gene-b-v301",
      geneName: "GeneB",
      assay: "RNA",
      exprVersion: 301,
    });
    await vi.waitFor(() => {
      expect(latestInputValue("inputFeatures-cachedExprKeys")).toEqual([
        "301::RNA::GeneB",
      ]);
      expect(latestInputValue("inputFeatures-cachedExprKeys")).not.toContain(
        "300::RNA::GeneA",
      );
      expect(Array.from(testState.reglInstance.origData.expressionData.GeneB)).toEqual([
        301,
        302,
      ]);
    });

    const fetchCountBeforeStale = arrowReader.fetchArrowIPCBuffer.mock.calls.length;
    testState.handlers.expr_ready({
      exprFile: "gene-stale-v299",
      geneName: "GeneStale",
      assay: "RNA",
      exprVersion: 299,
    });
    await Promise.resolve();
    await Promise.resolve();
    expect(arrowReader.fetchArrowIPCBuffer).toHaveBeenCalledTimes(fetchCountBeforeStale);
    expect(testState.reglInstance.origData.expressionData.GeneStale).toBeUndefined();

    testState.handlers.expr_cached({
      geneName: "GeneB",
      assay: "RNA",
      exprVersion: 301,
    });
    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.expressionData.GeneB)).toEqual([
        301,
        302,
      ]);
    });

    testState.handlers.expr_cached({
      geneName: "MissingGene",
      assay: "RNA",
      exprVersion: 301,
    });
    await vi.waitFor(() => {
      expect(latestInputValue("inputFeatures-cacheMissFeature")).toBe("MissingGene");
    });
  });

  it("delayed stale expr_ready results are ignored after fetch before cache or scatter mutation", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const staleFetch = createDeferred();
    addFeatureSparkLine("GeneA");
    addFeatureSparkLine("GeneB");
    arrowReader.fetchArrowIPCBuffer
      .mockImplementationOnce(() => staleFetch.promise)
      .mockResolvedValueOnce(encodeLabelBuffer("gene-b-v501"));
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      label: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table) => {
      const value = table.label.includes("gene-b") ? 501 : 500;
      return new Float32Array([value, value + 1]);
    });

    testState.handlers.expr_ready({
      exprFile: "gene-a-v500",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 500,
    });
    testState.handlers.expr_ready({
      exprFile: "gene-b-v501",
      geneName: "GeneB",
      assay: "RNA",
      exprVersion: 501,
    });

    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.expressionData.GeneB)).toEqual([
        501,
        502,
      ]);
      expect(latestInputValue("inputFeatures-cachedExprKeys")).toEqual([
        "501::RNA::GeneB",
      ]);
    });

    staleFetch.resolve(encodeLabelBuffer("gene-a-v500"));
    await Promise.resolve();
    await Promise.resolve();

    expect(testState.reglInstance.origData.expressionData.GeneA).toBeUndefined();
    expect(testState.reglInstance.updateExpressionDataCalls).toHaveLength(1);
    expect(latestInputValue("inputFeatures-cachedExprKeys")).toEqual([
      "501::RNA::GeneB",
    ]);
  });

  it("ignores a delayed expr_ready payload after a full object replacement", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const delayedExpression = createDeferred();
    addFeatureSparkLine("GeneA");
    arrowReader.fetchArrowIPCBuffer.mockReturnValue(delayedExpression.promise);
    arrowReader.readArrowIPC.mockResolvedValue({ table: "replacement-meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue({
      cells: { type: "cell_id", value: ["c2"] },
      cluster: { type: "category", value: { B: [0] } },
    });

    testState.handlers.expr_ready({
      exprFile: "gene-a-before-replacement",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 9000,
    });
    testState.handlers.meta_ready({ metaFile: "replacement-meta", metaVersion: 10000 });

    await vi.waitFor(() => {
      expect(document.getElementById("featureSparkLine").children).toHaveLength(0);
      expect(testState.reglInstance.origData.expressionData).toEqual({});
    });

    delayedExpression.resolve(encodeLabelBuffer("gene-a-before-replacement"));
    await Promise.resolve();
    await Promise.resolve();

    expect(testState.reglInstance.origData.expressionData.GeneA).toBeUndefined();
    expect(testState.reglInstance.updateExpressionDataCalls).toHaveLength(0);
  });

  it("keeps same-version expression requests available after a metadata-only refresh", async () => {
    const arrowReader = await resetArrowReaderMocks();
    addFeatureSparkLine("GeneA");
    addFeatureSparkLine("GeneB");
    arrowReader.readArrowIPC.mockResolvedValue({ table: "same-cells-meta" });
    arrowReader.parseMetaFromArrow.mockReturnValue({
      cells: { type: "cell_id", value: ["c1", "c2", "c3"] },
      cluster: { type: "category", value: { A: [0, 1], B: [2] } },
    });
    arrowReader.fetchArrowIPCBuffer.mockResolvedValue(encodeLabelBuffer("gene-b-same-version"));
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      label: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockReturnValue(new Float32Array([1, 2, 3]));

    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["c1", "c2", "c3"] },
      cluster: { type: "category", value: { A: [0, 1], B: [2] } },
    };
    testState.handlers.expr_ready({
      exprFile: "gene-a-same-version",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 9100,
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.expressionData.GeneA).toBeDefined();
    });

    testState.handlers.meta_ready({ metaFile: "same-cells-meta", metaVersion: 10001 });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.cellMetaData.cells.value).toEqual(["c1", "c2", "c3"]);
    });

    testState.handlers.expr_ready({
      exprFile: "gene-b-same-version",
      geneName: "GeneB",
      assay: "RNA",
      exprVersion: 9100,
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.expressionData.GeneB).toBeDefined();
    });
  });

  it("expr_ready failures show scoped expression copy and preserve category metadata", async () => {
    const arrowReader = await resetArrowReaderMocks();
    addFeatureSparkLine("GeneFail");
    const existingMeta = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { A: [0, 1], B: [2] } },
    };
    testState.reglInstance.origData.cellMetaData = existingMeta;
    arrowReader.fetchArrowIPCBuffer.mockRejectedValue(new Error("boom"));

    testState.handlers.expr_ready({
      exprFile: "gene-fail-v20000",
      geneName: "GeneFail",
      assay: "RNA",
      exprVersion: 20000,
    });

    await vi.waitFor(() => {
      const overlay = getPlotTransferError();
      expect(overlay).toBeTruthy();
      expect(overlay.textContent).toContain("Expression could not load");
      expect(overlay.textContent).toContain("GeneFail");
      expect(overlay.textContent).toContain("RNA");
      expect(overlay.textContent).toContain("category scatter remains available");
      expect(testState.reglInstance.origData.cellMetaData).toBe(existingMeta);
      expect(testState.reglInstance.origData.expressionData.GeneFail).toBeUndefined();
    });
  });

  it("transfer_error uses scoped expression and metadata patch failure copy", () => {
    addFeatureSparkLine("GeneErr");
    testState.handlers.transfer_error({
      payloadType: "expression",
      reasonCode: "write_failed",
      version: 100000,
      geneName: "GeneErr",
      assay: "RNA",
    });

    expect(getPlotTransferError().textContent).toContain("Expression could not load");
    expect(getPlotTransferError().textContent).toContain("GeneErr");

    testState.handlers.transfer_error({
      payloadType: "metadata_patch",
      reasonCode: "write_failed",
      version: 20001,
      cols: ["Phase", "S.Score"],
    });

    expect(getPlotTransferError().textContent).toContain("Metadata update could not apply");
    expect(getPlotTransferError().textContent).toContain("Phase, S.Score");
  });

  it("rejects an old expression epoch after explicit server invalidation", async () => {
    const arrowReader = await resetArrowReaderMocks();
    addFeatureSparkLine("GeneA");
    testState.handlers.clear_expr({ invalidateVersion: 200000 });
    addFeatureSparkLine("GeneA");
    arrowReader.fetchArrowIPCBuffer.mockResolvedValue(
      encodeLabelBuffer("gene-a-current"),
    );
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      label: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockReturnValue(new Float32Array([1, 2]));

    testState.handlers.expr_ready({
      exprFile: "gene-a-old",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 200000,
    });
    await Promise.resolve();
    await Promise.resolve();

    expect(arrowReader.fetchArrowIPCBuffer).not.toHaveBeenCalled();
    expect(testState.reglInstance.origData.expressionData.GeneA).toBeUndefined();

    testState.handlers.expr_ready({
      exprFile: "gene-a-current",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 200001,
    });

    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.expressionData.GeneA).toBeDefined();
    });
  });

  it("clears ordinary feature state without invalidating its expression epoch", async () => {
    const arrowReader = await resetArrowReaderMocks();
    addFeatureSparkLine("GeneA");
    arrowReader.fetchArrowIPCBuffer.mockResolvedValue(
      encodeLabelBuffer("gene-a-ordinary-clear"),
    );
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      label: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockReturnValue(new Float32Array([4, 5]));

    testState.handlers.expr_ready({
      exprFile: "gene-a-ordinary-clear",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 300000,
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.expressionData.GeneA).toBeDefined();
    });

    testState.handlers.clear_expr({});

    expect(testState.reglInstance.origData.expressionData).toEqual({});
    expect(document.getElementById("featureSparkLine").children).toHaveLength(0);
    expect(latestInputValue("inputFeatures-cachedExprKeys")).toEqual([]);

    addFeatureSparkLine("GeneA");
    testState.handlers.expr_ready({
      exprFile: "gene-a-ordinary-clear",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 300000,
    });

    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.expressionData.GeneA)).toEqual([4, 5]);
    });
  });

  it("normalizes malformed clear_expr payloads without creating an epoch barrier", async () => {
    const arrowReader = await resetArrowReaderMocks();
    addFeatureSparkLine("GeneA");
    arrowReader.fetchArrowIPCBuffer.mockResolvedValue(
      encodeLabelBuffer("gene-a-malformed-clear"),
    );
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      label: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockReturnValue(new Float32Array([6, 7]));

    testState.handlers.expr_ready({
      exprFile: "gene-a-malformed-clear",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 310000,
    });
    await vi.waitFor(() => {
      expect(testState.reglInstance.origData.expressionData.GeneA).toBeDefined();
    });

    testState.handlers.clear_expr({ invalidateVersion: true });
    expect(() => {
      testState.handlers.clear_expr(null);
      testState.handlers.clear_expr("");
      testState.handlers.clear_expr([]);
      testState.handlers.clear_expr({ invalidateVersion: -1 });
      testState.handlers.clear_expr({ invalidateVersion: Infinity });
      testState.handlers.clear_expr({ invalidateVersion: Number.NaN });
    }).not.toThrow();

    addFeatureSparkLine("GeneA");
    testState.handlers.expr_ready({
      exprFile: "gene-a-malformed-clear",
      geneName: "GeneA",
      assay: "RNA",
      exprVersion: 310000,
    });

    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.expressionData.GeneA)).toEqual([6, 7]);
    });
  });

  it("requests a full metadata recovery instead of silently dropping deferred patches", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const fullRead = createDeferred();
    const nextCellIdentity = "12121212121212121212121212121212";
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      batch: { type: "category", value: { old: [0, 1, 2] } },
    };
    arrowReader.readArrowIPC.mockImplementation((url) => {
      if (url.includes("overflow-full")) return fullRead.promise;
      throw new Error(`Deferred patch should not fetch before full metadata: ${url}`);
    });

    testState.handlers.meta_ready({
      metaFile: "overflow-full-ipc",
      metaVersion: 60000,
      cellIdentity: nextCellIdentity,
    });
    for (let version = 60001; version <= 60065; version += 1) {
      testState.handlers.meta_patch_ready({
        metaFile: `overflow-patch-${version}`,
        metaVersion: version,
        cols: [`column_${version}`],
        cellIdentity: nextCellIdentity,
      });
    }

    await vi.waitFor(() => {
      expect(latestInputValue("updateMetaData-requestFullRefresh")).toEqual({
        version: 60001,
        timestamp: expect.any(Number),
      });
    });
    expect(arrowReader.readArrowIPC).toHaveBeenCalledTimes(1);
  });

  it("keeps an unresolved metadata patch error visible after a reduction succeeds", async () => {
    const arrowReader = await resetArrowReaderMocks();
    arrowReader.fetchArrowIPCBuffer.mockResolvedValue(encodeLabelBuffer("umap-v90000"));
    arrowReader.decodeArrowIPC.mockImplementation((buffer) => ({
      url: decodeLabelBuffer(buffer),
    }));
    arrowReader.getFloat32Column.mockImplementation((table, colName) => {
      const value = numericValueFromResourceUrl(table.url);
      return new Float32Array([colName === "X" ? value : value + 0.5]);
    });

    testState.handlers.transfer_error({
      payloadType: "metadata_patch",
      reasonCode: "write_failed",
      version: 89999,
      cols: ["batch"],
    });
    testState.handlers.reduction_ready({
      reductionFile: "umap-v90000",
      reductionName: "umap",
      reductionVersion: 90000,
    });

    await vi.waitFor(() => {
      expect(Array.from(testState.reglInstance.origData.reductionData.X)).toEqual([90000]);
    });
    expect(getPlotTransferError().textContent).toContain("Metadata update could not apply");
  });

  it("rejects dot and data resource prefixes before IPC fetches", async () => {
    const arrowReader = await resetArrowReaderMocks();
    testState.handlers.meta_ready({
      resourcePrefix: ".",
      metaFile: "invalid-prefix-meta",
      metaVersion: 91000,
    });
    await Promise.resolve();
    expect(arrowReader.readArrowIPC).not.toHaveBeenCalled();
    expect(getPlotTransferError().textContent).toContain("Metadata could not load");

    testState.handlers.meta_ready({
      resourcePrefix: "data",
      metaFile: "invalid-prefix-meta-data",
      metaVersion: 91001,
    });
    await Promise.resolve();
    expect(arrowReader.readArrowIPC).not.toHaveBeenCalled();
  });
});
