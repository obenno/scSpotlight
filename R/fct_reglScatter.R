## This file contains app's data transfer related utilities

#' transfer_reduction
#'
#' transfer reduction dataframe to javascript
#'
#' @noRd
transfer_reduction <- function(reductionData, session){
  session$sendCustomMessage(
    type = "transfer_reduction",
    compress_message(reductionData)
  )
}

#' transfer_meta
#'
#' transfer reduction dataframe to javascript
#'
#' @noRd
transfer_meta <- function(metaData, session){
  session$sendCustomMessage(
    type = "transfer_meta",
    compress_message(metaData)
  )
}

#' transfer_expression
#'
#' transfer multi feature expression dataframe to javascript
#'
#' @noRd
transfer_expression <- function(expressionData, session){
  session$sendCustomMessage(
    type = "transfer_expression",
    compress_message(expressionData)
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

#' start_extract_expr
#'
#' Ask client to create feature sparkLine element
#'
#' @noRd
start_extract_expr <- function(feature, session){
  ## createSparkLine when start extracting expr
  session$sendCustomMessage(type = "createSparkLine", feature)
}

#' compress_message
#'
#' compress and encode message as base64
#'
#' @noRd
compress_message <- function(message){
  ## use memCompress to shrink the data
  ## https://github.com/rstudio/shiny/issues/3633
  data  <- message %>%
    shiny:::toJSON() %>%
    memCompress("gzip") %>%
    jsonlite::base64_enc()
  return(data)
}

#' write_compress_data
#'
#' compress data as base64 and write a binary file
#'
#' @noRd
write_expr_raw <- function(data, filePath){
  ## use memCompress to shrink the data
  ## https://github.com/rstudio/shiny/issues/3633
  d <- data %>%
    shiny:::toJSON() %>%
    memCompress("gzip")
  zz <- file(filePath, "wb")
  writeBin(d, zz)
  close(zz)
}
