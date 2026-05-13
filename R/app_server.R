#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny
#' @importFrom rlang %||%
#' @noRd
app_server <- function(input, output, session) {
  ## create temp dir to store Arrow IPC files and BPCells-backed session data
  tempDir <- file.path(getwd(), paste0("tmp_", session$token))
  if (dir.create(tempDir)) {
    ## create dir to store reduction, meta and expr files
    dir.create(file.path(tempDir, "reduction"))
    dir.create(file.path(tempDir, "meta"))
    dir.create(file.path(tempDir, "expr"))
    dir.create(file.path(tempDir, "backend"))
    addResourcePath("data", tempDir)
    session$userData$tempDir <- tempDir
    session$userData$backendDir <- file.path(tempDir, "backend")
    message("temp dir created: ", session$userData$tempDir)
  } else {
    stop("Failed to create temp dir")
  }

  ## setup nCores
  session$userData$nCores <- as.character(golem::get_golem_options("nCores"))

  ## setup universal status indicator
  seuratObj <- reactiveVal(NULL)
  runningMode <- normalize_running_mode(golem::get_golem_options("runningMode"))
  clusterSettings <- list(
    hvgSelectMethod = reactive("vst"),
    clusterDims = reactive(30),
    clusterResolution = reactive(0.5)
  )

  metaProcessed <- reactiveVal(FALSE)
  reductionProcessed <- reactiveVal(FALSE)

  ## indicator for gene list changes
  geneUpdateIndicator <- reactiveVal(0)
  ## indicator for meta changes
  metaUpdateIndicator <- reactiveVal(0)
  ## indicator for reduction changes
  reductionUpdateIndicator <- reactiveVal(0)
  ## indicator for view-driven plot changes (group.by/split.by/feature toggles)
  scatterUpdateIndicator <- reactiveVal(0)
  ## indicator for plot refresh after data transfer completion
  plotRefreshIndicator <- reactiveVal(0)
  ## request for partial metadata transfer
  metaPatchRequest <- reactiveVal(NULL)
  ## monotonic counter for partial metadata patch versions
  metaPatchVersion <- reactiveVal(0)
  ## Init value to store user defined groups/metaData
  userMetaData <- reactiveVal(NULL)

  active_plot_meta_cols <- reactive({
    cols <- c(categoryInfo$group.by(), categoryInfo$split.by())
    cols[!is.na(cols) & nzchar(cols) & cols != "None"]
  })

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

  if (identical(runningMode, "analysis")) {
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
      inputData$selectedAssay,
      metaPatchRequest,
      metaPatchVersion
    )
  }

  observeEvent(input$metaProcessed, {
    metaProcessed(input$metaProcessed)
    if (isTRUE(input$metaProcessed)) {
      plotRefreshIndicator(plotRefreshIndicator() + 1)
    }
  })
  ## Update metaData
  mod_UpdateMetaData_server(
    "updateMetaData",
    seuratObj,
    metaUpdateIndicator,
    metaPatchRequest,
    metaProcessed
  )

  observeEvent(input$reductionProcessed, {
    reductionProcessed(input$reductionProcessed)
    if (isTRUE(input$reductionProcessed)) {
      plotRefreshIndicator(plotRefreshIndicator() + 1)
    }
  })

  observeEvent(
    input$initialPlotReady,
    {
      waiter::waiter_hide()
    },
    ignoreNULL = TRUE
  )

  observeEvent(input$metaPatchProcessed, {
    patch_info <- input$metaPatchProcessed
    patch_cols <- patch_info$cols %||% character()

    if (!length(patch_cols)) {
      plotRefreshIndicator(plotRefreshIndicator() + 1)
      return()
    }

    if (length(intersect(patch_cols, active_plot_meta_cols())) > 0L) {
      plotRefreshIndicator(plotRefreshIndicator() + 1)
    }
  })
  ## Update reductions
  mod_UpdateReduction_server(
    "updateReduction",
    seuratObj,
    reductionUpdateIndicator,
    reductionProcessed
  )

  ## Update category
  metaSidebarState <- reactive({
    input$metaSidebarState
  })

  metaCols <- reactive({
    ## client side metaData column names
    ## only contains non-numeric columns
    state <- metaSidebarState()
    state$cols
  })

  categoryInfo <- mod_UpdateCategory_server(
    "updateCategory",
    metaCols,
    metaSidebarState,
    scatterUpdateIndicator
  )

  if (identical(runningMode, "analysis")) {
    mod_DEG_Window_server(
      "DEGWindow",
      seuratObj,
      categoryInfo$group.by
    )
  }

  ## Input Features
  featureInfo <- mod_InputFeature_server(
    "inputFeatures",
    seuratObj,
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
    plotRefreshIndicator,
    scatterUpdateIndicator,
    categoryInfo$group.by,
    categoryInfo$split.by,
    featureInfo$moduleScore
  )

  if (identical(runningMode, "analysis")) {
    ## Rename Clusters
    selectedPoints <- eventReactive(
      input$selectedPoints,
      {
        ##message("Selected Points: ", ifelse(isTruthy(input$selectedPoints), paste(input$selectedPoints, collapse = " "), "None"))
        input$selectedPoints
      },
      ignoreNULL = FALSE
    )

    observeEvent(input$newMetaColData, {
      d <- input$newMetaColData[[1]] %>% unlist()
      str(d)
      colName <- names(input$newMetaColData)[1]
      ## update seuratObj
      if (isTruthy(seuratObj())) {
        withProgress(message = "Updating seurat object...", {
          obj <- SeuratObject::AddMetaData(
            seuratObj(),
            metadata = d,
            col.name = colName
          )
          seuratObj(obj)
        })
      }

      if (colName %in% active_plot_meta_cols()) {
        plotRefreshIndicator(plotRefreshIndicator() + 1)
      }
    })

    mod_AssignCellCluster_server(
      "renameCluster",
      seuratObj,
      selectedPoints,
      geneUpdateIndicator,
      metaUpdateIndicator,
      reductionUpdateIndicator
    )

    ## Download Object
    mod_Download_server(
      "downloadObj",
      seuratObj
    )

    mod_DataConversion_server(
      "dataConversion"
    )
  }

  session$onSessionEnded(function() {
    tryCatch(
      {
        if (file.exists(session$userData$tempDir)) {
          ##message("session$userData$tempDir :", session$userData$tempDir)
          unlink(session$userData$tempDir, recursive = TRUE, force = TRUE)
        }
      },
      error = function(e) {
        message("Remove tempDir failed: ", e)
      }
    )
  })
}
