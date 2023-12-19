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
#' @importFrom Seurat Layers
#' @importFrom dplyr case_when
#' @importFrom stringr str_detect
#' @importFrom SeuratObject SaveSeuratRds
#' @noRd
mod_Download_server <- function(id,
                                seuratObj){
    moduleServer( id, function(input, output, session){
        ns <- session$ns
        ## Download code
        output$downloadData <- downloadHandler(
            filename = function(){
                obj <- seuratObj()
                prefix <- "scSpotlight."
                outFile <- case_when(
                    input$savingAssayVersion == "Assay3" ~ paste0(prefix, Sys.Date(), ".Rds"),
                    "counts" %in% Layers(obj) && class(GetAssayData(obj, layer="counts")) != "dgCMatrix" ~ paste0(prefix, Sys.Date(), ".tar.gz"),
                    "data" %in% Layers(obj) && class(GetAssayData(obj, layer="data")) != "dgCMatrix" ~ paste0(prefix, Sys.Date(), ".tar.gz"),
                    TRUE ~ paste0(prefix, Sys.Date(), ".Rds")
                )
            },
            content = function(file){
                obj <- seuratObj()
                assay <- DefaultAssay(obj)
                message(str(obj))
                if(input$savingAssayVersion == "Assay3" && class(obj[[assay]]) != "Assay"){
                    message("Coverting obj assay to version 3...")
                    obj[[assay]] <- as(object = obj[[assay]], Class = "Assay")
                }
                showSpinnerNotification(
                    message = "Saving Object...",
                    id = "savingNotification",
                    session = session
                )
                if(str_detect(file, "\\.Rds$")){
                    message("Saving Rds...")
                    SaveSeuratRds(obj, file)
                }else{
                    subPath <- tempfile(pattern = "scSpotlight_out_") %>%
                        basename()
                    dir.create(subPath)
                    prefix <- "scSpotlight."
                    rdsOut <- paste0(prefix, Sys.Date(), ".Rds")
                    SaveSeuratRds(
                        obj,
                        file.path(subPath, rdsOut),
                        move = TRUE,
                        relative = TRUE
                    )
                    system2("tar", c("cvzf", file, subPath))
                }
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
