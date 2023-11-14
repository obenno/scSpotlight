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
              inputId = ns("nFeature_min"),
              label = "nFeature min value",
              value = 200,
              step = 100
          ),
          numericInput(
              inputId = ns("nFeature_max"),
              label = "nFeature max value",
              value = 20000,
              step = 100
          ),
          numericInput(
              inputId = ns("percent.mt_max"),
              label = "Mitochondrial nCount Percentage cutoff",
              value = 50,
              step = 5
          ),
          actionButton(
              inputId = ns("filter_cell"),
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
#' @importFrom scales label_comma
#' 
#' @noRd 
mod_FilterCell_server <- function(id,
                                  seuratObj,
                                  hvgSelectMethod,
                                  clusterDims,
                                  clusterResolution){
    moduleServer( id, function(input, output, session){
        ns <- session$ns
        observeEvent(input$filter_cell, {
            req(seuratObj())
            withProgress(
                message = "Filtering Cells & Updating Reductions...",
                {
                    obj <- subset(seuratObj(),
                                  subset = nFeature_RNA > input$nFeature_min &
                                      nFeature_RNA < input$nFeature_max &
                                      percent.mt < input$percent.mt_max)
                    obj <- standard_process_seurat(obj, normalization = FALSE,
                                                   hvg_method = hvgSelectMethod(),
                                                   ndims = clusterDims(),
                                                   res = clusterResolution())
                    seuratObj(obj)
                }
            )

            nCells <- length(Cells(obj))
            showNotification(
                ui = paste0(scales::label_comma()(nCells), " Cells Left."),
                action = NULL,
                duration = 5,
                closeButton = TRUE,
                type = "message",
                session = session
            )


        })

    })
}
    
## To be copied in the UI
# mod_FilterCell_ui("FilterCell_1")
    
## To be copied in the server
# mod_FilterCell_server("FilterCell_1")
