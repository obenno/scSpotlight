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
  tagList(
 
  )
}
    
#' UpdateMetaData Server Functions
#'
#' @noRd
clean_meta_frame <- function(d) {
    d <- d %>% dplyr::mutate(cells = seq_len(nrow(d)) - 1L) %>% tibble::as_tibble()

    for (col in colnames(d)) {
        if (is.numeric(d[[col]])) {
            v <- d[[col]]
            v[is.nan(v) | is.infinite(v)] <- NA
            d[[col]] <- v
        } else if (is.character(d[[col]]) || is.logical(d[[col]])) {
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
mod_UpdateMetaData_server <- function(id,
                                      seuratObj,
                                      metaUpdateIndicator,
                                      metaPatchRequest,
                                      metaProcessed){
    moduleServer(id, function(input, output, session){
        ns <- session$ns

        observeEvent(metaUpdateIndicator(), {
            ## transfer metaData when metaUpdateIndicator changes
            req(isTruthy(seuratObj()))
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
            metaProcessed(FALSE)
            metaVersion <- metaUpdateIndicator()
            dirPath <- file.path(session$userData$tempDir, "meta")
            # BPCells-backed Seurat objects are not safe to ship across workers, so fetch on the main thread.
            d <- clean_meta_frame(get_backend_metadata(seuratObj()))
            meta_promise <- future_promise({
                filePath <- file.path(dirPath, hash_md5(paste0("meta_", metaVersion)))
                write_ipc_stream(as_arrow_table(d), filePath)
                list(metaFile = basename(filePath), metaVersion = metaVersion)
            }) %...>% (
                function(result) {
                    session$sendCustomMessage(type = "meta_ready", message = result)
                    result
                }
            ) %...!% (
                function(error) {
                    showNotification(
                        ui = paste("Metadata export failed:", conditionMessage(error)),
                        action = NULL,
                        duration = 6,
                        closeButton = TRUE,
                        type = "error",
                        session = session
                    )
                }
            )

            promises::finally(
                meta_promise,
                function() {
                    removeNotification(id = "update_meta_notification", session = session)
                }
            )

        }, priority = -200, ignoreNULL = TRUE)

        observeEvent(metaPatchRequest(), {
            req(isTruthy(seuratObj()))
            request <- metaPatchRequest()
            req(is.list(request), length(request$cols) > 0)

            showNotification(
                ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                             role = "status",
                             span(class = "sr-only", "Loading...")),
                         "Updating meta data columns..."),
                action = NULL,
                duration = NULL,
                closeButton = FALSE,
                type = "default",
                id = "update_meta_patch_notification",
                session = session
            )

            message("Transferring metaData patch for columns: ", paste(request$cols, collapse = ", "))
            dirPath <- file.path(session$userData$tempDir, "meta")
            patch_cols <- request$cols
            patch_version <- request$version
            # Keep BPCells reads in-process; only Arrow serialization happens in the worker.
            d <- clean_meta_frame(get_backend_metadata(seuratObj(), cols = patch_cols))
            meta_patch_promise <- future_promise({
                patch_key <- paste(sort(patch_cols), collapse = "|")
                filePath <- file.path(dirPath, hash_md5(paste0("meta_patch_", patch_key, "_", patch_version)))
                write_ipc_stream(as_arrow_table(d), filePath)
                list(
                    metaFile = basename(filePath),
                    cols = patch_cols,
                    metaVersion = patch_version
                )
            }) %...>% (
                function(result) {
                    session$sendCustomMessage(type = "meta_patch_ready", message = result)
                    metaPatchRequest(NULL)
                    result
                }
            ) %...!% (
                function(error) {
                    showNotification(
                        ui = paste("Metadata patch export failed:", conditionMessage(error)),
                        action = NULL,
                        duration = 6,
                        closeButton = TRUE,
                        type = "error",
                        session = session
                    )
                }
            )

            promises::finally(
                meta_patch_promise,
                function() {
                    metaPatchRequest(NULL)
                    removeNotification(id = "update_meta_patch_notification", session = session)
                }
            )
        }, ignoreNULL = TRUE)
    })
}

## To be copied in the UI
# mod_UpdateMetaData_ui("UpdateMetaData_1")
    
## To be copied in the server
# mod_UpdateMetaData_server("UpdateMetaData_1")
