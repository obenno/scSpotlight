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
#' @importFrom shiny validate need
#' @noRd
prepare_scatterReductionInput <- function(obj, reduction,
                                          mode = "clusterOnly",
                                          split.by = NULL){

    ## Tranlate 'split.by = None' to NULL
    if(isTruthy(split.by) && split.by == "None"){
        split.by <- NULL
    }
    ## Define five plotting mode, each with different numbers of panels
    mode_supported <- c("clusterOnly",
                        "cluster+expr+noSplit",
                        "cluster+expr+twoSplit",
                        "cluster+multiSplit",
                        "cluster+expr+multiSplit")
    validate(
        need(mode %in% mode_supported, "Plotting mode is not supported")
    )

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
        validate(
            need(split.is.valid(obj, split.by), "split.by is invalid")
        )

        split.by.levelNumber <- obj[[split.by]] %>%
            pull() %>%
            unique() %>%
            length()
        validate(
            need(split.by.levelNumber == 2, "split.by has more than 2 levels")
        )

        split_vector <- obj[[split.by]] %>%
            pull()
        reduction_splitList <- split(reduction_df, split_vector)
        ## four panels
        pointsData <- rep(reduction_splitList, each = 2)
    }else if(mode == "cluster+multiSplit"){
        validate(
            need(split.is.valid(obj, split.by), "split.by is invalid")
        )

        split_vector <- obj[[split.by]] %>%
            pull()
        reduction_splitList <- split(reduction_df, split_vector)
        ## Many panels
        pointsData <- reduction_splitList
    }else if(mode == "cluster+expr+multiSplit"){
        validate(
            need(split.is.valid(obj, split.by), "split.by is invalid")
        )

        split_vector <- obj[[split.by]] %>%
            pull()
        reduction_splitList <- split(reduction_df, split_vector)
        ## Many panels
        pointsData <- reduction_splitList
    }
    ## remove list element names to ensure it will be translated to a list not object
    names(pointsData) <- NULL
    reduction_data <- list(
        nPanels = nPanels,
        ##nCols = nCols,
        ##nRows = nRows,
        mode = mode,
        pointsData  = pointsData
    )

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
#' @importFrom shiny need validate
#' @noRd
prepare_scatterCatColorInput <- function(obj, col_name,
                                         mode = "clusterOnly",
                                         split.by = NULL,
                                         feature = NULL){

    ## Tranlate 'split.by = None' to NULL
    if(isTruthy(split.by) && split.by == "None"){
        split.by <- NULL
    }
    mode_supported <- c("clusterOnly",
                        "cluster+expr+noSplit",
                        "cluster+expr+twoSplit",
                        "cluster+multiSplit",
                        "cluster+expr+multiSplit")
    metaCols <- obj[[]] %>% colnames
    validate(
        need(mode %in% mode_supported, "Plotting mode is not supported")
    )

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
    cells <- rownames(metaData)
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
    ## zType: indicates zData type (category or expr)
    ## colos: color codes for each panel
    ## panelTitles: titles of each panel
    ## exprMin: expression min (for colorScale in javascript)
    ## exprMax: expression max (for colorScale in javascript)

    exprMin <- NULL
    exprMax <- NULL
    labelData <- NULL

    if(mode == "clusterOnly"){
        zData <- list(category)
        ## zType encode colorBy option of the regl-scatterplot
        zType <- list("category")
        colors <- list(catColors)
        panelTitles <- list(col_name)
        labelData <- list(paste0("Cat: ", metaData$meta))
        cellData <- list(cells)
    }else if(mode == "cluster+expr+noSplit"){
        validate(
            need(feature.is.valid(obj, feature), "Feature is invalid")
        )

        expr <- FetchData(obj, feature) %>% pull()
        exprMin <- min(expr)
        exprMax <- max(expr)
        exprColors <- grDevices::colorRampPalette(c("lightgrey", "#6450B5"))(100)

        zData <- list(category, expr)
        zType <- list("category", "expr")
        colors <- list(catColors, exprColors)
        panelTitles <- list(col_name, feature)
        ## expr value + category, as label data
        labels <- paste0("Cat: ",metaData$meta, " Expr: ", signif(expr, 3))
        labelData <- list(labels, labels)
        cellData <- list(cells, cells)
    }else if(mode == "cluster+expr+twoSplit"){
        validate(
            need(feature.is.valid(obj, feature), "Feature is invalid"),
            need(split.is.valid(obj, split.by), "split.by is invalid")
        )

        split.by.levelNumber <- obj[[split.by]] %>%
            pull() %>%
            unique() %>%
            length()
        validate(
            need(split.by.levelNumber == 2, "split.by has more than 2 levels")
        )

        split_vector <- obj[[split.by]] %>%
            pull()
        category_splitList <- split(category, split_vector)
        metaData_splitList <- split(metaData$meta, split_vector)
        cellData_splitList <- split(cells, split_vector)

        expr <- FetchData(obj, feature) %>% pull()
        exprMin <- min(expr)
        exprMax <- max(expr)
        expr_splitList <- split(expr, split_vector)

        exprColors <- grDevices::colorRampPalette(c("lightgrey", "#6450B5"))(100)
        ## four panels
        zData <- list()
        labelData <- list()
        cellData <- list()
        for(i in 1:length(category_splitList)){
            zData <- c(zData, category_splitList[i], expr_splitList[i])
            labels <- paste0("Cat: ", metaData_splitList[[i]], " Expr: ", signif(expr_splitList[[i]], 3))
            labelData <- c(labelData, list(labels, labels))
            cellData <- c(cellData, cellData_splitList[i], cellData_splitList[i])
        }
        zType <- c("category", "expr", "category", "expr")
        colors <- list(catColors, exprColors, catColors, exprColors)
        panelTitles <- list()
        panelColNames <- c(col_name, feature)
        panelRowNames <- names(category_splitList)
        for(i in 1:length(panelRowNames)){
            panelTitles <- c(panelTitles,
                             paste(panelRowNames[i], panelColNames[1], sep = " : "),
                             paste(panelRowNames[i], panelColNames[2], sep = " : "))
        }
        panelTitles <- panelTitles %>% as.list()

    }else if(mode == "cluster+multiSplit"){
        validate(
            need(split.is.valid(obj, split.by), "split.by is invalid")
        )

        split_vector <- obj[[split.by]] %>%
            pull()
        category_splitList <- split(category, split_vector)
        metaData_splitList <- split(metaData$meta, split_vector)

        zData <- category_splitList
        zType <- rep("category", length(zData)) %>%
            as.list()
        colors <- list()
        for(i in 1:length(zData)){
            colors[[i]] <- catColors
        }
        panelTitles <- names(category_splitList) %>% as.list()

        labelData <- metaData_splitList %>%
            lapply(function(x) paste0("Cat: ", x))
        cellData <- split(cells, split_vector)
    }else if(mode == "cluster+expr+multiSplit"){
        validate(
            need(feature.is.valid(obj, feature), "Feature is invalid"),
            need(split.is.valid(obj, split.by), "split.by is invalid")
        )

        split_vector <- obj[[split.by]] %>%
            pull()
        category_splitList <- split(category, split_vector)

        expr <- FetchData(obj, feature) %>% pull()
        exprMin <- min(expr)
        exprMax <- max(expr)
        expr_splitList <- split(expr, split_vector)

        exprColors <- grDevices::colorRampPalette(c("lightgrey", "#6450B5"))(100)

        zData <- expr_splitList
        zType <- rep("expr", length(zData)) %>%
            as.list()
        colors <- list()
        for(i in 1:length(zData)){
            colors[[i]] <- exprColors
        }
        panelTitles <- paste(names(category_splitList), feature, sep=" : ") %>% as.list()

        labelData <- expr_splitList %>%
            lapply(function(x) paste0("Expr: ", signif(x, 3)))
        cellData <- split(cells, split_vector)
    }
    ## remove list element names to ensure it will be translated to a list not object
    names(zData) <- NULL
    names(labelData) <- NULL
    names(cellData) <- NULL
    d <- list(
        nPanels = nPanels,
        ##nCols = nCols,
        ##nRows = nRows,
        mode = mode,
        zData = zData,
        colors = colors,
        zType = zType,
        panelTitles = panelTitles,
        labelData = labelData,
        cellData = cellData,
        feature = feature,
        exprMin = exprMin,
        exprMax = exprMax
    )

    return(d)
}

#' get_nPanels
#'
#' @description Auxiliary function to get nPanels for different plotting mode
#'
#' @import Seurat
#' @importFrom dplyr pull
#' @importFrom shiny validate need
#' @noRd
get_nPanels <- function(mode, obj, split.by = FALSE){

    mode_supported <- c("clusterOnly",
                        "cluster+expr+noSplit",
                        "cluster+expr+twoSplit",
                        "cluster+multiSplit",
                        "cluster+expr+multiSplit")
    validate(
        need(mode %in% mode_supported, "Plotting mode is not supported")
    )

    nPanels = switch(
        mode,
        "clusterOnly" = 1,
        "cluster+expr+noSplit" = 2,
        "cluster+expr+twoSplit" = 4,
        "cluster+multiSplit" = obj[[split.by]] %>% pull %>% unique %>% length,
        "cluster+expr+multiSplit" = obj[[split.by]] %>% pull %>% unique %>% length
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
