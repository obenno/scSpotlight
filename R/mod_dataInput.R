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
    tagList(
        fileInput(
            NS(id, "dataInput"),
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

#' @importFrom DT DTOutput
#'
#' @noRd
##mod_dataInput_outputUI <- function(id){
##  tagList(
##      div("out")
##  )
##}

#' dataInput Server Functions
#' @importFrom readr read_tsv
#' @importFrom scales hue_pal
#' @importFrom dplyr select
#' @importFrom shiny req
#' 
#' @noRd
mod_dataInput_server <- function(id,
                                 objIndicator){
                                 ##metaIndicator,
                                 ##scatterReductionIndicator, scatterColorIndicator){
  moduleServer( id, function(input, output, session){
      ns <- session$ns
      data <- reactive({
          req(input$dataInput)
          seuratObj <- readRDS(input$dataInput$datapath)
      })

      observeEvent(data(),{
          objIndicator(objIndicator()+1)
      })

      return(data)
  })
}

## To be copied in the UI
# mod_dataInput_ui("dataInput_1")

## To be copied in the server
# mod_dataInput_server("dataInput_1")
