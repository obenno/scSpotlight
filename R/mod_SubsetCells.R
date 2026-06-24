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
  seuratObj_orig,
  selectedCells,
  geneUpdateIndicator,
  metaUpdateIndicator,
  reductionUpdateIndicator
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    reset_subset_switch <- function() {
      updateSwitchInput(
        session = session,
        inputId = "subsetData",
        value = FALSE,
        label = NULL
      )
    }

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
      message("Subset/restore refreshed gene, metadata, and reduction indicators...")
      geneUpdateIndicator(geneUpdateIndicator() + 1)
      metaUpdateIndicator(metaUpdateIndicator() + 1)
      reductionUpdateIndicator(reductionUpdateIndicator() + 1)
    }

    ## Subset dataset code
    observeEvent(input$subsetData, {
      req(seuratObj())
      ##req(selectedCells())

      if (input$subsetData) {
        obj <- seuratObj()
        requested_cells <- selectedCells()
        requested_cells <- if (is.null(requested_cells)) {
          character(0)
        } else {
          as.character(requested_cells)
        }
        requested_cells <- requested_cells[!is.na(requested_cells) & nzchar(requested_cells)]
        requested_cells <- unique(requested_cells)
        valid_cells <- colnames(obj)[colnames(obj) %in% requested_cells]

        if (!length(valid_cells)) {
          notify_subset_status("Please select current cells before subsetting.")
          ## Reset subset switch
          reset_subset_switch()
          return(invisible(NULL))
        }

        if (!is.null(seuratObj_orig())) {
          notify_subset_status("Dataset is already subsetted. Restore before subsetting again.")
          return(invisible(NULL))
        }

        obj_sub <- tryCatch(
          safe_subset_seurat_object(
            obj,
            cells = valid_cells,
            input_label = "Selected cells"
          ),
          error = function(error) {
            notify_subset_status("Unable to subset selected cells safely.")
            reset_subset_switch()
            NULL
          }
        )
        if (is.null(obj_sub)) {
          return(invisible(NULL))
        }

        original_obj <- tryCatch(
          {
            cleaned_original <- drop_dense_scale_data(obj)
            assert_no_dense_scale_data(cleaned_original)
            cleaned_original
          },
          error = function(error) {
            notify_subset_status("Unable to preserve the original dataset safely.")
            reset_subset_switch()
            NULL
          }
        )
        if (is.null(original_obj)) {
          return(invisible(NULL))
        }

        ##DefaultAssay(seuratObj) <- "subsetData"
        notify_subset_status("Subsetted dataset to selected cells.")
        seuratObj_orig(original_obj)
        seuratObj(obj_sub)
        increment_subset_refresh_indicators()
        ## Reset manuallySelectedCells()
        ##manuallySelectedCells(NULL)
      } else {
        obj <- seuratObj_orig()
        if (is.null(obj)) {
          return(invisible(NULL))
        }

        restored_obj <- tryCatch(
          {
            restored <- drop_dense_scale_data(obj)
            assert_no_dense_scale_data(restored)
            restored
          },
          error = function(error) {
            notify_subset_status("Unable to restore the original dataset safely.")
            NULL
          }
        )
        if (is.null(restored_obj)) {
          return(invisible(NULL))
        }

        notify_subset_status("Restored the original dataset.")
        seuratObj(restored_obj)
        ## clear seuratObj_orig()
        seuratObj_orig(NULL)
        increment_subset_refresh_indicators()
      }
    })
  })
}

## To be copied in the UI
# mod_SubsetCells_ui("SubsetCells_1")

## To be copied in the server
# mod_SubsetCells_server("SubsetCells_1")
