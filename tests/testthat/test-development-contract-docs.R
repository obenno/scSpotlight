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
    "Reduction could not load",
    "Scatter could not initialize",
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
    "first-selected-gene main scatter behavior"
  ))
})
