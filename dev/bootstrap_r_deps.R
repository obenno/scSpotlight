#!/usr/bin/env Rscript

source("dev/r_dep_utils.R")

prepare_pixi_r_session(clear_toolchain = TRUE)

required <- required_description_packages(include_suggests = FALSE)
optional_profiles <- list(
  performance = optional_performance_packages(),
  llm = optional_llm_packages()
)

for (profile in names(optional_profiles)) {
  packages <- optional_profiles[[profile]]
  if (!length(packages)) {
    next
  }
  task <- if (identical(profile, "performance")) {
    "pixi run install-optional-packages"
  } else {
    paste0("pixi run install-optional-", profile)
  }
  message(
    "Optional ",
    profile,
    " packages are not installed by `pixi run setup`: ",
    paste(packages, collapse = ", "),
    ". Install them with `",
    task,
    "` when needed."
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
