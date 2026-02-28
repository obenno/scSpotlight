import { describe, expect, it } from "vitest";
import { computePanelLayout } from "./scatterLayout.js";

describe("computePanelLayout", () => {
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

    expect(layout.nCols).toBe(2);
    expect(layout.nRows).toBe(3);
    expect(layout.isSquare).toBe(true);
    expect(layout.panelWidth).toBe(layout.panelHeight);
  });
});
