
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
- Run `pixi install` to materialize the lockfile-backed environment.
- Run `pixi run setup` to install conda-first R dependencies,
  install pak fallbacks for missing packages, install `scSpotlight`,
  and install JavaScript dependencies.
- Run `pixi run doctor-env` to verify `scSpotlight` is installed,
  `.libPaths()` points to Pixi, and no required package is missing.
- Commit `pixi.toml` and `pixi.lock`; do not commit `.pixi/`.

### Quickstart with pixi

``` bash
# install pixi once: https://pixi.prefix.dev/latest/
pixi install
pixi run setup
pixi run doctor-env
pixi run run-app-processing
```

## Docker

To pull the latest image from the command line

    docker pull registry-intl.cn-hangzhou.aliyuncs.com/thunderbio/scspotlight:0.0.3

To run the app on `port:8081`, please use the command below:

    docker run -p 8081:8081 registry-intl.cn-hangzhou.aliyuncs.com/thunderbio/scspotlight:0.0.3 Rscript -e 'scSpotlight::run_app(options = list(port=8081, host="0.0.0.0", launch.browser = FALSE), runningMode="processing")'
