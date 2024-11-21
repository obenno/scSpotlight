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

        extract_meta <- ExtendedTask$new(function(filePath){
            future_promise({

                con <- duckConnect(session)
                on.exit(DBI::dbDisconnect(con))
                d <- queryDuckMeta(con, "metaData")
                d <- d %>% mutate(cells=1:nrow(d)) %>% as_tibble()

                if(file.exists(filePath)){
                    file.remove(filePath)
                }
                qsave(d, filePath, preset = "high")
                return(basename(filePath))

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
            promise_filePath <- file.path(
                session$userData$tempDir,
                hash_md5("metaData")
            )
            extract_meta$invoke(filePath = promise_filePath)

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
