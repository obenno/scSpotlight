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
                                      scatterReductionIndicator,
                                      scatterColorIndicator){
  moduleServer( id, function(input, output, session){

      ns <- session$ns
      obj_meta <- reactive({
          req(duckdbConnection())
          ##req(selectedAssay())
          ## select only non-numeric columns
          queryDuckMeta(duckdbConnection(), "metaData") %>%
              select(-starts_with(c("nFeature_", "nCount_", "percent.mt"))) %>%
              dplyr::select(!where(is.numeric)) %>%
              colnames()
      })

      observeEvent(obj_meta(), {
          req(obj_meta())
          if("seurat_clusters" %in% obj_meta()){
              selected <- "seurat_clusters"
          }else{
              selected <- NULL
          }
          updateSelectInput(
              session = session,
              inputId = "group.by",
              label = "Choose group.by",
              choices = obj_meta(),
              selected = selected
          )
          ## Also transfer metaData when obj_meta() changes
          showNotification(
              ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                           role = "status",
                           span(class = "sr-only", "Loading...")),
                       "Updating meta data..."),
              action = NULL,
              duration = NULL,
              closeButton = FALSE,
              type = "default",
              id = "update_meta_notification",
              session = session
          )
          message("Transferring metaData...")
          transfer_meta(tibble::rownames_to_column(queryDuckMeta(duckdbConnection(), "metaData"), "cells"), session)
          removeNotification(id = "update_meta_notification", session)
      }, priority = -10)

      observeEvent(obj_meta(), {
          req(obj_meta())
          ## use all non-numeric columns in meta data
          updateSelectInput(
              session = session,
              inputId = "split.by",
              label = "Choose split.by",
              choices = c("None", obj_meta()),
              selected = NULL
          )
      }, priority = 20)

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
