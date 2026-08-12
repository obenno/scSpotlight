development_doc_path <- scspotlight_test_source_path("DEVELOPMENT.md")
development_contract_path <- scspotlight_test_source_path(
  "inst",
  "protocol",
  "browser-payload-contracts.json"
)

read_development_doc <- function() {
  expect_true(file.exists(development_doc_path))
  paste(readLines(development_doc_path, warn = FALSE), collapse = "\n")
}

read_browser_payload_message_names <- function() {
  skip_if_not_installed("jsonlite")
  expect_true(file.exists(development_contract_path))
  contract <- jsonlite::fromJSON(
    development_contract_path,
    simplifyVector = FALSE
  )
  expect_false(is.null(contract$messages))
  names(contract$messages)
}

expect_development_doc_contains <- function(text, needles) {
  normalized_text <- gsub("[[:space:]]+", " ", text)
  normalized_needles <- gsub("[[:space:]]+", " ", needles)
  missing <- needles[
    !vapply(normalized_needles, grepl, logical(1), x = normalized_text, fixed = TRUE)
  ]
  if (length(missing)) {
    fail(paste("Missing DEVELOPMENT.md text:", paste(missing, collapse = ", ")))
  }
}

test_that("DEVELOPMENT documents runtime contract backbone", {
  doc_text <- read_development_doc()
  message_names <- read_browser_payload_message_names()

  expect_development_doc_contains(
    doc_text,
    c(
      "## Runtime Contract Backbone",
      "### Analysis Mode backend seams",
      "### Browser payload contracts",
      "### Payload change checklist",
      "### Runtime source-of-truth boundaries"
    )
  )

  expect_development_doc_contains(
    doc_text,
    c(
      "inst/protocol/browser-payload-contracts.json",
      "tests/testthat/test-browser-payload-contracts.R",
      "srcjs/index.test.js"
    )
  )

  expect_development_doc_contains(doc_text, message_names)

  expect_development_doc_contains(
    doc_text,
    c(
      "paired R producer test",
      "paired JS consumer test",
      "cache-version behavior",
      "do not reintroduce a mirrored DuckDB runtime for Analysis Mode"
    )
  )
})

test_that("DEVELOPMENT documents Phase 02 transfer reliability", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(
    doc_text,
    c(
      "### Phase 02 transfer reliability",
      "`transfer_error`",
      "visible transfer failures",
      "stale payloads",
      "active-reduction readiness",
      "Metadata could not load",
      "Metadata update could not apply",
      "Reduction could not load",
      "Scatter could not initialize",
      "Expression could not load",
      "PCA summary unavailable"
    )
  )

  expect_development_doc_contains(
    doc_text,
    c(
      "queued one-active expression jobs",
      "duplicate scoped key suppression",
      "path-based BPCells expression transfers",
      "DuckDB/Explore query-plan expression transfers",
      "Arrow IPC numeric `expr` vectors",
      "basename-only expression payloads",
      "Browser-side stale expression application",
      "`{exprVersion}::{assay}::{geneName}`",
      "`inputFeatures-cacheMissFeature`",
      "Metadata patches remain column-scoped",
      "patch shape, length, and type before merge",
      "Main scatter expression rendering remains first-selected-gene only",
      "selectedFeatures[0]",
      "sparkline primary state",
      "only the first selected gene receives semibold/`aria-current` primary emphasis"
    )
  )
})

test_that("DEVELOPMENT documents Phase 03 Analysis loading and processing safety", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(
    doc_text,
    c(
      "### Phase 03 Analysis Mode processing and mutation safety",
      "supported Analysis Mode inputs",
      "Seurat `.Rds`",
      "`.h5ad`",
      "BPCells bundle archive",
      "compressed 10x-style matrix archive",
      "Explore Parquet bundles remain rejected in Analysis Mode",
      "BPCells-backed assay layers",
      "memory-conserving derivation of normalized, HVG, PCA, neighbors, clusters, and UMAP state",
      "no final dense `scale.data`",
      "Phase 02 browser transfer contracts remain unchanged",
      "`meta_ready`",
      "`reduction_ready`",
      "`reductions_ready`",
      "`expr_ready`",
      "`meta_patch_ready`",
      "`transfer_error`"
    )
  )
})

test_that("DEVELOPMENT documents Phase 03 Analysis mutation safety", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(
    doc_text,
    c(
      "clustering, cell-cycle, and Analysis-subsetting mutation safety",
      "validated selected-cell sets",
      "safe_subset_seurat_object",
      "preserve source-object cell order",
      "reject stale selections before mutating app state",
      "Cluster and Analysis Mutation paths must drop final dense `scale.data`",
      "`Filter Cells` is deliberately excluded from the Analysis Mutation path",
      "Update All refreshes metadata and reductions",
      "Update nDim Only refreshes metadata and reductions",
      "Update Res Only reuses an existing graph and refreshes metadata without a reduction transfer",
      "Cell-cycle scoring first tries Seurat::CellCycleScoring()",
      "falls back to CellCycleScoring_2()",
      "reuse the existing `meta_patch_ready` path",
      "`S.Score`, `G2M.Score`, and `Phase`",
      "do not trigger a full metadata reload for cell-cycle scoring",
      "browser-visible mutation errors must be path-free"
    )
  )
})

test_that("DEVELOPMENT documents Phase 03 assignment consistency", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(
    doc_text,
    c(
      "assignment and category-selection consistency",
      "browser-owned rename filtering",
      "lasso selections take precedence over category selections",
      "bounded browser assignment intent",
      "renameCluster-assignmentIntent",
      "server resolves assigned cells from canonical Seurat metadata",
      "assignment mutates exactly one metadata column",
      "one-column scoped `meta_patch_ready` patch",
      "no full JSON cell-level metadata transfer",
      "clear stale rename selections on group.by or split.by changes",
      "clear stale rename selections after assignment completion"
    )
  )
})

test_that("DEVELOPMENT documents Phase 03 subset and restore safety", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(
    doc_text,
    c(
      "subset and restore refresh semantics",
      "subset uses safe_subset_seurat_object",
      "original object is stored once",
      "restore clears that controller-owned backup",
      "Session-scoped Analysis Transition serializes mutations",
      "View Filter Version",
      "publishes object, backup, transition state, and Change-set only after a complete candidate succeeds",
      "Invalid or repeated subset toggles do not mutate app state",
      "Successful subset and restore increment geneUpdateIndicator, metaUpdateIndicator, and reductionUpdateIndicator",
      "transfer-error payloads must discard stale versions before mutating browser state",
      "browser selected-cell, rename, assignment, expression cache, and feature state clear or reconcile after object replacement",
      "ordered canonical Cell IDs",
      "mismatched or reordered Cell-ID sequence",
      "expression epoch",
      "reuse existing Phase 02 contracts",
      "no final dense `scale.data` after subset or restore",
      "View Filter render is not object replacement"
    )
  )
})

test_that("DEVELOPMENT documents the View Filter contract and evidence boundary", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(
    doc_text,
    c(
      "### 36. View-only Filter, browser proof, and benchmark boundary",
      "`Filter Cells` is a View-only Filter",
      "Session-owned View Filter state",
      "viewFilterOnly",
      "viewFilterVersion",
      "never create a new Analysis Version",
      "stale View Filter contexts",
      "capture_operation_warnings()",
      "await_initial_plot_ready",
      "playwright.config.js",
      "tests/e2e/subset-restore.spec.js",
      "correctness-only",
      "must not be cited as 1M+ performance or memory evidence",
      "representative processed artifact",
       "peak server RSS",
       "settled browser-memory use",
       "Do not close issue #27",
       "### 37. Synthetic Explore 1M benchmark harness and staged package check",
       "pixi run benchmark-explore-1m",
       "synthetic_structural_workload",
       "biological_representativeness: not claimed",
        "benchmarks/.tmp/explore-1m/",
        "benchmarks/evidence/explore-1m-structural-2026-08-09.json",
        "source_worktree_snapshot_id",
        "fetch(..., { cache: \"no-store\" })",
        "SCSPOTLIGHT_TEST_SOURCE_ROOT",
       "pixi run r-check"
     )
  )
})

test_that("DEVELOPMENT documents Phase 03 gap-closure invariants", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(
    doc_text,
    c(
      "Phase 03 gap-closure invariants",
      "Safe archive extraction:",
      "compressed Analysis archives must validate unsafe entries before extraction",
      "Session-scoped IPC resource prefixes:",
      "metadata, reduction, PCA, expression, metadata patch, and transfer-error payloads",
      "Monotonic metadata versioning:",
      "metadata refreshes and metadata patches share one server-owned monotonic version sequence",
      "Server-trusted assignment validation:",
      "assignment validation must not trust browser-submitted current metadata versions",
      "Single assignment activation:",
      "normal assignment activation emits a single renameCluster-assignmentIntent",
      "Cell-ID and category subset flow:",
      "renameCluster-selectedCellsPayload",
      "renameCluster-categorySelectionContext",
      "Analysis Version, and lineage tokens",
      "The Analysis Transition rejects manual selections",
      "category-derived Cell IDs stay server-side",
      "A stale manual payload blocks category fallback",
      "Successful metadata patches clear the visible lasso",
      "mixed-validity, category-context-invalid, metadata-stale, version-stale, and lineage-stale requests publish no Analysis Version",
      "Session-root BPCells subset backing:",
      "subset backing must use the session backend root for BPCells-safe output",
      "IPC payload URLs use a session-scoped resourcePrefix plus basename instead of global /data paths"
    )
  )
})
