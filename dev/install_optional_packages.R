#!/usr/bin/env Rscript

source("dev/r_dep_utils.R")

prepare_pixi_r_session(clear_toolchain = FALSE)

args <- commandArgs(trailingOnly = TRUE)
profile <- if (length(args)) {
  args[[1]]
} else {
  Sys.getenv("SCSPOTLIGHT_OPTIONAL_PROFILE", "performance")
}
optional_pkgs <- optional_packages_for_profile(profile)
if (!length(optional_pkgs)) {
  message("No optional packages are defined for profile '", profile, "'.")
  quit(save = "no", status = 0)
}

pak_package_spec <- function(pkg) {
  overrides <- c(
    presto = "immunogenomics/presto"
  )

  if (pkg %in% names(overrides)) {
    return(unname(overrides[[pkg]]))
  }

  pkg
}

missing <- optional_pkgs[
  !vapply(optional_pkgs, requireNamespace, logical(1), quietly = TRUE)
]
if (!length(missing)) {
  message(
    "Optional package profile '",
    profile,
    "' is already installed: ",
    paste(optional_pkgs, collapse = ", "),
    "."
  )
  quit(save = "no", status = 0)
}

message(
  "Installing optional package profile '",
  profile,
  "' into the active Pixi R library with pak: ",
  paste(missing, collapse = ", "),
  "."
)

pak::repo_add(
  satijalab = "https://satijalab.r-universe.dev",
  bnprks = "https://bnprks.r-universe.dev",
  immunogenomics = "https://immunogenomics.r-universe.dev"
)
pak_specs <- vapply(
  missing,
  pak_package_spec,
  character(1),
  USE.NAMES = FALSE
)
pak::pkg_install(pak_specs, upgrade = FALSE)

still_missing <- optional_pkgs[
  !vapply(optional_pkgs, requireNamespace, logical(1), quietly = TRUE)
]
if (length(still_missing)) {
  stop(
    "Optional package profile '",
    profile,
    "' is incomplete after installation: ",
    paste(still_missing, collapse = ", "),
    ".",
    call. = FALSE
  )
}
