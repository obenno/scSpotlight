#' prepare_scatterMeta
#'
#' @importFrom dplyr pull tbl select
#' @importFrom shiny validate need
#' @importFrom scales hue_pal
#' @importFrom SeuratObject %||%
#' @noRd
prepare_scatterMeta <- function(con,
                                group.by = NULL,
                                mode = "clusterOnly",
                                split.by = NULL,
                                inputFeatures = NULL,
                                selectedFeature = NULL,
                                moduleScore = FALSE){
  ## ensure mode is in the list
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

  ## Translate 'split.by = None' to NULL
  if(split.by == "None"){
    split.by <- NULL
  }
  if(isTruthy(split.by)){
    ## Get number of the "split.by" column levels
    n_split.by <- tbl(con, "metaData") %>%
      select(split.by) %>%
      pull() %>%
      unique() %>%
      length()
  }

    ## Get panel numbers
    nPanels = switch(
        mode,
        "clusterOnly" = 1,
        "cluster+expr+noSplit" = 2,
        "cluster+expr+twoSplit" = 4,
        "cluster+multiSplit" = n_split.by %||% 1,
        "cluster+expr+multiSplit" = n_split.by %||% 1
    )

  nCat <- tbl(con, "metaData") %>% select(group.by) %>% pull() %>% unique %>% length
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
