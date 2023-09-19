#' FindMarkers UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_FindMarkers_ui <- function(id){
  ns <- NS(id)
  tagList(
 
  )
}
    
#' FindMarkers Server Functions
#'
#' @noRd 
mod_FindMarkers_server <- function(id){
  moduleServer( id, function(input, output, session){
    ns <- session$ns
 
  })
}
    
## To be copied in the UI
# mod_FindMarkers_ui("FindMarkers_1")
    
## To be copied in the server
# mod_FindMarkers_server("FindMarkers_1")
