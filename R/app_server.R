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
    ##seuratObj <- mod_dataInput_server("dataInput", objIndicator, metaIndicator, scatterReductionIndicator, scatterColorIndicator)
    seuratObj <- mod_dataInput_server("dataInput", objIndicator)


    ## Update reductions
    selectedReduction <- mod_UpdateReduction_server("reductionUpdate",
                                                    seuratObj,
                                                    scatterReductionIndicator,
                                                    scatterColorIndicator)

    ## Update category
    categoryInfo <- mod_UpdateCategory_server("categoryUpdate",
                                              seuratObj,
                                              scatterReductionIndicator,
                                              scatterColorIndicator)

    observeEvent(list(categoryInfo$group.by(), categoryInfo$split.by()), {
        message("Selected group.by is ", categoryInfo$group.by())
        message("Selected split.by is ", categoryInfo$split.by())
        message("scatterReductionIndicator() is ", scatterReductionIndicator())
        message("scatterColorIndicator() is ", scatterColorIndicator())
    })

    ## Update scatterReductionInput only when scatterReductionIndicator changes
    observeEvent(scatterReductionIndicator(), {
        req(seuratObj())
        validate(
            need(selectedReduction() %in% Reductions(seuratObj()),
                 paste0(selectedReduction(), " is not in object reductions"))
        )
        d <- prepare_scatterReductionInput(seuratObj(),
                                           reduction = selectedReduction(),
                                           mode = "clusterOnly",
                                           split.by = categoryInfo$split.by())
        message("Updating scatterReductionInput")
        scatterReductionInput(d)
    }, priority = -10)

    ## Update scatterColorInput only when scatterReductionIndicator changes
    observeEvent(scatterColorIndicator(), {
        req(seuratObj())
        validate(
            need(selectedReduction() %in% Reductions(seuratObj()),
                 paste0(selectedReduction(), " is not in object reductions"))
        )
        d <- prepare_scatterCatColorInput(seuratObj(),
                                          col_name = categoryInfo$group.by(),
                                          mode = "clusterOnly",
                                          split.by = categoryInfo$split.by(),
                                          feature = "IDO1")
        message("Updating scatterColorInput")
        scatterColorInput(d)
    }, priority = -20)

    ## Draw cluster plot
    mod_mainClusterPlot_server("mainClusterPlot",
                               scatterReductionIndicator,
                               scatterColorIndicator,
                               scatterReductionInput,
                               scatterColorInput)

}
