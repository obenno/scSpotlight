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
  currentMetadataVersion = NULL,
  currentGroupBy = NULL,
  currentSplitBy = NULL,
  currentViewFilter = NULL,
  currentViewFilterVersion = NULL
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    current_value <- function(value) {
      if (is.function(value)) value() else value
    }

    current_metadata_version <- function() {
      normalize_analysis_version(current_value(currentMetadataVersion))
    }

    current_view_filter_version <- function() {
      normalize_analysis_version(current_value(currentViewFilterVersion))
    }

    current_view_filter <- function() {
      current_value(currentViewFilter)
    }

    validate_selection_identity <- function(payload) {
      reject <- function(reason_code) list(reason_code = reason_code)
      if (!is.list(payload)) {
        return(reject("invalid_intent"))
      }

      metadata_version <- normalize_analysis_version(payload$metaVersion)
      active_metadata_version <- current_metadata_version()
      if (
        is.null(metadata_version) ||
          is.null(active_metadata_version) ||
          !identical(metadata_version, active_metadata_version)
      ) {
        return(reject("stale_analysis_version"))
      }

      view_filter_version <- normalize_analysis_version(payload$viewFilterVersion)
      active_view_filter_version <- current_view_filter_version()
      if (
        !is.null(active_view_filter_version) &&
          (
            is.null(view_filter_version) ||
              !identical(view_filter_version, active_view_filter_version)
          )
      ) {
        return(reject("stale_view_filter"))
      }

      expected_version <- normalize_analysis_version(payload$analysisVersion)
      lineage_id <- normalize_analysis_version(payload$analysisLineageId)
      if (is.null(expected_version) || is.null(lineage_id) || lineage_id < 1L) {
        return(reject("invalid_intent"))
      }

      list(
        expected_version = expected_version,
        lineage_id = lineage_id
      )
    }

    manual_selection_intent <- function(payload) {
      reject <- function(reason_code) list(reason_code = reason_code)
      identity <- validate_selection_identity(payload)
      if (!is.null(identity$reason_code)) {
        return(identity)
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

      view_filter <- current_view_filter()
      if (!is.null(view_filter)) {
        visible_cells <- tryCatch(
          resolve_view_filter_cells(seuratObj(), view_filter),
          error = function(...) NULL
        )
        if (is.null(visible_cells) || any(!cells %in% visible_cells)) {
          return(reject("stale_view_filter"))
        }
      }

      c(identity, list(cells = cells))
    }

    category_selection_intent <- function(payload) {
      reject <- function(reason_code) list(reason_code = reason_code)
      identity <- validate_selection_identity(payload)
      if (!is.null(identity$reason_code)) {
        return(identity)
      }

      context <- payload$context
      category <- payload$category
      if (!is.list(context) || !is.list(category)) {
        return(reject("invalid_category_context"))
      }

      current_group <- normalize_analysis_context_value(
        current_value(currentGroupBy)
      )
      current_split <- normalize_analysis_context_value(
        current_value(currentSplitBy)
      )
      submitted_group <- normalize_analysis_context_value(context$groupBy)
      submitted_split <- normalize_analysis_context_value(context$splitBy)
      category_group <- normalize_analysis_context_value(category$groupBy)
      category_split <- normalize_analysis_context_value(category$splitBy)
      if (
        is.null(current_group) ||
          is.null(current_split) ||
          is.null(submitted_group) ||
          is.null(submitted_split) ||
          is.null(category_group) ||
          is.null(category_split) ||
          identical(current_group, "None") ||
          !identical(submitted_group, current_group) ||
          !identical(submitted_split, current_split) ||
          !identical(category_group, current_group) ||
          !identical(category_split, current_split)
      ) {
        return(reject("invalid_category_context"))
      }

      group_levels <- normalize_analysis_context_levels(category$groupLevels)
      if (is.null(group_levels)) {
        return(reject("invalid_category_context"))
      }

      split_levels <- normalize_analysis_context_levels(
        category$splitLevels,
        allow_empty = identical(current_split, "None")
      )
      if (
        is.null(split_levels) ||
          (identical(current_split, "None") && length(split_levels) > 0L)
      ) {
        return(reject("invalid_category_context"))
      }

      category_intent <- list(
        groupBy = category_group,
        groupLevels = group_levels,
        splitBy = category_split,
        splitLevels = split_levels
      )
      view_filter <- current_view_filter()
      if (is.null(view_filter)) {
        return(c(identity, list(category = category_intent)))
      }

      category_result <- tryCatch(
        resolve_analysis_category_cells(seuratObj(), category_intent),
        error = function(...) list(reason_code = "invalid_category_context")
      )
      if (!is.null(category_result$reason_code)) {
        return(reject(category_result$reason_code))
      }
      visible_cells <- tryCatch(
        resolve_view_filter_cells(seuratObj(), view_filter),
        error = function(...) NULL
      )
      selected_cells <- category_result$cells[
        category_result$cells %in% visible_cells
      ]
      if (!length(selected_cells)) {
        return(reject("no_valid_cells"))
      }

      c(identity, list(cells = selected_cells))
    }

    selectionIntent <- reactive({
      manual_payload <- input$selectedCellsPayload
      if (!is.null(manual_payload)) {
        return(manual_selection_intent(manual_payload))
      }

      category_payload <- input$categorySelectionContext
      if (!is.null(category_payload)) {
        return(category_selection_intent(category_payload))
      }

      list(reason_code = "no_valid_cells")
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
