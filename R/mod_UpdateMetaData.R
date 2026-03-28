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
#' @importFrom arrow as_arrow_table write_ipc_stream
mod_UpdateMetaData_server <- function(id,
                                      metaUpdateIndicator,
                                      metaPatchRequest,
                                      metaProcessed){
    moduleServer(id, function(input, output, session){
        ns <- session$ns

        clean_meta_frame <- function(d){
            d <- d %>% mutate(cells = seq_len(nrow(d)) - 1L) %>% as_tibble()

            for (col in colnames(d)) {
                if (is.numeric(d[[col]])) {
                    v <- d[[col]]
                    v[is.na(v)] <- 0
                    v[is.nan(v)] <- 0
                    v[is.null(v)] <- 0
                    v[is.infinite(v)] <- 0
                    d[[col]] <- v
                } else if (is.character(d[[col]]) || is.logical(d[[col]])) {
                    d[[col]] <- as.factor(d[[col]])
                }
            }

            d
        }

        ## extract_meta will now only extract one column each time
        extract_meta <- ExtendedTask$new(function(dirPath){
            future_promise({

                con <- duckConnect(session)
                on.exit(DBI::dbDisconnect(con))
                d <- queryDuckMeta(con, "metaData")
                d <- clean_meta_frame(d)
                stopifnot(file.exists(dirPath))

                filePath <- file.path(dirPath, hash_md5("meta"))
                write_ipc_stream(as_arrow_table(d), filePath)

                return(list(metaFile = basename(filePath)))

            })
        })

        extract_meta_patch <- ExtendedTask$new(function(dirPath, cols){
            future_promise({
                con <- duckConnect(session)
                on.exit(DBI::dbDisconnect(con))

                stopifnot(length(cols) > 0)
                d <- queryDuckMeta(con, "metaData", cols = cols)
                d <- clean_meta_frame(d)
                stopifnot(file.exists(dirPath))

                patch_key <- paste(sort(cols), collapse = "|")
                filePath <- file.path(dirPath, hash_md5(paste0("meta_patch_", patch_key)))
                write_ipc_stream(as_arrow_table(d), filePath)

                return(list(metaFile = basename(filePath), cols = cols))
            })
        })

        observeEvent(metaUpdateIndicator(), {
            ## transfer metaData when metaUpdateIndicator changes
            req(file.exists(session$userData$duckdb))
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
            promise_dirPath <- file.path(
                session$userData$tempDir,
                "meta"
            )
            extract_meta$invoke(dirPath = promise_dirPath)

        }, priority = -200, ignoreNULL = TRUE) # lower priority than seurat2duckdb

        observeEvent(metaPatchRequest(), {
            req(file.exists(session$userData$duckdb))
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
            promise_dirPath <- file.path(
                session$userData$tempDir,
                "meta"
            )
            extract_meta_patch$invoke(dirPath = promise_dirPath, cols = request$cols)
        }, ignoreNULL = TRUE)

        observeEvent(extract_meta$status(), {
            if(extract_meta$status() == "success"){
                removeNotification(id = "update_meta_notification", session)
                session$sendCustomMessage(type = "meta_ready", extract_meta$result())
            }else{
                message("extract_meta error: ", extract_meta$result())
            }
        })

        observeEvent(extract_meta_patch$status(), {
            if(extract_meta_patch$status() == "success"){
                removeNotification(id = "update_meta_patch_notification", session)
                session$sendCustomMessage(type = "meta_patch_ready", extract_meta_patch$result())
                metaPatchRequest(NULL)
            }else if (extract_meta_patch$status() == "error"){
                removeNotification(id = "update_meta_patch_notification", session)
                message("extract_meta_patch error: ", extract_meta_patch$result())
            }
        })
    })
}

## To be copied in the UI
# mod_UpdateMetaData_ui("UpdateMetaData_1")
    
## To be copied in the server
# mod_UpdateMetaData_server("UpdateMetaData_1")
