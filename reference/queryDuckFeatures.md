# queryDuckFeatures

Query all the features of a specific assay from duckdb database

## Usage

``` r
queryDuckFeatures(
  con,
  assay = "RNA",
  table = "featureTbl",
  col_name = "features"
)
```

## Arguments

- con:

  duckdb connection object

- assay:

  assay name

- table:

  the table suffix used to query cell table, the real table name is like
  "RNA\_\_cellTbl"

- col_name:

  column name of the cellTbl, by default it's "cells"

## Value

A vector containing features
