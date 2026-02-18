import { describe, expect, it } from "vitest";
import {
  findIndexes,
  computeHighlightIndices,
} from "./scatterLegend.js";

const sortStringArray = (a, b) => String(a).localeCompare(String(b));

describe("scatterLegend utilities", () => {
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
