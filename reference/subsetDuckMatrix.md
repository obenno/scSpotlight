# subsetDuckMatrix

Update duckdb matrix (counts/data layer) to retain specific cells and
features

## Usage

``` r
subsetDuckMatrix(
  con,
  assay = "RNA",
  layers = c("counts", "data"),
  features,
  cells
)
```

## Arguments

- con:

  duckdb connection

- assay:

  assay name

- layers:

  layers to be subset, by default, both of the counts and data layer
  will be subset

- features:

  selected features

- cells:

  selected cells
