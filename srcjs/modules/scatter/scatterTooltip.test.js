import { describe, expect, it } from "vitest";
import { buildHoverText } from "./scatterTooltip.js";

const splitArrByMeta = (arr, by) => {
  const out = {};
  for (let i = 0; i < by.length; i++) {
    const key = by[i];
    if (!out[key]) out[key] = [];
    out[key].push(arr[i]);
  }
  return out;
};

const fmt = (v) => Number(v).toFixed(3);

describe("buildHoverText", () => {
  it("handles clusterOnly", () => {
    expect(
      buildHoverText({
        mode: "clusterOnly",
        panelIndex: 0,
        pointIndex: 1,
        groupByValues: ["A", "B"],
      }),
    ).toBe("Cat: B");
  });

  it("handles cluster+expr+noSplit", () => {
    expect(
      buildHoverText({
        mode: "cluster+expr+noSplit",
        panelIndex: 0,
        pointIndex: 0,
        groupByValues: ["A"],
        expressionValues: [1.2345],
        formatExpr: fmt,
      }),
    ).toBe("Cat: A");

    expect(
      buildHoverText({
        mode: "cluster+expr+noSplit",
        panelIndex: 1,
        pointIndex: 0,
        groupByValues: ["A"],
        expressionValues: [1.2345],
        formatExpr: fmt,
      }),
    ).toBe("Expr: 1.234");
  });

  it("handles split modes", () => {
    const common = {
      groupByValues: ["A", "B", "A", "B"],
      splitByValues: ["s1", "s1", "s2", "s2"],
      expressionValues: [0.1, 0.2, 1.1, 1.2],
      splitArrByMeta,
      formatExpr: fmt,
    };

    expect(
      buildHoverText({
        mode: "cluster+expr+twoSplit",
        panelIndex: 0,
        pointIndex: 1,
        ...common,
      }),
    ).toBe("Cat: B");

    expect(
      buildHoverText({
        mode: "cluster+expr+twoSplit",
        panelIndex: 1,
        pointIndex: 0,
        ...common,
      }),
    ).toBe("Expr: 0.100");

    expect(
      buildHoverText({
        mode: "cluster+multiSplit",
        panelIndex: 1,
        pointIndex: 0,
        ...common,
      }),
    ).toBe("Cat: A");

    expect(
      buildHoverText({
        mode: "cluster+expr+multiSplit",
        panelIndex: 1,
        pointIndex: 1,
        ...common,
      }),
    ).toBe("Expr: 1.200");
  });
});
