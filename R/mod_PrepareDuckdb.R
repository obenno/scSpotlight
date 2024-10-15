#' PrepareDuckdb UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_PrepareDuckdb_ui <- function(id){
  ns <- NS(id)
  tagList(
 
  )
}
    
#' PrepareDuckdb Server Functions
#'
#' @importFrom qs qsave
#' @noRd 
mod_PrepareDuckdb_server <- function(id,
                                     seuratObj,
                                     assay,
                                     duckdbConnection,
                                     metaProcessed){
    moduleServer( id, function(input, output, session){
        ns <- session$ns
        observeEvent(list(seuratObj(), assay()), {
            req(seuratObj(), assay())
            ## convert seuratObj to duckdb
            ## Get the layers
            selectedLayers <- intersect(c("counts", "data"), Layers(seuratObj()))
            stopifnot(length(selectedLayers)>0)
            ## first stope connection if already exists
            if(isTruthy(duckdbConnection())){
                dbDisconnect(duckdbConnection())
            }
            message("Converting duckdb")
            if(file.exists(session$userData$duckdb)){
              unlink(session$userData$duckdb)
            }
            seurat2duckdb(
                object = seuratObj(),
                dbFile = session$userData$duckdb,
                assay = assay(),
                layers = selectedLayers
            )
            message("Finished Convertion...")
            ## open new connection
            if(isTruthy(duckdbConnection())){
              message("Found previous connection, disconnecting...")
              dbDisconnect(duckdbConnection())
            }
            con <- dbConnect(duckdb::duckdb(), session$userData$duckdb, read_only = TRUE)
            duckdbConnection(con)
        }, priority = -100)

        extract_meta <- ExtendedTask$new(function(dbFile, filePath){
            future_promise({

                con <- DBI::dbConnect(duckdb::duckdb(),
                                      dbdir = dbFile,
                                      read_only = TRUE)
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

        observeEvent(duckdbConnection(), {
            ## transfer metaData when duckdbConnection is ready
            req(duckdbConnection())
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
            promise_dbFile <- session$userData$duckdb
            promise_filePath <- file.path(session$userData$tempDir, hash_md5("metaData"))
            extract_meta$invoke(dbFile = promise_dbFile,
                                filePath = promise_filePath)

        }, ignoreNULL = TRUE)

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
# mod_PrepareDuckdb_ui("PrepareDuckdb_1")
    
## To be copied in the server
# mod_PrepareDuckdb_server("PrepareDuckdb_1")
