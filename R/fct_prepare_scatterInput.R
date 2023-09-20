#' prepare_scatterInput 
#'
#' @description Function to extract scatter reduction data
#'
#' @return A list of scatter reduction data transferred to javascript from shiny
#'
#' @import Seurat
#' @importFrom dplyr pull
#' @noRd
prepare_scatterReductionInput <- function(obj, reduction,
                                          mode = "clusterOnly",
                                          split.by = NULL){

    ## Define five plotting mode, each with different numbers of panels
    split.is.valid <- FALSE
    if(!is.null(split.by) &&
       split.by %in% colnames(obj[[]])){
       split.is.valid <- TRUE
    }
    if(mode %in% c("cluster+multiSplit", "cluster+expr+twoSplit", "cluster+multiSplit") &&
       !split.is.valid){
        stop("split.by must be valid for plotting mode: ", mode)
    }

    nPanels = switch(
        mode,
        "clusterOnly" = 1,
        "cluster+expr+noSplit" = 2,
        "cluster+expr+twoSplit" = 4,
        "cluster+multiSplit" = obj[[split.by]] %>% pull %>% unqiue,
        "cluster+expr+multiSplit" = obj[[split.by]] %>% pull %>% unique
    )

    if(nPanels >= 2){
        nCols <- 2
    }else{
        nCols <- 1
    }

    nRows <- ceiling(nPanels/2)
    ## seurat assay v5 syntax
    reduction_df <- Embeddings(object = obj[[reduction]])[, 1:2] %>%
        as.data.frame()
    colnames(reduction_df) <- c("X", "Y")

    if(mode == "clusterOnly"){
        pointsData <- list(reduction_df)
    }else if(mode == "cluster+expr+noSplit"){
        pointsData <- list(reduction_df, reduction_df)
    }else if(mode == "cluster+expr+twoSplit"){
        pointsData <- list()
    }else if(mode == "cluster+multiSplit"){
        pointsData <- list()
    }else if(mode == "cluster+expr+multiSplit"){
        pointsData <- list()
    }else{
        pointsData <- list()
    }
    reduction_data <- list(
        nCols = nCols,
        nRows = nRows,
        mode = mode,
        pointsData  = pointsData
    )
    ##if(mode = "clusterOnly"){}
    return(reduction_data)
}

#' prepare_scatterInput
#'
#' @description Function to extract scatter category data
#'
#' @return A list of scatter category data transferred to javascript from shiny
#'
#'
#' @import Seurat
#' @importFrom scales hue_pal
#' @importFrom dplyr pull
#' @noRd
prepare_scatterCatColorInput <- function(obj, col_name,
                                         mode = "clusterOnly",
                                         split.by = NULL,
                                         feature = NULL){
    split.is.valid <- FALSE
    if(!is.null(split.by) &&
       split.by %in% colnames(obj[[]])){
       split.is.valid <- TRUE
    }
    if(mode %in% c("cluster+multiSplit", "cluster+expr+twoSplit", "cluster+multiSplit") &&
       !split.is.valid){
        stop("split.by must be valid for plotting mode: ", mode)
    }

    feature.is.valid <- FALSE
    if(!is.null(feature) &&
       feature %in% rownames(obj)){
        feature.is.valid <- TRUE
    }

    nPanels = switch(
        mode,
        "clusterOnly" = 1,
        "cluster+expr+noSplit" = 2,
        "cluster+expr+twoSplit" = 4,
        "cluster+multiSplit" = obj[[split.by]] %>% pull %>% unqiue,
        "cluster+expr+multiSplit" = obj[[split.by]] %>% pull %>% unique
    )

    if(nPanels >= 2){
        nCols <- 2
    }else{
        nCols <- 1
    }

    nRows <- ceiling(nPanels/2)
    ## seurat assay v5 syntax
    metaData <- obj[[col_name]]
    colnames(metaData) <- "meta"

    category <- as.factor(metaData$meta)
    catNames <- levels(category)
    levels(category) <- c(0:(length(levels(category))-1))
    catColors <- scales::hue_pal()(length(levels(category)))

    category <- category %>%
        as.character() %>%
        as.numeric()

    if(mode == "clusterOnly"){
        zData <- list(category)
        ## dataZ_type encode colorBy option of the regl-scatterplot
        zType <- c("category")
        colors <- list(catColors)
    }else if(mode == "cluster+expr+noSplit"){
        expr <- FetchData(obj, feature) %>% pull()
        exprColors <- grDevices::colorRampPalette(c("lightgrey", "#6450B5"))(100)
        zData <- list(category, expr)
        zType <- c("category", "expr")
        colors <- list(catColors, exprColors)
    }else if(mode == "cluster+expr+twoSplit"){
        catData <- list()
    }else if(mode == "cluster+multiSplit"){
        catData <- list()
    }else if(mode == "cluster+expr+multiSplit"){
        catData <- list()
    }else{
        catData <- list()
    }
    d <- list(
        nCols = nCols,
        nRows = nRows,
        mode = mode,
        zData = zData,
        catNames = catNames,
        colors = colors,
        zType = zType,
        feature = feature
    )
    return(d)
}
