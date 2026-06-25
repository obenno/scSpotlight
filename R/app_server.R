#' Validate a bounded browser assignment intent
#'
#' @param object A Seurat object.
#' @param intent Browser-submitted assignment intent.
#' @param current_context Current group/split metadata context.
#' @noRd
validate_assignment_intent <- function(
  object,
  intent,
  current_context = list()
) {
  if (!is.list(intent)) {
    stop("Invalid assignment intent", call. = FALSE)
  }

  full_vector_fields <- c(
    "metadataVector",
    paste0("newMetaCol", "Data"),
    "newMetaColVector",
    "metadata_vector"
  )
  if (any(full_vector_fields %in% names(intent))) {
    stop("Assignment intent must not include a full metadata vector", call. = FALSE)
  }

  col_name <- trimws(as.character(intent$newMetaCol %||% ""))
  if (
    length(col_name) != 1L ||
      !nzchar(col_name) ||
      !grepl("^[A-Za-z][A-Za-z0-9_.]*$", col_name)
  ) {
    stop("Invalid metadata column name", call. = FALSE)
  }

  col_value <- trimws(as.character(intent$assignAs %||% ""))
  if (length(col_value) != 1L || !nzchar(col_value)) {
    stop("Invalid assignment value", call. = FALSE)
  }

  normalize_context_value <- function(value) {
    value <- as.character(value %||% "None")
    if (length(value) == 0L || is.na(value[[1]]) || !nzchar(value[[1]])) {
      return("None")
    }
    value[[1]]
  }

  intent_context <- intent$context %||% list()
  current_group <- normalize_context_value(current_context$groupBy)
  current_split <- normalize_context_value(current_context$splitBy)
  intent_group <- normalize_context_value(intent_context$groupBy)
  intent_split <- normalize_context_value(intent_context$splitBy)

  if (!identical(intent_group, current_group) || !identical(intent_split, current_split)) {
    stop("stale assignment context", call. = FALSE)
  }

  normalize_context_version <- function(value) {
    if (is.null(value) || length(value) == 0L || is.na(value[[1]])) {
      return(NULL)
    }
    as.character(value[[1]])
  }
  current_version <- normalize_context_version(current_context$metaVersion %||% NULL)
  intent_version <- normalize_context_version(intent_context$metaVersion %||% NULL)
  if (is.null(current_version) || is.null(intent_version)) {
    stop("stale assignment context", call. = FALSE)
  }
  if (!identical(current_version, intent_version)) {
    stop("stale assignment context", call. = FALSE)
  }

  object_cells <- colnames(object)
  if (is.null(object_cells) || length(object_cells) == 0L) {
    stop("Object has no cells for assignment", call. = FALSE)
  }

  intent_type <- as.character(intent$type %||% "")
  if (!intent_type %in% c("selected_cells", "category_context")) {
    stop("Invalid assignment intent type", call. = FALSE)
  }

  if (identical(intent_type, "selected_cells")) {
    selected_cells <- as.character(intent$selectedCells %||% character(0))
    selected_cells <- selected_cells[nzchar(selected_cells)]
    if (length(selected_cells) == 0L) {
      stop("No selected cells in assignment intent", call. = FALSE)
    }
    if (anyDuplicated(selected_cells)) {
      stop("Assignment intent contains duplicate cells", call. = FALSE)
    }
    unknown_cells <- setdiff(selected_cells, object_cells)
    if (length(unknown_cells) > 0L) {
      stop("Assignment intent contains unknown cells", call. = FALSE)
    }
    return(list(
      type = intent_type,
      cells = selected_cells,
      colName = col_name,
      colValue = col_value,
      metadataVector = NULL
    ))
  }

  category <- intent$category %||% list()
  group_col <- normalize_context_value(category$groupBy)
  if (!identical(group_col, current_group) || identical(group_col, "None")) {
    stop("Invalid category metadata column", call. = FALSE)
  }
  group_levels <- as.character(category$groupLevels %||% character(0))
  group_levels <- group_levels[nzchar(group_levels)]
  if (length(group_levels) == 0L) {
    stop("Category assignment is missing group levels", call. = FALSE)
  }

  meta <- object[[]]
  if (!group_col %in% colnames(meta)) {
    stop("Unknown category metadata column", call. = FALSE)
  }
  matched <- as.character(meta[[group_col]]) %in% group_levels

  if (!identical(current_split, "None")) {
    split_col <- normalize_context_value(category$splitBy)
    if (!identical(split_col, current_split) || identical(split_col, "None")) {
      stop("Category assignment is missing split context", call. = FALSE)
    }
    split_levels <- as.character(category$splitLevels %||% character(0))
    split_levels <- split_levels[nzchar(split_levels)]
    if (length(split_levels) == 0L) {
      stop("Category assignment is missing split levels", call. = FALSE)
    }
    if (!split_col %in% colnames(meta)) {
      stop("Unknown split metadata column", call. = FALSE)
    }
    matched <- matched & as.character(meta[[split_col]]) %in% split_levels
  }

  resolved_cells <- rownames(meta)[matched]
  if (length(resolved_cells) == 0L) {
    stop("Category assignment resolved no cells", call. = FALSE)
  }

  list(
    type = intent_type,
    cells = resolved_cells,
    colName = col_name,
    colValue = col_value,
    metadataVector = NULL
  )
}

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
    dataResourcePrefix <- paste0("data-", session$token)
    session$userData$dataResourcePrefix <- dataResourcePrefix
    addResourcePath(dataResourcePrefix, tempDir)
    session$onSessionEnded(function() {
      removeResourcePath(dataResourcePrefix)
    })
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
  ## server-owned metadata version sequence shared by full refreshes and patches
  metadataVersion <- reactiveVal(0L)
  currentMetadataVersion <- function() {
    value <- metadataVersion()
    if (is.null(value) || length(value) == 0L || is.na(value[[1]])) {
      return(NULL)
    }
    as.integer(value[[1]])
  }
  nextMetadataVersion <- function() {
    current_version <- currentMetadataVersion() %||% 0L
    next_version <- current_version + 1L
    metadataVersion(next_version)
    next_version
  }
  ## indicator for reduction changes
  reductionUpdateIndicator <- reactiveVal(0)
  ## indicator for view-driven plot changes (group.by/split.by/feature toggles)
  scatterUpdateIndicator <- reactiveVal(0)
  ## indicator for plot refresh after data transfer completion
  plotRefreshIndicator <- reactiveVal(0)
  ## request for partial metadata transfer
  metaPatchRequest <- reactiveVal(NULL)
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
      nextMetadataVersion
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
    metaProcessed,
    nextMetadataVersion
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
  reductionInfo <- mod_UpdateReduction_server(
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

  DEG_state <- list(
    markers = reactive(NULL),
    pAdjCutoff = reactive(NULL)
  )

  if (identical(runningMode, "analysis")) {
    DEG_state <- mod_DEG_Window_server(
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

  llmAnalysisContext <- reactive({
    state <- metaSidebarState()
    meta_cols <- if (is.list(state)) state$cols else NULL
    build_llm_analysis_context(
      object = seuratObj(),
      running_mode = runningMode,
      selected_assay = inputData$selectedAssay(),
      selected_reduction = reductionInfo$reduction(),
      group_by = categoryInfo$group.by(),
      split_by = categoryInfo$split.by(),
      selected_features = selectedFeatures(),
      meta_cols = meta_cols,
      deg_markers = DEG_state$markers(),
      p_adj_cutoff = DEG_state$pAdjCutoff(),
      context_version = paste(
        metaUpdateIndicator(),
        reductionUpdateIndicator(),
        geneUpdateIndicator(),
        sep = ":"
      )
    )
  })

  if (llm_is_enabled()) {
    mod_LLMChat_server(
      "llmChat",
      analysisContext = llmAnalysisContext,
      seuratObj = seuratObj,
      group.by = categoryInfo$group.by,
      degMarkers = DEG_state$markers,
      pAdjCutoff = DEG_state$pAdjCutoff,
      llmConfig = llm_provider_config()
    )
  }

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

    observeEvent(input[["renameCluster-assignmentIntent"]], {
      assignmentIntent <- input[["renameCluster-assignmentIntent"]]
      req(isTruthy(seuratObj()))

      current_context <- list(
        groupBy = categoryInfo$group.by(),
        splitBy = categoryInfo$split.by(),
        metaVersion = currentMetadataVersion()
      )

      tryCatch(
        {
          assignment <- validate_assignment_intent(
            seuratObj(),
            assignmentIntent,
            current_context = current_context
          )

          withProgress(message = "Updating metadata assignment...", {
            obj <- seuratObj()
            meta <- obj[[]]
            assigned_col <- if (assignment$colName %in% colnames(meta)) {
              as.character(meta[[assignment$colName]])
            } else {
              rep("unknown", ncol(obj))
            }
            names(assigned_col) <- colnames(obj)
            assigned_col[assignment$cells] <- assignment$colValue
            obj <- SeuratObject::AddMetaData(
              obj,
              metadata = assigned_col,
              col.name = assignment$colName
            )
            seuratObj(obj)

            patch_version <- nextMetadataVersion()
            metaPatchRequest(list(
              cols = assignment$colName,
              version = patch_version
            ))
          })

          showNotification(
            ui = "Successfully assigned metadata.",
            action = NULL,
            duration = 3,
            closeButton = TRUE,
            type = "message",
            session = session
          )
        },
        error = function(e) {
          message("Metadata assignment rejected: ", conditionMessage(e))
          showNotification(
            ui = "Metadata assignment could not be applied. Refresh the plot and try again.",
            action = NULL,
            duration = 6,
            closeButton = TRUE,
            type = "error",
            session = session
          )
        }
      )
    })

    mod_AssignCellCluster_server(
      "renameCluster",
      seuratObj,
      selectedPoints,
      geneUpdateIndicator,
      metaUpdateIndicator,
      reductionUpdateIndicator,
      backend_root = session$userData$backendDir
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
