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
#' @noRd 
mod_PrepareDuckdb_server <- function(id,
                                     seuratObj,
                                     duckdbConnection){
    moduleServer( id, function(input, output, session){
        ns <- session$ns
        observeEvent(seuratObj(), {
            req(seuratObj())
            ## convert seuratObj to duckdb
            ## Get the layers
            selectedLayers <- intersect(c("counts", "data"), Layers(seuratObj()))
            stopifnot(length(selectedLayers)>0)
            ## first stope connection if already exists
            if(isTruthy(duckdbConnection())){
                dbDisconnect(duckdbConnection())
            }
            message("Coverting duckdb")
            seurat2duckdb(
                object = seuratObj(),
                dbFile = duckdbFile,
                assay = DefaultAssay(seuratObj()),
                layers = selectedLayers,
                reductions = Reductions(seuratObj())
            )
            message("Finished Coverting...")
            ## open new connection
            con <- dbConnect(duckdb::duckdb(), duckdbFile)
            duckdbConnection(con)
        }, priority = -100)


        observeEvent(duckdbConnection(), {
            ## transfer metaData when duckdbConnection is ready
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
            d <- queryDuckMeta(duckdbConnection(), "metaData")
            d <- d %>% mutate(cells=1:nrow(d)) %>% as_tibble()
            transfer_meta(d, session)
            rm(d)
            removeNotification(id = "update_meta_notification", session)
        }, ignoreNULL = TRUE)
    })
}

## To be copied in the UI
# mod_PrepareDuckdb_ui("PrepareDuckdb_1")
    
## To be copied in the server
# mod_PrepareDuckdb_server("PrepareDuckdb_1")
