/**
 * @vitest-environment jsdom
 */
import { describe, expect, it } from "vitest";
import {
  setLabelCanvasVisibility,
  setPanelOverlayVisibility,
  setResizeBlankVisibility,
} from "./scatterDOMState.js";

function makePlotEl() {
  const root = document.createElement("div");

  const deck = document.createElement("div");
  deck.id = "deck-container";
  root.appendChild(deck);

  const crosshair = document.createElement("canvas");
  crosshair.id = "crosshair-underlay";
  root.appendChild(crosshair);

  const lasso = document.createElement("canvas");
  lasso.id = "lasso-overlay";
  root.appendChild(lasso);

  const grid = document.createElement("div");
  grid.className = "deck-overlay-grid";
  root.appendChild(grid);

  const title = document.createElement("div");
  title.className = "mainClusterPlotTitle";
  root.appendChild(title);

  const label = document.createElement("canvas");
  label.className = "label-canvas";
  root.appendChild(label);

  return root;
}

describe("scatterDOMState", () => {
  it("toggles label visibility", () => {
    const plotEl = makePlotEl();
    setLabelCanvasVisibility(plotEl, false);
    expect(plotEl.querySelector(".label-canvas").style.opacity).toBe("0");
    setLabelCanvasVisibility(plotEl, true);
    expect(plotEl.querySelector(".label-canvas").style.opacity).toBe("1");
  });

  it("toggles panel overlay visibility", () => {
    const plotEl = makePlotEl();
    setPanelOverlayVisibility(plotEl, false);
    expect(plotEl.querySelector(".deck-overlay-grid").style.opacity).toBe("0");
    expect(plotEl.querySelector(".mainClusterPlotTitle").style.opacity).toBe("0");
    expect(plotEl.querySelector(".label-canvas").style.opacity).toBe("0");

    setPanelOverlayVisibility(plotEl, true);
    expect(plotEl.querySelector(".deck-overlay-grid").style.opacity).toBe("1");
    expect(plotEl.querySelector(".mainClusterPlotTitle").style.opacity).toBe("1");
    expect(plotEl.querySelector(".label-canvas").style.opacity).toBe("1");
  });

  it("toggles full resize blank visibility state", () => {
    const plotEl = makePlotEl();
    setResizeBlankVisibility(plotEl, true);
    expect(plotEl.querySelector("#deck-container").style.opacity).toBe("0");
    expect(plotEl.querySelector("#crosshair-underlay").style.opacity).toBe("0");
    expect(plotEl.querySelector("#lasso-overlay").style.opacity).toBe("0");
    expect(plotEl.querySelector(".deck-overlay-grid").style.opacity).toBe("0");

    setResizeBlankVisibility(plotEl, false);
    expect(plotEl.querySelector("#deck-container").style.opacity).toBe("1");
    expect(plotEl.querySelector("#crosshair-underlay").style.opacity).toBe("1");
    expect(plotEl.querySelector("#lasso-overlay").style.opacity).toBe("1");
    expect(plotEl.querySelector(".deck-overlay-grid").style.opacity).toBe("1");
  });
});
