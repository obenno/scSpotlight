# queryDuckCells

Query cells of a specific assy from duckdb database

## Usage

``` r
queryDuckCells(con, assay = "RNA", table = "cellTbl", col_name = "cells")
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

A vector containing cells
