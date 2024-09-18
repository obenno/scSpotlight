#' UpdateCategory UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
mod_UpdateCategory_ui <- function(id){
  ns <- NS(id)
  tagList(
      selectInput(
          ns("group.by"),
          "Choose group.by",
          choices = "None",
          selected = "None",
          multiple = FALSE,
          selectize = TRUE,
          width = NULL
      ),
      selectInput(
          ns("split.by"),
          "Choose split.by",
          choices = "None",
          selected = "None",
          multiple = FALSE,
          selectize = TRUE,
          width = NULL
      )
  )
}

#' UpdateCategory Server Functions
#'
#'
#' @importFrom dplyr starts_with select collect
#' @import Seurat
#' @import shiny
#' @noRd
mod_UpdateCategory_server <- function(id,
                                      duckdbConnection,
                                      metaCols,
                                      scatterReductionIndicator,
                                      scatterColorIndicator){
  moduleServer( id, function(input, output, session){

      ns <- session$ns

      observeEvent(metaCols(), {
          req(metaCols())
          if("seurat_clusters" %in% metaCols()){
              selected <- "seurat_clusters"
          }else{
              selected <- NULL
          }
          updateSelectInput(
              session = session,
              inputId = "group.by",
              label = "Choose group.by",
              choices = metaCols(),
              selected = selected
          )
          updateSelectInput(
              session = session,
              inputId = "split.by",
              label = "Choose split.by",
              choices = c("None", metaCols()),
              selected = NULL
          )
      }, priority = -10)

      observeEvent(input$group.by, {
          if(input$group.by!="None"){
              message("groupby increased scatterColorIndicator()")
              scatterColorIndicator(scatterColorIndicator()+1)
          }
      }, ignoreInit = TRUE)

      observeEvent(input$split.by, {
          req(duckdbConnection())
          scatterReductionIndicator(scatterReductionIndicator()+1)
          scatterColorIndicator(scatterColorIndicator()+1)
      }, ignoreInit = TRUE)

      selected_group.by <- reactive({
          input$group.by
      })

      selected_split.by <- reactive({
          input$split.by
      })

      list(
          group.by = selected_group.by,
          split.by = selected_split.by
      )
  })
}

## To be copied in the UI
# mod_UpdateCategory_ui("UpdateCategory_1")

## To be copied in the server
# mod_UpdateCategory_server("UpdateCategory_1")
