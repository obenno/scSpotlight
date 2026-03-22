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
      plotOutput(
          ns("elbowPlot"),
          width = "100%",
          height = "100%"
      )
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
    plot_width <- reactive({
        session$clientData[[paste0("output_", ns("elbowPlot"), "_width")]]
    })

    plot_height <- reactive({
        session$clientData[[paste0("output_", ns("elbowPlot"), "_height")]]
    })

    output$elbowPlot <- renderPlot(
        {
            obj <- seuratObj()
            width <- plot_width()
            height <- plot_height()

            validate(
                need(obj, "Elbow plot will be shown here when seuratObj is ready"),
                need("pca" %in% SeuratObject::Reductions(obj), "Elbow plot is available when PCA data exists"),
                need(!is.null(width) && width > 0, ""),
                need(!is.null(height) && height > 0, "")
            )

            ElbowPlot(obj, ndims = ncol(obj[["pca"]]), reduction = "pca")
        },
        width = plot_width,
        height = plot_height,
        res = 96
    )

    outputOptions(output, "elbowPlot", suspendWhenHidden = FALSE)
  })
}
    
## To be copied in the UI
# mod_ElbowPlot_ui("ElbowPlot_1")
    
## To be copied in the server
# mod_ElbowPlot_server("ElbowPlot_1")
