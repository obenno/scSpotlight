#!/usr/bin/env Rscript

source("dev/r_dep_utils.R")

prepare_pixi_r_session(clear_toolchain = FALSE)

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

pixi_package_spec <- function(pkg) {
    overrides <- list()

    if (pkg %in% names(overrides)) {
        spec <- overrides[[pkg]]
        return(c(package = spec$package, channel = spec$channel))
    }

    c(package = paste0("r-", tolower(pkg)), channel = "conda-forge")
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

pixi_has_exact_package <- function(pkg, channel, platform) {
    if (is.na(platform) || !nzchar(Sys.which("pixi"))) {
        return(FALSE)
    }

    result <- suppressWarnings(system2(
        "pixi",
        c("search", pkg, "--channel", channel, "--platform", platform),
        stdout = TRUE,
        stderr = TRUE
    ))
    status <- attr(result, "status") %||% 0L

    identical(status, 0L) && any(grepl(paste0("^", pkg, "-"), result))
}

install_with_pixi <- function(specs, platform) {
    if (!length(specs) || is.na(platform) || !nzchar(Sys.which("pixi"))) {
        return(FALSE)
    }

    status <- system2(
        "pixi",
        c("add", "--manifest-path", ".", "--platform", platform, unname(specs))
    )

    identical(status, 0L)
}

`%||%` <- function(x, y) {
    if (is.null(x)) y else x
}

platform <- current_pixi_platform()
pixi_specs <- lapply(optional_pkgs, pixi_package_spec)
pixi_candidates <- vapply(pixi_specs, `[[`, character(1), "package")
pixi_channels <- vapply(pixi_specs, `[[`, character(1), "channel")
names(pixi_candidates) <- optional_pkgs
names(pixi_channels) <- optional_pkgs
pixi_available <- names(pixi_candidates)[vapply(seq_along(pixi_candidates), function(i) {
    pixi_has_exact_package(pixi_candidates[[i]], pixi_channels[[i]], platform = platform)
}, logical(1))]
pak_install <- optional_pkgs

if (length(pixi_available)) {
    message(
        "Trying Pixi-native add for: ",
        paste(sprintf("%s (%s:%s)", pixi_available, pixi_channels[pixi_available], pixi_candidates[pixi_available]), collapse = ", "),
        "."
    )
    add_specs <- ifelse(
        pixi_channels[pixi_available] == "conda-forge",
        pixi_candidates[pixi_available],
        paste0(pixi_channels[pixi_available], "::", pixi_candidates[pixi_available])
    )
    pixi_success <- install_with_pixi(add_specs, platform = platform)
    if (pixi_success) {
        pak_install <- setdiff(optional_pkgs, pixi_available)
        message("Pixi-native install completed for available channel packages.")
    } else {
        message("Pixi-native add was unavailable or failed; falling back to pak for all optional packages.")
    }
} else {
    message("No exact conda-channel packages found for the optional package set on this platform; using pak fallback.")
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
pak_specs <- vapply(pak_install, pak_package_spec, character(1), USE.NAMES = FALSE)
pak::pkg_install(pak_specs, upgrade = FALSE)
