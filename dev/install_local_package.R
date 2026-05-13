#!/usr/bin/env Rscript

prepare_libpaths <- function() {
  libpaths <- .libPaths()
  if (!length(libpaths)) {
    stop("No writable R library configured for local install")
  }
  normalizePath(libpaths[[1]], winslash = "/", mustWork = FALSE)
}

install_local_package <- function(pkg = "scSpotlight") {
  lib <- prepare_libpaths()
  pkg_dir <- file.path(lib, pkg)
  lock_dir <- file.path(lib, paste0("00LOCK-", pkg))

  if (dir.exists(lock_dir)) {
    message("Removing stale install lock: ", lock_dir)
    unlink(lock_dir, recursive = TRUE, force = TRUE)
  }

  if (dir.exists(pkg_dir)) {
    message("Removing existing local install: ", pkg_dir)
    unlink(pkg_dir, recursive = TRUE, force = TRUE)
  }

  status <- system2(
    command = file.path(R.home("bin"), "R"),
    args = c("CMD", "INSTALL", "--preclean", "."),
    stdout = "",
    stderr = ""
  )

  if (!identical(status, 0L)) {
    stop("Local package install failed with status ", status)
  }
}

install_local_package()
