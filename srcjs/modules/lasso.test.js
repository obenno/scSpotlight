import { describe, expect, it, vi } from "vitest";
import { LassoTool } from "./lasso.js";

function makeTool() {
  const container = {
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    getBoundingClientRect: () => ({ left: 0, top: 0 }),
  };
  const overlayCanvas = {
    width: 1000,
    height: 800,
    getContext: () => ({ clearRect: vi.fn(), save: vi.fn(), restore: vi.fn(), beginPath: vi.fn(), moveTo: vi.fn(), lineTo: vi.fn(), stroke: vi.fn() }),
  };

  return new LassoTool({
    container,
    overlayCanvas,
    getViewports: () => [],
    getPanelPositions: () => null,
    onSelect: vi.fn(),
    onDeselect: vi.fn(),
  });
}

describe("LassoTool", () => {
  it("tests polygon hits in canvas coordinates for offset viewports", () => {
    const tool = makeTool();
    const viewport = {
      x: 400,
      y: 0,
      width: 400,
      height: 400,
      project: () => [20, 20],
    };
    const positions = new Float32Array([1, 2]);
    const polygon = [
      { x: 410, y: 10 },
      { x: 450, y: 10 },
      { x: 450, y: 50 },
      { x: 410, y: 50 },
    ];

    expect(tool.pickPointsInPolygon(positions, viewport, polygon)).toEqual([0]);
  });
});
