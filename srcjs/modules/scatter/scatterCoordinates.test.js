import { describe, expect, it } from "vitest";
import {
  projectWorldToPanel,
  projectWorldToCanvas,
  parsePanelIndexFromPickInfo,
} from "./scatterCoordinates.js";

function makeViewport({ x = 10, y = 20, width = 100, height = 80, project, unproject }) {
  return {
    x,
    y,
    width,
    height,
    project,
    unproject,
  };
}

describe("scatterCoordinates projection", () => {
  it("keeps local projection coordinates as panel-local", () => {
    const vp = makeViewport({
      x: 0,
      y: 0,
      project: () => [30, 40],
      unproject: ([x, y]) => [x / 30, y / 20],
    });
    expect(projectWorldToPanel(vp, 1, 2)).toEqual([30, 40]);
    expect(projectWorldToCanvas(vp, 1, 2)).toEqual([30, 40]);
  });

  it("converts global projection coordinates to panel-local", () => {
    const vp = makeViewport({
      project: () => [130, 220],
      unproject: ([x, y]) => [x / 120, y / 100],
    });
    expect(projectWorldToPanel(vp, 1, 2)).toEqual([120, 200]);
    expect(projectWorldToCanvas(vp, 1, 2)).toEqual([130, 220]);
  });

  it("treats ambiguous in-bounds second-panel coordinates as canvas-global", () => {
    const vp = makeViewport({
      x: 100,
      y: 0,
      width: 500,
      height: 400,
      project: () => [150, 80],
      unproject: ([x, y]) => [x / 50, y / 40],
    });
    expect(projectWorldToPanel(vp, 1, 2)).toEqual([50, 80]);
    expect(projectWorldToCanvas(vp, 1, 2)).toEqual([150, 80]);
  });

  it("keeps panned split-panel projections panel-local by subtracting viewport offset", () => {
    const vp = makeViewport({
      x: 300,
      y: 0,
      width: 300,
      height: 240,
      project: () => [150, 80],
      unproject: ([x, y]) => [x / -150, y / 40],
    });
    expect(projectWorldToPanel(vp, 1, 2)).toEqual([-150, 80]);
    expect(projectWorldToCanvas(vp, 1, 2)).toEqual([150, 80]);
  });
});

describe("scatterCoordinates panel index parsing", () => {
  it("prefers panelViewId from layer props", () => {
    const info = { layer: { props: { panelViewId: "panel_3" }, id: "panel_1_base" } };
    expect(parsePanelIndexFromPickInfo(info)).toBe(3);
  });

  it("falls back to layer id and then viewport id", () => {
    const fromLayerId = { layer: { id: "panel_2_hover_body" } };
    expect(parsePanelIndexFromPickInfo(fromLayerId)).toBe(2);

    const fromViewport = { viewport: { id: "panel_5" } };
    expect(parsePanelIndexFromPickInfo(fromViewport)).toBe(5);
  });

  it("returns NaN when no panel information is available", () => {
    expect(Number.isNaN(parsePanelIndexFromPickInfo({}))).toBe(true);
  });
});
