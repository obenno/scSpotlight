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
          inputId = ns("downloadFormat"),
          label = "Result Format",
          choices = "",
          selected = "",
          selectize = TRUE,
          width = NULL
      ),
      downloadButton(
          ns("downloadData"),
          "Download",
          style = "width:200px",
          class = "border border-1 border-primary shadow"
      )
  )
}

#' Download Server Functions
#'
#' @importFrom dplyr case_when
#' @importFrom stringr str_detect
#' @importFrom SeuratObject SaveSeuratRds Layers
#'
#' @noRd
mod_Download_server <- function(id,
                                seuratObj,
                                BPCells){
    moduleServer( id, function(input, output, session){
        ns <- session$ns
        ## Download code

        observe({
            runningMode <- golem::get_golem_options("runningMode")
            message("download, runningMode: ", runningMode)
            if(runningMode == "processing" && isTruthy(seuratObj()) && isTruthy(BPCells())){
                downloadFormat <- c("Rds", "duckdb", "BPCells", "metaData")
            }else if(runningMode == "processing" && isTruthy(seuratObj())){
                downloadFormat <- c("Rds", "duckdb", "metaData")
            }else if(runningMode == "processing"){
                downloadFormat <- c("duckdb", "metaData")
            }else{
                downloadFormat <- c("metaData")
            }

            if(!file.exists(session$userData$duckdb) && !isTruthy(seuratObj())){
                downloadFormat <- character(0)
            }
            updateSelectInput(
                "downloadFormat",
                session = session,
                label = "Result Format",
                selected="",
                choices = downloadFormat
            )
        })

        output$downloadData <- downloadHandler(
            filename = function(){
                obj <- seuratObj()
                prefix <- "scSpotlight."
                outFile <- case_when(
                    input$downloadFormat == "metaData" ~ paste0(prefix, "metaData.", Sys.Date(), ".tsv.gz"),
                    input$downloadFormat == "duckdb" ~ paste0(prefix, Sys.Date(), ".duckdb"),
                    input$downloadFormat == "BPCells" ~ paste0(prefix, Sys.Date(), ".tar.gz"),
                    TRUE ~ paste0(prefix, Sys.Date(), ".Rds")
                )
                outFile
            },
            content = function(file){
                obj <- seuratObj()
                assay <- DefaultAssay(obj)
                message("file: ", file)
                showSpinnerNotification(
                    message = "Saving...",
                    id = "savingNotification",
                    session = session
                )
                if(str_detect(file, "\\.Rds$")){
                    message("Saving Rds...")
                    SaveSeuratRds(obj, file)
                }else if(str_detect(file, "\\.duckdb$")){
                    ## code chunk for duckdb
                    if(file.exists(session$userData$duckdb)){
                        file.symlink(session$userData$duckdb, file)
                    }else{
                        showNotification(
                            ui = "The duckdb file does not exist",
                            action = NULL,
                            duration = 5,
                            closeButton = TRUE,
                            type = "error",
                            session = session
                        )
                    }
                }else if(input$downloadFormat == "metaData"){
                    ## Extract meta data from duckdb
                    con <- duckConnect(session)
                    on.exit(dbDisconnect(con))
                    metaData <- queryDuckMeta(con) %>%
                        tibble::rownames_to_column("cell")
                    readr::write_tsv(metaData, file)
                }else if(input$downloadFormat == "BPCells"){
                    ## code chunk for BPCells
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
                    tar(tarfile = file, files = subPath, compression = c("gzip"))
                }else{
                    stop("Format is not supported")
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
