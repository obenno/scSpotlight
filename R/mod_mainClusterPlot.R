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
             height="600px",
             class = "align-items-center m-0 p-1",
             as_fill_carrier(
                 div(id = ns("clusterPlot"))
             ),
             div(id = ns("note"), class = "mainClusterPlotNote")
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
      ## since the plot div id will be changed when calling module,
      ## send the id to js for initializing scatterplot instance
    ## data <- reactive({
    ##     req(input$dataInput)
    ##     d <- read_tsv(input$dataInput$datapath,
    ##                   col_names = TRUE)
    ##     d <- d %>%
    ##         column_to_rownames("NAME") %>%
    ##         select(X, Y, cell_type__ontology_label)
    ##       colnames(d) <- c('X', 'Y', 'meta')
    ##       category <- as.factor(d$meta)
    ##       levels(category) <- c(0:(length(levels(category))-1))
    ##       colors <- scales::hue_pal()(length(levels(category)))
    ##       ##names(colors) <- levels(category)
    ##       d <- d %>% mutate(Z = as.numeric(category)-1) %>%
    ##           select(X, Y, Z)
    ##       list(
    ##           pointsData = d,
    ##           colors = colors
    ##       )
    ##       ##d <- d[1:5000,]
    ##  })

    ## Plotting with the last priority
    observeEvent( scatterReductionIndicator(), {
        ##message("scatterReductionIndicator() is ", scatterReductionIndicator())
        ##message("scatterReductionInput() is ", is.null(scatterReductionInput()))
        req(scatterReductionIndicator() > 0)
        reglScatter_reduction(ns("clusterPlot"), scatterReductionInput(), session)
    }, priority = -100)

      observeEvent( scatterColorIndicator(), {
        req(scatterColorIndicator() > 0)
        reglScatter_color(ns("clusterPlot"), scatterColorInput(), session)
    }, priority = -100)
  })
}

## To be copied in the UI
# mod_mainClusterPlot_ui("mainClusterPlot_1")
    
## To be copied in the server
# mod_mainClusterPlot_server("mainClusterPlot_1")
