#!/usr/bin/env Rscript

source("dev/r_dep_utils.R")

prepare_pixi_r_session(clear_toolchain = FALSE)

args <- commandArgs(trailingOnly = TRUE)
profile <- if (length(args)) {
  args[[1]]
} else {
  Sys.getenv("SCSPOTLIGHT_OPTIONAL_PROFILE", "performance")
}
packages <- optional_packages_for_profile(profile)
missing <- packages[
  !vapply(packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing)) {
  stop(
    "Optional package profile '",
    profile,
    "' is missing: ",
    paste(missing, collapse = ", "),
    ". Run the matching Pixi install task first.",
    call. = FALSE
  )
}

versions <- vapply(
  packages,
  function(pkg) as.character(utils::packageVersion(pkg)),
  character(1)
)
message(
  "Optional package profile '",
  profile,
  "' is available: ",
  paste(paste0(names(versions), " ", versions), collapse = ", "),
  "."
)
