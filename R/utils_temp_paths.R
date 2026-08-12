#' @noRd
scspotlight_temp_root <- function(root = Sys.getenv("SCSPOTLIGHT_TEMP_ROOT", "")) {
  root <- as.character(root %||% "")
  root <- if (length(root)) trimws(root[[1]]) else ""

  if (!nzchar(root)) {
    return(normalizePath(tempdir(), winslash = "/", mustWork = TRUE))
  }

  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(root)) {
    stop("Unable to create scSpotlight temporary root.", call. = FALSE)
  }

  normalizePath(root, winslash = "/", mustWork = TRUE)
}

#' @noRd
scspotlight_temp_path <- function(pattern = "scspotlight_", root = NULL) {
  root <- root %||% scspotlight_temp_root()
  root <- scspotlight_temp_root(root)
  tempfile(pattern = pattern, tmpdir = root)
}
