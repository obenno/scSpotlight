#!/usr/bin/env Rscript

source("dev/r_dep_utils.R")

prepare_pixi_r_session()

required <- required_description_packages()
missing <- required[
  !vapply(required, requireNamespace, logical(1), quietly = TRUE)
]
perf_pkgs <- optional_performance_packages()
perf_installed <- perf_pkgs[vapply(
  perf_pkgs,
  requireNamespace,
  logical(1),
  quietly = TRUE
)]
perf_missing <- setdiff(perf_pkgs, perf_installed)

cat("== scSpotlight env doctor ==\n")
cat("R version:", R.version.string, "\n")
cat("R home:", R.home(), "\n")
cat(
  "scSpotlight installed:",
  requireNamespace("scSpotlight", quietly = TRUE),
  "\n"
)
if (requireNamespace("scSpotlight", quietly = TRUE)) {
  cat(
    "scSpotlight version:",
    as.character(utils::packageVersion("scSpotlight")),
    "\n"
  )
}

cat("\n.libPaths():\n")
for (lib in .libPaths()) {
  cat("-", lib, "\n")
}

cat("\nRequired DESCRIPTION packages:", length(required), "\n")
cat("Missing required packages:", length(missing), "\n")
if (length(missing)) {
  for (pkg in missing) {
    cat("-", pkg, "\n")
  }
}

if (length(perf_pkgs)) {
  cat(
    "\nOptional performance packages installed:",
    length(perf_installed),
    "/",
    length(perf_pkgs),
    "\n"
  )
  if (length(perf_installed)) {
    for (pkg in perf_installed) {
      cat("+", pkg, "\n")
    }
  }
  if (length(perf_missing)) {
    for (pkg in perf_missing) {
      cat("-", pkg, "(optional)\n")
    }
    cat("These packages are intentionally excluded from pixi run setup\n")
    cat("Install them with: pixi run install-optional-packages\n")
    cat(
      "That command prefers Pixi-native pixi add installs from conda-forge/bioconda and then uses pak as a fallback\n"
    )
  }
}
