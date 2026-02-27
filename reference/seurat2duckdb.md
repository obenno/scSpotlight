# seurat2duckdb

Convert seurat object to onDisk duckdb file

## Usage

``` r
seurat2duckdb(
  object,
  dbFile = "output.duckdb",
  assays = "RNA",
  layers = c("counts", "data"),
  reductions = Reductions(object),
  memory_limit = "4GB",
  threads = "8",
  overwrite = TRUE
)
```

## Arguments

- object:

  seurat object

- dbFile:

  output duckdb filename, please ensure no previous db exists,
  connection will be closed after conversion

- layers:

  layers to be converted, please ensure at least one of c("counts",
  "data") exists, scale.data is not supported yet

- reductions:

  object reductions to be included, default: c("pca", "umap", "tsne")

- memory_limit:

  memory limit for duckdb (SET memory_limit = '4GB';),

- threads:

  threads used by duckdb driver, note: need to parse string here

- overwrite:

  whether to overwrite existing tables, only could be TRUE for now

- assay:

  searat assay used

## Examples

``` r
if (FALSE) { # \dontrun{
pbmc <- LoadSeurat("pbmc3k.Rds")
seurat2duckdb(object = pbmc, dbFile = "pbmc3k.duckdb")
} # }
```
