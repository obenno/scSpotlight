#' AssignCellCluster UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_AssignCellCluster_ui <- function(id){
  ns <- NS(id)
  tagList(
 
  )
}
    
#' AssignCellCluster Server Functions
#'
#' @noRd 
mod_AssignCellCluster_server <- function(id){
  moduleServer( id, function(input, output, session){
    ns <- session$ns
 
  })
}
    
## To be copied in the UI
# mod_AssignCellCluster_ui("AssignCellCluster_1")
    
## To be copied in the server
# mod_AssignCellCluster_server("AssignCellCluster_1")
