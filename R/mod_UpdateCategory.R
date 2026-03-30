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
                                       metaCols,
                                       metaSidebarState,
                                       scatterUpdateIndicator){
  moduleServer( id, function(input, output, session){

      ns <- session$ns
      last_category_selection <- reactiveVal(list(group.by = NULL, split.by = NULL))

      observeEvent(metaSidebarState(), {
          state <- metaSidebarState()
          choices <- state$cols
          req(choices)

          current_group <- state$groupBy
          if (!isTruthy(current_group) || !current_group %in% choices) {
              current_group <- if ("seurat_clusters" %in% choices) "seurat_clusters" else NULL
          }

          split_choices <- c("None", choices)
          current_split <- state$splitBy
          if (!isTruthy(current_split) || !current_split %in% split_choices) {
              current_split <- "None"
          }

          updateSelectInput(
              session = session,
              inputId = "group.by",
              label = "Choose group.by",
              choices = choices,
              selected = current_group
          )
          updateSelectInput(
              session = session,
              inputId = "split.by",
              label = "Choose split.by",
              choices = split_choices,
              selected = current_split
          )
      }, priority = -10)

      observeEvent(list(input$group.by, input$split.by), {
          current_selection <- list(
              group.by = if (is.null(input$group.by)) "None" else input$group.by,
              split.by = if (is.null(input$split.by)) "None" else input$split.by
          )
          previous_selection <- last_category_selection()

          if (identical(current_selection, previous_selection)) {
              return()
          }

          last_category_selection(current_selection)
          message("category selection changed, increasing scatterUpdateIndicator()")
          scatterUpdateIndicator(scatterUpdateIndicator() + 1)
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
