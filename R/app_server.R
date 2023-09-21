#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
app_server <- function(input, output, session) {
    ## Your application server logic
    ## create mainClusterPlot via R, javascript instance init will fail, don't know why
    ##session$sendCustomMessage(type = "reglScatter_mainClusterPlot", "")

    ## setup universal status indicator
    ##seuratObj <- reactiveVal()
    objIndicator <- reactiveVal(0)
    metaIndicator <- reactiveVal(0)
    scatterReductionIndicator <- reactiveVal(0)
    scatterColorIndicator <- reactiveVal(0)
    scatterReductionInput <- reactiveVal(NULL)
    scatterColorInput <- reactiveVal(NULL)
    ##selectedFeatures <- reactiveVal()
    ##focusedFeature <- reactiveVal()

    ## Reads input data and save to a seuratObj
    seuratObj <- mod_dataInput_server("dataInput", objIndicator, metaIndicator, scatterReductionIndicator, scatterColorIndicator)

    ## Update scatterReductionInput only when scatterReductionIndicator changes
    observeEvent(scatterReductionIndicator(), {
        req(seuratObj())
        d <- prepare_scatterReductionInput(seuratObj(),
                                           reduction = "umap",
                                           mode = "cluster+expr+twoSplit",
                                           split.by = "stim")
        message("Updating scatterReductionInput")
        scatterReductionInput(d)
    }, priority = -10)

    ## Update scatterColorInput only when scatterReductionIndicator changes
    observeEvent(scatterColorIndicator(), {
        req(seuratObj())
        d <- prepare_scatterCatColorInput(seuratObj(),
                                          col_name = "seurat_clusters",
                                          mode = "cluster+expr+twoSplit",
                                          split.by = "stim",
                                          feature = "IDO1")
        message("Updating scatterColorInput")
        scatterColorInput(d)
    }, priority = -10)

    ## Draw cluster plot
    mod_mainClusterPlot_server("mainClusterPlot",
                               scatterReductionIndicator,
                               scatterColorIndicator,
                               scatterReductionInput,
                               scatterColorInput)
}
