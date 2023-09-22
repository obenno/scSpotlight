#' mainClusterPlot UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList 
mod_mainClusterPlot_ui <- function(id){
  ns <- NS(id)
  tagList(
     card(
         id = ns("mainClusterPlot"),
         full_screen = TRUE,
         height = "500px",
         class = c("border", "border-primary", "border-2", "mb-1", "shadow"),
         ## add resize property
         style = "resize:both;",
         card_body(
             id = ns("clusterPlot"),
             height="600px",
             class = "align-items-center m-0 p-1",
             div(id = ns("note"), class = "mainClusterPlotNote shadow")
         )
     )
  )
}

#' mainClusterPlot Server Functions
#'
#' @noRd 
mod_mainClusterPlot_server <- function(id, scatterReductionIndicator, scatterColorIndicator, scatterReductionInput, scatterColorInput){
  moduleServer( id, function(input, output, session){
      ns <- session$ns
    ## Plotting with the last priority
    observeEvent( scatterReductionIndicator(), {
        ##message("scatterReductionIndicator() is ", scatterReductionIndicator())
        ##message("scatterReductionInput() is ", is.null(scatterReductionInput()))
        req(scatterReductionIndicator() > 0)
        reglScatter_reduction(scatterReductionInput(), session)
    }, priority = -100)

      observeEvent( scatterColorIndicator(), {
        req(scatterColorIndicator() > 0)
        reglScatter_color(scatterColorInput(), session)
    }, priority = -100)
  })
}

## To be copied in the UI
# mod_mainClusterPlot_ui("mainClusterPlot_1")
    
## To be copied in the server
# mod_mainClusterPlot_server("mainClusterPlot_1")
