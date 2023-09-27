#' reglScatter
#'
#' @description reglScatter function to create a new plot
#'
#' @return The return value, if any, from executing the function.
#'
#' @noRd
reglScatter <- function(elID, pointsData, colorsData, session){
    x = list(
        id = elID,
        pointsData = pointsData,
        colorData = colorsData
    )
    session$sendCustomMessage(type = "reglScatter", x)
}

#' reglScatter_reduction
#'
#' @description reglScatter function to populate reduction point data
#'
#' @return The return value, if any, from executing the function.
#'
#' @noRd
reglScatter_reduction <- function(pointsData, session){
    ##x = list(
    ##    ##id = elID,
    ##    pointsData = pointsData
    ##)
    ##message(str(pointsData))
    session$sendCustomMessage(type = "reglScatter_reduction", pointsData)
}

#' reglScatter_color
#'
#' @description reglScatter function to update point colors
#'
#' @return The return value, if any, from executing the function.
#'
#' @noRd
reglScatter_color <- function(colorsData, session){
    ##x = list(
    ##    id = elID,
    ##    colorsData = colorsData[["data"]],
    ##    catNames = colorsData[["catNames"]],
    ##    catColors = colorsData[["catColors"]]
    ##)
    session$sendCustomMessage(type = "reglScatter_color", colorsData)
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