/**
 * @vitest-environment jsdom
 */

import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

const testState = vi.hoisted(() => ({
  handlers: {},
  inputs: [],
  reglInstance: null,
}));

vi.mock("shiny", () => ({}), { virtual: true });

vi.mock("./modules/spinner.js", () => ({
  initFullScreenSpinner: () => document.createElement("div"),
  removeFullScreenSpinner: vi.fn(),
  addOverlaySpinner: () => {
    const el = document.createElement("div");
    el.style.display = "none";
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
    <button id="renameCluster-assign"></button>
    <select id="updateReduction-reduction"><option value="umap" selected>umap</option></select>
    <div id="floatingVlnPlot"></div>
    <div id="floatingFeaturePlot"></div>
    <div id="floatingDotPlot"></div>
    <div class="accordion-item" data-value="analysis_category">
      <div class="accordion-body"></div>
    </div>
  `;
};

const installShiny = () => {
  globalThis.Shiny = {
    addCustomMessageHandler: (name, handler) => {
      testState.handlers[name] = handler;
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
  };
  testState.reglInstance.plotEl = document.createElement("div");
  testState.reglInstance.catLegendEl = document.createElement("div");
  testState.reglInstance.expLegendEl = document.createElement("div");
  testState.reglInstance.selectionSource = null;
  testState.reglInstance.selectionHandlers = null;
  testState.reglInstance.interactions = { clearLasso: vi.fn() };
};

const setCategoryMeta = (columnName, mapping) => {
  testState.reglInstance.origData.cellMetaData.cells = ["c1", "c2", "c3"];
  testState.reglInstance.origData.cellMetaData[columnName] = {
    type: "category",
    value: mapping,
  };
};

const selectValues = (id, values) => {
  const el = document.getElementById(id);
  [...el.options].forEach((option) => {
    option.selected = values.includes(option.value);
  });
  el.dispatchEvent(new Event("change"));
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

  it("settles initial plot readiness when reduction loading fails", async () => {
    const arrowReader = await import("./modules/arrowReader.js");
    arrowReader.fetchArrowIPCBuffer.mockRejectedValueOnce(new Error("network failed"));

    testState.handlers.await_initial_plot_ready({});
    testState.handlers.reduction_ready({
      reductionFile: "broken-ipc",
      reductionVersion: 1,
      reductionName: "umap",
    });

    await vi.waitFor(() => {
      expect(testState.inputs).toContainEqual([
        "initialPlotReady",
        expect.any(Number),
        { priority: "event" },
      ]);
    });
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
  });
});
