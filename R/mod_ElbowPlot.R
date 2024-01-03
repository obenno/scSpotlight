#' ElbowPlot UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_ElbowPlot_ui <- function(id){
  ns <- NS(id)
  tagList(
      plotOutput(ns("elbowPlot")) %>%
      withSpinner(fill_container = T)
      ##withWaiterOnElement(
      ##    target_element_ID = ns("elbowPlot"), # defined in infoBox_ui()
      ##    html = waiter::spin_loaders(5, color = "var(--bs-primary)"),
      ##    color = "#ffffff"
      ##)
  )
}
    
#' ElbowPlot Server Functions
#'
#' @noRd 
mod_ElbowPlot_server <- function(id,
                                 seuratObj){
  moduleServer( id, function(input, output, session){
    ns <- session$ns
    output$elbowPlot <- renderPlot({
        validate(
            need(seuratObj(), "Elbow plot will be shown here when seuratObj is ready")
        )
        ElbowPlot(seuratObj(), ndims = ncol(seuratObj()[["pca"]]), reduction = "pca")
    })
  })
}
    
## To be copied in the UI
# mod_ElbowPlot_ui("ElbowPlot_1")
    
## To be copied in the server
# mod_ElbowPlot_server("ElbowPlot_1")
