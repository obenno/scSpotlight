development_doc_path <- testthat::test_path("..", "..", "DEVELOPMENT.md")
development_contract_path <- testthat::test_path(
  "..",
  "..",
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
  contract <- jsonlite::fromJSON(development_contract_path, simplifyVector = FALSE)
  expect_false(is.null(contract$messages))
  names(contract$messages)
}

expect_development_doc_contains <- function(text, needles) {
  missing <- needles[!vapply(needles, grepl, logical(1), x = text, fixed = TRUE)]
  if (length(missing)) {
    fail(paste("Missing DEVELOPMENT.md text:", paste(missing, collapse = ", ")))
  }
}

test_that("DEVELOPMENT documents runtime contract backbone", {
  doc_text <- read_development_doc()
  message_names <- read_browser_payload_message_names()

  expect_development_doc_contains(doc_text, c(
    "## Runtime Contract Backbone",
    "### Analysis Mode backend seams",
    "### Browser payload contracts",
    "### Payload change checklist",
    "### Runtime source-of-truth boundaries"
  ))

  expect_development_doc_contains(doc_text, c(
    "inst/protocol/browser-payload-contracts.json",
    "tests/testthat/test-browser-payload-contracts.R",
    "srcjs/index.test.js"
  ))

  expect_development_doc_contains(doc_text, message_names)

  expect_development_doc_contains(doc_text, c(
    "paired R producer test",
    "paired JS consumer test",
    "cache-version behavior",
    "do not reintroduce a mirrored DuckDB runtime for Analysis Mode"
  ))
})

test_that("DEVELOPMENT documents Phase 02 transfer reliability", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(doc_text, c(
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
  ))

  expect_development_doc_contains(doc_text, c(
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
  ))
})

test_that("DEVELOPMENT documents Phase 03 Analysis loading and processing safety", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(doc_text, c(
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
  ))
})

test_that("DEVELOPMENT documents Phase 03 Analysis mutation safety", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(doc_text, c(
    "filter, cluster, and cell-cycle mutation safety",
    "validated selected-cell sets",
    "safe_subset_seurat_object",
    "preserve source-object cell order",
    "reject stale selections before mutating app state",
    "filtering and clustering must drop final dense `scale.data`",
    "Update All refreshes metadata and reductions",
    "Update nDim Only refreshes metadata and reductions",
    "Update Res Only reuses an existing graph and refreshes metadata without a reduction transfer",
    "Cell-cycle scoring first tries Seurat::CellCycleScoring()",
    "falls back to CellCycleScoring_2()",
    "reuse the existing `meta_patch_ready` path",
    "`S.Score`, `G2M.Score`, and `Phase`",
    "do not trigger a full metadata reload for cell-cycle scoring",
    "browser-visible mutation errors must be path-free"
  ))
})

test_that("DEVELOPMENT documents Phase 03 assignment consistency", {
  doc_text <- read_development_doc()

  expect_development_doc_contains(doc_text, c(
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
  ))
})
