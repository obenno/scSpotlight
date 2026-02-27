# duckRowMeans

Calculate the row (feature) mean value of the layer

## Usage

``` r
duckRowMeans(
  con,
  assay = "RNA",
  layer = "counts",
  features = NULL,
  cells = NULL,
  featureTable = "featureTbl",
  cellTable = "cellTbl",
  featureColName = "features",
  cellColName = "cells"
)
```

## Arguments

- con:

  Duckdb connection object

- assay:

  Assay name, by default "RNA"

- layer:

  Layer name, by default "counts"

- features:

  Features to be included to calculate row mean, used to subset raw data

- cells:

  Cells to be included to calculate row mean, used to subset raw data

- featureTable:

  The table suffix used to query feature table, the real table name is
  like "RNA\_\_featureTbl"

- cellTable:

  The table suffix used to query cell table, the real table name is like
  "RNA\_\_cellTbl"

- featureColName:

  The column name of the featureTbl, by default it's "features"

- cellColName:

  The column name of the cellTbl, by default it's "cells"

## Value

A named vector of rowMeans
