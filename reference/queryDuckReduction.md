# queryDuckReduction

Query reduction data from duckdb database

## Usage

``` r
queryDuckReduction(con, reduction = "umap", nComponents = 2L)
```

## Arguments

- con:

  duckdb connection object

- reduction:

  reduction name to be extract

- nComponents:

  number of components (column) to be kept

## Value

A list containing gene's expression, each of the element was neamed by
gene's name, and 0 value was discarded.
