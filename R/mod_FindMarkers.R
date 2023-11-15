#' FindMarkers UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
mod_FindMarkers_ui <- function(id){
  ns <- NS(id)
  tagList(
      selectInput(
          inputId = ns("DEG_method"),
          label = "Choose DEG Calculation Method",
          choices = c("wilcox", "MAST"),
          selected = "wilcox"
      ),
      numericInput(
          inputId = ns("min.pct"),
          label = tagList("min.pct", infoIcon("only test genes that are detected in a minimum fraction of min.pct cells in either of the two populations. Meant to speed up the function by not testing genes that are very infrequently expressed. Default of Seurat v4 is 0.1", "right")),
          value = 0.1,
          min = 0.1,
          max = 1,
          step = 0.05,
          width = NULL
      ),
      numericInput(
          inputId = ns("logfc.threshold"),
          label = tagList("logfc.threshold", infoIcon("Limit testing to genes which show, on average, at least X-fold difference (log-scale) between the two groups of cells. Default of Seurat v4 is 0.25 Increasing logfc.threshold speeds up the function, but can miss weaker signals.", "right")),
          value = 0.25,
          min = 0,
          max = NA,
          step = 0.05,
          width = NULL
      ),
      actionButton(
          inputId = ns("runFindAllMarkers"),
          label = "Find Markers",
          icon = icon("stats", lib = "glyphicon"),
          width = "200px",
          class = c("border", "border-1", "border-primary", "shadow")
      )
  )
}

#' FindMarkers Server Functions
#'
#' @importFrom promises %...>% finally
#' @noRd 
mod_FindMarkers_server <- function(id,
                                   seuratObj,
                                   group.by){
    moduleServer( id, function(input, output, session){
        ns <- session$ns

        DEG_markers <- reactiveVal()
        observeEvent(input$runFindAllMarkers,{

            if(!isTruthy(seuratObj())){
                showNotification(
                    ui = "Please input single cell data before calculating markers...",
                    action = NULL,
                    duration = 3,
                    closeButton = TRUE,
                    type = "default",
                    session = session
                )
            }else{
                showNotification(
                    ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                                 role = "status",
                                 span(class = "sr-only", "Loading...")),
                             "Calculating DEG result..."),
                    action = NULL,
                    duration = NULL,
                    closeButton = FALSE,
                    type = "default",
                    id = "DEG_notification",
                    session = session
                )
                obj <- seuratObj()
                DEG_method <- input$DEG_method
                future_promise({
                    message("Started FindAllMarkers...")
                    if(group.by() != "None"){
                        ## save original idents
                        Idents(obj) <- group.by()
                    }
                    markers <- FindAllMarkers(obj,
                                              test.use = DEG_method,
                                              only.pos = TRUE,
                                              min.pct = input$min.pct,
                                              logfc.threshold = input$logfc.threshold)

                    markers
                }) %...>%
                DEG_markers() %>%
                finally(function(){ removeNotification(id = "DEG_notification") })

            }
            return(NULL) ## pretty important, or the future_promise will block the main thread
        })
    })

    DEG_out <- reactive({
        DEG_markers()
    })
    return(DEG_out)

}
    
## To be copied in the UI
# mod_FindMarkers_ui("FindMarkers_1")
    
## To be copied in the server
# mod_FindMarkers_server("FindMarkers_1")
