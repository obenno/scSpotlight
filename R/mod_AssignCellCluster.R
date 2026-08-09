#' AssignCellCluster UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_AssignCellCluster_ui <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      span(
        span(id = ns("selectedCellsText"), "0 Cells Selected"),
        class = "badge text-bg-primary mb-2",
        style = "font-size: 1em;"
      )
    ),
    p(id = ns("selectCellFromCat"), tags$b("Select Cells from Category")),
    selectInput(
      inputId = ns("chosenGroup"),
      label = "Identities from group.by",
      choices = "None",
      selected = "None",
      multiple = TRUE,
      selectize = FALSE,
      width = NULL
    ),
    selectInput(
      inputId = ns("chosenSplit"),
      label = "Identities from split.by",
      choices = "None",
      selected = "None",
      multiple = TRUE,
      selectize = FALSE,
      width = NULL
    ),
    textInput(
      ns("newMeta"),
      "New Category Name",
      value = NULL,
      width = NULL,
      placeholder = "cellType"
    ),
    textInput(
      ns("assignAs"),
      "Assign As",
      value = NULL,
      width = NULL,
      placeholder = "T cell"
    ),
    actionButton(
      ns("assign"),
      "Assign",
      icon = icon("pencil", lib = "glyphicon"),
      width = "100px",
      style = "position:relative; float:right;",
      class = c("border", "border-1", "border-primary", "shadow", "mb-2")
    ),
    span(
      "Subset Dataset to Selected Cells",
      style = "display: inline-block; margin-bottom: 0.5rem",
      infoIcon(
        "Switch on to subset original dataset and only keep the selected cells",
        "left"
      )
    ),
    mod_SubsetCells_ui(ns("subsetCells"))
  )
}

#' AssignCellCluster Server Functions
#'
#' @importFrom scales label_comma
#' @importFrom arrow arrow_table
#' @importFrom dplyr pull filter mutate
#' @importFrom tibble tibble column_to_rownames
#' @importFrom DBI dbDisconnect
#'
#' @noRd
mod_AssignCellCluster_server <- function(
  id,
  seuratObj,
  geneUpdateIndicator,
  metaUpdateIndicator,
  reductionUpdateIndicator,
  analysisTransition,
  backend_root = NULL,
  currentMetadataVersion = NULL
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    selectionIntent <- reactive({
      reject <- function(reason_code) list(reason_code = reason_code)
      payload <- input$selectedCellsPayload
      if (is.null(payload)) {
        return(reject("no_valid_cells"))
      }
      if (!is.list(payload)) {
        return(reject("invalid_intent"))
      }

      cells <- payload$cells %||% character(0)
      if (
        !is.character(cells) ||
          is.list(cells) ||
          !is.atomic(cells) ||
          !length(cells) ||
          any(is.na(cells) | !nzchar(cells)) ||
          anyDuplicated(cells)
      ) {
        return(reject("no_valid_cells"))
      }

      metadata_version <- normalize_analysis_version(payload$metaVersion)
      current_metadata_version <- if (is.function(currentMetadataVersion)) {
        normalize_analysis_version(currentMetadataVersion())
      } else {
        normalize_analysis_version(currentMetadataVersion)
      }
      if (
        is.null(metadata_version) ||
          is.null(current_metadata_version) ||
          !identical(metadata_version, current_metadata_version)
      ) {
        return(reject("stale_analysis_version"))
      }

      expected_version <- normalize_analysis_version(payload$analysisVersion)
      lineage_id <- normalize_analysis_version(payload$analysisLineageId)
      if (is.null(expected_version) || is.null(lineage_id) || lineage_id < 1L) {
        return(reject("invalid_intent"))
      }

      list(
        cells = cells,
        expected_version = expected_version,
        lineage_id = lineage_id
      )
    })

    observeEvent(input$assign, {
      message("Triggered...")
      if (!isTruthy(input$newMeta)) {
        showNotification(
          ui = "Please input a new category name...",
          action = NULL,
          duration = 3,
          closeButton = TRUE,
          type = "default",
          session = session
        )
      } else if (!isTruthy(input$assignAs)) {
        showNotification(
          ui = "Please input a valid label for the new cell type",
          action = NULL,
          duration = 3,
          closeButton = TRUE,
          type = "default",
          session = session
        )
      } else {
        message("Metadata assignment intent submitted for validation.")
      }
    })

    mod_SubsetCells_server(
      "subsetCells",
      seuratObj,
      selectionIntent,
      geneUpdateIndicator,
      metaUpdateIndicator,
      reductionUpdateIndicator,
      backend_root = backend_root,
      analysisTransition = analysisTransition
    )
  })
}

## To be copied in the UI
# mod_AssignCellCluster_ui("AssignCellCluster_1")

## To be copied in the server
# mod_AssignCellCluster_server("AssignCellCluster_1")
