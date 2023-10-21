#' DotPlot UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
#' @import ggplot2
#' @importFrom waiter withWaiter
mod_DotPlot_ui <- function(id){
  ns <- NS(id)
  tagList(
      plotOutput(ns("dotPlot")) %>%
      ##withWaiter()
      ##withSpinner(fill_container = T)
      withWaiterOnElement(
          target_element_ID = ns("dotPlot"), # defined in infoBox_ui()
          html = waiter::spin_loaders(5, color = "var(--bs-primary)"),
          color = "#ffffff"
      )
  )
}

#' DotPlot Server Functions
#'
#' @noRd 
mod_DotPlot_server <- function(id,
                               obj,
                               group.by,
                               split.by,
                               inputFeatures){
  moduleServer( id, function(input, output, session){
    ns <- session$ns

    output$dotPlot <- renderCachedPlot({
        validate(
            need(obj(), "DotPlot will be shown here when seuratObj is ready.")
        )
        validate(
            need(inputFeatures(), "DotPlot will be shown here when genes were indicated.")
        )
        req(group.by()!="None")
        ## Visualize QC metrics as a violin plot
        group.by <- group.by()

        if(split.by() == "None"){
            split.by <- NULL
            colors <- c("lightgrey", "#5D3FD3")
        }else{
            split.by <- split.by()
            n.split.by = obj()[[]] %>%
                pull({{ split.by }}) %>%
                unique() %>% length()
            if(n.split.by == 2){
                colors <- c("#ef8a62", "#67a9cf")
            }else{
                colors <- c("lightgrey", "#5D3FD3")
                split.by <- NULL
                showNotification(
                    ui = "DotPlot only supports two groups in 'split.by'",
                    action = NULL,
                    duration = 3,
                    closeButton = TRUE,
                    type = "default",
                    session = session
                )
            }

        }
        p <- DotPlot(obj(),
                     features = inputFeatures(),
                     group.by = group.by,
                     split.by = split.by,
                     cols = colors)+
            xlab("")+
            theme(axis.text.x = element_text(angle=45, hjust=1, vjust = 0.5))
        p
    },
    cacheKeyExpr = {
        list(
            obj(),
            split.by(),
            group.by(),
            inputFeatures()
        )
    },
    cache = "session")
  })
}

## To be copied in the UI
# mod_DotPlot_ui("DotPlot_1")

## To be copied in the server
# mod_DotPlot_server("DotPlot_1")
