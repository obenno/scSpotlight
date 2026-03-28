#!/usr/bin/env Rscript

source("dev/r_dep_utils.R")

prepare_pixi_r_session(clear_toolchain = TRUE)

optional_pkgs <- optional_performance_packages()
if (!length(optional_pkgs)) {
    message("No optional packages are defined in DESCRIPTION.")
    quit(save = "no", status = 0)
}

current_pixi_platform <- function() {
    sysname <- Sys.info()[["sysname"]]
    machine <- Sys.info()[["machine"]]

    if (identical(sysname, "Linux")) {
        return("linux-64")
    }

    if (identical(sysname, "Darwin")) {
        if (grepl("arm64|aarch64", machine, ignore.case = TRUE)) {
            return("osx-arm64")
        }

        return("osx-64")
    }

    if (identical(sysname, "Windows")) {
        return("win-64")
    }

    NA_character_
}

conda_exact_package <- function(pkg) {
    paste0("r-", tolower(pkg))
}

conda_has_exact_package <- function(conda_pkg, platform) {
    if (is.na(platform) || !nzchar(Sys.which("pixi"))) {
        return(FALSE)
    }

    result <- suppressWarnings(system2(
        "pixi",
        c("search", conda_pkg, "--channel", "conda-forge", "--platform", platform),
        stdout = TRUE,
        stderr = TRUE
    ))
    status <- attr(result, "status") %||% 0L

    identical(status, 0L) && any(grepl(paste0("^", conda_pkg, "-"), result))
}

install_with_conda <- function(conda_pkgs) {
    conda_bin <- Sys.which("conda")
    prefix <- Sys.getenv("CONDA_PREFIX", unset = "")

    if (!length(conda_pkgs) || !nzchar(conda_bin) || !nzchar(prefix)) {
        return(FALSE)
    }

    status <- system2(
        conda_bin,
        c("install", "-y", "-p", prefix, "-c", "conda-forge", unname(conda_pkgs))
    )

    identical(status, 0L)
}

`%||%` <- function(x, y) {
    if (is.null(x)) y else x
}

platform <- current_pixi_platform()
conda_candidates <- vapply(optional_pkgs, conda_exact_package, character(1), USE.NAMES = TRUE)
conda_available <- names(conda_candidates)[vapply(conda_candidates, conda_has_exact_package, logical(1), platform = platform)]
pak_install <- optional_pkgs

if (length(conda_available)) {
    message(
        "Trying Pixi-native conda-forge install for: ",
        paste(conda_available, collapse = ", "),
        "."
    )
    conda_success <- install_with_conda(conda_candidates[conda_available])
    if (conda_success) {
        pak_install <- setdiff(optional_pkgs, conda_available)
        message("Pixi-native install completed for available conda packages.")
    } else {
        message("Pixi-native conda install was unavailable or failed; falling back to pak for all optional packages.")
    }
} else {
    message("No exact conda-forge packages found for the optional package set on this platform; using pak fallback.")
}

if (!length(pak_install)) {
    message("No optional packages require pak fallback installation.")
    quit(save = "no", status = 0)
}

message(
    "Installing optional packages with pak fallback: ",
    paste(pak_install, collapse = ", "),
    "."
)

pak::repo_add(
    satijalab = "https://satijalab.r-universe.dev",
    bnprks = "https://bnprks.r-universe.dev",
    immunogenomics = "https://immunogenomics.r-universe.dev"
)
pak::pkg_install(pak_install, upgrade = FALSE)
