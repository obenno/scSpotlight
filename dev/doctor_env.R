#!/usr/bin/env Rscript

source("dev/r_dep_utils.R")

required <- required_description_packages()
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]

cat("== scSpotlight env doctor ==\n")
cat("R version:", R.version.string, "\n")
cat("R home:", R.home(), "\n")
cat("scSpotlight installed:", requireNamespace("scSpotlight", quietly = TRUE), "\n")
if (requireNamespace("scSpotlight", quietly = TRUE)) {
    cat("scSpotlight version:", as.character(utils::packageVersion("scSpotlight")), "\n")
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
