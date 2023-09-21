#' prepare_scatterInput 
#'
#' @description Function to extract scatter reduction data. We use two functions to
#'              transfer reduction data (points XY) and category/expression data
#'              separately. prepare_scatterReductionInput() will only prepare and
#'              transfer reduction data.
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

    ## Get nPanels
    nPanels <- get_nPanels(mode = mode,
                           obj = obj,
                           split.by = split.by)

    if(nPanels >= 2){
        nCols <- 2
    }else{
        nCols <- 1
    }

    nRows <- ceiling(nPanels/2)

    ## Get basic reduction data
    reduction_df <- Embeddings(object = obj[[reduction]])[, 1:2] %>%
        as.data.frame()
    colnames(reduction_df) <- c("X", "Y")

    if(mode == "clusterOnly"){
        pointsData <- list(reduction_df)
    }else if(mode == "cluster+expr+noSplit"){
        pointsData <- list(reduction_df, reduction_df)
    }else if(mode == "cluster+expr+twoSplit"){
        need()
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
#' @description Function to extract scatter category data as well as other meta info
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

    ## Get panel numbers
    nPanels <- get_nPanels(mode = mode,
                           obj = obj,
                           split.by = split.by)

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

    ## Data of each panel were combined into a list
    ## Compulsory data:
    ## zData: values encode category (integer) or expression value (seurat data slot)
    ## zType: indicate zData type
    ## colos: color codes for each panel
    ## panelTitles: titles of each panel
    if(mode == "clusterOnly"){
        zData <- list(category)
        ## zType encode colorBy option of the regl-scatterplot
        zType <- c("category")
        colors <- list(catColors)
        panelTitles <- list("Category")
    }else if(mode == "cluster+expr+noSplit"){
        if(feature.is.valid(obj, feature)){
            expr <- FetchData(obj, feature) %>% pull()
            exprColors <- grDevices::colorRampPalette(c("lightgrey", "#6450B5"))(100)
        }else{
            ## Throw errors, modify later
            stop("feature is invalid")
        }
        zData <- list(category, expr)
        zType <- c("category", "expr")
        colors <- list(catColors, exprColors)
        panelTitles <- list("Category", feature)
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
        panelTitles = panelTitles,
        feature = feature
    )
    return(d)
}

#' get_nPanels
#'
#' @description Auxiliary function to get nPanels for different plotting mode
#'
#' @import Seurat
#' @importFrom dplyr pull
#' @noRd
get_nPanels <- function(mode, obj, split.by = FALSE){
    nPanels = switch(
        mode,
        "clusterOnly" = 1,
        "cluster+expr+noSplit" = 2,
        "cluster+expr+twoSplit" = 4,
        "cluster+multiSplit" = obj[[split.by]] %>% pull %>% unqiue,
        "cluster+expr+multiSplit" = obj[[split.by]] %>% pull %>% unique
    )
    return(nPanels)
}


#' split.is.valid
#'
#' @description Auxiliary function to check if split.by is valid
#'
#' @import Seurat
#' @importFrom shiny isTruthy
#' @noRd
split.is.valid <- function(obj, split.by){

    if(isTruthy(split.by) &&
       split.by %in% colnames(obj[[]])){
        return(TRUE)
    }else{
        return(FALSE)
    }

}

#' feature.is.valid
#'
#' @description Auxiliary function to check if split.by is valid
#'
#' @import Seurat
#' @importFrom shiny isTruthy
#' @noRd
feature.is.valid <- function(obj, feature){

    if(isTruthy(feature) &&
       feature %in% rownames(obj)){
        return(TRUE)
    }else{
        return(FALSE)
    }

}
