# queryDuckExpr

Query feature expressions from duckdb database

## Usage

``` r
queryDuckExpr(
  con,
  assay = "RNA",
  layer = "data",
  features = NULL,
  populateZero = FALSE,
  cellNames = TRUE
)
```

## Arguments

- con:

  duckdb connection object

- assay:

  searat assay to be queried, which was used as prefix of the table name
  in duckdb

- layer:

  layers to be queried, default "data"

- populateZero:

  Whether 0 value will be populated into the result list to ensure each
  element having the same order and equal length

- cellNames:

  Whether to name the expression value with cell names, by default it's
  TRUE, this will make it easily to convert result list to dataframe
  with as.data.frame().

- feature:

  A vector containing features to be extracted

## Value

A list containing gene's expression, each of the element was neamed by
gene's name, and 0 value was discarded.
