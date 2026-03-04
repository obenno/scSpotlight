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

fallback <- required
if (identical(Sys.info()[["sysname"]], "Linux")) {
    fallback <- setdiff(fallback, "duckdb")
}

missing <- fallback[!vapply(fallback, requireNamespace, logical(1), quietly = TRUE)]

if (!length(missing)) {
    message("All fallback packages already available.")
    quit(save = "no", status = 0)
}

pak::repo_add(
    satijalab = "https://satijalab.r-universe.dev",
    bnprks = "https://bnprks.r-universe.dev",
    immunogenomics = "https://immunogenomics.r-universe.dev"
)
pak::pkg_install(missing, upgrade = FALSE)
