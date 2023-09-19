#' prepare_scatterInput 
#'
#' @description Function to extract scatter reduction data
#'
#' @return A list of scatter reduction data transferred to javascript from shiny
#'
#' @import Seurat
#' @noRd
prepare_scatterReductionInput <- function(obj, reduction){
    ## seurat assay v5 syntax
    reduction_df <- Embeddings(object = obj[[reduction]])[, 1:2] %>%
        as.data.frame()
    colnames(reduction_df) <- c("X", "Y")
    return(reduction_df)
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
#' @noRd
prepare_scatterCatColorInput <- function(obj, col_name){
    ## seurat assay v5 syntax
    metaData <- obj[[col_name]]
    colnames(metaData) <- "meta"

    category <- as.factor(metaData$meta)
    catNames <- levels(category)
    levels(category) <- c(0:(length(levels(category))-1))
    colors <- scales::hue_pal()(length(levels(category)))

    category <- category %>%
        as.character() %>%
        as.numeric()
    d <-list(
        data = data.frame(catValues = category),
        catNames = catNames,
        catColors = colors
    )
    return(d)
}
