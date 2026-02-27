# updateDuckReduction

Udpate the reducions data of a duckdb database

## Usage

``` r
updateDuckReduction(con, reductions = c("pca", "umap"), data = list())
```

## Arguments

- con:

  duckdb connection

- reductions:

  a vector of the reductions to be udpated

- data:

  list of data frames corresponding to the reductions to be updated
