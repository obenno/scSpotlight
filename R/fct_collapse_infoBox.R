#' collapse_infoBox 
#'
#' @description A fct function
#'
#' @return The return value, if any, from executing the function.
#'
#' @noRd
collapse_infoBox <- function(session){
    session$sendCustomMessage(type = "collapse_infoBox", message = "")
}

show_infoBox <- function(session){
    session$sendCustomMessage(type = "show_infoBox", message = "")
}
