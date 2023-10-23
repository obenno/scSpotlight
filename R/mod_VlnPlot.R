#' VlnPlot UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
#' @importFrom ggplot2 theme
#' @importFrom promises future_promise
#' @importFrom waiter withWaiter
#' @import Seurat
mod_VlnPlot_ui <- function(id){
  ns <- NS(id)
  tagList(
      plotOutput(ns("vlnPlot")) %>%
      ##withWaiter()
      ##withSpinner(fill_container = T)
      withWaiterOnElement(
          target_element_ID = ns("vlnPlot"), # defined in infoBox_ui()
          html = waiter::spin_loaders(5, color = "var(--bs-primary)"),
          color = "#ffffff"
      )
  )
}

#' VlnPlot Server Functions
#'
#' @noRd 
mod_VlnPlot_server <- function(id,
                               obj,
                               group.by,
                               split.by,
                               selectedFeature){
  moduleServer( id, function(input, output, session){
    ns <- session$ns

    ##outputOptions(output, "vlnPlot", priority = -100)
    output$vlnPlot <- renderCachedPlot({

        validate(
            need(obj(), "VlnPlot will be shown here when seuratObj is ready")
        )
        req(group.by() != "None")
        ##req(selectedAssay())
        ## Visualize QC metrics as a violin plot
        if(group.by() == "orig.ident"){
            vln_ncol <- 4
        }else{
            vln_ncol <- 2
        }
        if(split.by() == "None"){
            split.by <- NULL
        }else{
            split.by <- split.by()
        }

        groupBy_number <- obj()[[group.by()]] %>%
            pull() %>% is.numeric()
        if(groupBy_number){
            group.by <- "orig.ident"
        }else{
            group.by <- group.by()
        }

        ## future_promise cannot utilize reactive expressions
        obj <- obj()
        selectedFeature <- selectedFeature()
        ## pt.size has huge impact on plotting time
        ## use different pt.size and alpha when object has different input cells
        cellNum <- Cells(obj()) %>% length()
        ##future_promise({
            if(cellNum < 20000){
                pt.size <- 2
                alpha <- 0.4
            }else if(cellNum < 100000){
                pt.size <- 1
                alpha <- 0.4
            }else if(cellNum < 200000){
                pt.size <- 0.5
                alpha <- 0.4
            }else{
                pt.size <- 0.2
                alpha <- 0.2
            }
            if(isTruthy(selectedFeature)){
                p <- VlnPlot(obj,
                             features = selectedFeature,
                             stack = FALSE,
                             pt.size = pt.size,
                             ##idents = NULL,
                             alpha = alpha,
                             group.by = group.by,
                             split.by = split.by)
            }else{
                p <- VlnPlot(obj,
                             features = c("nFeature_RNA", "nCount_RNA", "percent.mt", "percent.rp"),
                             ncol = vln_ncol,
                             stack = FALSE,
                             pt.size = pt.size,
                             ##idents = NULL,
                             alpha = alpha,
                             group.by = group.by,
                             split.by = split.by)
            }

            if(isTruthy(split.by)){
                p <- p+theme(legend.position = "right")
            }else{
                p <- p+NoLegend()
            }
            p
       ##})
    },
    cacheKeyExpr = {
        list(
            obj(),
            split.by(),
            group.by(),
            selectedFeature()
        )
    },
    cache = "session")
  })
}
    
## To be copied in the UI
# mod_VlnPlot_ui("VlnPlot_1")
    
## To be copied in the server
# mod_VlnPlot_server("VlnPlot_1")
