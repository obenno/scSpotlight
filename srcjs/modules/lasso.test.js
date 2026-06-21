import { describe, expect, it, vi } from "vitest";
import { LassoTool } from "./lasso.js";

function makeTool(overrides = {}) {
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
    ...overrides,
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

  it("selects points from non-origin high-cardinality split panels", () => {
    const onSelect = vi.fn();
    const onDeselect = vi.fn();
    const viewports = Array.from({ length: 12 }, (_, i) => ({
      id: `panel_${i}`,
      x: (i % 4) * 200,
      y: Math.floor(i / 4) * 200,
      width: 200,
      height: 200,
      project: ([x, y]) => [x, y],
    }));
    const positions = new Float32Array([
      20, 20,
      60, 60,
      160, 160,
    ]);
    const tool = makeTool({
      getViewports: () => viewports,
      getPanelPositions: (panelIdx) => (panelIdx === 10 ? positions : null),
      onSelect,
      onDeselect,
    });
    tool.path = [
      { x: 405, y: 405 },
      { x: 470, y: 405 },
      { x: 470, y: 470 },
      { x: 405, y: 470 },
    ];
    tool.active = true;
    tool.activeViewId = "panel_10";

    tool.handlePointerUp();

    expect(onSelect).toHaveBeenCalledWith("panel_10", [0, 1]);
    expect(onDeselect).not.toHaveBeenCalled();
  });

  it("clears selection for short or empty gestures", () => {
    const onDeselect = vi.fn();
    const tool = makeTool({ onDeselect });
    tool.path = [{ x: 1, y: 1 }, { x: 2, y: 2 }];
    tool.active = true;
    tool.activeViewId = "panel_0";

    tool.handlePointerUp();

    expect(onDeselect).toHaveBeenCalledTimes(1);
    expect(tool.active).toBe(false);
    expect(tool.activeViewId).toBe(null);
    expect(tool.path).toEqual([]);
  });
});
