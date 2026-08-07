#' UpdateMetaData UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_UpdateMetaData_ui <- function(id) {
  ns <- NS(id)
  tagList()
}

#' UpdateMetaData Server Functions
#'
#' @noRd
clean_meta_frame <- function(d) {
  cell_ids <- rownames(d)
  if (
    is.null(cell_ids) ||
      length(cell_ids) != nrow(d) ||
      .row_names_info(d, type = 1L) < 0L ||
      any(is.na(cell_ids) | !nzchar(cell_ids))
  ) {
    stop(
      "Metadata transfer requires canonical Cell IDs in row names.",
      call. = FALSE
    )
  }

  d <- tibble::as_tibble(d)
  d$cells <- as.character(cell_ids)

  for (col in colnames(d)) {
    if (is.numeric(d[[col]])) {
      v <- d[[col]]
      v[is.nan(v) | is.infinite(v)] <- NA
      d[[col]] <- v
    } else if (
      col != "cells" &&
        (is.character(d[[col]]) || is.logical(d[[col]]))
    ) {
      d[[col]] <- as.factor(d[[col]])
    }
  }

  d
}

#'
#' @noRd
#' @importFrom cli hash_md5
#' @importFrom arrow as_arrow_table write_ipc_stream
#' @importFrom promises future_promise %...>% %...!% finally
mod_UpdateMetaData_server <- function(
  id,
  seuratObj,
  metaUpdateIndicator,
  metaPatchRequest,
  metaProcessed,
  nextMetadataVersion = NULL
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    allocate_full_metadata_version <- function() {
      if (is.function(nextMetadataVersion)) {
        return(nextMetadataVersion())
      }
      metaUpdateIndicator()
    }

    observeEvent(
      metaUpdateIndicator(),
      {
        ## transfer metaData when metaUpdateIndicator changes
        req(isTruthy(seuratObj()))
        showNotification(
          ui = div(
            div(
              class = c("spinner-border", "spinner-border-sm", "text-primary"),
              role = "status",
              span(class = "sr-only", "Loading...")
            ),
            "Updating meta data..."
          ),
          action = NULL,
          duration = NULL,
          closeButton = FALSE,
          type = "default",
          id = "update_meta_notification",
          session = session
        )
        message("Transferring metaData...")
        metaProcessed(FALSE)
        metaVersion <- allocate_full_metadata_version()
        dirPath <- file.path(session$userData$tempDir, "meta")
        transfer <- prepare_backend_metadata_transfer(
          seuratObj(),
          dir_path = dirPath,
          meta_version = metaVersion,
          resource_prefix = session$userData$dataResourcePrefix
        )
        meta_promise <- future_promise({
          capture_warnings(write_backend_metadata_transfer(transfer))
        }) %...>%
          (function(result) {
            show_captured_warnings(
              result$warnings,
              title = "Metadata export completed with warnings",
              session = session
            )
            session$sendCustomMessage(
              type = "meta_ready",
              message = result$value
            )
            result$value
          }) %...!%
          (function(error) {
            message("Metadata export failed during IPC write.")
            session$sendCustomMessage(
              type = "transfer_error",
              message = make_transfer_error_payload(
                "metadata",
                "write_failed",
                metaVersion,
                resource_prefix = session$userData$dataResourcePrefix
              )
            )
            showNotification(
              ui = "Metadata export failed. Retry transfer or reload the dataset.",
              action = NULL,
              duration = 6,
              closeButton = TRUE,
              type = "error",
              session = session
            )
          })

        promises::finally(
          meta_promise,
          function() {
            removeNotification(
              id = "update_meta_notification",
              session = session
            )
          }
        )
      },
      priority = -200,
      ignoreNULL = TRUE
    )

    observeEvent(
      metaPatchRequest(),
      {
        req(isTruthy(seuratObj()))
        request <- metaPatchRequest()
        req(is.list(request), length(request$cols) > 0)

        showNotification(
          ui = div(
            div(
              class = c("spinner-border", "spinner-border-sm", "text-primary"),
              role = "status",
              span(class = "sr-only", "Loading...")
            ),
            "Updating meta data columns..."
          ),
          action = NULL,
          duration = NULL,
          closeButton = FALSE,
          type = "default",
          id = "update_meta_patch_notification",
          session = session
        )

        message(
          "Transferring metaData patch for columns: ",
          paste(request$cols, collapse = ", ")
        )
        patch_cols <- request$cols
        patch_version <- request$version
        dirPath <- file.path(session$userData$tempDir, "meta")
        transfer <- prepare_backend_metadata_transfer(
          seuratObj(),
          dir_path = dirPath,
          meta_version = patch_version,
          cols = patch_cols,
          resource_prefix = session$userData$dataResourcePrefix
        )
        meta_patch_promise <- future_promise({
          capture_warnings(write_backend_metadata_transfer(transfer))
        }) %...>%
          (function(result) {
            show_captured_warnings(
              result$warnings,
              title = "Metadata patch export completed with warnings",
              session = session
            )
            session$sendCustomMessage(
              type = "meta_patch_ready",
              message = result$value
            )
            metaPatchRequest(NULL)
            result$value
          }) %...!%
          (function(error) {
            message("Metadata patch export failed during IPC write.")
            session$sendCustomMessage(
              type = "transfer_error",
              message = make_transfer_error_payload(
                "metadata_patch",
                "write_failed",
                patch_version,
                list(cols = patch_cols),
                resource_prefix = session$userData$dataResourcePrefix
              )
            )
            showNotification(
              ui = "Metadata patch export failed. Retry the metadata update.",
              action = NULL,
              duration = 6,
              closeButton = TRUE,
              type = "error",
              session = session
            )
          })

        promises::finally(
          meta_patch_promise,
          function() {
            metaPatchRequest(NULL)
            removeNotification(
              id = "update_meta_patch_notification",
              session = session
            )
          }
        )
      },
      ignoreNULL = TRUE
    )
  })
}

## To be copied in the UI
# mod_UpdateMetaData_ui("UpdateMetaData_1")

## To be copied in the server
# mod_UpdateMetaData_server("UpdateMetaData_1")
