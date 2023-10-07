#' dataInput UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList fileInput
#'
mod_dataInput_inputUI <- function(id){
    ns <- NS(id)

    dataDir <- golem::get_golem_options("dataDir")
    runningMode <- golem::get_golem_options("runningMode")
    if(isTruthy(dataDir) && runningMode == "viewer"){
        tagList(
            selectInput(
                ns("dataDirFile"),
                label = "Choose a RDS input file",
                choices = "",
                selected = NULL,
                multiple = FALSE,
                selectize = TRUE
            )
        )
    }else{
        tagList(
            fileInput(
                ns("dataInput"),
                tagList("Upload Input File",
                        infoIcon("Please upload processed seuratObj (RDS), or compressed matrix directory (zip, tgz, tbz2)", "right")),
                multiple = FALSE,
                width = "100%",
                accept = c(##".h5seurat", ".h5Seurat", ".H5Seurat", "H5seurat",
                    ".rds", "Rds", "RDS")
                ##".zip",
                ##"tar.gz", "tgz",
                ##"tar.bz2", "tbz2")
            )
        )
    }
}

#' @importFrom DT DTOutput
#'
#' @noRd
##mod_dataInput_outputUI <- function(id){
##  tagList(
##      div("out")
##  )
##}

#' dataInput Server Functions
#'
#' @import Seurat
#' @import BPCells
#' @import shiny
#' @importFrom readr read_tsv
#' 
#' @noRd
mod_dataInput_server <- function(id,
                                 obj,
                                 objIndicator){
    moduleServer( id, function(input, output, session){
        ns <- session$ns

        ## use golem_opts to parse dataDir arguments when invoking run_app()
        dataDir <- golem::get_golem_options("dataDir")
        if(isTruthy(dataDir)){
            if(!file.exists(dataDir)){
                showNotification(
                    ui = "dataDir parsed but does not exist",
                    action = NULL,
                    duration = NULL,
                    closeButton = TRUE,
                    type = "default",
                    session = session
                )
            }else{
                ## set working directory to the dataDir
                ## to ensure BPCells matrix path is correct
                setwd(dataDir)
                updateSelectInput(
                    session,
                    inputId = "dataDirFile",
                    choices = list.files(path = dataDir,
                                         pattern = ".rds",
                                         recursive = TRUE),
                    selected = ""
                )
            }
        }

      observe({
          req(isTruthy(input$dataInput) || isTruthy(input$dataDirFile))
          waiter_show(html = waiting_screen(), color = "var(--bs-primary)")
          if(isTruthy(input$dataDirFile)){
              seuratObj <- readRDS(file.path(dataDir, input$dataDirFile))
          }else{
              seuratObj <- readRDS(input$dataInput$datapath)
          }
          waiter_hide()
          obj(seuratObj)
      })

      observeEvent(obj(),{
          req(obj())
          objIndicator(objIndicator()+1)
      })

  })
}

## To be copied in the UI
# mod_dataInput_ui("dataInput_1")

## To be copied in the server
# mod_dataInput_server("dataInput_1")
