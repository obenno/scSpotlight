scspotlight_test_source_root <- function() {
  staged_root <- Sys.getenv("SCSPOTLIGHT_TEST_SOURCE_ROOT", "")
  if (nzchar(staged_root) && file.exists(file.path(staged_root, "DESCRIPTION"))) {
    return(normalizePath(staged_root, winslash = "/", mustWork = TRUE))
  }

  checkout_root <- testthat::test_path("..", "..")
  if (file.exists(file.path(checkout_root, "DESCRIPTION"))) {
    return(normalizePath(checkout_root, winslash = "/", mustWork = TRUE))
  }

  NULL
}

scspotlight_test_source_path <- function(...) {
  source_root <- scspotlight_test_source_root()
  if (is.null(source_root)) {
    return(testthat::test_path("..", "..", ...))
  }
  file.path(source_root, ...)
}
