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
#' @importFrom SeuratObject Layers Embeddings
#' @importFrom tibble tibble
#' @importFrom DBI dbWriteTable dbListTables
seurat2duckdb <- function(object,
                          dbFile = "output.duckdb",
                          assay = "RNA",
                          layers = c("counts", "data"),
                          reductions = c("pca", "umap", "tsne"),
                          overwrite = TRUE){

  stopifnot(!file.exists(dbFile))
  con <- dbConnect(duckdb::duckdb(), dbdir = dbFile, read_only = FALSE)

  existLayers <- SeuratObject::Layers(object, assay = assay)
  selectedLayers <- intersect(layers, existLayers)

  dbTables <- dbListTables(con)

  stopifnot(length(dbTables)==0, overwrite)

  for(l in selectedLayers){
  ## Add counts layer

    m <- LayerData(object, assay = "RNA", layer = l)
    stopifnot(class(m) == "dgCMatrix")

    d <- Matrix::summary(m) %>% as.data.frame

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
  selectedReductions <- intersect(reductions, Reductions(object))

  if(length(selectedReductions) > 0){
    for(i in seq_along(selectedReductions)){
      d <- Embeddings(object[[selectedReductions[i]]]) %>%
        as.data.frame %>%
        tibble::rownames_to_column("cell") %>%
        tibble::as_tibble()

      tableName <- paste0("Reductions__", selectedReductions[i])
      dbWriteTable(con, tableName, d, overwrite= overwrite)
    }
  }
  ## Add meta data
  if(!("metaData" %in% dbListTables(con)) || overwrite) {
    metaData <- object[[]] %>%
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
#' @importFrom dplyr tbl collect select mutate pull
#' @importFrom tidyr pivot_wider
#' @export
queryDuckExpr <- function(con,
                          assay = "RNA",
                          layer = "data",
                          feature){

  dataTableName <- paste0(assay, "__", layer)
  featureTableName <- paste0(assay, "__", "featureTbl")
  cellTableName <- paste0(assay, "__", "cellTbl")
  idx <- tbl(con, featureTableName) %>%
    mutate(rowIndex = row_number()) %>%
    filter(features %in% feature) %>%
    pull(rowIndex)
  df <- tbl(con, dataTableName) %>%
    filter(i %in% idx) %>%
    collect()

  allCells <- tbl(con, cellTableName) %>% pull("cells")
  cells <- allCells[df$j]
  filteredFeatures <- pull(tbl(con, featureTableName), "features")[df$i]

  d0 <- df %>%
    mutate(feature = filteredFeatures,
           cell = cells) %>%
    select(feature, cell, x) %>%
    pivot_wider(id_cols = "cell", names_from = "feature", values_from = "x") %>%
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
#' @importFrom dplyr tbl collect
#' @importFrom DBI dbListTables
#' @export
queryDuckMeta <- function(con, meta = "metaData"){

  stopifnot(meta %in% dbListTables(con))

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
#' @importFrom dplyr tbl collect
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

#' listDuckReduction
#'
#' Query reduction data from duckdb database
#'
#' @param con duckdb connection object
#'
#' @return Table names of the reductions stored in the duckdb
#'
#' @importFrom stringr str_detect str_remove
#' @importFrom DBI dbListTables
#' @export
listDuckReduction <- function(con){

  dbTables <- dbListTables(con)
  dbTables <- dbTables[which(str_detect(dbTables, "^Reductions__"))]
  return(str_remove(dbTables, "^Reductions__"))

}

#' queryDuckCells
#'
#' Query cells of a specific assy from duckdb database
#'
#' @param con duckdb connection object
#' @param assay assay name
#' @param table the table suffix used to query cell table, the real table name is like "RNA__cellTbl"
#' @param col_name column name of the cellTbl, by default it's "cells"
#'
#' @return A vector containing cells
#'
#' @importFrom dplyr tbl pull
#' @export
queryDuckCells <- function(con,
                           assay = "RNA",
                           table = "cellTbl", # the real table name is "RNA__cellTbl"
                           col_name = "cells"){
    tableName <- paste0(assay, "__", table)
    cells <- tbl(con, tableName) %>%
        pull(col_name)
    return(cells)
}

#' queryDuckFeatures
#'
#' Query all the features of a specific assay from duckdb database
#'
#' @param con duckdb connection object
#' @param assay assay name
#' @param table the table suffix used to query cell table, the real table name is like "RNA__cellTbl"
#' @param col_name column name of the cellTbl, by default it's "cells"
#'
#'
#' @return A vector containing features
#'
#' @importFrom dplyr tbl pull
#' @export
queryDuckFeatures <- function(con,
                           assay = "RNA",
                           table = "featureTbl", # the real table name is "RNA__cellTbl"
                           col_name = "features"){
    tableName <- paste0(assay, "__", table)
    features <- tbl(con, tableName) %>%
        pull(col_name)
    return(features)
}

#' duckRowMeans
#'
#' Calculate the row (feature) mean value of the layer
#'
#' @param con Duckdb connection object
#' @param assay Assay name, by default "RNA"
#' @param layer Layer name, by default "counts"
#' @param features Features to be included to calculate row mean, used to subset raw data
#' @param cells Cells to be included to calculate row mean, used to subset raw data
#' @param featureTable The table suffix used to query feature table, the real table name is like "RNA__featureTbl"
#' @param cellTable The table suffix used to query cell table, the real table name is like "RNA__cellTbl"
#' @param featureColName The column name of the featureTbl, by default it's "features"
#' @param cellColName The column name of the cellTbl, by default it's "cells"
#'
#'
#' @return A named vector of rowMeans
#'
#' @import dplyr
#' @export
duckRowMeans <- function(con,
                        assay = "RNA",
                        layer = "counts",
                        features = NULL,
                        cells = NULL,
                        featureTable = "featureTbl",
                        cellTable = "cellTbl",
                        featureColName = "features",
                        cellColName = "cells"){

    featureTableName <- paste0(assay, "__", featureTable)
    cellTableName <- paste0(assay, "__", cellTable)
    dataTableName <- paste0(assay, "__", layer)

    if(!all(c(featureTableName, cellTableName, dataTableName) %in% dbListTables(con))){
        stop("Please ensure query table was properly stored in db")
    }

    allFeatures <- tbl(con, featureTableName) %>% pull(featureColName)
    nFeatures <- length(allFeatures)
    allCells <- tbl(con, cellTableName) %>% pull(cellColName)
    nCells <- length(allCells)

    if(is.null(features)){
        selectedFeatures <- allFeatures
    }else{
        selectedFeatures <- intersect(features, allFeatures)
    }
    if(is.null(cells)){
        selectedCells <- allCells
    }else{
        selectedCells <- intersect(cells, allCells)
    }

    featureIdx <- match(selectedFeatures, allFeatures)
    cellIdx <- match(selectedCells, allCells)

    d <- tbl(con, dataTableName) %>%
        filter(i %in% featureIdx, j %in% cellIdx) %>%
        group_by(i) %>%
        summarize(sumValue = sum(x)) %>%
        mutate(meanValue = sumValue/nCells) %>%
        collect() %>%
        mutate(feature = allFeatures[i]) %>%
        select(feature, meanValue) %>%
        column_to_rownames("feature")
    d <- d[selectedFeatures, ]
    names(d) <- selectedFeatures

    return(d)
}

#' duckColMeans
#'
#' Calculate the column (cell) mean value of the layer
#'
#' @param con Duckdb connection object
#' @param assay Assay name, by default "RNA"
#' @param layer Layer name, by default "counts"
#' @param features Features to be included to calculate column mean, used to subset raw data
#' @param cells Cells to be included to calculate column mean, used to subset raw data
#' @param featureTable The table suffix used to query feature table, the real table name is like "RNA__featureTbl"
#' @param cellTable The table suffix used to query cell table, the real table name is like "RNA__cellTbl"
#' @param featureColName The column name of the featureTbl, by default it's "features"
#' @param cellColName The column name of the cellTbl, by default it's "cells"
#'
#'
#' @return A named vector of colMeans
#'
#' @import dplyr
#' @export
duckColMeans <- function(con,
                         assay = "RNA",
                         layer = "counts",
                         features = NULL,
                         cells = NULL,
                         featureTable = "featureTbl",
                         cellTable = "cellTbl",
                         featureColName = "features",
                         cellColName = "cells"){

    featureTableName <- paste0(assay, "__", featureTable)
    cellTableName <- paste0(assay, "__", cellTable)
    dataTableName <- paste0(assay, "__", layer)

    if(!all(c(featureTableName, cellTableName, dataTableName) %in% dbListTables(con))){
        stop("Please ensure query table was properly stored in db")
    }

    allFeatures <- tbl(con, featureTableName) %>% pull(featureColName)
    nFeatures <- length(allFeatures)
    allCells <- tbl(con, cellTableName) %>% pull(cellColName)
    nCells <- length(allCells)
    if(is.null(features)){
        selectedFeatures <- allFeatures
    }else{
        selectedFeatures <- intersect(features, allFeatures)
    }

    if(is.null(cells)){
        selectedCells <- allCells
    }else{
        selectedCells <- intersect(cells, allCells)
    }

    featureIdx <- match(selectedFeatures, allFeatures)
    cellIdx <- match(selectedCells, allCells)

    d <- tbl(con, dataTableName) %>%
        filter(i %in% featureIdx, j %in% cellIdx) %>%
        group_by(j) %>%
        summarize(sumValue = sum(x)) %>%
        mutate(meanValue = sumValue/nFeatures) %>%
        collect() %>%
        mutate(cell = allCells[j]) %>%
        select(cell, meanValue) %>%
        column_to_rownames("cell")

    d <- d[selectedCells, ]
    names(d) <- selectedCells
    return(d)
}


#' AddDuckModuleScore
#'
#' A modified version of Seurat::AddModuleScore() function querying expression data
#' from duckdb backend
#'
#' @inheritParams Seurat::AddModuleScore
#' @param con duckdb connection object
#'
#' @return Table names of the reductions stored in the duckdb
#'
#' @importFrom Seurat AddModuleScore
#' @importFrom SeuratObject %||%
#' @importFrom stringr str_detect str_remove
#' @import dplyr
#' @importFrom DBI dbListTables
#' @export
duckModuleScore <- function(con,
                               features,
                               pool = NULL,
                               nbin = 24,
                               ctrl = 100,
                               assay = "RNA",
                               name = 'Cluster',
                               seed = 1,
                               search = FALSE,
                               slot = 'data',
                               ...){

    if (!is.null(x = seed)) {
        set.seed(seed = seed)
    }
    tableName <- paste0(assay, "__", slot)
    if(!(tableName %in% dbListTables(con))){
        stop("Cannot find assay or slot")
    }
    assay.data <- tbl(con, tableName)
    features.old <- features
    if (is.null(x = features)) {
        stop("Missing input feature list")
    }

    allFeatures <- queryDuckFeatures(con = con, assay = assay)

    features <- lapply(
        X = features,
        FUN = function(x) {
            missing.features <- setdiff(x = x, y = allFeatures)
            if (length(x = missing.features) > 0) {
                warning(
                    "The following features are not present in the object: ",
                    paste(missing.features, collapse = ", "),
                    ifelse(
                        test = search,
                        yes = ", attempting to find updated synonyms",
                        no = ", not searching for symbol synonyms"
                    ),
                    call. = FALSE,
                    immediate. = TRUE
                )
                if (search) {
                    tryCatch(
                        expr = {
                            updated.features <- UpdateSymbolList(symbols = missing.features, ...)
                            names(x = updated.features) <- missing.features
                            for (miss in names(x = updated.features)) {
                                index <- which(x == miss)
                                x[index] <- updated.features[miss]
                            }
                        },
                        error = function(...) {
                            warning(
                                "Could not reach HGNC's gene names database",
                                call. = FALSE,
                                immediate. = TRUE
                            )
                        }
                    )
                    missing.features <- setdiff(x = x, y = allFeatures)
                    if (length(x = missing.features) > 0) {
                        warning(
                            "The following features are still not present in the object: ",
                            paste(missing.features, collapse = ", "),
                            call. = FALSE,
                            immediate. = TRUE
                        )
                    }
                }
            }
            return(intersect(x = x, y = allFeatures))
        }
    )
    cluster.length <- length(x = features)

    if (!all(LengthCheck(values = features))) {
        warning(paste(
            'Could not find enough features in the object from the following feature lists:',
            paste(names(x = which(x = !LengthCheck(values = features)))),
            'Attempting to match case...'
        ))
        features <- lapply(
            X = features.old,
            FUN = CaseMatch,
            match = allFeatures
        )
    }
    if (!all(LengthCheck(values = features))) {
        stop(paste(
            'The following feature lists do not have enough features present in the object:',
            paste(names(x = which(x = !LengthCheck(values = features)))),
            'exiting...'
        ))
    }

    pool <- pool %||% allFeatures
    data.avg <- duckRowMeans(con, assay = assay, layer = slot, features = features)
    data.avg <- data.avg[order(data.avg)]
    data.cut <- cut_number(x = data.avg + rnorm(n = length(data.avg))/1e30, n = nbin, labels = FALSE, right = FALSE)
                                        #data.cut <- as.numeric(x = Hmisc::cut2(x = data.avg, m = round(x = length(x = data.avg) / (nbin + 1))))
    names(x = data.cut) <- names(x = data.avg)
    ctrl.use <- vector(mode = "list", length = cluster.length)
    for (i in 1:cluster.length) {
        features.use <- features[[i]]
        for (j in 1:length(x = features.use)) {
            ctrl.use[[i]] <- c(
                ctrl.use[[i]],
                names(x = sample(
                          x = data.cut[which(x = data.cut == data.cut[features.use[j]])],
                          size = ctrl,
                          replace = FALSE
                      ))
            )
        }
    }
    ctrl.use <- lapply(X = ctrl.use, FUN = unique)
    ctrl.scores <- matrix(
        data = numeric(length = 1L),
        nrow = length(x = ctrl.use),
        ncol = ncol(x = object)
    )
    for (i in 1:length(ctrl.use)) {
        features.use <- ctrl.use[[i]]
        ctrl.scores[i, ] <- duckColMeans(con = con, assay = assay, layer = slot, features = features.use)
    }
    features.scores <- matrix(
        data = numeric(length = 1L),
        nrow = cluster.length,
        ncol = length(queryDuckCells(con, assay = assay))
    )
    for (i in 1:cluster.length) {
        features.use <- features[[i]]
        features.scores[i, ] <- duckColMeans(con = con, assay = assay,
                                             layer = slot, features = features.use)
    }
    features.scores.use <- features.scores - ctrl.scores
    rownames(x = features.scores.use) <- paste0(name, 1:cluster.length)
    features.scores.use <- as.data.frame(x = t(x = features.scores.use))
    allCells <- queryDuckCells(con = con, assay = assay)
    rownames(x = features.scores.use) <- allCells
    return(features.scores.use)
}

# Check the length of components of a list
#
# @param values A list whose components should be checked
# @param cutoff A minimum value to check for
#
# @return a vector of logicals
#
## copyed from seurat utilities.R
LengthCheck <- function(values, cutoff = 0) {
  return(vapply(
    X = values,
    FUN = function(x) {
      return(length(x = x) > cutoff)
    },
    FUN.VALUE = logical(1)
  ))
}
