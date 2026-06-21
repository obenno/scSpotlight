/**
 * @vitest-environment jsdom
 */

import { beforeEach, describe, expect, it, vi } from "vitest";
import { createSparkLine, updateSparkLine } from "./featureSparkLine.js";

vi.mock("jquery-sparkline", () => ({}));

const testState = {
  inputs: [],
  selectionEvents: 0,
};

const installSparklineStub = () => {
  globalThis.$ = vi.fn((selector) => ({
    sparkline: vi.fn(() => {
      const target = selector.startsWith("#")
        ? document.getElementById(selector.slice(1))
        : document.querySelector(selector);
      if (target && !target.querySelector("canvas")) {
        target.appendChild(document.createElement("canvas"));
      }
    }),
  }));
};

const installShinyStub = () => {
  globalThis.Shiny = {
    setInputValue: (...args) => {
      testState.inputs.push(args);
    },
  };
};

const latestInputValue = (name) => {
  const found = [...testState.inputs].reverse().find(([inputName]) => inputName === name);
  return found?.[1];
};

const makeReglState = () => ({
  plotMetaData: {
    selectedFeatures: [],
  },
  origData: {
    expressionData: {
      GeneA: new Float32Array([0, 1, 2, 3]),
      GeneB: new Float32Array([3, 2, 1, 0]),
      GeneC: new Float32Array([2, 2, 2, 2]),
    },
  },
});

const appendUpdatedSparkLine = (feature, reglState) => {
  const container = createSparkLine(feature);
  document.body.appendChild(container);
  updateSparkLine(container, () => reglState);
  return container;
};

const geneLabel = (container) => container.querySelector(".feature-gene-symbol");

describe("feature sparkline first-selected-gene state", () => {
  beforeEach(() => {
    document.body.innerHTML = "";
    testState.inputs = [];
    testState.selectionEvents = 0;
    installSparklineStub();
    installShinyStub();
    window.addEventListener("scspotlight:featurePlotSelectionChanged", () => {
      testState.selectionEvents += 1;
    }, { once: true });
  });

  it("creates accessible, escaped sparkline labels", () => {
    const container = createSparkLine("Gene<unsafe>");

    expect(container.classList.contains("featureSparkLine")).toBe(true);
    expect(container.getAttribute("role")).toBe("button");
    expect(container.getAttribute("tabindex")).toBe("0");
    expect(container.getAttribute("aria-pressed")).toBe("false");
    expect(geneLabel(container).textContent).toBe("Gene<unsafe>");
    expect(geneLabel(container).innerHTML).toBe("Gene&lt;unsafe&gt;");
  });

  it("keeps checked order and emphasizes only selectedFeatures[0]", () => {
    const reglState = makeReglState();
    const geneA = appendUpdatedSparkLine("GeneA", reglState);
    const geneB = appendUpdatedSparkLine("GeneB", reglState);
    const geneC = appendUpdatedSparkLine("GeneC", reglState);

    geneB.click();
    geneA.click();

    expect(reglState.plotMetaData.selectedFeatures).toEqual(["GeneB", "GeneA"]);
    expect(latestInputValue("selectedFeatures")).toEqual(["GeneB", "GeneA"]);
    expect(geneLabel(geneB).getAttribute("data-primary")).toBe("true");
    expect(geneLabel(geneB).style.fontWeight).toBe("600");
    expect(geneB.getAttribute("aria-current")).toBe("true");
    expect(geneA.getAttribute("aria-current")).toBe("false");
    expect(geneLabel(geneA).getAttribute("data-primary")).toBe("false");
    expect(geneC.getAttribute("aria-current")).toBe("false");

    geneB.click();

    expect(reglState.plotMetaData.selectedFeatures).toEqual(["GeneA"]);
    expect(latestInputValue("selectedFeatures")).toEqual(["GeneA"]);
    expect(geneB.getAttribute("data-status")).toBe("ready");
    expect(geneB.getAttribute("aria-pressed")).toBe("false");
    expect(geneA.getAttribute("aria-current")).toBe("true");
    expect(geneLabel(geneA).style.fontWeight).toBe("600");
    expect(geneLabel(geneB).style.fontWeight).toBe("400");
  });

  it("preserves existing checked state when refreshing a loaded sparkline", () => {
    const reglState = makeReglState();
    reglState.plotMetaData.selectedFeatures = ["GeneA", "GeneB"];
    const geneA = appendUpdatedSparkLine("GeneA", reglState);
    const geneB = appendUpdatedSparkLine("GeneB", reglState);

    expect(geneA.getAttribute("data-status")).toBe("checked");
    expect(geneA.getAttribute("aria-pressed")).toBe("true");
    expect(geneA.getAttribute("aria-current")).toBe("true");
    expect(geneB.getAttribute("data-status")).toBe("checked");
    expect(geneB.getAttribute("aria-pressed")).toBe("true");
    expect(geneB.getAttribute("aria-current")).toBe("false");

    updateSparkLine(geneB, () => reglState);

    expect(reglState.plotMetaData.selectedFeatures).toEqual(["GeneA", "GeneB"]);
    expect(geneB.getAttribute("data-status")).toBe("checked");
    expect(geneB.getAttribute("aria-pressed")).toBe("true");
    expect(geneB.getAttribute("aria-current")).toBe("false");
  });

  it("supports keyboard toggling without changing first-gene semantics", () => {
    const reglState = makeReglState();
    const geneA = appendUpdatedSparkLine("GeneA", reglState);
    const geneB = appendUpdatedSparkLine("GeneB", reglState);

    geneA.dispatchEvent(new KeyboardEvent("keydown", { key: " ", bubbles: true }));
    geneB.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));

    expect(reglState.plotMetaData.selectedFeatures).toEqual(["GeneA", "GeneB"]);
    expect(geneA.getAttribute("aria-current")).toBe("true");
    expect(geneB.getAttribute("aria-current")).toBe("false");
  });
});
