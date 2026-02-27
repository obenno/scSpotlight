# scSpotlight

The goal of scSpotlight is to simplify your single cell analysis and
easily annotate your dataset with curated cell type markers.
`scSpotlight` is built on [shiny](https://shiny.posit.co/),
[Seurat](https://satijalab.org/seurat/) and
[regl-scatterplot](https://github.com/flekschas/regl-scatterplot).
Please refer to the documentation website for detailed instructions:

- <https://obenno.github.io/scSpotlight/>
- <https://scspotlight.netlify.app/> (EN, CN)

![](https://raw.githubusercontent.com/obenno/scSpotlight/main/vignettes/articles/images/scSpotlight_landingFigure.png)

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

- `DESCRIPTION` is the source of truth for package dependencies.
- `renv.lock` is used for reproducible project environments (for example
  pkgdown builds and deployment workflows).
- Commit `renv.lock`, `renv/activate.R`, and `renv/settings.json`.
- Do not commit `renv/library/` or other cache directories.
- CI jobs can use both approaches: install from `DESCRIPTION` for
  package checks, and run `renv::restore()` for reproducible docs/app
  jobs.

## Docker

To pull the latest image from the command line

``` R
docker pull registry-intl.cn-hangzhou.aliyuncs.com/thunderbio/scspotlight:0.0.3
```

To run the app on `port:8081`, please use the command below:

``` R
docker run -p 8081:8081 registry-intl.cn-hangzhou.aliyuncs.com/thunderbio/scspotlight:0.0.3 Rscript -e 'scSpotlight::run_app(options = list(port=8081, host="0.0.0.0", launch.browser = FALSE), runningMode="processing")'
```
