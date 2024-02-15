#' prepare_scatterMeta
#'
#' @importFrom dplyr pull
#' @importFrom shiny validate need
#' @importFrom scales hue_pal
#' @noRd
prepare_scatterMeta <- function(obj,
                                group.by = NULL,
                                mode = "clusterOnly",
                                split.by = NULL,
                                inputFeatures = NULL,
                                selectedFeature = NULL,
                                moduleScore = FALSE){
    ## Tranlate 'split.by = None' to NULL
    if(isTruthy(split.by) && split.by == "None"){
        split.by <- NULL
    }
    mode_supported <- c("clusterOnly",
                        "cluster+expr+noSplit",
                        "cluster+expr+twoSplit",
                        "cluster+multiSplit",
                        "cluster+expr+multiSplit")
    expression_mode <- c("cluster+expr+noSplit",
                        "cluster+expr+twoSplit",
                        "cluster+expr+multiSplit")
    validate(
        need(mode %in% mode_supported, "Plotting mode is not supported")
    )

    ## Get panel numbers
    nPanels <- get_nPanels(mode = mode,
                           obj = obj,
                           split.by = split.by)


    nCat <- obj[[group.by]] %>% pull %>% unique %>% length
    catColors <- scales::hue_pal()(nCat)
    ##exprColors <- grDevices::colorRampPalette(c("lightgrey", "#6450B5"))(100)

    d <- list(
        nPanels = nPanels,
        mode = mode,
        group_by = group.by,
        split_by = split.by,
        catColors = catColors,
        inputFeatures = inputFeatures,
        selectedFeature = selectedFeature,
        moduleScore = moduleScore
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
       (feature %in% rownames(obj) ||
        feature == "Module")){
        return(TRUE)
    }else{
        return(FALSE)
    }

}

#' countCells
#'
#' @import Seurat
#' @importFrom dplyr pull
#'
#' @noRd
countCells <- function(obj, col_name, catNames){
    k <- obj[[col_name]] %>%
        pull() %>%
        table()
    k[catNames] %>% as.numeric()
}