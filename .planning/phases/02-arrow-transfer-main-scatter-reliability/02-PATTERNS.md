# Phase 02: Arrow Transfer & Main Scatter Reliability - Pattern Map

**Mapped:** 2026-06-21  
**Files analyzed:** 26  
**Analogs found:** 26 / 26

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `inst/protocol/browser-payload-contracts.json` | config / contract | request-response, file-I/O | same file + `DEVELOPMENT.md` runtime contract section | exact |
| `tests/testthat/test-browser-payload-contracts.R` | test | file-I/O, transform | same file | exact |
| `tests/testthat/test-bpcells-expression-transfer.R` | test | streaming, file-I/O | same file | exact |
| `tests/testthat/test-development-contract-docs.R` | test | contract/docs | same file | exact |
| `R/fct_backend_transfer_adapter.R` | service / utility | file-I/O, transform | same file | exact |
| `R/fct_bpcells_backend.R` | service | streaming, file-I/O | `extract_bpcells_expr_to_ipc()` in same file | exact |
| `R/mod_UpdateMetaData.R` | provider / Shiny module | event-driven, file-I/O | `R/mod_UpdateReduction.R` async producer pattern | role-match |
| `R/mod_UpdateReduction.R` | provider / Shiny module | event-driven, file-I/O | same file + `R/mod_UpdateMetaData.R` | exact |
| `R/mod_InputFeature.R` | provider / Shiny module | event-driven, streaming queue | same file expression queue | exact |
| `srcjs/modules/arrowReader.js` | utility | fetch/decode, transform | same file | exact |
| `srcjs/modules/arrowReader.test.js` | test | fetch/decode, transform | same file | exact |
| `srcjs/index.js` | controller / message handler | event-driven, request-response | same file Shiny handlers/cache/error paths | exact |
| `srcjs/index.test.js` | test | event-driven, request-response | same file handler mocks | exact |
| `srcjs/modules/scatter/scatterModel.js` | model | transform | same file | exact |
| `srcjs/modules/scatter/scatterModel.test.js` | test | transform | same file | exact |
| `srcjs/modules/scatter/scatterLayout.js` | utility | transform | same file | exact |
| `srcjs/modules/scatter/scatterLayout.test.js` | test | transform | same file | exact |
| `srcjs/modules/scatter/scatterLifecycle.js` | model / utility | event-driven state machine | same file | exact |
| `srcjs/modules/scatter/scatterLifecycle.test.js` | test | event-driven state machine | same file | exact |
| `srcjs/modules/scatter/scatterInteractions.js` | utility | event-driven | same file | exact |
| `srcjs/modules/deckScatter.js` | component / renderer | event-driven, streaming render | same file deck.gl renderer | exact |
| `srcjs/modules/deckScatter.test.js` | test | event-driven render/selection | same file | exact |
| `srcjs/modules/lasso.js` | utility / interaction | event-driven | same file | exact |
| `srcjs/modules/lasso.test.js` | test | event-driven geometry | same file | exact |
| `srcjs/modules/scatter/scatterUI.js` / `inst/app/www/css/app.css` | component utility / style config | event-driven UI state | count badge + note helpers in same files | role-match |
| `DEVELOPMENT.md` | documentation / contract | contract-change | runtime contract backbone section | exact |

## Pattern Assignments

### `inst/protocol/browser-payload-contracts.json` (config, request-response/file-I/O)

**Analog:** `inst/protocol/browser-payload-contracts.json`

**Manifest message pattern** (lines 4-54):
```json
"meta_ready": {
  "required_fields": ["metaFile", "metaVersion"],
  "file_fields": ["metaFile"],
  "version_field": "metaVersion",
  "ipc_contract": "meta_ready"
},
"expr_ready": {
  "required_fields": ["exprFile", "geneName", "assay", "exprVersion"],
  "file_fields": ["exprFile"],
  "version_field": "exprVersion",
  "cache_family": "expression",
  "ipc_contract": "expr_ready"
}
```

**Cache/path policy pattern** (lines 76-99):
```json
"cache_versions": {
  "reduction": {
    "key_shape": "{reductionVersion}::{reductionName}",
    "stale_policy": "ignore_older_versions",
    "cache_miss_input": "updateReduction-cacheMissReduction"
  }
},
"browser_path_policy": {
  "allow_absolute_paths": false,
  "forbidden_payload_fields": ["filePath", "output_file", "matrix_dir"]
}
```

**Apply:** Any new failure/status payload fields must update this manifest before R/JS tests. Keep file fields as basenames only.

---

### `tests/testthat/test-browser-payload-contracts.R` (test, file-I/O/transform)

**Analog:** same file

**Shared test helpers** (lines 118-135):
```r
expect_payload_satisfies_contract <- function(contract, message_name, payload) {
  message_contract <- contract$messages[[message_name]]
  expect_false(is.null(message_contract), info = message_name)
  expect_true(
    all(message_contract$required_fields %in% names(payload)),
    info = message_name
  )
  expect_browser_payload_hides_local_paths(contract, payload)
}
```

**Producer + IPC assertion pattern** (lines 223-246, 283-295):
```r
metadata_transfer <- prepare_backend_metadata_transfer(
  object,
  dir_path = file.path(transfer_dir, "meta"),
  meta_version = 10L
)
metadata_payload <- write_backend_metadata_transfer(metadata_transfer)
expect_payload_satisfies_contract(contract, "meta_ready", metadata_payload)
metadata_table <- arrow::read_ipc_stream(metadata_transfer$filePath)
expect_true(all(contract$ipc_columns$meta_ready$required %in% names(metadata_table)))

expression_payload <- write_backend_expression_transfer(expression_transfer)
expect_payload_satisfies_contract(contract, "expr_ready", expression_payload)
expression_table <- arrow::read_ipc_stream(expression_transfer$output_file)
expect_true(all(contract$ipc_columns$expr_ready$required %in% names(expression_table)))
```

**Apply:** Extend this test first for any Phase 02 contract or failure payload addition; assert basename-only payloads and IPC column names.

---

### `R/fct_backend_transfer_adapter.R` (service/utility, file-I/O/transform)

**Analog:** same file

**Metadata / patch producer pattern** (lines 5-60):
```r
prepare_backend_metadata_transfer <- function(object, dir_path, meta_version, cols = NULL) {
  if (isTruthy(cols)) {
    file_name <- hash_md5(paste0("meta_patch_", patch_key, "_", meta_version))
    payload <- list(metaFile = file_name, cols = cols, metaVersion = meta_version)
  } else {
    file_name <- hash_md5(paste0("meta_", meta_version))
    payload <- list(metaFile = file_name, metaVersion = meta_version)
  }
  list(filePath = file.path(dir_path, file_name), payload = payload, ...)
}

write_backend_metadata_transfer <- function(transfer) {
  write_ipc_stream(as_arrow_table(transfer$data), transfer$filePath)
  transfer$payload
}
```

**Reduction/PCA numeric IPC pattern** (lines 63-84, 127-147):
```r
write_ipc_stream(
  arrow_table(stdev = Array$create(pca_stdev, type = float32())),
  file_path
)

write_ipc_stream(
  arrow_table(
    X = Array$create(reduction_data$X, type = float32()),
    Y = Array$create(reduction_data$Y, type = float32())
  ),
  transfer$filePath
)
```

**Expression transfer dispatch pattern** (lines 149-242):
```r
payload = list(
  geneName = feature,
  assay = layer_ref$assay,
  exprVersion = expr_version,
  exprFile = file_name
)

write_backend_expression_transfer <- function(transfer) {
  if (identical(transfer$backend, "bpcells")) {
    extract_bpcells_expr_to_ipc(
      matrix_dir = transfer$matrix_dir,
      feature = transfer$feature,
      output_file = transfer$output_file
    )
    return(transfer$payload)
  }
}
```

**Apply:** Preserve basename payloads and typed Arrow IPC columns. If adding structured error payloads, do not include `filePath`, `output_file`, `matrix_dir`, temp paths, or stack traces.

---

### `R/fct_bpcells_backend.R` and `tests/testthat/test-bpcells-expression-transfer.R` (service/test, streaming file-I/O)

**Analog:** `extract_bpcells_expr_to_ipc()` and its test

**Chunked BPCells writer pattern** (`R/fct_bpcells_backend.R` lines 1297-1360):
```r
extract_bpcells_expr_to_ipc <- function(matrix_dir, feature, output_file, chunk_size = scspotlight_expression_transfer_chunk_size) {
  mat <- BPCells::open_matrix_dir(matrix_dir)
  feature_idx <- match(feature, rownames(mat))
  sink <- arrow::FileOutputStream$create(output_file)
  writer <- arrow::RecordBatchStreamWriter$create(
    sink,
    arrow::schema(expr = arrow::float32())
  )
  on.exit({
    if (!writer_closed) try(writer$close(), silent = TRUE)
    if (!sink_closed) try(sink$close(), silent = TRUE)
  }, add = TRUE)

  while (chunk_start <= cell_count) {
    expr_chunk <- extract_expr_slice(mat, feature_idx, seq.int(chunk_start, chunk_end))
    writer$write(arrow::arrow_table(expr = arrow::Array$create(expr_chunk, type = arrow::float32())))
  }
}
```

**Test pattern** (`test-bpcells-expression-transfer.R` lines 56-65, 67-88):
```r
extract_bpcells_expr_to_ipc(
  matrix_dir = matrix_dir,
  feature = "g2",
  output_file = output_file,
  chunk_size = 2L
)
expression_table <- arrow::read_ipc_stream(output_file)
expect_equal(as.numeric(expression_table$expr), as.numeric(counts["g2", ]))

expect_true(any(grepl("future_promise", expression_export_source)))
expect_false(any(grepl("seuratObj\\(\\)", expression_export_source)))
```

**Apply:** Keep expression extraction path-based and chunked. Do not pass live Seurat/BPCells objects into futures or materialize dense matrices.

---

### `R/mod_UpdateMetaData.R`, `R/mod_UpdateReduction.R`, `R/mod_InputFeature.R` (Shiny modules/providers, event-driven file-I/O)

**Analog:** existing async producer observers in these files

**Metadata async transfer pattern** (`R/mod_UpdateMetaData.R` lines 51-115):
```r
metaProcessed(FALSE)
metaVersion <- metaUpdateIndicator()
dirPath <- file.path(session$userData$tempDir, "meta")
transfer <- prepare_backend_metadata_transfer(seuratObj(), dir_path = dirPath, meta_version = metaVersion)
meta_promise <- future_promise({
  capture_warnings(write_backend_metadata_transfer(transfer))
}) %...>%
  (function(result) {
    session$sendCustomMessage(type = "meta_ready", message = result$value)
    result$value
  }) %...!%
  (function(error) {
    showNotification(ui = paste("Metadata export failed:", conditionMessage(error)), type = "error", session = session)
  })
```

**Reduction prefetch/cache-miss pattern** (`R/mod_UpdateReduction.R` lines 86-104, 270-310):
```r
prefetch_limit <- if (get_backend_cell_count(seuratObj()) >= 250000L) 1L else 5L
prefetched_reductions <- if (prefetch_limit == 1L) selected_reduction else utils::head(ordered_reduction, prefetch_limit)
invoke_all_reduction_transfer(prefetched_reductions, selected_reduction)

cacheKey <- paste0(reductionVersion, cache_key_delim, input$reduction)
if (isTruthy(input$cachedReductionKeys) && cacheKey %in% input$cachedReductionKeys) {
  session$sendCustomMessage(type = "reduction_cached", message = list(reductionName = input$reduction, reductionVersion = reductionVersion))
  return()
}
observeEvent(input$cacheMissReduction, { invoke_reduction_transfer(input$cacheMissReduction) })
```

**Expression queue pattern** (`R/mod_InputFeature.R` lines 209-267, 278-335):
```r
expression_queue <- list()
expression_active <- FALSE
queued_expression_keys <- character()

process_next_expression_transfer <- function() {
  if (expression_active || !length(expression_queue)) return(invisible(NULL))
  job <- expression_queue[[1]]
  expression_queue <<- expression_queue[-1]
  expression_active <<- TRUE
  expr_promise <- future_promise({
    capture_warnings(write_backend_expression_transfer(job$transfer))
  }) %...>%
    (function(result) {
      session$sendCustomMessage(type = "expr_ready", message = result$value)
      result$value
    })
  promises::finally(expr_promise, function() {
    expression_active <<- FALSE
    queued_expression_keys <<- setdiff(queued_expression_keys, job$key)
    process_next_expression_transfer()
  })
}
```

**Apply:** For Phase 02 failures, keep server notifications concise but route browser-visible plot failures through JS payload/status handlers where possible. Preserve queue/no-overlap semantics and targeted cache-miss regeneration.

---

### `srcjs/modules/arrowReader.js` and `srcjs/modules/arrowReader.test.js` (utility/test, fetch/decode transform)

**Analog:** same files

**Imports and fetch/decode pattern** (`arrowReader.js` lines 1-20, 67-91):
```javascript
import { tableFromIPC, Type } from "apache-arrow";

export async function fetchArrowIPCBuffer(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch Arrow IPC ${url}: ${response.status} ${response.statusText}`);
  }
  return response.arrayBuffer();
}

export function getFloat32Column(table, name) {
  const col = table.getChild(name);
  if (!col) throw new Error(`Column "${name}" not found in Arrow table`);
  const arr = col.toArray();
  return arr instanceof Float32Array ? arr : new Float32Array(arr);
}
```

**Categorical metadata parse pattern** (`arrowReader.js` lines 116-179):
```javascript
for (const field of table.schema.fields) {
  const col = table.getChild(field.name);
  if (field.type.typeId === Type.Dictionary) {
    const catMap = {};
    let globalRowIndex = 0;
    for (const chunk of col.data) {
      const labels = Array.from({ length: chunk.dictionary.length }, (_, i) => chunk.dictionary.get(i));
      const indices = getChunkIndices(chunk);
      for (let j = 0; j < indices.length; j++) {
        const label = labels[indices[j]];
        if (label != null) catMap[label].push(globalRowIndex);
        globalRowIndex += 1;
      }
    }
    out[field.name] = { type: "category", value: catMap };
  }
}
```

**Test pattern** (`arrowReader.test.js` lines 25-50, 80-107, 109-146): use `tableFromArrays()`/`tableToIPC()`, mock `fetch`, and assert missing-column errors.

**Apply:** Add schema/column validation helpers here if Phase 02 needs them; tests should cover HTTP failure, missing columns, and dictionary parsing without per-row `col.get()` loops.

---

### `srcjs/index.js` and `srcjs/index.test.js` (controller/test, event-driven request-response)

**Analog:** same files

**Imports + module conventions** (`srcjs/index.js` lines 1-46):
```javascript
import "shiny";
import { initFloatingPlots, requestFloatingPlotRefresh } from "./modules/floatingPlots.js";
import { reglScatterCanvas, expandMeta, getMetaLevels, invalidateMetaCache } from "./modules/deckScatter.js";
import { readArrowIPC, fetchArrowIPCBuffer, decodeArrowIPC, getFloat32Column, parseMetaFromArrow } from "./modules/arrowReader.js";
```

**Versioned cache pattern** (`srcjs/index.js` lines 138-219):
```javascript
const ipcCache = { reductions: new Map(), expr: new Map(), reductionVersion: null, exprVersion: null };
const CACHE_KEY_DELIMITER = "::";
const makeReductionCacheKey = (version, reductionName) => `${version}${CACHE_KEY_DELIMITER}${reductionName}`;
const makeExprCacheKey = (version, assay, geneName) => `${version}${CACHE_KEY_DELIMITER}${assay}${CACHE_KEY_DELIMITER}${geneName}`;
const ensureReductionCacheVersion = (version) => {
  if (ipcCache.reductionVersion !== null && Number(version) < Number(ipcCache.reductionVersion)) return false;
  if (ipcCache.reductionVersion !== version) { ipcCache.reductions.clear(); ipcCache.reductionVersion = version; updateReductionCacheKeys(); }
  return true;
};
```

**Visible error pattern** (`srcjs/index.js` lines 242-278):
```javascript
const showPlotTransferError = (message) => {
  const parentDiv = document.getElementById(mainPlotElId);
  let errorEl = parentDiv.querySelector("#plot-transfer-error");
  if (!errorEl) {
    errorEl = document.createElement("div");
    errorEl.id = "plot-transfer-error";
    errorEl.style.position = "absolute";
    errorEl.style.inset = "1rem auto auto 1rem";
    errorEl.style.zIndex = "10";
    errorEl.style.background = "#fff3cd";
    parentDiv.appendChild(errorEl);
  }
  errorEl.textContent = message;
};
const handlePlotTransferError = (error, requestId, message) => {
  console.error("There was a problem:", error);
  mainPlotSpinner.style.display = "none";
  showPlotTransferError(message);
  if (requestId) notifyInitialPlotSettled(requestId);
};
```

**Handlers to copy from** (`srcjs/index.js` lines 574-683, 728-750, 1065-1219):
```javascript
Shiny.addCustomMessageHandler("reductions_ready", (msg) => {
  const requestId = pendingInitialPlotRequestId;
  (async () => {
    if (!ensureReductionCacheVersion(msg.reductionVersion)) return;
    const reductions = Array.isArray(msg.reductions) ? msg.reductions : [];
    const activeReduction = resolveActiveReduction(reductions, msg.activeReduction);
    const activeBuffer = await fetchArrowIPCBuffer(`${window.location.origin}/data/reduction/${activeReduction.reductionFile}`);
    setCacheEntry(ipcCache.reductions, makeReductionCacheKey(msg.reductionVersion, activeReduction.reductionName), activeBuffer, REDUCTION_CACHE_LIMIT);
    plotReductionBuffer(activeBuffer);
  })().catch((error) => handlePlotTransferError(error, requestId, "Reduction data failed to load. Try switching reductions or reloading the dataset."));
});
```

**Atomic render replacement pattern** (`srcjs/index.js` lines 1330-1466):
```javascript
const previousReglElementData = reglElementData;
const nextReglElementData = previousReglElementData.createRenderReplacement();
try {
  nextReglElementData.generatePlotEl();
  parentDiv.appendChild(nextPlotEl);
  nextReglElementData.mountDeck();
  reglElementData = nextReglElementData;
  nextPlotEl.style.display = "flex";
  previousReglElementData.destroy();
  notifyInitialPlotReady(requestId);
} catch (error) {
  nextReglElementData.destroy();
  reglElementData = previousReglElementData;
  reglElementData.plotMetaData = previousPlotMetaData;
  mainPlotSpinner.style.display = "none";
  notifyInitialPlotSettled(requestId);
}
```

**Test harness pattern** (`srcjs/index.test.js` lines 39-45, 231-246, 477-527, 623-868): mock `arrowReader`, collect `Shiny.addCustomMessageHandler` handlers, call handlers directly, and assert resource URLs/caches/errors.

**Apply:** Add stale gates both before fetch and immediately before state mutation. Use payload-specific copy from `02-UI-SPEC.md`; add `role="alert"`/`aria-live="assertive"` when touching `showPlotTransferError()`.

---

### `srcjs/modules/scatter/scatterModel.js` and `scatterModel.test.js` (model/test, transform)

**Analog:** same files

**Patch validation pattern** (`scatterModel.js` lines 60-125):
```javascript
validateCellMetaDataPatch(cellMetaDataPatch) {
  const existingMeta = this.origData.cellMetaData || {};
  const expectedLength = existingMeta.cells ? expandMeta(existingMeta.cells).length : null;
  Object.entries(cellMetaDataPatch).forEach(([key, value]) => {
    if (!value || value.type === undefined || value.value === undefined) throw new Error(`Invalid metadata patch payload for column ${key}`);
    if (expectedLength !== null && expandMeta(value).length !== expectedLength) throw new Error(`Metadata patch length mismatch for ${key}`);
    if (existingMeta[key]?.type !== undefined && existingMeta[key].type !== value.type) throw new Error(`Metadata patch type mismatch for ${key}`);
  });
}
```

**Mode/first-gene pattern** (`scatterModel.js` lines 133-180, 182-198):
```javascript
const selectedFeatures = this.plotMetaData.selectedFeatures || [];
const hasSelectedFeature = selectedFeatures.length > 0;
if (hasSelectedFeature && nSplitBy === 0) plottingMode = "cluster+expr+noSplit";
else if (hasSelectedFeature && nSplitBy === 2) plottingMode = "cluster+expr+twoSplit";
else if (hasSelectedFeature && nSplitBy > 2) plottingMode = "cluster+expr+multiSplit";

const selectedFeature = selectedFeatures[0];
const expressionData = selectedFeature ? expressionAll[selectedFeature] : [];
```

**Expression scaling pattern** (`scatterModel.js` lines 496-523):
```javascript
if (minValue === maxValue) return new Float32Array(values.length);
if (minValue < 0) {
  const zScale = d3.scaleLinear([minValue, maxValue], [0, 1]).nice();
  return Float32Array.from(values, (e) => zScale(e));
}
const zScale = d3.scaleLinear([0, maxValue], [0, 1]).nice();
return Float32Array.from(values, (e) => zScale(e));
```

**Test pattern** (`scatterModel.test.js` lines 98-196, 198-340): use fixture factory + `model.setConfig()` + `derivePlotMetaData()` + `buildPlotData()`; assert panel counts, titles, typed arrays, cell-ID subsets, and first selected feature behavior.

**Apply:** Put group/split/expression correctness here before renderer tests. Reject malformed metadata patches before merging into `origData`.

---

### `srcjs/modules/scatter/scatterLayout.js` and `scatterLayout.test.js` (utility/test, transform)

**Analog:** same files

**Adaptive panel minimums** (`scatterLayout.js` lines 1-9):
```javascript
export function resolveMinPanelSize(nPanels) {
  const panels = Math.max(1, nPanels || 1);
  if (panels >= 96) return 180;
  if (panels >= 72) return 200;
  if (panels >= 48) return 240;
  if (panels >= 24) return 280;
  if (panels >= 12) return 320;
  return 400;
}
```

**Grid/layout pattern** (`scatterLayout.js` lines 38-99): compute safe panel widths, keep 1-2 panels non-square, enforce square panels for multi-row layouts, and return content dimensions for scroll.

**Test pattern** (`scatterLayout.test.js` lines 4-107): assert threshold values, balanced grids, narrow viewport fallback, square multi-row panels, and high-cardinality content size.

**Apply:** Preserve UI spec thresholds exactly; add explicit boundary tests for 12/24/48/72/96 panels if touched.

---

### `srcjs/modules/scatter/scatterLifecycle.js` and `scatterLifecycle.test.js` (state machine/test, event-driven)

**Analog:** same files

**Lifecycle pattern** (`scatterLifecycle.js` lines 1-45):
```javascript
export const ScatterLifecycleState = Object.freeze({
  IDLE: "idle",
  MOUNTING: "mounting",
  READY: "ready",
  RESIZING: "resizing",
  CLEARING: "clearing",
});
export class ScatterLifecycle {
  constructor() { this.state = ScatterLifecycleState.IDLE; }
  setReady() { this.state = ScatterLifecycleState.READY; }
  isReady() { return this.state === ScatterLifecycleState.READY; }
}
```

**Test pattern** (`scatterLifecycle.test.js` lines 4-27): instantiate lifecycle, call transitions in order, and assert predicate helpers.

**Apply:** Use lifecycle state for readiness/resize guards; do not treat failed or stale loads as ready unless a valid current render succeeded.

---

### `srcjs/modules/deckScatter.js`, `deckScatter.test.js`, and `scatterInteractions.js` (component/renderer/test, event-driven render)

**Analog:** same files

**Deck imports and constructor pattern** (`deckScatter.js` lines 1-52, 54-130): use ES module imports from local scatter helpers, instantiate `ScatterModel`, `ScatterRenderer`, `ScatterInteractions`, and `ScatterLifecycle` inside `reglScatterCanvas`.

**Deck creation pattern** (`deckScatter.js` lines 961-1010):
```javascript
this.panelBuffers = this.buildPanelBuffers();
this.globalBounds = getGlobalBoundsFromPanels(this.panelBuffers);
this.deck = this.renderer.create({
  parent: deckContainer,
  views,
  viewState: this.viewStates,
  layers: this.createAllLayers(),
  onViewStateChange: (args) => this.handleDeckViewStateChange(args),
  onHover: (info) => this.handleHover(info),
  layerFilter: panelLayerFilter,
  onLoad: () => this.handleDeckOnLoad(),
});
this.setupLassoBinding(deckContainer);
```

**Adaptive/binary layer pattern** (`deckScatter.js` lines 1124-1150, 1152-1199, 1248-1301):
```javascript
getPointOptions(nPoints) {
  if (nPoints < 15000) return { opacity: 0.8, pointSize: 4, pickable: true };
  if (nPoints < 50000) return { opacity: 0.7, pointSize: 3, pickable: true };
  if (nPoints < 500000) return { opacity: 0.6, pointSize: 2, pickable: true };
  if (nPoints < 1000000) return { opacity: 0.5, pointSize: 1, pickable: true };
  if (nPoints < 2000000) return { opacity: 0.4, pointSize: 0.5, pickable: true };
  return { opacity: 0.2, pointSize: 0.2, pickable: false };
}

new ScatterplotLayer({
  data: { length: panel.nPoints, attributes: { getPosition: { value: panel.positions, size: 2 }, getFillColor: { value: panel.colors, size: 4 } } },
  radiusUnits: "pixels",
  pickable: this.shouldEnablePicking(panel, viewId),
});
```

**Selection/highlight pattern** (`deckScatter.js` lines 1303-1374, 1441-1514): `createHighlightLayers()` builds three binary highlight layers; `setSelectedCells()` reconciles selection by cell ID across panels; `handleLassoSelect()` maps panel indices to cell IDs and calls selection handlers.

**Lasso binding pattern** (`deckScatter.js` lines 1072-1091; `scatterInteractions.js` lines 8-29):
```javascript
this.lassoTool = this.interactions.bindLasso({
  container: deckContainer,
  overlayCanvas: lassoCanvas,
  getViewports: () => (this.deck ? this.deck.getViewports() : []),
  getPanelPositions: (panelIdx) => this.panelBuffers[panelIdx]?.positions,
  onSelect: (viewId, indices) => this.handleLassoSelect(viewId, indices),
  onDeselect: () => this.handleLassoDeselect(),
});
```

**Test pattern** (`deckScatter.test.js` lines 35-128): create `Object.create(reglScatterCanvas.prototype)`, inject minimal `plotData`/`panelBuffers`, spy on `applyHighlight()`/`updateCellCount()`, and assert selected cell IDs/highlight panel indices.

**Apply:** Keep deck.gl as the only primary renderer. Add focused tests for `getPointOptions()`, `shouldEnablePicking()` at >2M, binary attributes, count badge updates, and highlight mirroring.

---

### `srcjs/modules/lasso.js` and `lasso.test.js` (utility/test, event-driven geometry)

**Analog:** same files

**Pointer/viewport pattern** (`lasso.js` lines 47-107):
```javascript
handlePointerDown(event) {
  if (!event.shiftKey) return;
  const p = this.toLocalPoint(event);
  const viewport = this.pickViewport(p.x, p.y);
  if (!viewport) return;
  event.preventDefault();
  this.active = true;
  this.activeViewId = viewport.id;
  this.path = [p];
}

handlePointerUp() {
  const viewport = this.getViewports().find((vp) => vp.id === activeViewId);
  const panelIdx = Number.parseInt(activeViewId.replace("panel_", ""), 10);
  const positions = this.getPanelPositions(panelIdx);
  const selected = this.pickPointsInPolygon(positions, viewport, polygon);
  if (selected.length > 0) this.onSelect(activeViewId, selected);
  else this.onDeselect();
}
```

**Hit-test pattern** (`lasso.js` lines 150-198): project each point with `projectWorldToCanvas(viewport, worldX, worldY)`, prefilter with polygon bounding box, then point-in-polygon.

**Test pattern** (`lasso.test.js` lines 26-45): use an offset viewport and polygon in canvas coordinates to prove non-origin panel selection.

**Apply:** Keep lasso client-side; add tests for empty lasso deselect, every-panel selection, and high-cardinality split layouts.

---

### `srcjs/modules/scatter/scatterUI.js` and `inst/app/www/css/app.css` (UI helper/style, event-driven UI state)

**Analog:** count badge and note helpers/styles

**Count badge DOM pattern** (`scatterUI.js` lines 92-138):
```javascript
export function createCellCountElement({ plotEl, id, count }) {
  const countEl = document.createElement("div");
  countEl.id = id;
  countEl.classList.add("mainClusterPlotCellCount");
  const createMetric = (label, value, valueClass) => { /* label + value spans */ };
  countEl.appendChild(createMetric("Total", count, "cell-count-total"));
  countEl.appendChild(createMetric("Selected", 0, "cell-count-selected"));
  plotEl.appendChild(countEl);
}
```

**Count badge style pattern** (`app.css` lines 682-714):
```css
.mainClusterPlotCellCount {
    top: 0.5rem;
    right: 0.5rem;
    display: inline-flex;
    color: #fff;
    background-color: rgba(var(--bs-secondary-rgb), 0.9);
    border-radius: 999px;
}
.mainClusterPlotCellCount .cell-count-value { font-weight: 700; }
```

**Apply:** If moving `showPlotTransferError()` out of `index.js`, follow this helper + CSS class pattern. Error overlay placement/copy must match `02-UI-SPEC.md` lines 159-188: top-left, warning colors, max width, `role="alert"`, `aria-live="assertive"`, do not cover top-right count badge.

---

### `DEVELOPMENT.md` and `tests/testthat/test-development-contract-docs.R` (documentation/test, contract-change)

**Analog:** Runtime Contract Backbone and docs guard

**Docs contract pattern** (`DEVELOPMENT.md` lines 243-280):
```markdown
### Browser payload contracts

The machine-readable payload contract is `inst/protocol/browser-payload-contracts.json`. The paired R producer test is `tests/testthat/test-browser-payload-contracts.R`, and the paired JS consumer test is `srcjs/index.test.js`.

Browser payload file fields are resource basenames, not local paths. The browser fetches them through `/data/meta/`, `/data/reduction/`, or `/data/expr/`; payloads must not expose producer-local `filePath`, `output_file`, or `matrix_dir` fields.
```

**Recent reliability rule pattern** (`DEVELOPMENT.md` lines 826-875):
```markdown
- `reductions_ready` fetches and plots the resolved active reduction before warming the cache with inactive reductions.
- `srcjs/index.test.js` covers stale DOM reduction values and missing active-reduction fallback behavior.

### 28. Plot data transfer failures must be visible to users

- Reduction and metadata transfer failures should show a visible in-plot error message, not only `console.error()`.
- Initial plot waiters should still settle on transfer failures so users are not trapped behind a loading overlay.
```

**Docs guard pattern** (`test-development-contract-docs.R` lines 23-56):
```r
expect_development_doc_contains <- function(text, needles) {
  missing <- needles[!vapply(needles, grepl, logical(1), x = text, fixed = TRUE)]
  if (length(missing)) fail(paste("Missing DEVELOPMENT.md text:", paste(missing, collapse = ", ")))
}

test_that("DEVELOPMENT documents runtime contract backbone", {
  expect_development_doc_contains(doc_text, c(
    "## Runtime Contract Backbone",
    "### Browser payload contracts",
    "### Payload change checklist"
  ))
})
```

**Apply:** Any Phase 02 behavior/contract change must update `DEVELOPMENT.md`; extend docs guard if adding required headings for visible failures/stale payload policy.

## Shared Patterns

### Versioned Arrow IPC resource notifications
**Source:** `R/fct_backend_transfer_adapter.R` lines 5-60, 86-147, 149-242; `inst/protocol/browser-payload-contracts.json` lines 4-99  
**Apply to:** all R producers and JS handlers  
Use hashed basename fields (`metaFile`, `reductionFile`, `stdevFile`, `exprFile`) plus version fields. Browser fetches via `/data/meta/`, `/data/reduction/`, `/data/expr/` only.

### Async Shiny producer workflow
**Source:** `R/mod_UpdateMetaData.R` lines 51-115; `R/mod_UpdateReduction.R` lines 114-176; `R/mod_InputFeature.R` lines 223-267  
**Apply to:** metadata, reduction, expression transfers  
Pattern is `showNotification()` → set processed `FALSE` → prepare transfer in-process → `future_promise({ capture_warnings(write_...) })` → `session$sendCustomMessage()` → `%...!%` error notification → `promises::finally()` cleanup.

### Browser cache and stale-version gates
**Source:** `srcjs/index.js` lines 138-219, 574-683, 1131-1219  
**Apply to:** reductions, expression, PCA, metadata patches if versioned gating is added  
Use `ensure*CacheVersion()` before work; re-check active request/version before mutating state for delayed fetch/decode promises.

### Visible recoverable transfer/render errors
**Source:** `srcjs/index.js` lines 242-278, 1330-1466; `02-UI-SPEC.md` lines 159-188  
**Apply to:** `meta_ready`, `meta_patch_ready`, `reduction_ready`, `reductions_ready`, `reduction_cached`, `pca_ready`, `expr_ready`, `expr_cached`, render setup  
Hide stuck waiter, preserve previous scatter when possible, show concise payload-specific copy, settle initial readiness on active failure, and never expose local paths/stack traces.

### deck.gl binary main scatter
**Source:** `srcjs/modules/deckScatter.js` lines 961-1010, 1124-1199, 1248-1301  
**Apply to:** all main scatter rendering  
Build `Float32Array` positions and `Uint8Array` colors once per panel; pass as `data.attributes` to `ScatterplotLayer`; keep deck.gl as the only primary scatter path.

### Selection and lasso synchronization
**Source:** `srcjs/modules/deckScatter.js` lines 1072-1091, 1477-1514; `srcjs/modules/lasso.js` lines 47-107, 150-198  
**Apply to:** lasso, category selection, selected counts, redraw reconciliation  
Map panel-local indices to cell IDs, dedupe by ID, mirror highlights across every panel, and update the persistent `Total`/`Selected` badge immediately.

### Contract-first tests
**Source:** `tests/testthat/test-browser-payload-contracts.R` lines 118-319; `srcjs/index.test.js` lines 299-868; scatter test files listed above  
**Apply to:** every Phase 02 fix  
Add failing tests before implementation. Use small fixtures that assert large-data invariants: typed arrays, basename paths, cache keys, stale ignores, panel geometry, and selection-by-cell-ID behavior.

## No Analog Found

No required Phase 02 file lacks an existing analog. If the planner introduces a brand-new `Retry transfer` control, there is no dedicated current retry-button implementation for plot transfers; copy Bootstrap/button accessibility patterns from existing Shiny controls and keep the overlay contract from `02-UI-SPEC.md`.

## Metadata

**Analog search scope:** `R/`, `srcjs/`, `tests/testthat/`, `inst/protocol/`, `inst/app/www/css/`, `DEVELOPMENT.md`  
**Files scanned:** 31 pattern candidates; 26 classified as likely create/modify targets  
**Pattern extraction date:** 2026-06-21  
**Project skills:** none found in `.claude/skills/` or `.agents/skills/`  
**Project constraints applied:** Arrow IPC + TypedArrays, BPCells/path-based expression futures, deck.gl-only main scatter, stable browser payload contracts, no source edits outside this PATTERNS artifact.
