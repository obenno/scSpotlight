import { describe, expect, it } from "vitest";
import { ScatterModel } from "./scatterModel.js";

function makeUtils() {
  const expandMeta = (x) => {
    if (Array.isArray(x)) return x;
    if (x && Array.isArray(x.value)) return x.value;
    return [];
  };

  const isMissingLevel = (value) => (
    value == null || String(value).trim() === "" || String(value) === "undefined"
  );
  const sortStringArray = (a, b) => String(a).localeCompare(String(b));
  const getMetaLevels = (x) => [...new Set(expandMeta(x))]
    .filter((value) => !isMissingLevel(value))
    .sort(sortStringArray);

  const splitArrByMeta = (arr, by) => {
    const out = {};
    for (let i = 0; i < by.length; i++) {
      const key = by[i];
      if (isMissingLevel(key)) continue;
      if (!out[key]) out[key] = [];
      out[key].push(arr[i]);
    }
    return out;
  };

  const convert_stringArr_to_integer = (arr) => {
    const levels = [...new Set(arr)].filter((value) => !isMissingLevel(value)).sort(sortStringArray);
    const map = new Map(levels.map((x, i) => [x, i]));
    return Int16Array.from(arr.map((x) => map.get(x) ?? -1));
  };

  const hue_pal = (n) => {
    const out = [];
    for (let i = 0; i < n; i++) {
      const h = Math.round((i / Math.max(1, n)) * 360);
      out.push(`hsl(${h}, 70%, 45%)`);
    }
    return out;
  };

  const rgbToHex = (rgbString) => {
    const m = /rgb\((\d+),\s*(\d+),\s*(\d+)\)/.exec(String(rgbString));
    if (!m) return "#808080";
    const toHex = (x) => Number(x).toString(16).padStart(2, "0");
    return `#${toHex(m[1])}${toHex(m[2])}${toHex(m[3])}`;
  };

  return {
    expandMeta,
    getMetaLevels,
    sortStringArray,
    splitArrByMeta,
    convert_stringArr_to_integer,
    hue_pal,
    rgbToHex,
  };
}

function createFixture() {
  const cells = ["c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8"];
  return {
    reductionData: {
      X: [0, 1, 2, 3, 4, 5, 6, 7],
      Y: [7, 6, 5, 4, 3, 2, 1, 0],
    },
    cellMetaData: {
      cells: { value: cells },
      group: {
        value: ["A", "A", "B", "B", "A", "B", "A", "B"],
      },
      split: {
        value: [
          "healthy",
          "healthy",
          "healthy",
          "healthy",
          "patient",
          "patient",
          "patient",
          "patient",
        ],
      },
      split3: {
        value: ["s1", "s1", "s2", "s2", "s3", "s3", "s3", "s3"],
      },
      splitMissing: {
        value: ["s1", "", "s2", undefined, "undefined", null, "s1", "s2"],
      },
      groupMissing: {
        value: ["A", "", "B", undefined, "undefined", null, "A", "B"],
      },
    },
    expressionData: {
      GeneA: [0.1, 0.2, 0.3, 0.4, 3.1, 3.2, 3.3, 3.4],
      GeneB: [9, 8, 7, 6, 5, 4, 3, 2],
    },
    pcaStdev: [4.2, 2.8, 1.6, 1.1],
  };
}

function buildModel() {
  const model = new ScatterModel({ utils: makeUtils() });
  model.setData(createFixture());
  return model;
}

describe("ScatterModel mode derivation", () => {
  it("merges metadata patches without replacing existing columns", () => {
    const model = buildModel();
    model.setData({
      cellMetaDataPatch: {
        Phase: {
          type: "category",
          value: ["G1", "S", "G2M", "G1", "S", "G2M", "G1", "S"],
        },
      },
    });

    expect(model.origData.cellMetaData.group).toBeDefined();
    expect(model.origData.cellMetaData.cells).toBeDefined();
    expect(model.origData.cellMetaData.Phase).toBeDefined();
    expect(model.origData.cellMetaData.Phase.value[0]).toBe("G1");
  });

  it("rejects metadata patches with mismatched length", () => {
    const model = buildModel();
    expect(() => {
      model.setData({
        cellMetaDataPatch: {
          Phase: { type: "category", value: ["G1", "S"] },
        },
      });
    }).toThrow(/length mismatch/);
  });

  it("rejects metadata patches with mismatched type", () => {
    const model = buildModel();
    model.origData.cellMetaData.group.type = "category";
    expect(() => {
      model.setData({
        cellMetaDataPatch: {
          group: { type: "number", value: [1, 1, 2, 2, 1, 2, 1, 2] },
        },
      });
    }).toThrow(/type mismatch/);
  });

  it("stores PCA standard deviations as typed array data", () => {
    const model = buildModel();
    expect(model.origData.pcaStdev).toBeInstanceOf(Float32Array);
    expect(Array.from(model.origData.pcaStdev)).toHaveLength(4);
    expect(model.origData.pcaStdev[0]).toBeCloseTo(4.2);
    expect(model.origData.pcaStdev[1]).toBeCloseTo(2.8);
    expect(model.origData.pcaStdev[2]).toBeCloseTo(1.6);
    expect(model.origData.pcaStdev[3]).toBeCloseTo(1.1);
  });

  it("uses clusterOnly when no feature and no split", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: [], moduleScore: false });
    const meta = model.derivePlotMetaData("group", null, false);
    expect(meta.mode).toBe("clusterOnly");
    expect(meta.nPanels).toBe(1);
  });

  it("uses cluster+expr+noSplit when one feature and no split", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: ["GeneA"], moduleScore: false });
    const meta = model.derivePlotMetaData("group", null, false);
    expect(meta.mode).toBe("cluster+expr+noSplit");
    expect(meta.nPanels).toBe(2);
  });

  it("uses cluster+expr+twoSplit when one feature and two split levels", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: ["GeneA"], moduleScore: false });
    const meta = model.derivePlotMetaData("group", "split", false);
    expect(meta.mode).toBe("cluster+expr+twoSplit");
    expect(meta.nPanels).toBe(4);
  });

  it("uses cluster+multiSplit when no feature and multiple split levels", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: [], moduleScore: false });
    const meta = model.derivePlotMetaData("group", "split", false);
    expect(meta.mode).toBe("cluster+multiSplit");
    expect(meta.nPanels).toBe(2);
  });

  it("uses cluster+expr+multiSplit when one feature and >2 split levels", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: ["GeneA"], moduleScore: false });
    const meta = model.derivePlotMetaData("group", "split3", false);
    expect(meta.mode).toBe("cluster+expr+multiSplit");
    expect(meta.nPanels).toBe(3);
  });

  it("ignores missing split levels when deriving mode and panel count", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: ["GeneA"], moduleScore: false });
    const meta = model.derivePlotMetaData("group", "splitMissing", false);
    expect(meta.mode).toBe("cluster+expr+twoSplit");
    expect(meta.nPanels).toBe(4);
  });

  it("uses the first selected feature when multiple features are present", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: ["GeneA", "GeneB"], moduleScore: false });
    const meta = model.derivePlotMetaData("group", null, false);
    expect(meta.mode).toBe("cluster+expr+noSplit");
    expect(meta.nPanels).toBe(2);
    const plot = model.buildPlotData();
    expect(plot.plotFeature).toBe("GeneA");
    expect(plot.panelTitles[1]).toBe("GeneA");
    expect(Array.from(plot.pointsData[1].z)).toEqual(
      Array.from(model.scaleDataZ(model.origData.expressionData.GeneA)),
    );
    expect(Array.from(plot.pointsData[1].z)).not.toEqual(
      Array.from(model.scaleDataZ(model.origData.expressionData.GeneB)),
    );
  });
});

describe("ScatterModel panel data assembly", () => {
  it("keeps cell ids indexable in no-split expression mode", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: ["GeneA"], moduleScore: false });
    model.derivePlotMetaData("group", null, false);
    const plot = model.buildPlotData();

    expect(plot.pointsData).toHaveLength(2);
    expect(plot.cells[0]).toEqual(["c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8"]);
    expect(plot.cells[1]).toEqual(plot.cells[0]);
    expect(plot.cells[0][3]).toBe("c4");
  });

  it("builds 2 split-by panels with grouped colors", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: [], moduleScore: false });
    model.derivePlotMetaData("group", "split", false);
    const plot = model.buildPlotData();

    expect(plot.pointsData).toHaveLength(2);
    expect(plot.panelTitles).toHaveLength(2);
    expect(plot.pointsData[0].x.length).toBe(4);
    expect(plot.pointsData[1].x.length).toBe(4);
    expect(plot.pointsData[0].x).toBeInstanceOf(Float32Array);
    expect(plot.pointsData[0].y).toBeInstanceOf(Float32Array);
    expect(plot.pointsData[1].x).toBeInstanceOf(Float32Array);
    expect(plot.pointsData[1].y).toBeInstanceOf(Float32Array);
    expect(plot.zType.every((z) => z === "category")).toBe(true);
    expect(plot.cells[0]).toHaveLength(4);
    expect(plot.cells[1]).toHaveLength(4);

    // split.by panel mapping should preserve the correct cell subsets
    expect(plot.panelTitles).toEqual(["healthy", "patient"]);
    expect(plot.cells[0]).toEqual(["c1", "c2", "c3", "c4"]);
    expect(plot.cells[1]).toEqual(["c5", "c6", "c7", "c8"]);
    expect(Array.from(plot.pointsData[0].z)).toEqual([0, 0, 1, 1]);
    expect(Array.from(plot.pointsData[1].z)).toEqual([0, 1, 0, 1]);

    // category labels should map to group names, not integer ids
    const panel0Labels = (plot.catLabelCoordinates[0] || []).map((d) => d.label).sort();
    expect(panel0Labels).toEqual(["A", "B"]);
  });

  it("builds 4 panels for two-split expression mode", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: ["GeneA"], moduleScore: false });
    model.derivePlotMetaData("group", "split", false);
    const plot = model.buildPlotData();

    expect(plot.pointsData).toHaveLength(4);
    plot.pointsData.forEach((panel) => {
      expect(panel.x).toBeInstanceOf(Float32Array);
      expect(panel.y).toBeInstanceOf(Float32Array);
    });
    expect(plot.pointsData[1].z).toBeInstanceOf(Float32Array);
    expect(plot.pointsData[3].z).toBeInstanceOf(Float32Array);
    expect(plot.zType).toEqual(["category", "expr", "category", "expr"]);
    expect(plot.pointsData[0].x.length).toBe(4);
    expect(plot.pointsData[1].x.length).toBe(4);
    expect(plot.pointsData[2].x.length).toBe(4);
    expect(plot.pointsData[3].x.length).toBe(4);

    // cluster/expr pair panels must refer to the same split-by subset
    expect(plot.cells[0]).toEqual(plot.cells[1]);
    expect(plot.cells[2]).toEqual(plot.cells[3]);
    expect(plot.panelTitles[0]).toContain("healthy");
    expect(plot.panelTitles[2]).toContain("patient");
  });

  it("builds expression multi-split panels with sorted split levels", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: ["GeneA"], moduleScore: false });
    model.derivePlotMetaData("group", "split3", false);
    const plot = model.buildPlotData();

    expect(plot.panelTitles).toEqual(["s1", "s2", "s3"]);
    expect(plot.pointsData).toHaveLength(3);
    expect(plot.cells[0]).toEqual(["c1", "c2"]);
    expect(plot.cells[1]).toEqual(["c3", "c4"]);
    expect(plot.cells[2]).toEqual(["c5", "c6", "c7", "c8"]);

    // each split panel scales expression independently into a bounded 0-1 range
    const zS1 = Array.from(plot.pointsData[0].z);
    const zS2 = Array.from(plot.pointsData[1].z);
    const zS3 = Array.from(plot.pointsData[2].z);

    expect(zS1[0]).toBeLessThan(zS1[1]);
    expect(zS2[0]).toBeLessThan(zS2[1]);

    const allZ = [...zS1, ...zS2, ...zS3];
    allZ.forEach((z) => {
      expect(z).toBeGreaterThanOrEqual(0);
      expect(z).toBeLessThanOrEqual(1);
    });

    expect(zS3[0]).toBeLessThan(zS3[1]);
    expect(zS3[1]).toBeLessThan(zS3[2]);
    expect(zS3[2]).toBeLessThan(zS3[3]);
  });

  it("filters missing category and split levels from titles, labels, and cell subsets", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: ["GeneA"], moduleScore: false });
    model.derivePlotMetaData("groupMissing", "splitMissing", false);
    const plot = model.buildPlotData();

    expect(plot.panelTitles).toEqual([
      "s1 : groupMissing",
      "s1 : GeneA",
      "s2 : groupMissing",
      "s2 : GeneA",
    ]);
    expect(plot.cells[0]).toEqual(["c1", "c7"]);
    expect(plot.cells[1]).toEqual(plot.cells[0]);
    expect(plot.cells[2]).toEqual(["c3", "c8"]);
    expect(plot.cells[3]).toEqual(plot.cells[2]);
    expect(plot.zType).toEqual(["category", "expr", "category", "expr"]);

    const categoryLabels = plot.catLabelCoordinates
      .flatMap((coords) => coords || [])
      .map((coord) => coord.label)
      .sort();
    expect(categoryLabels).toEqual(["A", "B"]);
    expect(plot.catLabelCoordinates[1]).toBeUndefined();
    expect(plot.catLabelCoordinates[3]).toBeUndefined();
  });

  it("uses first selected gene for multi-split expression panels", () => {
    const model = buildModel();
    model.setConfig({ selectedFeatures: ["GeneA", "GeneB"], moduleScore: false });
    model.derivePlotMetaData("group", "split3", false);
    const plot = model.buildPlotData();

    expect(plot.plotFeature).toBe("GeneA");
    expect(plot.zType).toEqual(["expr", "expr", "expr"]);
    expect(plot.catLabelCoordinates).toEqual([]);
  });

  it("maps constant expression values to low-end color scale", () => {
    const model = buildModel();
    const scaled = model.scaleDataZ([0, 0, 0, 0]);
    expect(scaled).toBeInstanceOf(Float32Array);
    expect(Array.from(scaled)).toEqual([0, 0, 0, 0]);

    const scaledNonZeroConstant = model.scaleDataZ([5, 5, 5]);
    expect(scaledNonZeroConstant).toBeInstanceOf(Float32Array);
    expect(Array.from(scaledNonZeroConstant)).toEqual([0, 0, 0]);
  });

  it("accepts typed arrays for expression scaling", () => {
    const model = buildModel();
    const scaled = model.scaleDataZ(new Float32Array([0, 5, 10]));
    expect(scaled).toBeInstanceOf(Float32Array);
    expect(scaled).toHaveLength(3);
    expect(scaled[0]).toBeLessThan(scaled[1]);
    expect(scaled[1]).toBeLessThan(scaled[2]);
    scaled.forEach((z) => {
      expect(z).toBeGreaterThanOrEqual(0);
      expect(z).toBeLessThanOrEqual(1);
    });
  });

  it("anchors expression scaling at zero", () => {
    const model = buildModel();
    const scaled = model.scaleDataZ(new Float32Array([2, 4, 8]));
    expect(scaled[0]).toBeCloseTo(0.25, 3);
    expect(scaled[1]).toBeCloseTo(0.5, 3);
    expect(scaled[2]).toBeCloseTo(1, 3);
  });

  it("preserves mixed-sign expression variation", () => {
    const model = buildModel();
    const scaled = model.scaleDataZ(new Float32Array([-2, -1, 0, 1, 2]));
    expect(scaled).toBeInstanceOf(Float32Array);
    expect(scaled[0]).toBeCloseTo(0, 3);
    expect(scaled[1]).toBeCloseTo(0.25, 3);
    expect(scaled[2]).toBeCloseTo(0.5, 3);
    expect(scaled[3]).toBeCloseTo(0.75, 3);
    expect(scaled[4]).toBeCloseTo(1, 3);
  });
});
