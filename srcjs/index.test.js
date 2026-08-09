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
      };
      this.plotData = {
        selectedCells: [],
        cells: [["c1", "c2", "c3"]],
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

    generatePlotEl() {}

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
      this.plotData.selectedCells = [...new Set(selectedCells)];
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
        ? (msg) => handler({ resourcePrefix: TEST_RESOURCE_PREFIX, ...msg })
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
  };
  testState.reglInstance.plotData = {
    selectedCells: [],
    cells: [["c1", "c2", "c3"]],
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

describe("rename cluster client selection", () => {
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
    testState.reglInstance.setSelectedCells(["c1", "missing-cell"], { source: "lasso" });
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

  it("meta_patch_ready fetches patch metadata and reports changed cols", async () => {
    const arrowReader = await resetArrowReaderMocks();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { old: [0, 1, 2] } },
      batch: { type: "category", value: { A: [0], B: [1, 2] } },
    };
    testState.reglInstance.plotMetaData.group_by = "cluster";
    const parsedPatch = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
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
  });

  it("meta_patch_ready rejects reordered Cell IDs before merging by position", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const existingBatch = { type: "category", value: { A: [0], B: [1, 2] } };
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      batch: existingBatch,
    };
    arrowReader.readArrowIPC.mockResolvedValue({ table: "reordered-patch" });
    arrowReader.parseMetaFromArrow.mockReturnValue({
      cells: { type: "cell_id", value: ["Cell2", "Cell1", "Cell3"] },
      batch: { type: "category", value: { A: [0, 2], B: [1] } },
    });

    testState.handlers.meta_patch_ready({
      metaFile: "reordered-meta-patch-ipc",
      metaVersion: 412,
      cols: ["batch"],
    });

    await vi.waitFor(() => {
      expect(testState.reglInstance.updateCellMetaDataPatchCalls).toHaveLength(0);
      expect(testState.reglInstance.origData.cellMetaData.batch).toBe(existingBatch);
      expect(getPlotTransferError().textContent).toContain("Metadata update could not apply");
    });
  });

  it("delayed stale meta_patch_ready results are ignored after fetch", async () => {
    const arrowReader = await resetArrowReaderMocks();
    const staleRead = createDeferred();
    testState.reglInstance.origData.cellMetaData = {
      cells: { type: "cell_id", value: ["Cell1", "Cell2", "Cell3"] },
      cluster: { type: "category", value: { old: [0, 1, 2] } },
    };
    testState.reglInstance.plotMetaData.group_by = "cluster";
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
});
