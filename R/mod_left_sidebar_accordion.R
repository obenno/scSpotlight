#' left_sidebar_accordion UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_left_sidebar_accordion_ui <- function(id){
  ns <- NS(id)
  tagList(
      accordion(
          id = ns("left_sidebar"),
          accordion_panel(title = "Test", value="test")
       ##accordion_panel(
       ##    "File Input",
       ##    icon = bsicons::bs_icon("file-earmark-arrow-up"),
       ##    tagList(),
       ##    ##mod_dataInput_inputUI("dataInput"),
       ##    class = "bg-light text-black"
       ##)
     )
  )
}
    
#' left_sidebar_accordion Server Functions
#'
#' @noRd 
mod_left_sidebar_accordion_server <- function(id){
  moduleServer( id, function(input, output, session){
    ns <- session$ns
 
  })
}
    
## To be copied in the UI
# mod_left_sidebar_accordion_ui("left_sidebar_accordion_1")
    
## To be copied in the server
# mod_left_sidebar_accordion_server("left_sidebar_accordion_1")
