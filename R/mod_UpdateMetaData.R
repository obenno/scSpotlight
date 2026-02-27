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
                d <- d %>% mutate(cells=1:nrow(d)) %>% as_tibble()
                stopifnot(file.exists(dirPath))
                out = list()
                for(i in seq_along(colnames(d))){
                    data <- d %>% dplyr::pull(i)
                    if(is.numeric(data)){
                        data[is.na(data)] <- 0
                        data[is.nan(data)] <- 0
                        data[is.null(data)] <- 0
                        data[is.infinite(data)] <- 0
                        k <- list(
                            type = "number",
                            value = data
                        )
                    }else{
                        k <- list(
                            type = "category",
                            value = split(seq_along(data), data)
                        )
                    }
                    out[[i]] <- k
                }
                names(out) <- colnames(d)
                filePath <- file.path(
                    dirPath,
                    hash_md5("meta")
                )
                qs_save(out, filePath, compress_level = 9L)

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
