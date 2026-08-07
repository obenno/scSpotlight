import { describe, expect, it } from "vitest";
import {
  tableFromArrays,
  tableToIPC,
  Dictionary,
  Utf8,
  Int8,
  Float32,
  makeBuilder,
} from "apache-arrow";
import {
  readArrowIPC,
  getFloat32Column,
  parseMetaFromArrow,
} from "./arrowReader.js";

/**
 * Build an Arrow IPC buffer from column arrays for testing.
 */
function makeIPCBuffer(columns) {
  const table = tableFromArrays(columns);
  return tableToIPC(table, "stream");
}

describe("getFloat32Column", () => {
  it("extracts a Float32Array from a table with float32 columns", () => {
    const table = tableFromArrays({
      X: Float32Array.from([1.0, 2.0, 3.0]),
      Y: Float32Array.from([4.0, 5.0, 6.0]),
    });
    const x = getFloat32Column(table, "X");
    expect(x).toBeInstanceOf(Float32Array);
    expect(Array.from(x)).toEqual([1.0, 2.0, 3.0]);
  });

  it("converts Float64 to Float32", () => {
    const table = tableFromArrays({
      val: Float64Array.from([1.5, 2.5, 3.5]),
    });
    const v = getFloat32Column(table, "val");
    expect(v).toBeInstanceOf(Float32Array);
    expect(v[0]).toBeCloseTo(1.5);
    expect(v[2]).toBeCloseTo(3.5);
  });

  it("throws on missing column", () => {
    const table = tableFromArrays({ X: Float32Array.from([1]) });
    expect(() => getFloat32Column(table, "Z")).toThrow('Column "Z" not found');
  });
});

describe("parseMetaFromArrow", () => {
  it("parses numeric columns as typed arrays", () => {
    const table = tableFromArrays({
      nCount: Float32Array.from([1.5, 2.5, 3.5]),
      nFeature: Int32Array.from([50, 60, 70]),
    });
    const meta = parseMetaFromArrow(table);

    expect(meta.nCount.type).toBe("number");
    expect(meta.nCount.value).toBeInstanceOf(Float32Array);
    expect(meta.nCount.value[0]).toBeCloseTo(1.5);

    expect(meta.nFeature.type).toBe("number");
    expect(meta.nFeature.value).toBeInstanceOf(Int32Array);
    expect(Array.from(meta.nFeature.value)).toEqual([50, 60, 70]);
  });

  it("normalizes non-Int32 integer arrays to Int32Array", () => {
    const table = tableFromArrays({
      smallInts: Int8Array.from([1, 2, 3]),
    });
    const meta = parseMetaFromArrow(table);

    expect(meta.smallInts.type).toBe("number");
    expect(meta.smallInts.value).toBeInstanceOf(Int32Array);
    expect(Array.from(meta.smallInts.value)).toEqual([1, 2, 3]);
  });

  it("parses dictionary-encoded columns as category maps", () => {
    // Build a dictionary-encoded column using DictionaryBuilder
    const builder = makeBuilder({
      type: new Dictionary(new Utf8(), new Int8()),
    });
    const labels = ["TypeA", "TypeA", "TypeB", "TypeB", "TypeC"];
    for (const v of labels) builder.append(v);
    const dictVec = builder.finish().toVector();

    const table = tableFromArrays({
      nCount: Float32Array.from([1, 2, 3, 4, 5]),
      cluster: dictVec,
    });

    const meta = parseMetaFromArrow(table);

    expect(meta.cluster.type).toBe("category");
    expect(Object.keys(meta.cluster.value).sort()).toEqual([
      "TypeA",
      "TypeB",
      "TypeC",
    ]);
    // TypeA at indices 0,1; TypeB at 2,3; TypeC at 4
    expect(meta.cluster.value["TypeA"]).toEqual([0, 1]);
    expect(meta.cluster.value["TypeB"]).toEqual([2, 3]);
    expect(meta.cluster.value["TypeC"]).toEqual([4]);
  });

  it("parses UTF-8 cell IDs as an ordered identity vector", () => {
    const table = tableFromArrays({
      cells: ["Cell-A", "Cell-B", "Cell-A"],
    });
    const meta = parseMetaFromArrow(table);

    expect(meta.cells.type).toBe("cell_id");
    expect(meta.cells.value).toEqual(["Cell-A", "Cell-B", "Cell-A"]);
  });
});

describe("readArrowIPC", () => {
  it("rejects on HTTP error", async () => {
    // Mock fetch to return 404
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => ({
      ok: false,
      status: 404,
      statusText: "Not Found",
    });
    try {
      await expect(readArrowIPC("/fake/url")).rejects.toThrow("404");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("decodes a valid Arrow IPC buffer", async () => {
    const buf = makeIPCBuffer({
      X: Float32Array.from([1, 2, 3]),
      Y: Float32Array.from([4, 5, 6]),
    });

    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => ({
      ok: true,
      arrayBuffer: async () => buf.buffer,
    });
    try {
      const table = await readArrowIPC("/test/url");
      expect(table.numRows).toBe(3);
      expect(table.numCols).toBe(2);
      const x = table.getChild("X").toArray();
      expect(Array.from(x)).toEqual([1, 2, 3]);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
