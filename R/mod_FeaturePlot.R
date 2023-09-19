#' FeaturePlot UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_FeaturePlot_ui <- function(id){
  ns <- NS(id)
  tagList(
 
  )
}
    
#' FeaturePlot Server Functions
#'
#' @noRd 
mod_FeaturePlot_server <- function(id){
  moduleServer( id, function(input, output, session){
    ns <- session$ns
 
  })
}
    
## To be copied in the UI
# mod_FeaturePlot_ui("FeaturePlot_1")
    
## To be copied in the server
# mod_FeaturePlot_server("FeaturePlot_1")
