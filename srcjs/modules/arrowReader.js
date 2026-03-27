/**
 * Arrow IPC reader utilities for R→JS data transfer.
 *
 * Replaces the webR-based qs2 deserialization pipeline with native
 * apache-arrow JS decoding — zero-copy column access, no WASM overhead.
 */
import { tableFromIPC, Type } from "apache-arrow";

/**
 * Fetch an Arrow IPC stream file and return the decoded Table.
 * @param {string} url - URL to the .arrow file served via addResourcePath
 * @returns {Promise<import("apache-arrow").Table>}
 */
export async function readArrowIPC(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(
      `Failed to fetch Arrow IPC ${url}: ${response.status} ${response.statusText}`,
    );
  }
  const buffer = await response.arrayBuffer();
  return tableFromIPC(buffer);
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
      // Category column — Arrow dictionary encoding
      // Build { catName: [cell indices (0-based)] }
      const catMap = {};
      const nRows = col.length;

      // Collect dictionary keys first
      const dictVec = col.data[0].dictionary;
      for (let i = 0; i < dictVec.length; i++) {
        catMap[dictVec.get(i)] = [];
      }

      // Iterate rows and bucket cell indices by category
      for (let j = 0; j < nRows; j++) {
        const label = col.get(j);
        if (label != null) {
          catMap[label].push(j);
        }
      }

      out[field.name] = { type: "category", value: catMap };
    } else {
      // Numeric column
      const dataArray = col.toArray();
      if (dataArray instanceof Int32Array) {
        out[field.name] = { type: "number", value: dataArray };
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
