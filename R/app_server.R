#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny
#' @import DBI
#' @importFrom rlang %||%
#' @noRd
app_server <- function(input, output, session) {

    ## create temp dir to store expression binary files, reduction, metaData and
    ## newly created duckdb file
    tempDir <- file.path(getwd(), paste0("tmp_", session$token))
    if(dir.create(tempDir)){
        ## create dir to store reduction, meta and expr files
        dir.create(file.path(tempDir, "reduction"))
        dir.create(file.path(tempDir, "meta"))
        dir.create(file.path(tempDir, "expr"))
        addResourcePath("data", tempDir)
        session$userData$tempDir <- tempDir
        message("temp dir created: ", session$userData$tempDir)
    }else{
        stop("Failed to create temp dir")
    }

    ## store duckdb file in userData space
    session$userData$duckdb <- tempfile(
        pattern = paste0("session_", session$token),
        fileext = ".duckdb",
        tmpdir = session$userData$tempDir
    )

    ## setup nCores
    session$userData$nCores <- as.character(golem::get_golem_options("nCores"))

    ## setup universal status indicator
    seuratObj <- reactiveVal(NULL)

    metaProcessed <- reactiveVal(FALSE)
    reductionProcessed <- reactiveVal(FALSE)


    ## indicator for gene list changes
    geneUpdateIndicator <- reactiveVal(0)
    ## indicator for meta changes
    metaUpdateIndicator <- reactiveVal(0)
    ## indicator for reduction changes
    reductionUpdateIndicator <- reactiveVal(0)
    ## indicator for invoking regl plot
    scatterUpdateIndicator <- reactiveVal(0)
    ## Init value to store user defined groups/metaData
    userMetaData <- reactiveVal(NULL)

    ## seuratObj changes, plottingMode will change, and indicators will increase
    ## Thus filterCells and ClusterSetting do not need to alter indicators
    inputData <- mod_dataInput_server(
        "dataInput",
        seuratObj,
        clusterSettings$hvgSelectMethod,
        clusterSettings$clusterDims,
        clusterSettings$clusterResolution,
        geneUpdateIndicator,
        metaUpdateIndicator,
        reductionUpdateIndicator
    )

    ## Update Clusters
    clusterSettings <- mod_ClusterSetting_server(
        "clusterSettings",
        seuratObj,
        inputData$selectedAssay,
        metaUpdateIndicator,
        reductionUpdateIndicator
    )

    ## Filter Clusters
    mod_FilterCell_server(
        "filterCells",
        seuratObj,
        inputData$selectedAssay,
        clusterSettings$hvgSelectMethod,
        clusterSettings$clusterDims,
        clusterSettings$clusterResolution,
        geneUpdateIndicator,
        metaUpdateIndicator,
        reductionUpdateIndicator
    )

    mod_CellCycling_server(
        "cellCycling",
        seuratObj,
        inputData$selectedAssay
    )

    DEG_markers <- mod_FindMarkers_server(
        "findMarkers",
        inputData$seuratObj,
        categoryInfo$group.by
    )

    mod_DEG_Table_server(
        "DEGList",
        DEG_markers
    )

    observeEvent(input$metaProcessed, {
        metaProcessed(input$metaProcessed)
    })
    ## Update metaData
    mod_UpdateMetaData_server(
        "updateMetaData",
        metaUpdateIndicator,
        metaProcessed
    )

    observeEvent(input$reductionProcessed, {
        reductionProcessed(input$reductionProcessed)
    })
    ## Update reductions
    mod_UpdateReduction_server(
        "updateReduction",
        seuratObj,
        reductionUpdateIndicator,
        reductionProcessed
    )

    ## Update category
    metaCols <- reactive({
        ## client side metaData column names
        ## only contains non-numeric columns
        input$metaCols
    })

    metaColLevels <- reactive({
        input$metaColLevels
    })

    categoryInfo <- mod_UpdateCategory_server(
        "updateCategory",
        metaCols,
        scatterUpdateIndicator
    )

    ## Input Features
    featureInfo <- mod_InputFeature_server(
        "inputFeatures",
        inputData$selectedAssay,
        geneUpdateIndicator,
        scatterUpdateIndicator
    )

    selectedFeatures <- reactive({
        ## has to be parsed by reactive()
        message("input$selectedFeatures: ", input$selectedFeatures)
        input$selectedFeatures
    })

    ## Draw cluster plot
    mod_mainClusterPlot_server(
        "mainClusterPlot",
        reductionProcessed,
        metaProcessed,
        scatterUpdateIndicator,
        categoryInfo$group.by,
        categoryInfo$split.by,
        featureInfo$moduleScore
    )

    ## Rename Clusters
    selectedPoints <- eventReactive(input$selectedPoints, {
        ##message("Selected Points: ", ifelse(isTruthy(input$selectedPoints), paste(input$selectedPoints, collapse = " "), "None"))
        input$selectedPoints
    }, ignoreNULL = FALSE)

    categorySelectedCells <- reactive({
        input$categorySelectedCells
    })

    observeEvent(input$newMetaColData, {
        d <- input$newMetaColData[[1]] %>% unlist()
        str(d)
        colName <- names(input$newMetaColData)[1]
        ## update seuratObj
        if(isTruthy(seuratObj())){
            withProgress(
                message = "Updating seurat object...",
                {
                    obj <- SeuratObject::AddMetaData(
                        seuratObj(),
                        metadata = d,
                        col.name = colName)
                    seuratObj(obj)
                }
            )
        }
        ## update duckdb
        if(file.exists(session$userData$duckdb)){
            withProgress(
                message = "Updating duckdb...",
                {
                    con <- duckConnect(session, read_only=FALSE)
                    on.exit(dbDisconnect(con))
                    if(!(colName %in% colnames(tbl(con, "metaData")))){
                        dbExecute(
                            con,
                            sprintf("ALTER TABLE metaData ADD COLUMN %s VARCHAR", colName)
                        )
                    }
                    ## duckdb rowid starts from 0, not 1 !
                    for(i in seq_along(d)) {
                        dbExecute(
                            con,
                            sprintf("UPDATE metaData SET %s = '%s' WHERE rowid = %d", colName, d[i], i-1)
                        )
                    }

                }
            )
        }
        ##userMetaData(input$newMetaColData)
    })

    mod_AssignCellCluster_server(
        "renameCluster",
        selectedPoints,
        categorySelectedCells,
        categoryInfo$group.by,
        categoryInfo$split.by,
        metaColLevels,
        userMetaData
    )

    ## Download Object
    mod_Download_server(
        "downloadObj",
        seuratObj,
        inputData$BPCells
    )

    ## close duckdb when session ends
    session$onSessionEnded(function(){
        tryCatch(
        {
          if(file.exists(session$userData$tempDir)){
            ##message("session$userData$tempDir :", session$userData$tempDir)
            unlink(session$userData$tempDir,
                   recursive = TRUE, force = TRUE)
          }
        },
        error = function(e){
          message("Remove tempDir failed: ", e)
        }
        )
    })
}
