/**
 * Arrow IPC reader utilities for R→JS data transfer.
 *
 * Replaces the webR-based qs2 deserialization pipeline with native
 * apache-arrow JS decoding — zero-copy column access, no WASM overhead.
 */
import { tableFromIPC, Type } from "apache-arrow";

export async function fetchArrowIPCBuffer(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(
      `Failed to fetch Arrow IPC ${url}: ${response.status} ${response.statusText}`,
    );
  }
  return response.arrayBuffer();
}

export function decodeArrowIPC(buffer) {
  return tableFromIPC(buffer);
}

function isIntegerTypedArray(arr) {
  return (
    arr instanceof Int8Array ||
    arr instanceof Uint8Array ||
    arr instanceof Uint8ClampedArray ||
    arr instanceof Int16Array ||
    arr instanceof Uint16Array ||
    arr instanceof Int32Array ||
    arr instanceof Uint32Array ||
    arr instanceof BigInt64Array ||
    arr instanceof BigUint64Array
  );
}

function isChunkValueValid(chunk, rowIndex) {
  if (!chunk || chunk.nullCount === 0) {
    return true;
  }

  const nullBitmap = chunk.nullBitmap;
  if (!nullBitmap || nullBitmap.length === 0) {
    return true;
  }

  const bitIndex = chunk.offset + rowIndex;
  return (nullBitmap[bitIndex >> 3] & (1 << (bitIndex & 7))) !== 0;
}

function getChunkIndices(chunk) {
  const values = chunk.values;
  if (!values) {
    return [];
  }

  const start = chunk.offset ?? 0;
  const end = start + chunk.length;
  return values.subarray(start, end);
}

/**
 * Fetch an Arrow IPC stream file and return the decoded Table.
 * @param {string} url - URL to the .arrow file served via addResourcePath
 * @returns {Promise<import("apache-arrow").Table>}
 */
export async function readArrowIPC(url) {
  const buffer = await fetchArrowIPCBuffer(url);
  return decodeArrowIPC(buffer);
}

/**
 * Extract a numeric column from an Arrow table as a Float32Array.
 * If the column is already Float32, this is a zero-copy view.
 * @param {import("apache-arrow").Table} table
 * @param {string} name - column name
 * @returns {Float32Array}
 */
export function getFloat32Column(table, name) {
  const col = table.getChild(name);
  if (!col) {
    throw new Error(`Column "${name}" not found in Arrow table`);
  }
  const arr = col.toArray();
  // If already Float32Array, return as-is (zero-copy)
  if (arr instanceof Float32Array) {
    return arr;
  }
  // Otherwise convert (e.g. Float64 → Float32)
  return new Float32Array(arr);
}

/**
 * Check if a value is an integer-valued array (no fractional parts).
 * Used to decide Int32Array vs Float32Array for numeric metadata columns.
 * @param {ArrayLike<number>} arr
 * @returns {boolean}
 */
function isIntegerArray(arr) {
  for (let i = 0; i < arr.length; i++) {
    if (!Number.isInteger(arr[i])) return false;
  }
  return true;
}

/**
 * Parse an Arrow table containing cell metadata into the format expected
 * by ScatterModel.setData({ cellMetaData }).
 *
 * Numeric columns → { type: "number", value: Int32Array | Float32Array }
 * Dictionary (factor) columns → { type: "category", value: { catName: [0-based indices] } }
 *
 * @param {import("apache-arrow").Table} table
 * @returns {Object} metadata object keyed by column name
 */
export function parseMetaFromArrow(table) {
  const out = {};

  for (const field of table.schema.fields) {
    const col = table.getChild(field.name);
    const typeId = field.type.typeId;

    if (typeId === Type.Dictionary) {
      // Category column — Arrow dictionary encoding.
      // Decode via dictionary/index buffers directly to avoid per-row col.get().
      const catMap = {};
      let globalRowIndex = 0;

      for (const chunk of col.data) {
        const dictVec = chunk.dictionary;
        const labels = Array.from({ length: dictVec.length }, (_, i) =>
          dictVec.get(i),
        );

        for (const label of labels) {
          if (label != null && catMap[label] === undefined) {
            catMap[label] = [];
          }
        }

        const indices = getChunkIndices(chunk);
        for (let j = 0; j < indices.length; j++) {
          if (!isChunkValueValid(chunk, j)) {
            globalRowIndex += 1;
            continue;
          }

          const label = labels[indices[j]];
          if (label != null) {
            catMap[label].push(globalRowIndex);
          }
          globalRowIndex += 1;
        }
      }

      out[field.name] = { type: "category", value: catMap };
    } else {
      // Numeric column
      const dataArray = col.toArray();
      if (dataArray instanceof Int32Array) {
        out[field.name] = { type: "number", value: dataArray };
      } else if (isIntegerTypedArray(dataArray)) {
        out[field.name] = {
          type: "number",
          value: Int32Array.from(dataArray, Number),
        };
      } else if (isIntegerArray(dataArray)) {
        out[field.name] = { type: "number", value: Int32Array.from(dataArray) };
      } else {
        out[field.name] = {
          type: "number",
          value: Float32Array.from(dataArray),
        };
      }
    }
  }

  return out;
}
