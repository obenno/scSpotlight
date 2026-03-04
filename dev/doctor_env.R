#!/usr/bin/env Rscript

parse_pkg_field <- function(field_value) {
    if (is.na(field_value) || !nzchar(field_value)) {
        return(character())
    }

    pkgs <- unlist(strsplit(field_value, ",", fixed = TRUE), use.names = FALSE)
    pkgs <- trimws(gsub("\\s*\\(.*\\)", "", pkgs))
    pkgs[nzchar(pkgs)]
}

desc <- read.dcf("DESCRIPTION")[1, ]
required <- unique(c(
    parse_pkg_field(desc[["Depends"]]),
    parse_pkg_field(desc[["Imports"]])
))
required <- setdiff(required, "R")
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
