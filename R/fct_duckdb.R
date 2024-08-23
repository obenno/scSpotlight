#' seurat2duckdb
#'
#' @description Convert seurat object to onDisk duckdb file
#'
#' @param object seurat object
#' @param dbFile output duckdb filename, please ensure no previous db exists, connection will be closed after conversion
#' @param assay searat assay used
#' @param layers layers to be converted, please ensure at least one of c("counts", "data") exists, scale.data is not supported yet
#' @param reductions object reductions to be included, default: c("pca", "umap", "tsne")
#' @param overwrite whether to overwrite existing tables, only could be TRUE for now
#'
#' @examples
#' \dontrun{
#'  pbmc <- LoadSeurat("pbmc3k.Rds")
#'  seurat2duckdb(object = pbmc, db = "pbmc3k.duckdb")
#' }
#'
#' @export
#' @importFrom SeuratObject Layers
#' @importFrom DBI dbWriteTable dbListTables
#' @importFrom dbplyr
seurat2duckdb <- function(object = obj,
                          dbFile = "output.duckdb",
                          assay = "RNA",
                          layers = c("counts", "data"),
                          reductions = c("pca", "umap", "tsne"),
                          overwrite = TRUE){

  stopifnot(!file.exists(dbFile))
  con <- dbConnect(duckdb(), dbdir = db, read_only = FALSE)

  existLayers <- SeuratObject::Layers(obj, assay = assay)
  selectedLayers <- intersect(layers, existLayers)

  dbTables <- dbListTables(con)

  stopifnot(length(dbTables)==0, overwrite)

  for(l in selectedLayers){
  ## Add counts layer

    m <- LayerData(obj, assay = "RNA", layer = l)
    stopifnot(class(m) == "dgCMatrix")

    d <- summary(m) %>% as.data.frame

    tableName <- paste0(assay, "__", l)
    dbWriteTable(con, tableName, d, overwrite = overwrite)
    tableName <- paste0(assay, "__", "featureTbl")
    if(!(tableName %in% dbListTables(con)) || overwrite) {

      features <- rownames(m)
      dbWriteTable(con, tableName, tibble(features = features), overwrite= overwrite)

    }
    
    tableName <- paste0(assay, "__", "cellTbl")
    if(!(tableName %in% dbListTables(con)) || overwrite) {

      cells <- colnames(m)
      dbWriteTable(con, tableName, tibble(cells = cells), overwrite= overwrite)

    }
  }

  ## Add all of the reductions
  selectedReductions <- intersect(reductions, Reductions(obj))
  message("Reductions: ", paste(selectedReductions, collapse=", "))
  if(length(selectedReductions) > 0){
    for(i in seq_along(selectedReductions)){
      d <- Embeddings(obj[[selectedReductions[i]]]) %>%
        as.data.frame %>%
        tibble::rownames_to_column("cell") %>%
        tibble::as_tibble()

      tableName <- paste0("Reductions__", selectedReductions[i])
      dbWriteTable(con, tableName, d, overwrite= overwrite)
    }
  }
  ## Add meta data
  if(!("metaData" %in% dbListTables(con)) || overwrite) {
    metaData <- obj[[]] %>%
      tibble::rownames_to_column("cell") %>%
      tibble::as_tibble()
    dbWriteTable(con, "metaData", metaData, overwrite= overwrite)
  }

  ## close connection
  dbDisconnect(con)
}


#' queryDuckExpr
#'
#' Query feature expressions from duckdb database
#'
#' @param con duckdb connection object
#' @param assay searat assay to be queried, which was used as prefix of the table name in duckdb
#' @param layer layers to be queried, default "data"
#'
#' @return A list containing gene's expression, each of the element was neamed by gene's name, and 0 value was discarded.
#'
#' @importFrom dbplyr tbl
#' @export
queryDuckExpr <- function(con,
                          assay = "RNA",
                          layer = "data",
                          feature){

  dataTableName <- paste0(assay, "__", layer)
  featureTableName <- paste0(assay, "__", "featureTbl")
  cellTableName <- paste0(assay, "__", "cellTbl")
  idx <- tbl(con, featureTableName) %>%
    dbplyr::mutate(rowIndex = row_number()) %>%
    dbplyr::filter(features %in% feature) %>%
    dbplyr::pull(rowIndex)
  df <- dbplyr::tbl(con, dataTableName) %>%
    dbplyr::filter(i %in% idx) %>%
    dbplyr::collect()

  allCells <- tbl(con, cellTableName) %>% dbplyr::pull("cells")
  cells <- allCells[df$j]
  filteredFeatures <- dbplyr::pull(tbl(con, featureTableName), "features")[df$i]

  d0 <- df %>%
    dplyr::mutate(feature = filteredFeatures,
                  cell = cells) %>%
    dplyr::select(feature, cell, x) %>%
    dplyr::pivot_wider(id_cols = "cell", names_from = "feature", values_from = "x") %>%
    tibble::column_to_rownames("cell") %>%
    as.data.frame()
  d0 <- d0[allCells[which(allCells %in% rownames(d0))], feature]
  expr <- d0 %>%
    as.list() %>%
    sapply(FUN = function(x){
      names(x) <- rownames(d0);
      x[!is.na(x)]
    })

  return(expr)
}


#' queryDuckMeta
#'
#' Query meta data from duckdb database
#'
#' @param con duckdb connection object
#' @param metaData metaData table name, by default metaData
#'
#' @return A list containing gene's expression, each of the element was neamed by gene's name, and 0 value was discarded.
#'
#' @importFrom dbplyr tbl collect
#' @importFrom DBI dbListTables
#' @export
queryDuckMeta <- function(con, meta = "metaData"){

  stopifnot(tableName %in% dbListTables(con))

  d <- tbl(con, meta) %>%
    collect() %>%
    tibble::column_to_rownames("cell")

  return(d)
}

#' queryDuckReduction
#'
#' Query reduction data from duckdb database
#'
#' @param con duckdb connection object
#' @param reduction reduction name to be extract
#' @param nComponents number of components (column) to be kept
#'
#' @return A list containing gene's expression, each of the element was neamed by gene's name, and 0 value was discarded.
#'
#' @importFrom dbplyr tbl collect
#' @importFrom DBI dbListTables
#' @export
queryDuckReduction <- function(con,
                               reduction = "umap",
                               nComponents = 2L){

  tableName <- paste0("Reductions__", reduction)

  stopifnot(tableName %in% dbListTables(con))

  d <- tbl(con, tableName) %>%
    collect() %>%
    tibble::column_to_rownames("cell")

  n <- min(ncol(d), nComponents)

  d <- d %>% dplyr::select(1:n)

  return(d)
}
