import { describe, expect, it, vi } from "vitest";
import { ScatterplotLayer } from "@deck.gl/layers";
import {
  reglScatterCanvas,
  convert_stringArr_to_integer,
  expandMeta,
  getMetaLevels,
  invalidateMetaCache,
  splitArrByMeta,
} from "./deckScatter.js";

describe("metadata cache helpers", () => {
  it("reuses cached expansions and levels until invalidated", () => {
    const meta = {
      type: "category",
      value: {
        B: [1],
        A: [0, 2],
      },
    };

    const expanded1 = expandMeta(meta);
    const expanded2 = expandMeta(meta);
    const levels1 = getMetaLevels(meta);
    const levels2 = getMetaLevels(meta);

    expect(expanded2).toBe(expanded1);
    expect(levels1).toEqual(["A", "B"]);
    expect(levels2).toBe(levels1);

    meta.value.C = [3];
    invalidateMetaCache(meta);

    expect(getMetaLevels(meta)).toEqual(["A", "B", "C"]);
  });

  it("ignores nullish and empty category levels", () => {
    const meta = {
      type: "category",
      value: {
        B: [1],
        "": [2],
        A: [0, 5],
        undefined: [3],
      },
    };

    expect(getMetaLevels(meta)).toEqual(["A", "B"]);

    const encoded = convert_stringArr_to_integer(["B", "", "A", null, undefined, "A"]);
    expect(Array.from(encoded)).toEqual([1, -1, 0, -1, -1, 0]);

    const split = splitArrByMeta(new Float32Array([10, 20, 30, 40, 50]), ["s2", "", "s1", null, "s2"]);
    expect(Object.keys(split)).toEqual(["s1", "s2"]);
    expect(Array.from(split.s1)).toEqual([30]);
    expect(Array.from(split.s2)).toEqual([10, 50]);
  });
});

describe("reglScatterCanvas adaptive deck.gl rendering", () => {
  it("uses the normative adaptive point thresholds", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);

    expect(canvas.getPointOptions(14999)).toEqual({ opacity: 0.8, pointSize: 4, pickable: true });
    expect(canvas.getPointOptions(15000)).toEqual({ opacity: 0.7, pointSize: 3, pickable: true });
    expect(canvas.getPointOptions(49999)).toEqual({ opacity: 0.7, pointSize: 3, pickable: true });
    expect(canvas.getPointOptions(50000)).toEqual({ opacity: 0.6, pointSize: 2, pickable: true });
    expect(canvas.getPointOptions(499999)).toEqual({ opacity: 0.6, pointSize: 2, pickable: true });
    expect(canvas.getPointOptions(500000)).toEqual({ opacity: 0.5, pointSize: 1, pickable: true });
    expect(canvas.getPointOptions(999999)).toEqual({ opacity: 0.5, pointSize: 1, pickable: true });
    expect(canvas.getPointOptions(1000000)).toEqual({ opacity: 0.4, pointSize: 0.5, pickable: true });
    expect(canvas.getPointOptions(1999999)).toEqual({ opacity: 0.4, pointSize: 0.5, pickable: true });
    expect(canvas.getPointOptions(2000000)).toEqual({ opacity: 0.2, pointSize: 0.2, pickable: false });
  });

  it("does not re-enable base picking for 2M+ point panels when zoomed", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);
    canvas.viewStates = { panel_0: { zoom: 8 } };
    canvas.baseZoomByView = { panel_0: 0 };

    expect(canvas.shouldEnablePicking({ nPoints: 2000000, pickable: false }, "panel_0")).toBe(false);
    expect(canvas.shouldEnablePicking({ nPoints: 2500000, pickable: false }, "panel_0")).toBe(false);
    expect(canvas.shouldEnablePicking({ nPoints: 1000000, pickable: true }, "panel_0")).toBe(true);
  });

  it("creates ScatterplotLayer base layers with typed binary attributes", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);
    canvas.viewStates = {};
    canvas.baseZoomByView = {};
    canvas.highlightByPanel = null;
    canvas.hoveredPoint = null;
    canvas.plotData = {
      pointsData: [
        {
          x: new Float32Array([0, 1]),
          y: new Float32Array([2, 3]),
          z: new Int16Array([0, 1]),
        },
      ],
      zType: ["category"],
      colorData: [["#ff0000", "#00ff00"]],
    };
    canvas.panelBuffers = canvas.buildPanelBuffers();

    const layers = canvas.createAllLayers();
    const baseLayer = layers[0];

    expect(baseLayer).toBeInstanceOf(ScatterplotLayer);
    expect(baseLayer.props.panelViewId).toBe("panel_0");
    expect(Array.isArray(baseLayer.props.data)).toBe(false);
    expect(baseLayer.props.data.length).toBe(2);
    expect(baseLayer.props.data.attributes.getPosition.value).toBeInstanceOf(Float32Array);
    expect(baseLayer.props.data.attributes.getFillColor.value).toBeInstanceOf(Uint8Array);
    expect(baseLayer.props.data.attributes.getPosition.value).toBe(canvas.panelBuffers[0].positions);
    expect(baseLayer.props.data.attributes.getFillColor.value).toBe(canvas.panelBuffers[0].colors);
  });
});

describe("reglScatterCanvas lasso selection", () => {
  it("syncs selected cell ids across panels", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);
    canvas.plotData = {
      cells: [["c1", "c2", "c3"], ["c1", "c4", "c3"]],
      selectedCells: [],
    };
    canvas.panelBuffers = [{}, {}];
    canvas.highlightByPanel = null;
    canvas.applyHighlight = vi.fn();
    canvas.clearHighlight = vi.fn();
    canvas.updateCellCount = vi.fn();

    canvas.setSelectedCells(["c1", "c3"], { source: "category" });

    expect(canvas.selectionSource).toBe("category");
    expect(canvas.plotData.selectedCells).toEqual(["c1", "c3"]);
    expect(canvas.highlightByPanel).toEqual([[0, 2], [0, 2]]);
    expect(canvas.applyHighlight).toHaveBeenCalledTimes(1);
    expect(canvas.updateCellCount).toHaveBeenCalledWith({ selectedCount: 2 });
  });

  it("maps lasso indices to cell ids for selected panel", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);
    canvas.plotData = {
      cells: [
        ["c1", "c2", "c3", "c4"],
        ["d1", "d2", "d3", "d4"],
      ],
      selectedCells: [],
    };
    canvas.panelBuffers = [{}, {}];
    canvas.highlightByPanel = null;
    canvas.applyHighlight = vi.fn();
    canvas.updateCellCount = vi.fn();
    canvas.selectionHandlers = { onSelect: vi.fn(), onDeselect: null };

    canvas.handleLassoSelect("panel_1", [0, 2]);

    expect(canvas.plotData.selectedCells).toEqual(["d1", "d3"]);
    expect(canvas.highlightByPanel).toEqual([[], [0, 2]]);
    expect(canvas.applyHighlight).toHaveBeenCalledTimes(1);
    expect(canvas.updateCellCount).toHaveBeenCalledWith({ selectedCount: 2 });
    expect(canvas.selectionHandlers.onSelect).toHaveBeenCalledWith({
      panelIdx: 1,
      indices: [0, 2],
      selectedCells: ["d1", "d3"],
    });
  });

  it("filters out undefined cells when index is out of bounds", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);
    canvas.plotData = {
      cells: [["c1", "c2"]],
      selectedCells: [],
    };
    canvas.panelBuffers = [{}];
    canvas.highlightByPanel = null;
    canvas.applyHighlight = vi.fn();
    canvas.updateCellCount = vi.fn();
    canvas.selectionHandlers = { onSelect: vi.fn(), onDeselect: null };

    canvas.handleLassoSelect("panel_0", [0, 5]);

    expect(canvas.plotData.selectedCells).toEqual(["c1"]);
    expect(canvas.updateCellCount).toHaveBeenCalledWith({ selectedCount: 1 });
    expect(canvas.selectionHandlers.onSelect).toHaveBeenCalledWith({
      panelIdx: 0,
      indices: [0, 5],
      selectedCells: ["c1"],
    });
  });

  it("syncs repeated selected cells across panels", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);
    canvas.plotData = {
      cells: [
        ["c1", "c2", "c3"],
        ["c1", "c2", "c3"],
      ],
      selectedCells: [],
    };
    canvas.panelBuffers = [{}, {}];
    canvas.highlightByPanel = null;
    canvas.applyHighlight = vi.fn();
    canvas.updateCellCount = vi.fn();
    canvas.selectionHandlers = { onSelect: vi.fn(), onDeselect: null };

    canvas.handleLassoSelect("panel_1", [0, 2]);

    expect(canvas.plotData.selectedCells).toEqual(["c1", "c3"]);
    expect(canvas.highlightByPanel).toEqual([[0, 2], [0, 2]]);
  });

  it("reconciles requested selections to currently visible cells", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);
    canvas.plotData = {
      cells: [["c1", "c2"], ["c2", "c3"]],
      selectedCells: [],
    };
    canvas.panelBuffers = [{}, {}];
    canvas.highlightByPanel = null;
    canvas.applyHighlight = vi.fn();
    canvas.clearHighlight = vi.fn();
    canvas.updateCellCount = vi.fn();

    canvas.setSelectedCells(["missing", "c2", "c2"], { source: "lasso" });

    expect(canvas.plotData.selectedCells).toEqual(["c2"]);
    expect(canvas.highlightByPanel).toEqual([[1], [0]]);
    expect(canvas.applyHighlight).toHaveBeenCalledTimes(1);
    expect(canvas.updateCellCount).toHaveBeenCalledWith({ selectedCount: 1 });

    canvas.setSelectedCells(["missing"], { source: "lasso" });

    expect(canvas.plotData.selectedCells).toEqual([]);
    expect(canvas.clearHighlight).toHaveBeenCalledTimes(1);
    expect(canvas.updateCellCount).toHaveBeenLastCalledWith({ selectedCount: 0 });
  });

  it("updates the persistent count badge with thousands separators", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);
    const plotEl = document.createElement("div");
    plotEl.innerHTML = `
      <div id="cellCount">
        <span class="cell-count-total">0</span>
        <span class="cell-count-selected">0</span>
      </div>
    `;
    canvas.plotEl = plotEl;

    canvas.updateCellCount({ totalCount: 12345, selectedCount: 6789 });

    expect(plotEl.querySelector(".cell-count-total").textContent).toBe("12,345");
    expect(plotEl.querySelector(".cell-count-selected").textContent).toBe("6,789");
  });
});

describe("reglScatterCanvas category labels", () => {
  it("clears stale label canvases for non-category panels", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);
    const panel0Canvas = document.createElement("canvas");
    panel0Canvas.width = 200;
    panel0Canvas.height = 100;
    const panel1Canvas = document.createElement("canvas");
    panel1Canvas.width = 200;
    panel1Canvas.height = 100;

    const panel0Ctx = { clearRect: vi.fn(), fillText: vi.fn() };
    const panel1Ctx = { clearRect: vi.fn(), fillText: vi.fn() };
    panel0Canvas.getContext = vi.fn(() => panel0Ctx);
    panel1Canvas.getContext = vi.fn(() => panel1Ctx);

    const plotEl = document.createElement("div");
    panel0Canvas.classList.add("label-canvas");
    panel0Canvas.dataset.viewId = "panel_0";
    panel1Canvas.classList.add("label-canvas");
    panel1Canvas.dataset.viewId = "panel_1";
    plotEl.appendChild(panel0Canvas);
    plotEl.appendChild(panel1Canvas);

    canvas.plotEl = plotEl;
    canvas.plotData = {
      catLabelCoordinates: [[{ x: 1, y: 2, label: "A" }]],
    };
    canvas.plotMetaData = { labelSize: 14 };
    canvas.deck = {
      getViewports: () => [
        { id: "panel_0", x: 0, y: 0, width: 200, height: 100, project: () => [10, 20] },
        { id: "panel_1", x: 200, y: 0, width: 200, height: 100, project: () => [30, 40] },
      ],
    };

    const originalDpr = window.devicePixelRatio;
    Object.defineProperty(window, "devicePixelRatio", {
      value: 1,
      configurable: true,
    });

    canvas.showCatLabel();

    expect(panel0Ctx.clearRect).toHaveBeenCalledTimes(2);
    expect(panel0Ctx.fillText).toHaveBeenCalledWith("A", 10, 20);
    expect(panel1Ctx.clearRect).toHaveBeenCalledTimes(1);
    expect(panel1Ctx.fillText).not.toHaveBeenCalled();

    Object.defineProperty(window, "devicePixelRatio", {
      value: originalDpr,
      configurable: true,
    });
  });

  it("only clears requested panel labels during partial redraw", () => {
    const canvas = Object.create(reglScatterCanvas.prototype);
    const panel0Canvas = document.createElement("canvas");
    panel0Canvas.width = 200;
    panel0Canvas.height = 100;
    const panel1Canvas = document.createElement("canvas");
    panel1Canvas.width = 200;
    panel1Canvas.height = 100;

    const panel0Ctx = { clearRect: vi.fn(), fillText: vi.fn() };
    const panel1Ctx = { clearRect: vi.fn(), fillText: vi.fn() };
    panel0Canvas.getContext = vi.fn(() => panel0Ctx);
    panel1Canvas.getContext = vi.fn(() => panel1Ctx);

    const plotEl = document.createElement("div");
    panel0Canvas.classList.add("label-canvas");
    panel0Canvas.dataset.viewId = "panel_0";
    panel1Canvas.classList.add("label-canvas");
    panel1Canvas.dataset.viewId = "panel_1";
    plotEl.appendChild(panel0Canvas);
    plotEl.appendChild(panel1Canvas);

    canvas.plotEl = plotEl;
    canvas.plotData = {
      catLabelCoordinates: [[{ x: 1, y: 2, label: "A" }], [{ x: 3, y: 4, label: "B" }]],
    };
    canvas.plotMetaData = { labelSize: 14 };
    canvas.deck = {
      getViewports: () => [
        { id: "panel_0", x: 0, y: 0, width: 200, height: 100, project: () => [10, 20] },
        { id: "panel_1", x: 200, y: 0, width: 200, height: 100, project: () => [30, 40] },
      ],
    };

    const originalDpr = window.devicePixelRatio;
    Object.defineProperty(window, "devicePixelRatio", {
      value: 1,
      configurable: true,
    });

    canvas.showCatLabel(["panel_0"]);

    expect(panel0Ctx.clearRect).toHaveBeenCalledTimes(2);
    expect(panel0Ctx.fillText).toHaveBeenCalledWith("A", 10, 20);
    expect(panel1Ctx.clearRect).not.toHaveBeenCalled();
    expect(panel1Ctx.fillText).not.toHaveBeenCalled();

    Object.defineProperty(window, "devicePixelRatio", {
      value: originalDpr,
      configurable: true,
    });
  });
});
