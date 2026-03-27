## This file contains app's data transfer related utilities

reglScatter_plot <- function(plotMetaData, session){
    session$sendCustomMessage(type = "reglScatter_plot", plotMetaData)
}

#' reglScatter_removeGrid
#'
#' @noRd
reglScatter_removeGrid <- function(session){
    session$sendCustomMessage(type = "reglScatter_removeGrid", "")
}

#' reglScatter_addGoBack
#'
#' @noRd
reglScatter_addGoBack <- function(session){
    session$sendCustomMessage(type = "reglScatter_addGoBack", "")
}


#' reglScatter_deselect
#'
#' Ask reglScatter to deselect all the points on instances
#'
#' @noRd
reglScatter_deselect <- function(session){
    session$sendCustomMessage(type = "reglScatter_deselect", "")
}

#' start_extract_expr
#'
#' Ask client to create feature sparkLine element
#'
#' @noRd
start_extract_expr <- function(feature, session){
  ## createSparkLine when start extracting expr
  session$sendCustomMessage(type = "createSparkLine", feature)
}
