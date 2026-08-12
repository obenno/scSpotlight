#' SubsetCells UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_SubsetCells_ui <- function(id) {
  ns <- NS(id)
  tagList(
    switchInput(
      inputId = ns("subsetData"),
      label = NULL,
      size = "mini",
      value = FALSE
    )
  )
}

#' SubsetCells Server Functions
#'
#' @noRd
mod_SubsetCells_server <- function(
  id,
  seuratObj,
  selectionIntent,
  geneUpdateIndicator,
  metaUpdateIndicator,
  reductionUpdateIndicator,
  analysisTransition,
  backend_root = NULL
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    known_lineage_id <- analysisTransition$lineage_id()
    reset_acknowledgement_pending <- FALSE

    sync_subset_switch <- function() {
      updateSwitchInput(
        session = session,
        inputId = "subsetData",
        value = analysisTransition$is_subsetted(),
        label = NULL
      )
    }

    observe({
      current_lineage_id <- analysisTransition$lineage_signal()
      if (!identical(current_lineage_id, known_lineage_id)) {
        known_lineage_id <<- current_lineage_id
        reset_acknowledgement_pending <<-
          analysisTransition$reset_replaces_active_analysis()
        sync_subset_switch()
      }
    })

    notify_subset_status <- function(message) {
      showNotification(
        ui = message,
        action = NULL,
        duration = 3,
        closeButton = TRUE,
        type = "default",
        session = session
      )
    }

    increment_subset_refresh_indicators <- function() {
      message(
        "Subset/restore refreshed gene, metadata, and reduction indicators..."
      )
      geneUpdateIndicator(geneUpdateIndicator() + 1)
      metaUpdateIndicator(metaUpdateIndicator() + 1)
      reductionUpdateIndicator(reductionUpdateIndicator() + 1)
    }

    read_selection_intent <- function() {
      if (is.function(selectionIntent)) {
        return(selectionIntent())
      }
      selectionIntent
    }

    notify_transition_failure <- function(reason_code, operation) {
      message <- switch(
        reason_code,
        no_valid_cells = "Please select current cells before subsetting.",
        already_subsetted = "Dataset is already subsetted. Restore before subsetting again.",
        invalid_category_context = "Category selection is stale. Refresh the plot and try again.",
        subset_failed = "Unable to subset selected cells safely.",
        original_state_failed = "Unable to preserve the original dataset safely.",
        restore_failed = "Unable to restore the original dataset safely.",
        stale_analysis_version = "Analysis state is stale. Refresh and try again.",
        stale_view_filter = "View state is stale. Refresh the plot and try again.",
        invalid_intent = "Analysis request could not be understood.",
        invalid_operation = "Analysis operation is not supported.",
        stale_analysis_lineage = "Analysis state is stale. Refresh and try again.",
        version_exhausted = "Analysis version limit reached. Reload the dataset.",
        cancelled = NULL,
        mutation_in_progress = "Another Analysis change is in progress. Try again.",
        transition_failed = "Analysis change could not be applied safely.",
        if (identical(operation, "restore")) {
          NULL
        } else {
          "Analysis operation could not be applied."
        }
      )

      if (!is.null(message)) {
        notify_subset_status(message)
      }
      invisible(NULL)
    }

    ## Subset and Restore route through one Analysis Transition seam.
    observeEvent(input$subsetData, {
      subset_value <- input$subsetData
      if (
        length(subset_value) != 1L ||
          !is.logical(subset_value) ||
          is.na(subset_value)
      ) {
        sync_subset_switch()
        notify_transition_failure("invalid_intent", "subset")
        return(invisible(NULL))
      }

      if (isTRUE(reset_acknowledgement_pending)) {
        reset_acknowledgement_pending <<- FALSE
        if (isTRUE(subset_value)) {
          sync_subset_switch()
          notify_transition_failure("stale_analysis_lineage", "subset")
        }
        return(invisible(NULL))
      }

      req(seuratObj())

      operation <- if (isTRUE(subset_value)) "subset" else "restore"
      subset_backend_root <- if (
        isTRUE(subset_value) && isTruthy(backend_root)
      ) {
        file.path(backend_root, "subset")
      } else {
        NULL
      }

      if (identical(operation, "subset")) {
        selection_intent <- read_selection_intent()
        if (!is.list(selection_intent)) {
          notify_transition_failure("no_valid_cells", operation)
          sync_subset_switch()
          return(invisible(NULL))
        }

        reason_code <- selection_intent$reason_code %||% NULL
        if (!is.null(reason_code)) {
          if (
            length(reason_code) != 1L ||
              !is.character(reason_code) ||
              is.na(reason_code)
          ) {
            reason_code <- "invalid_intent"
          }
          notify_transition_failure(reason_code, operation)
          sync_subset_switch()
          return(invisible(NULL))
        }

        intent <- c(
          list(
            operation = operation,
            expected_version = selection_intent$expected_version,
            lineage_id = selection_intent$lineage_id
          ),
          if (!is.null(selection_intent$category)) {
            list(category = selection_intent$category)
          } else {
            list(cells = selection_intent$cells %||% character(0))
          }
        )
      } else {
        transition_context <- analysisTransition$intent_context()
        intent <- list(
          operation = operation,
          expected_version = transition_context$expected_version,
          lineage_id = transition_context$lineage_id
        )
      }

      result <- analysisTransition$apply(
        intent = intent,
        backend_root = subset_backend_root
      )

      if (!isTRUE(result$committed)) {
        notify_transition_failure(result$reason_code, operation)
        sync_subset_switch()
        return(invisible(NULL))
      }

      if (identical(operation, "subset")) {
        notify_subset_status("Subsetted dataset to selected cells.")
      } else {
        notify_subset_status("Restored the original dataset.")
      }
      session$sendCustomMessage(
        type = "clear_expr",
        # Invalidate the just-replaced Analysis epoch, including jobs that have
        # not yet reached the browser cache.
        message = make_clear_expr_payload(geneUpdateIndicator())
      )
      increment_subset_refresh_indicators()
    })
  })
}

## To be copied in the UI
# mod_SubsetCells_ui("SubsetCells_1")

## To be copied in the server
# mod_SubsetCells_server("SubsetCells_1")
