# queryDuckAssays

List assays from a duckdb connection, based on existing of counts and
data tables (e.g. "RNA\_\_conunts", "RNA\_\_data").

## Usage

``` r
queryDuckAssays(con)
```

## Arguments

- con:

  duckdb connection object

## Value

A vector of of the assays, return NULL if none detected.
