# updateDuckMeta

Update the meta data table of a duckdb database

## Usage

``` r
updateDuckMeta(con, assay = "RNA", data)
```

## Arguments

- con:

  duckdb connection

- data:

  meta data (data frame) to be updated, with the first column as 'cell'
