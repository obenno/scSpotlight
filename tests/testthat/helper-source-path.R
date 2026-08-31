scspotlight_test_source_root <- function() {
  is_source_root <- function(path) {
    is.character(path) &&
      length(path) == 1L &&
      dir.exists(path) &&
      file.exists(file.path(path, "DESCRIPTION")) &&
      dir.exists(file.path(path, "R")) &&
      dir.exists(file.path(path, "tests", "testthat"))
  }

  configured_root <- trimws(Sys.getenv("SCSPOTLIGHT_TEST_SOURCE_ROOT", ""))
  if (nzchar(configured_root)) {
    if (!is_source_root(configured_root)) {
      stop(
        "SCSPOTLIGHT_TEST_SOURCE_ROOT does not contain package source: ",
        configured_root,
        call. = FALSE
      )
    }
    return(normalizePath(configured_root, winslash = "/", mustWork = TRUE))
  }

  find_package_root <- function(path) {
    if (!is.character(path) || length(path) != 1L || !dir.exists(path)) {
      return(NULL)
    }

    current <- normalizePath(path, winslash = "/", mustWork = TRUE)
    repeat {
      if (is_source_root(current)) {
        return(current)
      }
      parent <- dirname(current)
      if (identical(parent, current)) {
        return(NULL)
      }
      current <- parent
    }
  }

  candidates <- unique(c(
    testthat::test_path(),
    getwd(),
    system.file(package = "scSpotlight")
  ))
  for (candidate in candidates) {
    package_root <- find_package_root(candidate)
    if (!is.null(package_root)) {
      return(package_root)
    }
  }

  testthat::skip(
    "Source-inspection tests require a package source checkout or SCSPOTLIGHT_TEST_SOURCE_ROOT."
  )
}

scspotlight_test_source_path <- function(...) {
  file.path(scspotlight_test_source_root(), ...)
}
