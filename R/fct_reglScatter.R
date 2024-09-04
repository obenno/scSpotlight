#' transfer_reduction
#'
#' transfer reduction dataframe to javascript
#'
#' @noRd
transfer_reduction <- function(reductionData, session){
    session$sendCustomMessage(type = "transfer_reduction", reductionData)
}

#' transfer_meta
#'
#' transfer reduction dataframe to javascript
#'
#' @noRd
transfer_meta <- function(metaData, session){
    session$sendCustomMessage(type = "transfer_meta", metaData)
}

#' transfer_expression
#'
#' transfer multi feature expression dataframe to javascript
#'
#' @noRd
transfer_expression <- function(expressionData, session){
  ## use memCompress to shrink the data
  ## https://github.com/rstudio/shiny/issues/3633
  ##data  <- expressionData %>%
  ##  shiny:::toJSON() %>%
  ##  memCompress("gzip") %>%
  ##  jsonlite::base64_enc()
  session$sendCustomMessage(
    type = "transfer_expression",
    expressionData
  )
}

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
