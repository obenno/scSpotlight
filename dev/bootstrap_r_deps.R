#!/usr/bin/env Rscript

source("dev/r_dep_utils.R")

prepare_pixi_r_session(clear_toolchain = TRUE)

required <- required_description_packages(include_suggests = FALSE)
perf_pkgs <- optional_performance_packages()

if (length(perf_pkgs)) {
  message(
    "Optional performance packages are not installed by `pixi run setup`: ",
    paste(perf_pkgs, collapse = ", "),
    "."
  )
  message(
    "Install them later with `pixi run install-optional-packages` when needed."
  )
  message(
    "Hard dependency bootstrap will continue with: ",
    paste(perf_pkgs, collapse = ", "),
    " left out."
  )
}

fallback <- required

missing <- fallback[
  !vapply(fallback, requireNamespace, logical(1), quietly = TRUE)
]

if (!length(missing)) {
  message("All fallback packages already available.")
  quit(save = "no", status = 0)
}

message("Installing fallback R packages: ", paste(missing, collapse = ", "))

pak::repo_add(
  satijalab = "https://satijalab.r-universe.dev",
  bnprks = "https://bnprks.r-universe.dev",
  immunogenomics = "https://immunogenomics.r-universe.dev"
)
pak::pkg_install(missing, upgrade = FALSE)
