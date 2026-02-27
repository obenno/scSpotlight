import { describe, expect, it, vi } from "vitest";
import { reglScatterCanvas } from "./deckScatter.js";

describe("reglScatterCanvas lasso selection", () => {
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
    canvas.selectionHandlers = { onSelect: vi.fn(), onDeselect: null };

    canvas.handleLassoSelect("panel_1", [0, 2]);

    expect(canvas.plotData.selectedCells).toEqual(["d1", "d3"]);
    expect(canvas.highlightByPanel).toEqual([[], [0, 2]]);
    expect(canvas.applyHighlight).toHaveBeenCalledTimes(1);
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
    canvas.selectionHandlers = { onSelect: vi.fn(), onDeselect: null };

    canvas.handleLassoSelect("panel_0", [0, 5]);

    expect(canvas.plotData.selectedCells).toEqual(["c1"]);
    expect(canvas.selectionHandlers.onSelect).toHaveBeenCalledWith({
      panelIdx: 0,
      indices: [0, 5],
      selectedCells: ["c1"],
    });
  });
});
