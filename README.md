
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
[R-universe](https://r-universe.dev/) with:

``` r
install.packages(
  "scSpotlight",
  repos = c(
    "https://obenno.r-universe.dev",
    "https://satijalab.r-universe.dev",
    "https://bnprks.r-universe.dev",
    "https://cloud.r-project.org"
  )
)
```

You can also install the development version from [GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("obenno/scSpotlight")
```

or a much faster installation with `pak`:

``` r
# install.packages("pak")
pak::pkg_install("obenno/scSpotlight")
```

After installation, start the app from any R session; a source checkout is not required:

``` r
scSpotlight::run_app()
scSpotlight::run_app(runningMode = "explore")
```

## Development and CI environment

- `DESCRIPTION` is the source of truth for installed-package runtime
  dependencies.
- `pixi.toml` is the source of truth for source-checkout development,
  CI, JavaScript builds, and Docker builds.
- Pixi is not required to run an already installed `scSpotlight` R
  package.
- The repo no longer uses `renv`; contributor setup is managed through
  Pixi plus `pak` fallbacks.
- `pixi run ...` commands materialize the environment automatically,
  so `pixi install` is optional unless you want to prefetch the
  environment without running a task.
- Run `pixi run setup` from the repository root to install conda-first
  R dependencies, install `pak` fallbacks for missing required
  packages, install `scSpotlight`, and install JavaScript dependencies.
- Run `pixi run setup-r` when you only need to bootstrap R dependencies
  and install the local R package without JavaScript dependencies.
- `BPCells >= 0.3.1` is a required runtime dependency and is installed
  by `pixi run setup` via the fallback R package bootstrap.
- `rhdf5` is a required runtime dependency for full `.h5ad`
  import/export support and is installed by `pixi run setup`.
- Run `pixi run install-optional-packages` when you want optional
  performance support via `presto`. It uses `pak`, with `presto`
  sourced from `immunogenomics/presto`.
- Run `pixi run doctor-env` to verify `scSpotlight` is installed,
  `.libPaths()` points to Pixi, and no required package is missing.
- Run `pixi run run-app` to start the app in Analysis Mode.
- Run `pixi run run-app-explore` to start the app in Explore Mode.
- Commit `pixi.toml` and `pixi.lock`; do not commit `.pixi/`.

### R and RStudio with pixi

- `pixi` manages the R runtime and package libraries for this repo
  across Linux, macOS, and Windows.
- Use `pixi run R` or launch RStudio from a Pixi-activated shell so
  the IDE inherits the Pixi-managed `R` and library paths.
- The `bootstrap-r` task clears conflicting library and toolchain
  environment variables inside R, so `pixi run setup` works on native
  Windows as well as Unix shells.
- `pixi run setup` installs the BPCells-backed runtime used by both
  Analysis Mode and Explore Mode.

### Source checkout quickstart

``` bash
# install pixi once: https://pixi.prefix.dev/latest/
pixi run setup
pixi run doctor-env
pixi run run-app
```

For Explore Mode instead of Analysis Mode:

``` bash
pixi run setup
pixi run doctor-env
pixi run run-app-explore
```

### Pixi commands

- `pixi install` - prefetch/materialize the lockfile environment
  without running a task
- `pixi run setup-r` - install required R fallbacks and install the
  local R package
- `pixi run setup` - run the full app bootstrap: use Pixi-native
  dependencies where available, fall back to `pak::pkg_install()` for
  missing R packages, install JavaScript dependencies, and install the
  local package
- `pixi run dev` - start the Vite development server
- `pixi run build-js` - build the frontend bundle
- `pixi run test-js` - run frontend tests once
- `pixi run r-check` - run `devtools::check()`
- `pixi run build-pkgdown` - build the pkgdown site
- `pixi run run-app` - launch the source-checkout app in Analysis Mode
- `pixi run run-app-analysis` - explicitly launch the source-checkout app
  in Analysis Mode
- `pixi run run-app-explore` - launch the source-checkout app in Explore
  Mode

## Docker

The Docker image uses Pixi during the build to create a locked
production R environment, but the final image runs the installed R
package directly with `Rscript`.

To build the image locally:

``` bash
docker build -t scspotlight .
```

To run the app on `port:8081`:

``` bash
docker run -p 8081:8081 scspotlight
```

To pull the latest image from the command line

    docker pull registry-intl.cn-hangzhou.aliyuncs.com/thunderbio/scspotlight:0.0.3

To run the app on `port:8081`, please use the command below:

    docker run -p 8081:8081 registry-intl.cn-hangzhou.aliyuncs.com/thunderbio/scspotlight:0.0.3
