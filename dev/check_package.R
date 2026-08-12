source_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
scratch_root <- Sys.getenv("SCSPOTLIGHT_TEMP_ROOT", "")
if (nzchar(trimws(scratch_root))) {
  dir.create(scratch_root, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(scratch_root)) {
    stop("Unable to create SCSPOTLIGHT_TEMP_ROOT for package checking.", call. = FALSE)
  }
  scratch_root <- normalizePath(scratch_root, winslash = "/", mustWork = TRUE)
} else {
  scratch_root <- tempdir()
}
stage_root <- tempfile("scspotlight-check-source-", tmpdir = scratch_root)
stage_package <- file.path(stage_root, basename(source_root))

on.exit(unlink(stage_root, recursive = TRUE, force = TRUE), add = TRUE)

excluded_path <- function(relative_path) {
  grepl(
    "(^|/)(\\.git|\\.pixi|node_modules|\\.codegraph|playwright-report|test-results)(/|$)|^tests/e2e/\\.tmp(/|$)|^benchmarks/\\.tmp(/|$)",
    relative_path,
    perl = TRUE
  )
}

copy_source_tree <- function(source, destination, relative_path = "") {
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  entries <- list.files(
    source,
    all.files = TRUE,
    no.. = TRUE,
    full.names = TRUE
  )

  for (entry in entries) {
    name <- basename(entry)
    child_relative_path <- if (nzchar(relative_path)) {
      file.path(relative_path, name)
    } else {
      name
    }
    if (excluded_path(child_relative_path)) {
      next
    }

    link_target <- Sys.readlink(entry)
    if (length(link_target) && nzchar(link_target[[1]])) {
      stop(
        "Refusing to stage unexpected symbolic link: ",
        child_relative_path,
        call. = FALSE
      )
    }

    child_destination <- file.path(destination, name)
    if (dir.exists(entry)) {
      copy_source_tree(entry, child_destination, child_relative_path)
      next
    }

    copied <- file.copy(
      entry,
      child_destination,
      copy.mode = TRUE,
      copy.date = TRUE
    )
    if (!isTRUE(copied)) {
      stop("Failed to stage package source file: ", child_relative_path, call. = FALSE)
    }
  }
}

copy_source_tree(source_root, stage_package)

devtools::check(
  pkg = stage_package,
  document = FALSE,
  manual = FALSE,
  cran = TRUE,
  env_vars = c(
    NOT_CRAN = "true",
    SCSPOTLIGHT_TEST_SOURCE_ROOT = stage_package
  ),
  error_on = "error"
)
