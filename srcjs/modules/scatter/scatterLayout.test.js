import { describe, expect, it } from "vitest";
import { computePanelGrid, computePanelLayout, resolveMinPanelSize } from "./scatterLayout.js";

describe("computePanelLayout", () => {
  it("shrinks min panel size for very high panel counts", () => {
    expect(resolveMinPanelSize(1)).toBe(400);
    expect(resolveMinPanelSize(11)).toBe(400);
    expect(resolveMinPanelSize(12)).toBe(320);
    expect(resolveMinPanelSize(23)).toBe(320);
    expect(resolveMinPanelSize(24)).toBe(280);
    expect(resolveMinPanelSize(47)).toBe(280);
    expect(resolveMinPanelSize(48)).toBe(240);
    expect(resolveMinPanelSize(71)).toBe(240);
    expect(resolveMinPanelSize(72)).toBe(200);
    expect(resolveMinPanelSize(95)).toBe(200);
    expect(resolveMinPanelSize(96)).toBe(180);
  });

  it("uses a balanced multi-column grid for many panels", () => {
    const grid = computePanelGrid({
      nPanels: 24,
      containerWidth: 1600,
      containerHeight: 900,
      gap: 4,
      minPanelSize: 400,
    });

    expect(grid.nCols).toBeGreaterThan(2);
    expect(grid.nRows).toBeLessThan(12);
  });

  it("uses one column for single panel and no square constraint", () => {
    const layout = computePanelLayout({
      nPanels: 1,
      containerWidth: 1200,
      containerHeight: 700,
      gap: 4,
    });

    expect(layout.nCols).toBe(1);
    expect(layout.nRows).toBe(1);
    expect(layout.isSquare).toBe(false);
    expect(layout.gridTemplateColumns).toBe("repeat(1, 1200px)");
  });

  it("uses half viewport width for 2 panels when wide enough", () => {
    const layout = computePanelLayout({
      nPanels: 2,
      containerWidth: 1200,
      containerHeight: 700,
      gap: 4,
      minPanelSize: 400,
    });

    expect(layout.nCols).toBe(2);
    expect(layout.nRows).toBe(1);
    expect(layout.isSquare).toBe(false);
    expect(layout.panelWidth).toBe(598);
  });

  it("falls back to min width when viewport is narrow", () => {
    const layout = computePanelLayout({
      nPanels: 2,
      containerWidth: 700,
      containerHeight: 700,
      gap: 4,
      minPanelSize: 400,
    });

    expect(layout.panelWidth).toBe(400);
    expect(layout.contentWidth).toBe(804);
  });

  it("enforces square panels for multi-row layouts", () => {
    const layout = computePanelLayout({
      nPanels: 5,
      containerWidth: 1300,
      containerHeight: 900,
      gap: 4,
      minPanelSize: 400,
    });

    expect(layout.nCols).toBe(3);
    expect(layout.nRows).toBe(2);
    expect(layout.isSquare).toBe(true);
    expect(layout.panelWidth).toBe(layout.panelHeight);
  });

  it("widens the grid for high panel counts", () => {
    const layout = computePanelLayout({
      nPanels: 24,
      containerWidth: 1600,
      containerHeight: 900,
      gap: 4,
      minPanelSize: 400,
    });

    expect(layout.nCols).toBeGreaterThan(2);
    expect(layout.nRows).toBeLessThan(12);
  });

  it("keeps high-cardinality layouts from exploding in size", () => {
    const layout = computePanelLayout({
      nPanels: 72,
      containerWidth: 1600,
      containerHeight: 900,
      gap: 4,
    });

    expect(layout.panelWidth).toBeLessThan(280);
    expect(layout.contentWidth).toBeLessThan(3000);
    expect(layout.contentHeight).toBeLessThan(3000);
  });

  it("uses scrollable content instead of shrinking below the adaptive minimum", () => {
    const layout = computePanelLayout({
      nPanels: 24,
      containerWidth: 500,
      containerHeight: 500,
      gap: 4,
    });

    expect(layout.panelWidth).toBe(resolveMinPanelSize(24));
    expect(layout.panelHeight).toBe(resolveMinPanelSize(24));
    expect(layout.contentWidth).toBeGreaterThan(500);
    expect(layout.contentHeight).toBeGreaterThan(500);
  });
});
