#' Download UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_Download_ui <- function(id){
  ns <- NS(id)
  tagList(
 
  )
}
    
#' Download Server Functions
#'
#' @noRd 
mod_Download_server <- function(id){
  moduleServer( id, function(input, output, session){
    ns <- session$ns
 
  })
}
    
## To be copied in the UI
# mod_Download_ui("Download_1")
    
## To be copied in the server
# mod_Download_server("Download_1")
