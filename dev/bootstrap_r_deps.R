#!/usr/bin/env Rscript

source("dev/r_dep_utils.R")

include_suggests <- identical(Sys.getenv("SCSPOTLIGHT_INSTALL_SUGGESTS"), "true")
required <- required_description_packages(include_suggests = include_suggests)

fallback <- required
if (identical(Sys.info()[["sysname"]], "Linux")) {
    fallback <- setdiff(fallback, "duckdb")
}

missing <- fallback[!vapply(fallback, requireNamespace, logical(1), quietly = TRUE)]

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
