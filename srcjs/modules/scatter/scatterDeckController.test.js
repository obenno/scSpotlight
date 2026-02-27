import { describe, expect, it } from "vitest";
import { panelLayerFilter, resolveViewStateUpdate } from "./scatterDeckController.js";

describe("panelLayerFilter", () => {
  it("matches by explicit panelViewId when available", () => {
    const ok = panelLayerFilter({
      layer: { id: "panel_0_base", props: { panelViewId: "panel_1" } },
      viewport: { id: "panel_1" },
    });
    expect(ok).toBe(true);
  });

  it("falls back to id prefix match", () => {
    const ok = panelLayerFilter({
      layer: { id: "panel_2_hover_body", props: {} },
      viewport: { id: "panel_2" },
    });
    expect(ok).toBe(true);
  });
});

describe("resolveViewStateUpdate", () => {
  it("keeps target unchanged when not dragging", () => {
    const prev = { target: [1, 2, 0], zoom: 5, minZoom: -10, maxZoom: 30 };
    const next = { target: [10, 20, 0], zoom: 6, minZoom: -10, maxZoom: 30 };
    const out = resolveViewStateUpdate({
      prevState: prev,
      nextState: next,
      interactionState: { isZooming: true, isDragging: false },
      isRelayouting: false,
      zoomSensitivity: 0.5,
    });
    expect(out.next.target).toEqual([1, 2, 0]);
    expect(out.next.zoom).toBeCloseTo(5.5, 6);
  });

  it("skips passive update during relayout", () => {
    const prev = { target: [0, 0, 0], zoom: 4, minZoom: -10, maxZoom: 30 };
    const next = { target: [0, 0, 0], zoom: 8, minZoom: -10, maxZoom: 30 };
    const out = resolveViewStateUpdate({
      prevState: prev,
      nextState: next,
      interactionState: { isZooming: false, isDragging: false },
      isRelayouting: true,
      zoomSensitivity: 0.35,
    });
    expect(out.shouldApply).toBe(false);
    expect(out.next).toEqual(prev);
  });
});
