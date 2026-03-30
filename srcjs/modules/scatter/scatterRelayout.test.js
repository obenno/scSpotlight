import { describe, expect, it } from "vitest";
import { getPanelViewRects, hasInvalidPanelRects } from "./scatterRelayout.js";

function makePanel({ clientWidth, clientHeight, offsetLeft, offsetTop }) {
  return {
    clientWidth,
    clientHeight,
    offsetLeft,
    offsetTop,
    getBoundingClientRect() {
      return {
        left: offsetLeft,
        top: offsetTop,
        width: clientWidth,
        height: clientHeight,
      };
    },
  };
}

describe("scatterRelayout", () => {
  it("builds panel view rects from measured panel sizes", () => {
    const rects = getPanelViewRects({
      panelEls: [
        makePanel({ clientWidth: 500, clientHeight: 400, offsetLeft: 0, offsetTop: 0 }),
        makePanel({ clientWidth: 500, clientHeight: 400, offsetLeft: 504, offsetTop: 0 }),
      ],
      nCols: 2,
      nRows: 1,
      fallbackPanelWidth: 300,
      fallbackPanelHeight: 300,
    });

    expect(rects).toHaveLength(2);
    expect(rects[0]).toMatchObject({ viewId: "panel_0", x: 0, y: 0, width: 500, height: 400 });
    expect(rects[1]).toMatchObject({ viewId: "panel_1", x: 504, y: 0, width: 500, height: 400 });
    expect(hasInvalidPanelRects(rects)).toBe(false);
  });

  it("uses fallback positioning/sizing when panel size is unavailable", () => {
    const rects = getPanelViewRects({
      panelEls: [
        makePanel({ clientWidth: 0, clientHeight: 0, offsetLeft: 0, offsetTop: 0 }),
        makePanel({ clientWidth: 0, clientHeight: 0, offsetLeft: 0, offsetTop: 0 }),
        makePanel({ clientWidth: 0, clientHeight: 0, offsetLeft: 0, offsetTop: 0 }),
      ],
      nCols: 2,
      nRows: 2,
      fallbackPanelWidth: 450,
      fallbackPanelHeight: 450,
    });

    expect(rects[0]).toMatchObject({ x: 0, y: 0, width: 450, height: 450 });
    expect(rects[1]).toMatchObject({ x: 450, y: 0, width: 450, height: 450 });
    expect(rects[2]).toMatchObject({ x: 0, y: 450, width: 450, height: 450 });
    expect(hasInvalidPanelRects(rects)).toBe(true);
  });

  it("measures panel rects relative to the deck container", () => {
    const rects = getPanelViewRects({
      panelEls: [
        makePanel({ clientWidth: 500, clientHeight: 400, offsetLeft: 120, offsetTop: 80 }),
        makePanel({ clientWidth: 500, clientHeight: 400, offsetLeft: 624, offsetTop: 80 }),
      ],
      nCols: 2,
      nRows: 1,
      fallbackPanelWidth: 300,
      fallbackPanelHeight: 300,
      referenceEl: {
        getBoundingClientRect() {
          return { left: 120, top: 80, width: 1000, height: 400 };
        },
      },
    });

    expect(rects[0]).toMatchObject({ x: 0, y: 0, width: 500, height: 400 });
    expect(rects[1]).toMatchObject({ x: 504, y: 0, width: 500, height: 400 });
  });
});
