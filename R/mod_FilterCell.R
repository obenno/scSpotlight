#' FilterCell UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
#' @importFrom shinyWidgets sliderTextInput
#' 
mod_FilterCell_ui <- function(id){
  ns <- NS(id)
  tagList(
      cellFiltering_settings <- list(
          shinyWidgets::sliderTextInput(
              inputId = ns("min.cells"),
              label = "Features observed in at least below number of cells:",
              choices = seq(1, 20, by=1),
              selected = 3,
              grid = TRUE
          ),
          shinyWidgets::sliderTextInput(
              inputId = ns("min.features"),
              label = "Cells containing at least below number of features:",
              choices = seq(50, 500, by=50),
              selected = 200,
              grid = TRUE
          ),
          numericInput(
              inputId = "nFeature_min",
              label = "nFeature min value",
              value = 200,
              step = 100
          ),
          numericInput(
              inputId = "nFeature_max",
              label = "nFeature max value",
              value = 20000,
              step = 100
          ),
          numericInput(
              inputId = "percent.mt_max",
              label = "Mitochondrial nCount Percentage cutoff",
              value = 50,
              step = 5
          ),
          actionButton(
              inputId = "filter_cell",
              label = "Filter Cells",
              icon = icon("filter"),
              style = "width:200px",
              class = "border border-1 border-primary shadow"
          )
      )
  )
}
    
#' FilterCell Server Functions
#'
#' @noRd 
mod_FilterCell_server <- function(id){
  moduleServer( id, function(input, output, session){
    ns <- session$ns
 
  })
}
    
## To be copied in the UI
# mod_FilterCell_ui("FilterCell_1")
    
## To be copied in the server
# mod_FilterCell_server("FilterCell_1")
