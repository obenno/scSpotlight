---
phase: 03-analysis-mode-processing-mutation-safety
reviewed: 2026-06-25T18:03:53Z
depth: standard
files_reviewed: 24
files_reviewed_list:
  - R/app_server.R
  - R/fct_backend_transfer_adapter.R
  - R/fct_bpcells_backend.R
  - R/mod_AssignCellCluster.R
  - R/mod_CellCyling.R
  - R/mod_ClusterSetting.R
  - R/mod_FilterCell.R
  - R/mod_InputFeature.R
  - R/mod_SubsetCells.R
  - R/mod_UpdateCategory.R
  - R/mod_UpdateMetaData.R
  - R/mod_UpdateReduction.R
  - R/mod_dataInput.R
  - inst/protocol/browser-payload-contracts.json
  - srcjs/index.js
  - srcjs/index.test.js
  - srcjs/modules/arrowReader.js
  - srcjs/modules/scatter/scatterModel.js
  - tests/testthat/test-analysis-loading-processing-safety.R
  - tests/testthat/test-analysis-mutation-safety.R
  - tests/testthat/test-assignment-metadata-safety.R
  - tests/testthat/test-browser-payload-contracts.R
  - tests/testthat/test-filter-cell-qc-metadata.R
  - tests/testthat/test-subset-cells.R
findings:
  critical: 1
  warning: 2
  info: 0
  total: 3
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-06-25T18:03:53Z
**Depth:** standard
**Files Reviewed:** 24
**Status:** issues_found

## Summary

Reviewed the current post-gap-closure Phase 03 Analysis Mode loading, mutation, assignment, subset, and browser IPC code. The earlier Phase 03 blockers for unsafe archive extraction, global `/data` IPC paths, non-monotonic metadata patch versions, browser-trusted assignment versions, selected-cell ID coercion, and subset backing outside the session root have been addressed in the current source.

One remaining blocker-class security issue remains: expression extraction failures can still expose raw backend error text to Shiny users, violating the Phase 03 no-path-leak constraint. Two robustness warnings from the earlier review also remain in active mutation paths.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Expression extraction notifications can leak raw backend paths and diagnostics

**Classification:** BLOCKER
**File:** `R/mod_InputFeature.R:244-265`, `R/mod_InputFeature.R:310-337`
**Issue:** Phase 03 explicitly requires path-free browser-visible failures, but expression transfer error handling still pastes `conditionMessage(error)` into Shiny notifications. Errors from Arrow/BPCells/file-backed expression extraction can include local matrix directories, temp paths, or other raw backend diagnostics. Those messages cross from server internals into the browser, violating the no-path-leak/privacy constraint for uploaded Analysis data.
**Fix:** Log raw conditions server-side only, and show a generic path-free notification to the user.

```r
error = function(error) {
  message("Expression export failed during IPC write: ", conditionMessage(error))
  session$sendCustomMessage(
    type = "transfer_error",
    message = make_transfer_error_payload(
      payload_type = "expression",
      reason_code = "write_failed",
      version = job$transfer$payload$exprVersion,
      context = list(
        geneName = job$transfer$payload$geneName %||% job$transfer$feature,
        assay = job$transfer$payload$assay %||% job$transfer$assay
      ),
      resource_prefix = session$userData$dataResourcePrefix
    )
  )
  showNotification(
    ui = "Expression export failed. Retry transfer or choose another feature.",
    type = "error",
    duration = 6,
    closeButton = TRUE,
    session = session
  )
}
```

Apply the same pattern to the `prepare_backend_expression_transfer()` `tryCatch()` at lines 310-337.

## Warnings

### WR-01: Filter-cell observer still lets expected edge cases escape as Shiny errors

**Classification:** WARNING
**File:** `R/mod_FilterCell.R:129-163`
**Issue:** The filter mutation path assumes `nFeature_<selectedAssay>` and `percent.mt` are present and that the chosen thresholds leave at least one cell. If a switched assay lacks the expected QC column, or if thresholds filter out all cells, dplyr/safe-subset errors escape the observer instead of producing a controlled warning and leaving indicators unchanged.
**Fix:** Pre-validate required metadata columns and empty selections, then wrap subset/reprocess in `tryCatch()` before mutating `seuratObj()` or incrementing indicators.

```r
meta <- obj[[]]
required_cols <- c(nGeneColName, "percent.mt")
missing_cols <- setdiff(required_cols, colnames(meta))
if (length(missing_cols)) {
  showNotification("Selected assay is missing required QC metadata.", type = "warning")
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

### WR-02: Cluster updates do not validate requested dimensions against available PCA components

**Classification:** WARNING
**File:** `R/mod_ClusterSetting.R:99-116`, `R/mod_ClusterSetting.R:127-138`
**Issue:** `Update nDim Only` and the graph-rebuild path for `Update Res Only` pass `seq_len(ndims)` directly to `RunUMAP()` / `FindNeighbors()` without checking the active PCA embedding width. Loaded or processed objects can have fewer PCs than the UI default, causing recoverable user input to become an observer error.
**Fix:** Clamp or reject `ndims` before downstream Seurat calls.

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

_Reviewed: 2026-06-25T18:03:53Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
