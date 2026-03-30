import { describe, expect, it } from "vitest";
import { JSDOM } from "jsdom";
import {
  createLegendEntryElement,
  findIndexes,
  computeHighlightIndices,
} from "./scatterLegend.js";

const sortStringArray = (a, b) => String(a).localeCompare(String(b));

describe("scatterLegend utilities", () => {
  it("renders labels as text, not HTML", () => {
    const dom = new JSDOM("<!doctype html><html><body></body></html>");
    global.document = dom.window.document;
    const entry = createLegendEntryElement("<img src=x onerror=alert(1)>", "#ff0000", 7);
    const label = entry.querySelector(".legend-label");
    const count = entry.querySelector(".num-points");

    expect(label.innerHTML).toBe("&lt;img src=x onerror=alert(1)&gt;");
    expect(label.textContent).toBe("<img src=x onerror=alert(1)>");
    expect(count.textContent).toBe("7");

    delete global.document;
  });

  it("accepts hyphenated legend titles", () => {
    const dom = new JSDOM("<!doctype html><html><body></body></html>");
    global.document = dom.window.document;

    const hyphenated = createLegendEntryElement("CD4-T", "#ff0000", 2);

    expect(hyphenated.id).toBe("legend_CD4-T");
    expect(hyphenated.querySelector(".legend-label").textContent).toBe("CD4-T");

    delete global.document;
  });

  it("findIndexes returns matching indices", () => {
    expect(findIndexes([0, 1, 0, 2], 0)).toEqual([0, 2]);
    expect(findIndexes([1, 2, 3], 9)).toEqual([]);
  });

  it("computeHighlightIndices handles cluster+expr+twoSplit", () => {
    const pointsData = [
      { z: [0, 1, 0, 1] },
      { z: [0, 1, 0, 1] },
      { z: [1, 1, 0] },
      { z: [1, 1, 0] },
    ];

    const out = computeHighlightIndices({
      mode: "cluster+expr+twoSplit",
      pointsData,
      groupByValues: ["A", "B"],
      selectedGroupBy: "A",
      sortStringArray,
    });

    expect(out[0]).toEqual([0, 2]);
    expect(out[1]).toEqual([0, 2]);
    expect(out[2]).toEqual([2]);
    expect(out[3]).toEqual([2]);
  });
});
