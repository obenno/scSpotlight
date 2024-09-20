#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny
#' @import DBI
#' @noRd
app_server <- function(input, output, session) {

    ## create temp dir to store expression binary files, reduction, metaData and
    ## newly created duckdb file
    tempDir <- file.path(getwd(), paste0("tmp_", session$token))
    if(dir.create(tempDir)){
        addResourcePath("data", tempDir)
        session$userData$tempDir <- tempDir
    }else{
        stop("Failed to create temp dir")
    }

    ## store duckdb file in userData space
    session$userData$duckdb <- tempfile(
        pattern = paste0("session_", session$token),
        fileext = ".duckdb",
        tmpdir = session$userData$tempDir
    )


    ## setup universal status indicator
    seuratObj <- reactiveVal(NULL)
    duckdbFile <- session$userData$duckdb
    message("Init duckdbConnection...")
    duckdbConnection <- reactiveVal(NULL)
    scatterReductionIndicator <- reactiveVal(0)
    scatterColorIndicator <- reactiveVal(0)

    ## Reads input data and save to a seuratObj
    ##seuratObj <- mod_dataInput_server("dataInput", objIndicator, metaIndicator, scatterReductionIndicator, scatterColorIndicator)

    ## seuratObj changes, plottingMode will change, and indicators will increase
    ## Thus filterCells and ClusterSetting do not need to alter indicators
    selectedAssay <- mod_dataInput_server(
        "dataInput",
        seuratObj,
        duckdbConnection,
        clusterSettings$hvgSelectMethod,
        clusterSettings$clusterDims,
        clusterSettings$clusterResolution,
        scatterReductionIndicator,
        scatterColorIndicator,
        objIndicator
    )

    observeEvent(selectedAssay(), {
        req(seuratObj())
        obj <- seuratObj()
        DefaultAssay(obj) <- selectedAssay()
        seuratObj(obj)
    })

    ## Update Clusters
    clusterSettings <- mod_ClusterSetting_server(
        "clusterSettings",
        seuratObj,
        scatterReductionIndicator,
        scatterColorIndicator
    )

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

    ## convert seuratObj to duckdb
    mod_PrepareDuckdb_server("duckdb",
                             seuratObj,
                             duckdbConnection)

    ## Update reductions
    selectedReduction <- mod_UpdateReduction_server(
        "reductionUpdate",
        duckdbConnection,
        scatterReductionIndicator
    )

    ## Update category
    metaCols <- reactive({
        ## client side metaData column names
        ## only contains non-numeric columns
        input$metaCols
    })

    metaColLevels <- reactive({
        d <- input$metaColLevels
    })

    categoryInfo <- mod_UpdateCategory_server(
        "categoryUpdate",
        duckdbConnection,
        metaCols,
        scatterReductionIndicator,
        scatterColorIndicator
    )

    ## Input Features
    featureInfo <- mod_InputFeature_server(
        "inputFeatures",
        duckdbConnection,
        selectedAssay,
        scatterColorIndicator
    )

    selectedFeatures <- reactive({
        ## has to be parsed by reactive()
        message("input$selectedFeatures: ", input$selectedFeatures)
        input$selectedFeatures
    })

    ## Draw cluster plot
    mod_mainClusterPlot_server(
        "mainClusterPlot",
        duckdbConnection,
        selectedAssay,
        scatterReductionIndicator,
        scatterColorIndicator,
        categoryInfo$group.by,
        categoryInfo$split.by,
        selectedFeatures,
        featureInfo$moduleScore
    )

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
    ##mod_VlnPlot_server("vlnPlot",
    ##                   seuratObj,
    ##                   categoryInfo$group.by,
    ##                   categoryInfo$split.by,
    ##                   selectedFeature,
    ##                   featureInfo$filteredInputFeatures,
    ##                   featureInfo$moduleScore)

    ## Draw DotPlot
    ##mod_DotPlot_server("dotPlot",
    ##                   seuratObj,
    ##                   categoryInfo$group.by,
    ##                   categoryInfo$split.by,
    ##                   featureInfo$filteredInputFeatures)

    ## Rename Clusters
    selectedPoints <- reactive({
        message("Selected Points: ", ifelse(isTruthy(input$selectedPoints), paste(input$selectedPoints, collapse = " "), "None"))
        input$selectedPoints
    })

    categorySelectedCells <- reactive({
        input$categorySelectedCells
    })

    mod_AssignCellCluster_server(
        "renameCluster",
        duckdbConnection,
        selectedPoints,
        categorySelectedCells,
        categoryInfo$group.by,
        categoryInfo$split.by,
        metaColLevels,
        scatterReductionIndicator,
        scatterColorIndicator
    )

    ## Download Object
    mod_Download_server(
        "downloadObj",
        seuratObj
    )

    ## close duckdb when session ends
    session$onSessionEnded(function(){
        if(isTruthy(isolate(duckdbConnection()))){
            dbDisconnect(isolate(duckdbConnection()))
        }
        tryCatch(
        {
            if(file.exists(session$userData$tempDir)){
                unlink(session$userData$tempDir,
                       recursive = TRUE, force = TRUE)
            }
        },
        error = {
            message("Remove tempDir failed...")
        }
        )
    })
}
