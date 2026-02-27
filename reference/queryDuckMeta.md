# queryDuckMeta

Query meta data from duckdb database

## Usage

``` r
queryDuckMeta(con, meta = "metaData")
```

## Arguments

- con:

  duckdb connection object

- metaData:

  metaData table name, by default metaData

## Value

A list containing gene's expression, each of the element was neamed by
gene's name, and 0 value was discarded.
