import { describe, expect, it, vi } from "vitest";
import {
  reglScatterCanvas,
  expandMeta,
  getMetaLevels,
  invalidateMetaCache,
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
});
