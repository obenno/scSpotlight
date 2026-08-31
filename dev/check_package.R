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
stage_root <- normalizePath(
  tempfile("scspotlight-check-source-", tmpdir = scratch_root),
  winslash = "/",
  mustWork = FALSE
)
stage_package <- file.path(stage_root, basename(source_root))
build_root <- file.path(stage_root, "build")
artifact_root <- file.path(stage_root, "artifact")
check_root <- file.path(stage_root, "check")

on.exit(unlink(stage_root, recursive = TRUE, force = TRUE), add = TRUE)

relative_path_from_source <- function(path) {
  if (identical(path, source_root)) {
    return("")
  }

  source_prefix <- paste0(source_root, "/")
  if (!startsWith(path, source_prefix)) {
    return(NULL)
  }

  substring(path, nchar(source_prefix) + 1L)
}

stage_relative_path <- relative_path_from_source(stage_root)
scratch_relative_path <- relative_path_from_source(scratch_root)

excluded_path <- function(relative_path) {
  relative_path <- gsub("\\\\", "/", relative_path)
  inside_staging_root <- function(path) {
    !is.null(path) &&
      nzchar(path) &&
      (
        identical(relative_path, path) ||
          startsWith(relative_path, paste0(path, "/"))
      )
  }

  if (
    inside_staging_root(scratch_relative_path) ||
      inside_staging_root(stage_relative_path)
  ) {
    return(TRUE)
  }

  grepl(
    "(^|/)(\\.git|\\.pixi|\\.tmp|node_modules|\\.codegraph|\\.review-tmp|playwright-report|test-results)(/|$)|^tests/e2e/\\.tmp(/|$)|^benchmarks/\\.tmp(/|$)",
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

dir.create(build_root, recursive = TRUE, showWarnings = FALSE)
package_archive <- devtools::build(
  pkg = stage_package,
  path = build_root,
  manual = FALSE
)

dir.create(artifact_root, recursive = TRUE, showWarnings = FALSE)
utils::untar(package_archive, exdir = artifact_root)
package_name <- read.dcf(file.path(stage_package, "DESCRIPTION"), fields = "Package")[[1]]
artifact_package <- file.path(artifact_root, package_name)
if (!file.exists(file.path(artifact_package, "DESCRIPTION"))) {
  stop("Built package archive did not contain the expected source tree.", call. = FALSE)
}
dir.create(check_root, recursive = TRUE, showWarnings = FALSE)

devtools::check_built(
  path = package_archive,
  manual = FALSE,
  cran = TRUE,
  env_vars = c(
    NOT_CRAN = "true",
    SCSPOTLIGHT_TEST_SOURCE_ROOT = artifact_package
  ),
  check_dir = check_root,
  error_on = "error"
)
