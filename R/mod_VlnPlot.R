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
#' @import Seurat
mod_VlnPlot_ui <- function(id){
  ns <- NS(id)
  tagList(
      plotOutput(ns("vlnPlot"))
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

    output$vlnPlot <- renderPlot({
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
        }
        if(isTruthy(selectedFeature())){
            p <- VlnPlot(obj(),
                         features = selectedFeature(),
                         stack = FALSE,
                         pt.size = 2,
                         ##idents = NULL,
                         alpha = 0.4,
                         group.by = group.by(),
                         split.by = split.by)
        }else{
            p <- VlnPlot(obj(),
                         features = c("nFeature_RNA", "nCount_RNA", "percent.mt", "percent.rp"),
                         ncol = vln_ncol,
                         stack = FALSE,
                         pt.size = 2,
                         ##idents = NULL,
                         alpha = 0.4,
                         group.by = group.by(),
                         split.by = split.by)
        }

        if(isTruthy(split.by)){
            p <- p+theme(legend.position = "right")
        }else{
            p <- p+NoLegend()
        }
        p
    })
  })
}
    
## To be copied in the UI
# mod_VlnPlot_ui("VlnPlot_1")
    
## To be copied in the server
# mod_VlnPlot_server("VlnPlot_1")
