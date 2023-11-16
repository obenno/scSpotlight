#' Download UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_Download_ui <- function(id){
  ns <- NS(id)
  tagList(
      selectInput(
          inputId = ns("savingAssayVersion"),
          label = "Seurat Assay Version",
          choices = c("Assay3", "Assay5"),
          selected = "Assay3",
          selectize = TRUE,
          width = NULL
      ),
      downloadButton(ns("downloadData"), "Download RDS File", style = "width:200px", class = "border border-1 border-primary shadow")
  )
}
    
#' Download Server Functions
#'
#' @noRd 
mod_Download_server <- function(id,
                                seuratObj){
    moduleServer( id, function(input, output, session){
        ns <- session$ns
        ## Download code
        output$downloadData <- downloadHandler(
            filename = function(){
                paste0("seuratObj.", Sys.Date(), ".rds")
            },
            content = function(file){
                obj <- seuratObj()
                assay <- DefaultAssay(obj)
                if(input$savingAssayVersion == "Assay3"){
                    obj[[assay]] <- as(object = seuratObj[[assay]], Class = "Assay")
                }
                showSpinnerNotification(
                    message = "Saving Object...",
                    id = "savingNotification",
                    session = session
                )
                base::saveRDS(obj, file)
                removeNotification(id = "savingNotification", session)
            },
            contentType = NULL,
            outputArgs = list()
        )

  })
}

#' showSpinnerNotification
#'
#' @importFrom shiny showNotification
#'
#' @noRd
showSpinnerNotification <- function(message,
                                    action = NULL,
                                    duration = NULL,
                                    closeButton = FALSE,
                                    type = "default",
                                    id,
                                    session = getDefaultReactiveDomain()){
    showNotification(
        ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                     role = "status",
                     span(class = "sr-only", "Loading...")),
                 message),
        action = action,
        duration = duration,
        closeButton = closeButton,
        type = type,
        id = id,
        session = session
    )
}
## To be copied in the UI
# mod_Download_ui("Download_1")
    
## To be copied in the server
# mod_Download_server("Download_1")
