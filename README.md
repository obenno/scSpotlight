
<!-- README.md is generated from README.Rmd. Please edit that file -->

# scSpotlight <a href="https://obenno.github.io/scSpotlight/"><img src="man/figures/logo.png" align="right" height="139" alt="scSpotlight website" /></a>

<!-- badges: start -->

[![scSpotlight status
badge](https://obenno.r-universe.dev/badges/scSpotlight)](https://obenno.r-universe.dev/scSpotlight)
<!-- badges: end -->

The goal of scSpotlight is to simplify your single cell analysis and
easily annotate your dataset with curated cell type markers.
`scSpotlight` is built on [shiny](https://shiny.posit.co/),
[Seurat](https://satijalab.org/seurat/) and
[regl-scatterplot](https://github.com/flekschas/regl-scatterplot).
Please refer to the documentation website for detailed instructions:

  - <https://obenno.github.io/scSpotlight/>
  - <https://scspotlight.netlify.app/> (EN, CN)

<img src="https://raw.githubusercontent.com/obenno/scSpotlight/main/vignettes/articles/images/scSpotlight_landingFigure.png" width="80%" />

## Installation

You can install the development version of scSpotlight from
[GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("obenno/scSpotlight")
```

or a much faster installation with `pak`:

``` r
# install.packages("pak")
pak::pkg_install("obenno/scSpotlight")
```

## Dependency policy (dev + CI)

- `pixi.toml` is the source of truth for the development and CI
  environment.
- `DESCRIPTION` remains the source of truth for R package runtime
  dependencies.
- The repo no longer uses `renv`; package and toolchain setup are
  managed through Pixi plus `pak` fallbacks.
- `pixi run ...` commands materialize the environment automatically,
  so `pixi install` is optional unless you want to prefetch the
  environment without running a task.
- Run `pixi run setup` to install conda-first R dependencies,
  install `pak` fallbacks for missing required packages, install
  `scSpotlight`, and install JavaScript dependencies.
- Run `pixi run install-optional-packages` when you want optional
  Seurat performance helpers such as `BPCells` and `presto`. It
  prefers Pixi-native conda-forge installs and then uses `pak` as a
  fallback.
- Run `pixi run doctor-env` to verify `scSpotlight` is installed,
  `.libPaths()` points to Pixi, and no required package is missing.
- Run `pixi run run-app` to start the app in viewer mode.
- Run `pixi run run-app-processing` to start the app in processing
  mode.
- Commit `pixi.toml` and `pixi.lock`; do not commit `.pixi/`.

### R and RStudio with pixi

- `pixi` manages the R runtime and package libraries for this repo
  across Linux, macOS, and Windows.
- Use `pixi run R` or launch RStudio from a Pixi-activated shell so
  the IDE inherits the Pixi-managed `R` and library paths.
- The `bootstrap-r` task clears conflicting library and toolchain
  environment variables inside R, so `pixi run setup` works on native
  Windows as well as Unix shells.
- `r-duckdb` is available from conda-forge for Linux and macOS Intel
  in the current R 4.5 stack. macOS Apple Silicon and Windows still
  fall back to `pak` for `duckdb` in this repo's setup flow.

### Quickstart with pixi

``` bash
# install pixi once: https://pixi.prefix.dev/latest/
pixi run setup
pixi run doctor-env
pixi run run-app
```

For processing mode instead of viewer mode:

``` bash
pixi run setup
pixi run doctor-env
pixi run run-app-processing
```

### Pixi commands

#### User-facing

- `pixi run setup` - install required R and JavaScript dependencies
  and install `scSpotlight`
- `pixi run install-optional-packages` - install optional
  performance packages such as `BPCells` and `presto`
- `pixi run doctor-env` - verify the active Pixi/R environment and
  report missing optional packages
- `pixi run run-app` - launch the app in viewer mode
- `pixi run run-app-processing` - launch the app in processing mode

#### Developer-oriented

- `pixi install` - prefetch/materialize the lockfile environment
  without running a task
- `pixi run bootstrap-r` - install missing required R packages with
  `pak` fallbacks only
- `pixi run install-js` - run `npm install`
- `pixi run install-local` - install the local package into the Pixi
  R library
- `pixi run dev` - start the Vite development server
- `pixi run build-js` - build the frontend bundle
- `pixi run test-js` - run frontend tests once
- `pixi run r-check` - run `devtools::check()`
- `pixi run build-pkgdown` - build the pkgdown site

## Docker

To pull the latest image from the command line

    docker pull registry-intl.cn-hangzhou.aliyuncs.com/thunderbio/scspotlight:0.0.3

To run the app on `port:8081`, please use the command below:

    docker run -p 8081:8081 registry-intl.cn-hangzhou.aliyuncs.com/thunderbio/scspotlight:0.0.3 Rscript -e 'scSpotlight::run_app(options = list(port=8081, host="0.0.0.0", launch.browser = FALSE), runningMode="processing")'
