import { describe, expect, it } from "vitest";
import {
  getPanelBoundsFromPositions,
  getGlobalBoundsFromPanels,
  computeViewStateFromBounds,
} from "./scatterViewState.js";

describe("scatterViewState bounds", () => {
  it("computes panel bounds from interleaved positions", () => {
    const pos = new Float32Array([1, 5, -2, 3, 4, -1]);
    const bounds = getPanelBoundsFromPositions(pos);
    expect(bounds).toEqual({ minX: -2, maxX: 4, minY: -1, maxY: 5 });
  });

  it("returns fallback bounds for empty input", () => {
    expect(getPanelBoundsFromPositions(null)).toEqual({
      minX: -1,
      maxX: 1,
      minY: -1,
      maxY: 1,
    });
  });

  it("computes global bounds across panels", () => {
    const panels = [
      { positions: new Float32Array([0, 0, 1, 1]) },
      { positions: new Float32Array([-5, 2, 3, -4]) },
    ];
    expect(getGlobalBoundsFromPanels(panels)).toEqual({
      minX: -5,
      maxX: 3,
      minY: -4,
      maxY: 2,
    });
  });
});

describe("scatterViewState camera", () => {
  it("centers on bounds midpoint and computes zoom", () => {
    const view = computeViewStateFromBounds({
      bounds: { minX: -2, maxX: 2, minY: -1, maxY: 3 },
      panelWidth: 800,
      panelHeight: 600,
      padding: 0.92,
      minZoom: -10,
      maxZoom: 30,
    });

    expect(view.target).toEqual([0, 1, 0]);
    // span is 4, minDim is 600 => log2((600*0.92)/4)
    expect(view.zoom).toBeCloseTo(Math.log2((600 * 0.92) / 4), 6);
    expect(view.baseZoom).toBeCloseTo(view.zoom, 6);
  });
});
