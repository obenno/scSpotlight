#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny
#' @import DBI
#' @noRd
app_server <- function(input, output, session) {
    ## Your application server logic
    ## create mainClusterPlot via R, javascript instance init will fail, don't know why
    ##session$sendCustomMessage(type = "reglScatter_mainClusterPlot", "")

    ## store duckdb file in userData space
    session$userData$duckdb <- tempfile(pattern = paste0("session", session$token, "_"),
                                        fileext = ".duckdb",
                                        tmpdir = getwd())

    ## setup universal status indicator
    seuratObj <- reactiveVal(NULL)
    duckdbFile <- session$userData$duckdb
    message("Init duckdbConnection...")
    duckdbConnection <- reactiveVal(NULL)
    objIndicator <- reactiveVal(0)
    metaIndicator <- reactiveVal(0)
    scatterReductionIndicator <- reactiveVal(0)
    scatterColorIndicator <- reactiveVal(0)
    scatterReductionInput <- reactiveVal(NULL)
    scatterColorInput <- reactiveVal(NULL)

    ## Reads input data and save to a seuratObj
    ##seuratObj <- mod_dataInput_server("dataInput", objIndicator, metaIndicator, scatterReductionIndicator, scatterColorIndicator)

    ## seuratObj changes, plottingMode will change, and indicators will increase
    ## Thus filterCells and ClusterSetting do not need to alter indicators
    selectedAssay <- mod_dataInput_server("dataInput",
                                          seuratObj,
                                          clusterSettings$hvgSelectMethod,
                                          clusterSettings$clusterDims,
                                          clusterSettings$clusterResolution,
                                          scatterReductionIndicator,
                                          scatterColorIndicator,
                                          objIndicator)
    observeEvent(selectedAssay(), {
        req(seuratObj())
        obj <- seuratObj()
        DefaultAssay(obj) <- selectedAssay()
        seuratObj(obj)
    })

    ## Update Clusters
    clusterSettings <- mod_ClusterSetting_server("clusterSettings",
                                                 seuratObj,
                                                 scatterReductionIndicator,
                                                 scatterColorIndicator)
    ## Filter Clusters
    mod_FilterCell_server("filterCells",
                          seuratObj,
                          clusterSettings$hvgSelectMethod,
                          clusterSettings$clusterDims,
                          clusterSettings$clusterResolution,
                          scatterReductionIndicator,
                          scatterColorIndicator)

    mod_CellCycling_server("cellCycling",
                           seuratObj)

    DEG_markers <- mod_FindMarkers_server("findMarkers",
                                          seuratObj,
                                          categoryInfo$group.by)
    mod_DEG_Table_server("DEGList",
                         DEG_markers)

    mod_ElbowPlot_server("elbowPlot",
                         seuratObj)

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

    ## Update reductions
    selectedReduction <- mod_UpdateReduction_server("reductionUpdate",
                                                    duckdbConnection,
                                                    scatterReductionIndicator,
                                                    scatterColorIndicator)

    ## Update category
    categoryInfo <- mod_UpdateCategory_server("categoryUpdate",
                                              duckdbConnection,
                                              scatterReductionIndicator,
                                              scatterColorIndicator)

    observeEvent(list(
        categoryInfo$group.by(),
        categoryInfo$split.by(),
        scatterReductionIndicator(),
        scatterColorIndicator()
    ), {
        message("Selected group.by is ", categoryInfo$group.by())
        message("Selected split.by is ", categoryInfo$split.by())
        message("scatterReductionIndicator() is ", scatterReductionIndicator())
        message("scatterColorIndicator() is ", scatterColorIndicator())
    })

    ## Input Features
    ##selectedFeature <- reactiveVal(NULL)
    featureInfo <- mod_InputFeature_server("inputFeatures", seuratObj)

    goBackButton <- reactive({
        ## goBack cannot be read directly in module
        ## has to be parsed by reactive()
        input$goBack
    })

    ## Draw cluster plot
    selectedFeature <- mod_mainClusterPlot_server("mainClusterPlot",
                                                  seuratObj,
                                                  duckdbConnection,
                                                  scatterReductionIndicator,
                                                  scatterColorIndicator,
                                                  scatterReductionInput,
                                                  scatterColorInput,
                                                  selectedReduction,
                                                  categoryInfo$group.by,
                                                  categoryInfo$split.by,
                                                  featureInfo$filteredInputFeatures,
                                                  featureInfo$moduleScore,
                                                  goBackButton)

    ## infoBox needs to be collapsed by default
    observeEvent(input$infoBox_show, {
        message("input$infoBox_show is ", input$infoBox_show)
        if(input$infoBox_show){
            message("show infoBox")
            show_infoBox(session)
        }else{
            message("collapse infoBox")
            ## default value of input$infoBox_show is FALSE
            collapse_infoBox(session)
        }
    }, priority = 100) # high priority for UI components
    ## Draw VlnPlot
    mod_VlnPlot_server("vlnPlot",
                       seuratObj,
                       categoryInfo$group.by,
                       categoryInfo$split.by,
                       selectedFeature,
                       featureInfo$filteredInputFeatures,
                       featureInfo$moduleScore)

    ## Draw DotPlot
    mod_DotPlot_server("dotPlot",
                       seuratObj,
                       categoryInfo$group.by,
                       categoryInfo$split.by,
                       featureInfo$filteredInputFeatures)

    ## Rename Clusters
    selectedPoints <- reactive({
        if(isTruthy(goBackButton())){
            NULL
        }else{
            message("Selected Points: ", ifelse(isTruthy(input$selectedPoints), paste(input$selectedPoints, collapse = " "), "None"))
            input$selectedPoints
        }
    })
    mod_AssignCellCluster_server("renameCluster",
                                 seuratObj,
                                 selectedPoints,
                                 categoryInfo$group.by,
                                 categoryInfo$split.by,
                                 scatterReductionIndicator,
                                 scatterColorIndicator)

    ## Download Object
    mod_Download_server("downloadObj",
                        seuratObj)

    ## close duckdb when session ends
    session$onSessionEnded(function(){
        if(isTruthy(isolate(duckdbConnection()))){
            dbDisconnect(isolate(duckdbConnection()))
        }

    })
}
