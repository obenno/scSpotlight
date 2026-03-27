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
                                      metaProcessed){
    moduleServer(id, function(input, output, session){
        ns <- session$ns

        ## extract_meta will now only extract one column each time
        extract_meta <- ExtendedTask$new(function(dirPath){
            future_promise({

                con <- duckConnect(session)
                on.exit(DBI::dbDisconnect(con))
                d <- queryDuckMeta(con, "metaData")
                d <- d %>% mutate(cells = seq_len(nrow(d)) - 1L) %>% as_tibble()
                stopifnot(file.exists(dirPath))

                ## Clean numeric columns and convert character to factor
                ## (Arrow encodes factors as dictionary-encoded columns)
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
                    ## factors stay as-is — Arrow will encode them as dictionary
                }

                filePath <- file.path(dirPath, hash_md5("meta"))
                write_ipc_stream(as_arrow_table(d), filePath)

                return(list(metaFile = basename(filePath)))

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

        observeEvent(extract_meta$status(), {
            if(extract_meta$status() == "success"){
                removeNotification(id = "update_meta_notification", session)
                session$sendCustomMessage(type = "meta_ready", extract_meta$result())
            }else{
                message("extract_meta error: ", extract_meta$result())
            }
        })
    })
}

## To be copied in the UI
# mod_UpdateMetaData_ui("UpdateMetaData_1")
    
## To be copied in the server
# mod_UpdateMetaData_server("UpdateMetaData_1")
