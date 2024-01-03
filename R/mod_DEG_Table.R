#' DEG_Table UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
#' @importFrom DT renderDT DTOutput
mod_DEG_Table_ui <- function(id){
  ns <- NS(id)
  tagList(
      DTOutput(ns("DEG_list"), width = "100%", height = "auto", fill = TRUE) %>%
      withSpinner(fill_container = T)
      ##withWaiterOnElement(
      ##    target_element_ID = ns("DEG_list"), # defined in infoBox_ui()
      ##    html = waiter::spin_loaders(5, color = "var(--bs-primary)"),
      ##    color = "#ffffff"
      ##)

  )
}
    
#' DEG_Table Server Functions
#'
#' @noRd 
mod_DEG_Table_server <- function(id,
                                 DEG_markers){
  moduleServer( id, function(input, output, session){
      ns <- session$ns
      output$DEG_list <- renderDT({
          validate(
              need(DEG_markers(), 'Please use "Find Markers" to generate DEG marker list')
          )
          DEG_markers()
      })

  })
}
    
## To be copied in the UI
# mod_DEG_Table_ui("DEG_Table_1")
    
## To be copied in the server
# mod_DEG_Table_server("DEG_Table_1")
