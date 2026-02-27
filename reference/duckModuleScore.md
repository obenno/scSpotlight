# AddDuckModuleScore

A modified version of Seurat::AddModuleScore() function querying
expression data from duckdb backend

## Usage

``` r
duckModuleScore(
  con,
  features,
  pool = NULL,
  nbin = 24,
  ctrl = 100,
  assay = "RNA",
  name = "Cluster",
  seed = 1,
  search = FALSE,
  slot = "data",
  ...
)
```

## Arguments

- con:

  duckdb connection object

- features:

  A list of vectors of features for expression programs; each entry
  should be a vector of feature names

- pool:

  List of features to check expression levels against, defaults to
  `rownames(x = object)`

- nbin:

  Number of bins of aggregate expression levels for all analyzed
  features

- ctrl:

  Number of control features selected from the same bin per analyzed
  feature

- assay:

  Name of assay to use

- name:

  Name for the expression programs; will append a number to the end for
  each entry in `features` (eg. if `features` has three programs, the
  results will be stored as `name1`, `name2`, `name3`, respectively)

- seed:

  Set a random seed. If NULL, seed is not set.

- search:

  Search for symbol synonyms for features in `features` that don't match
  features in `object`? Searches the HGNC's gene names database; see
  [`UpdateSymbolList`](https://satijalab.org/seurat/reference/UpdateSymbolList.html)
  for more details

- slot:

  Slot to calculate score values off of. Defaults to data slot (i.e
  log-normalized counts)

- ...:

  Extra parameters passed to
  [`UpdateSymbolList`](https://satijalab.org/seurat/reference/UpdateSymbolList.html)

## Value

A dataframe with a single column of module score, using cells as
rownames
