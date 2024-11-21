#' PrepareDuckdb UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_Convert2Duckdb_ui <- function(id){
  ns <- NS(id)
  tagList(
 
  )
}
    
#' PrepareDuckdb Server Functions
#'
#' @importFrom qs qsave
#' @noRd 
mod_Convert2Duckdb_server <- function(id,
                                     seuratObj,
                                     assay,
                                     geneUpdateIndicator,
                                     metaUpdateIndicator,
                                     reductionUpdateIndicator){
    moduleServer( id, function(input, output, session){
        ns <- session$ns
        observeEvent(list(seuratObj(), assay()), {
            req(seuratObj(), assay())
            ## convert seuratObj to duckdb
            ## Get the layers
            selectedLayers <- intersect(c("counts", "data"), Layers(seuratObj()))
            stopifnot(length(selectedLayers)>0)

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
            geneUpdateIndicator(geneUpdateIndicator()+1)
            metaUpdateIndicator(metaUpdateIndicator()+1)
            reductionUpdateIndicator(reductionUpdateIndicator()+1)

        }, priority = -100)



    })
}

## To be copied in the UI
# mod_PrepareDuckdb_ui("PrepareDuckdb_1")
    
## To be copied in the server
# mod_PrepareDuckdb_server("PrepareDuckdb_1")
