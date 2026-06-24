---
phase: 03-analysis-mode-processing-mutation-safety
reviewed: 2026-06-24T02:54:06Z
depth: standard
files_reviewed: 23
files_reviewed_list:
  - R/app_server.R
  - R/fct_bpcells_backend.R
  - R/mod_AssignCellCluster.R
  - R/mod_CellCyling.R
  - R/mod_ClusterSetting.R
  - R/mod_FilterCell.R
  - R/mod_SubsetCells.R
  - R/mod_UpdateCategory.R
  - R/mod_dataInput.R
  - inst/app/www/index.js
  - inst/app/www/index.js.map
  - srcjs/index.js
  - srcjs/index.test.js
  - tests/testthat/test-analysis-loading-processing-safety.R
  - tests/testthat/test-analysis-mutation-safety.R
  - tests/testthat/test-assignment-metadata-safety.R
  - tests/testthat/test-bpcells-hvg.R
  - tests/testthat/test-bpcells-matrix-coercion.R
  - tests/testthat/test-browser-payload-contracts.R
  - tests/testthat/test-development-contract-docs.R
  - tests/testthat/test-filter-cell-qc-metadata.R
  - tests/testthat/test-subset-cells.R
  - tests/testthat/test-update-category.R
findings:
  critical: 6
  warning: 3
  info: 0
  total: 9
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-06-24T02:54:06Z
**Depth:** standard
**Files Reviewed:** 23
**Status:** issues_found

## Summary

Reviewed the Analysis Mode processing/mutation safety files, with generated `inst/app/www/index.js` and `index.js.map` treated as build artifacts and source JS reviewed primarily through `srcjs/index.js`. The implementation still has several blocker-class correctness and security failures around metadata patch versioning, session-scoped Arrow resource serving, archive extraction, and browser/server selected-cell contracts. These issues can leave the browser showing stale metadata after successful server mutations, leak or mix per-session IPC files, write outside the intended extraction directory from uploaded archives, and break selected-cell subsetting.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Metadata patch versions are not monotonic with full metadata versions, so valid patches are dropped as stale

**Classification:** BLOCKER
**File:** `R/app_server.R:197-199`, `R/app_server.R:446-450`, `R/mod_CellCyling.R:129-134`, `srcjs/index.js:285-300`, `srcjs/index.js:1681-1685`
**Issue:** Full metadata transfers use `metaUpdateIndicator()` as `metaVersion`, while assignment and cell-cycle patches use a separate `metaPatchVersion()` counter starting at zero. The browser has a single `activeMetaVersion` and rejects any patch whose version is lower than the last full metadata version. After a dataset load/filter/subset increments `metaUpdateIndicator()` beyond the patch counter, later successful server-side metadata mutations emit `meta_patch_ready` with a lower version and are silently ignored by `startMetaRequest()`. The server object is mutated, but the browser never receives the updated assignment/cell-cycle columns.
**Fix:** Use one trusted monotonic metadata version for both full and patch transfers; do not maintain a separate patch counter that can lag behind full transfers.

```r
# app_server.R
metadataVersion <- reactiveVal(0L)
nextMetadataVersion <- function() {
  version <- metadataVersion() + 1L
  metadataVersion(version)
  version
}

# Full metadata refresh trigger/version
metaUpdateIndicator(nextMetadataVersion())

# Assignment/cell-cycle patch version
patch_version <- nextMetadataVersion()
metaPatchRequest(list(cols = assignment$colName, version = patch_version))
```

### CR-02: Global `/data` resource path can expose or mix per-session Arrow IPC files

**Classification:** BLOCKER
**File:** `R/app_server.R:156-164`, `srcjs/index.js:787-789`, `srcjs/index.js:1633`, `srcjs/index.js:1753`
**Issue:** Each Shiny session creates a different temp directory, but every session registers it under the same global resource prefix with `addResourcePath("data", tempDir)`. Shiny resource paths are app-global, not session-local. A second session can overwrite the `/data` mapping used by the first session, causing browser fetches like `/data/meta/...`, `/data/reduction/...`, and `/data/expr/...` to read another session's files or fail. This is a correctness bug and a privacy boundary failure for uploaded single-cell data.
**Fix:** Register a session-specific resource prefix and include that opaque prefix in browser payloads or initialize it once client-side; remove the prefix on session end.

```r
resource_prefix <- paste0("data-", session$token)
addResourcePath(resource_prefix, tempDir)
session$userData$dataResourcePrefix <- resource_prefix

session$onSessionEnded(function() {
  removeResourcePath(resource_prefix)
  unlink(session$userData$tempDir, recursive = TRUE, force = TRUE)
})
```

Then build browser URLs from the session prefix instead of hard-coding `/data/...`, and update the payload contract/tests accordingly.

### CR-03: Uploaded archives are extracted without path traversal validation

**Classification:** BLOCKER
**File:** `R/mod_dataInput.R:920-937`
**Issue:** `decompress_matrix_input()` directly calls `untar(..., exdir = tmpMatrixDir)` and `zip::unzip(..., exdir = tmpMatrixDir)` on user-provided uploads. There is no validation that archive entries are relative paths under `tmpMatrixDir`, nor any rejection of `../`, absolute paths, Windows drive paths, or symlink entries. A malicious `.zip`, `.tar.gz`, or `.tbz2` upload can write files outside the intended temp directory with the Shiny server's permissions.
**Fix:** List archive entries first, reject unsafe paths/symlinks, and only then extract.

```r
assert_safe_archive_entries <- function(paths) {
  unsafe <- grepl("^(?:/|[A-Za-z]:|\\\\\\\\)", paths) |
    grepl("(^|/)\\.\\.(/|$)", paths)
  if (any(unsafe)) {
    stop("Archive contains unsafe paths and was not extracted.", call. = FALSE)
  }
}

if (str_detect(fileName, "\\.tar.gz$|\\.tgz$|\\.tar\\.bz2$|\\.tbz2$")) {
  entries <- utils::untar(filePath, list = TRUE)
  assert_safe_archive_entries(entries)
  utils::untar(tarfile = filePath, exdir = tmpMatrixDir)
} else if (str_detect(fileName, "\\.[Zz][Ii][Pp]$")) {
  entries <- zip::zip_list(filePath)$filename
  assert_safe_archive_entries(entries)
  zip::unzip(zipfile = filePath, exdir = tmpMatrixDir)
}
```

### CR-04: Browser sends selected cell IDs, but the subset server still treats them as numeric point indices

**Classification:** BLOCKER
**File:** `R/mod_AssignCellCluster.R:94-107`, `srcjs/index.js:2035-2041`
**Issue:** The browser selection handler sends `selectedCells` (cell IDs) to Shiny as `selectedPoints`, but `manuallySelectedCells()` coerces `selectedPoints()` with `as.integer(...) + 1L` and indexes into `all_cells`. For real cell names such as `Cell1` or barcodes, this produces `NA` and no valid selection. As a result, the "Subset Dataset to Selected Cells" path cannot reliably subset lasso/category selections despite the UI showing selected cells. The tests inject `selectedCells` directly into the module and do not exercise this JS-to-R contract.
**Fix:** Make the R server consume cell IDs, or change the browser to send numeric indices consistently. Prefer cell IDs so stale selections can be validated against current object columns.

```r
manuallySelectedCells <- reactive({
  req(isTruthy(selectedPoints()), isTruthy(seuratObj()))
  all_cells <- colnames(seuratObj())
  submitted <- as.character(selectedPoints())
  valid <- all_cells[all_cells %in% submitted]
  if (!length(valid)) return(NULL)
  valid
})
```

### CR-05: Subsetting BPCells-backed objects writes large backing directories outside session cleanup

**Classification:** BLOCKER
**File:** `R/fct_bpcells_backend.R:246-252`, `R/mod_SubsetCells.R:93-98`
**Issue:** `safe_subset_seurat_object()` creates a new BPCells backing root with `tempfile("scspotlight_subset_layers_")` whenever the source object is BPCells-backed and the caller does not supply `backend_root`. `mod_SubsetCells_server()` calls it without `backend_root`, so selected-cell subsetting can persist large per-user BPCells layer directories outside `session$userData$tempDir`. Those directories are not removed by `session$onSessionEnded()`, leaking private expression data on disk and accumulating unbounded storage for 1M+ cell workflows.
**Fix:** Thread the session backend directory into the subset module and require subset backing under the session cleanup root.

```r
# mod_SubsetCells_server(..., backend_root)
obj_sub <- safe_subset_seurat_object(
  obj,
  cells = valid_cells,
  backend_root = file.path(backend_root, "subset_layers"),
  input_label = "Selected cells"
)

# app/module wiring
mod_SubsetCells_server(
  "subsetCells",
  seuratObj,
  seuratObj_orig,
  selectedCells,
  geneUpdateIndicator,
  metaUpdateIndicator,
  reductionUpdateIndicator,
  backend_root = session$userData$backendDir
)
```

### CR-06: Stale assignment protection falls back to the browser-submitted version

**Classification:** BLOCKER
**File:** `R/app_server.R:413-419`, `R/app_server.R:58-66`
**Issue:** The assignment observer builds `current_context$metaVersion` from trusted `metaSidebarState()` but falls back to `(assignmentIntent$context)$metaVersion` when the trusted value is absent. That makes the stale-version check in `validate_assignment_intent()` pass with an attacker-controlled or stale browser value. A delayed assignment can therefore mutate current Seurat metadata using a context/version the server never verified, especially around full metadata refreshes or object replacement.
**Fix:** Never use the browser-submitted version as the current trusted version. Use a server-side metadata version counter, and reject versioned assignment intents when the server cannot verify the current version.

```r
trusted_meta_version <- (metaSidebarState() %||% list())$metaVersion %||% NULL
current_context <- list(
  groupBy = categoryInfo$group.by(),
  splitBy = categoryInfo$split.by(),
  metaVersion = trusted_meta_version
)

if (is.null(trusted_meta_version) && !is.null((assignmentIntent$context %||% list())$metaVersion)) {
  stop("stale assignment context", call. = FALSE)
}
```

## Warnings

### WR-01: A normal assign click sends duplicate assignment intents

**Classification:** WARNING
**File:** `srcjs/index.js:1566-1571`
**Issue:** The assign button binds `pushRenameAssignmentIntent` to both `pointerdown` and `click`. A single mouse/touch activation commonly fires both events, so Shiny can receive two `renameCluster-assignmentIntent` events for one user action. That duplicates server metadata mutation work, patch version increments, notifications, and Arrow patch writes.
**Fix:** Bind only one activation event, or guard duplicate sends with a short-lived in-flight flag.

```javascript
if (assignBtn && assignBtn.dataset.renameClusterBound !== "true") {
  assignBtn.dataset.renameClusterBound = "true";
  assignBtn.addEventListener("click", (event) => {
    event.preventDefault();
    pushRenameAssignmentIntent();
  });
}
```

### WR-02: Filter-cell expected edge cases escape as Shiny observer errors

**Classification:** WARNING
**File:** `R/mod_FilterCell.R:136-154`
**Issue:** The filter observer assumes `nFeature_<assay>` exists and that the thresholds leave at least one selected cell. Missing QC metadata for a switched assay, `NULL` assay state, or thresholds that filter every cell cause dplyr/safe-subset errors to escape the observer. The user gets a broken operation rather than a controlled notification, and downstream indicators may not reflect the attempted state.
**Fix:** Validate metadata columns and empty selections before mutating or processing the object, and wrap safe subsetting/processing in a user-facing `tryCatch()`.

```r
meta <- obj[[]]
if (!nGeneColName %in% colnames(meta)) {
  showNotification("Selected assay is missing nFeature QC metadata.", type = "warning")
  return(invisible(NULL))
}
selectedCells <- rownames(meta)[
  meta[[nGeneColName]] > input$nFeature_min &
    meta[[nGeneColName]] < input$nFeature_max &
    meta[["percent.mt"]] < input$percent.mt_max
]
if (!length(selectedCells)) {
  showNotification("No cells pass the current filters.", type = "warning")
  return(invisible(NULL))
}
```

### WR-03: Cluster updates do not clamp requested dimensions to available PCA components

**Classification:** WARNING
**File:** `R/mod_ClusterSetting.R:101-116`, `R/mod_ClusterSetting.R:129-138`
**Issue:** `Update nDim Only` and the graph rebuild path for `Update Res Only` pass `seq_len(ndims)` directly into `RunUMAP()`/`FindNeighbors()` without checking how many PCA components exist. Loaded processed objects can legitimately have fewer PCs than the UI default/requested value, causing the observer to error instead of showing a recoverable validation message.
**Fix:** Validate or clamp `ndims` against the active PCA embedding before running UMAP/neighbors.

```r
pca_dims <- ncol(Seurat::Embeddings(object[["pca"]]))
if (ndims > pca_dims) {
  stop(
    "Requested ", ndims, " dimensions but PCA only has ", pca_dims, ".",
    call. = FALSE
  )
}
dims_use <- seq_len(ndims)
object <- run_umap_fun(object, dims = dims_use, reduction = "pca")
object <- find_neighbors_fun(object, dims = dims_use, reduction = "pca")
```

---

_Reviewed: 2026-06-24T02:54:06Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
