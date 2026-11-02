#' dataInput UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList fileInput
#'
mod_dataInput_inputUI <- function(id) {
  ns <- NS(id)

  dataDir <- golem::get_golem_options("dataDir")
  runningMode <- normalize_running_mode(golem::get_golem_options(
    "runningMode"
  ))
  upload_label <- if (identical(runningMode, "explore")) {
    tagList(
      "Upload Explore Parquet Bundle",
      infoIcon(
        "Please upload a scSpotlight Explore Parquet archive ending in .explore-parquet.zip",
        "right"
      )
    )
  } else {
    tagList(
      "Upload Input File",
      infoIcon(
        "Please upload a processed Seurat object (RDS), a Scanpy/AnnData h5ad file, or a compressed matrix directory (zip, tgz, tbz2)",
        "right"
      )
    )
  }
  upload_accept <- if (identical(runningMode, "explore")) {
    ".explore-parquet.zip"
  } else {
    c(
      ".rds",
      ".h5ad",
      ".zip",
      ".tar.gz",
      ".tgz",
      ".tar.bz2",
      ".tbz2"
    )
  }
  ##runningMode <- golem::get_golem_options("runningMode")
  ##if(isTruthy(dataDir) && runningMode == "explore"){
  if (isTruthy(dataDir)) {
    tagList(
      selectizeInput(
        ns("dataDirFile"),
        label = "Choose an input file",
        choices = "",
        selected = NULL,
        multiple = FALSE,
        options = list(dropdownParent = "body")
      ),
      selectizeInput(
        ns("selectAssay"),
        "Switch Assays",
        choices = "",
        selected = NULL,
        multiple = FALSE,
        options = list(dropdownParent = "body"),
        width = NULL
      ) %>%
        tagAppendAttributes(class = c("mb-1"))
    )
  } else {
    tagList(
      fileInput(
        ns("dataInput"),
        upload_label,
        multiple = FALSE,
        width = "100%",
        accept = upload_accept
      ),
      selectizeInput(
        ns("selectAssay"),
        "Switch Assays",
        choices = "",
        selected = NULL,
        multiple = FALSE,
        options = list(dropdownParent = "body"),
        width = NULL
      ) %>%
        tagAppendAttributes(class = c("mb-1"))
    )
  }
}

#' Analysis Mode input loading helper
#'
#' @noRd
load_analysis_input_file <- function(
  input_file,
  input_name = basename(input_file),
  backend_root,
  hvgSelectMethod = "vst",
  nDims = 30,
  resolution = 1,
  temp_root = NULL,
  status = function(...) NULL,
  notify = function(...) NULL
) {
  if (
    !is.character(input_file) || length(input_file) != 1L || !nzchar(input_file)
  ) {
    stop("Expected a single Analysis input file path", call. = FALSE)
  }
  if (!file.exists(input_file)) {
    stop(
      "Analysis input file does not exist: ",
      basename(input_file),
      call. = FALSE
    )
  }

  input_name <- input_name %||% basename(input_file)
  backend_root <- backend_root %||%
    scspotlight_temp_path("scspotlight_analysis_layers_")
  temp_root <- temp_root %||% dirname(backend_root)
  dir.create(backend_root, recursive = TRUE, showWarnings = FALSE)
  dir.create(temp_root, recursive = TRUE, showWarnings = FALSE)

  compressionFormatPattern <- "\\.zip$|\\.tar.gz$|\\.tgz$|\\.tar\\.bz2$|\\.tbz2"
  rdsFormatPattern <- "\\.rds$|\\.RDS$|\\.Rds$"
  h5adFormatPattern <- "\\.[Hh]5[Aa][Dd]$"
  hvg_method <- if (isTruthy(hvgSelectMethod)) {
    hvgSelectMethod
  } else {
    "vst"
  }
  nDims <- suppressWarnings(as.integer(nDims %||% 30L))
  if (is.na(nDims) || nDims < 1L) {
    nDims <- 30L
  }
  resolution <- suppressWarnings(as.numeric(resolution %||% 1))
  if (is.na(resolution) || resolution <= 0) {
    resolution <- 1
  }

  prefer_vst_warning <- function(object) {
    if (
      is_seurat_bpcells(object) &&
        isTruthy(hvgSelectMethod) &&
        !identical(hvgSelectMethod, "vst")
    ) {
      notify(
        HTML(
          "BPCells backend active, prefer <b>vst</b> on the <b>counts</b> layer for large datasets"
        ),
        type = "warning",
        duration = 5
      )
    }
  }

  finalize_analysis_object <- function(object) {
    object <- drop_dense_scale_data(object)
    assert_no_dense_scale_data(object)
    object <- ensure_bpcells_backing(
      object,
      root_dir = backend_root,
      layers = NULL
    )
    assert_no_dense_scale_data(object)
    assert_scspotlight_backend(object)
    object
  }

  load_rds_analysis_object <- function(path) {
    bundle_error <- NULL
    object <- tryCatch(
      load_scspotlight_bundle(path),
      error = function(error) {
        bundle_error <<- error
        NULL
      }
    )
    if (isTruthy(object)) {
      return(object)
    }

    object <- tryCatch(
      readRDS(path),
      error = function(error) {
        stop(
          "Failed to load Seurat RDS input '",
          basename(path),
          "'.",
          call. = FALSE
        )
      }
    )
    if (!inherits(object, "Seurat")) {
      if (!is.null(bundle_error)) {
        stop(
          "Failed to load Seurat RDS input '",
          basename(path),
          "'.",
          call. = FALSE
        )
      }
      stop("RDS input did not contain a Seurat object.", call. = FALSE)
    }
    object
  }

  if (str_detect(input_name, scspotlight_explore_archive_pattern)) {
    message <- paste(
      "This file is an Explore Parquet bundle, which is read-only and can only be opened in Explore Mode.",
      "Restart scSpotlight with runningMode = 'explore' to open it, or choose a Seurat RDS, h5ad, BPCells bundle, or 10x matrix archive for Analysis Mode."
    )
    notify(message, type = "error", duration = 8)
    status("This Explore Parquet bundle can only be opened in Explore Mode.")
    stop(message, call. = FALSE)
  }

  seuratObj <- NULL
  if (str_detect(input_name, rdsFormatPattern)) {
    seuratObj <- load_rds_analysis_object(input_file)
    assay <- DefaultAssay(seuratObj)
    if (inherits(seuratObj[[assay]], "Assay")) {
      seuratObj[[assay]] <- as(seuratObj[[assay]], Class = "Assay5")
    }
    seuratObj <- drop_dense_scale_data(seuratObj)
    assert_no_dense_scale_data(seuratObj)
    seuratObj <- ensure_bpcells_backing(
      seuratObj,
      root_dir = backend_root,
      layers = NULL
    )
    prefer_vst_warning(seuratObj)
    seuratObj <- validate_seuratRDS(
      seuratObj,
      runningMode = "analysis",
      hvgSelectMethod = hvg_method,
      nDims = nDims,
      resolution = resolution,
      backend_root = backend_root
    )
  } else if (str_detect(input_name, h5adFormatPattern)) {
    status("Importing h5ad...")
    seuratObj <- import_h5ad_as_seurat_bpcells(
      input_file,
      backend_root = backend_root
    )
    prefer_vst_warning(seuratObj)
    seuratObj <- validate_seuratRDS(
      seuratObj,
      runningMode = "analysis",
      hvgSelectMethod = hvg_method,
      nDims = nDims,
      resolution = resolution,
      backend_root = backend_root
    )
  } else if (str_detect(input_name, compressionFormatPattern)) {
    status("Decompressing...")
    dataDir <- decompress_matrix_input(
      input_name,
      input_file,
      temp_root = temp_root
    )
    if (isTruthy(find_scspotlight_explore_bundle_root(dataDir))) {
      message <- paste(
        "This file is an Explore Parquet bundle, which is read-only and can only be opened in Explore Mode.",
        "Restart scSpotlight with runningMode = 'explore' to open it, or choose a Seurat RDS, h5ad, BPCells bundle, or 10x matrix archive for Analysis Mode."
      )
      notify(message, type = "error", duration = 8)
      status("This Explore Parquet bundle can only be opened in Explore Mode.")
      stop(message, call. = FALSE)
    }

    BPCells_Rds <- dir(
      dataDir,
      recursive = TRUE,
      pattern = "*.[Rr][Dd][Ss]$"
    )
    if (length(BPCells_Rds) > 0) {
      bundleRoot <- if (is_scspotlight_bundle_dir(dataDir)) {
        dataDir
      } else {
        candidate_roots <- unique(dirname(file.path(dataDir, BPCells_Rds)))
        matched_root <- candidate_roots[vapply(
          candidate_roots,
          is_scspotlight_bundle_dir,
          logical(1)
        )]
        if (!length(matched_root)) {
          stop(
            "Compressed RDS bundle detected, but manifest.json is missing or invalid",
            call. = FALSE
          )
        }
        matched_root[[1]]
      }
      bundleRds <- find_scspotlight_bundle_rds(bundleRoot)
      seuratObj <- load_scspotlight_bundle(bundleRds)
      prefer_vst_warning(seuratObj)
      seuratObj <- validate_seuratRDS(
        seuratObj,
        runningMode = "analysis",
        hvgSelectMethod = "vst",
        nDims = nDims,
        resolution = resolution,
        backend_root = backend_root
      )
    } else {
      status("Reading Matrix...")
      counts <- BPCells_Read10X(dataDir, temp_root = temp_root)
      if (isTruthy(hvgSelectMethod) && !identical(hvgSelectMethod, "vst")) {
        notify(
          HTML(
            "BPCells backend active, prefer <b>vst</b> on the <b>counts</b> layer for large datasets"
          ),
          type = "warning",
          duration = 5
        )
      }
      status("Creating seuratObj...")
      seuratObj <- CreateSeuratObject(counts = counts, min.cells = 1)
      status("Calculating percent.mt...")
      seuratObj[["percent.mt"]] <- PercentageFeatureSet(
        seuratObj,
        pattern = "^(MT-|mt-)"
      )
      seuratObj[["percent.rp"]] <- PercentageFeatureSet(
        seuratObj,
        pattern = "^(RPL|RPS|Rpl|Rps)"
      )
      seuratObj <- standard_process_seurat(
        seuratObj,
        hvg_method = hvg_method,
        ndims = nDims,
        res = resolution,
        backend_root = backend_root
      )
    }
  } else {
    status("Input format not supported, please reload the page...")
    stop("Input format not supported", call. = FALSE)
  }

  finalize_analysis_object(seuratObj)
}

#' Explore Mode input loading helper
#'
#' @noRd
find_explore_manifest_candidate_root <- function(path) {
  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    return(NULL)
  }

  if (file.exists(path) && identical(basename(path), "manifest.json")) {
    manifest_paths <- path
  } else if (dir.exists(path)) {
    manifest_paths <- list.files(
      path,
      pattern = "^manifest\\.json$",
      recursive = TRUE,
      full.names = TRUE
    )
  } else {
    return(NULL)
  }

  if (!length(manifest_paths)) {
    return(NULL)
  }
  if (length(manifest_paths) != 1L) {
    stop(
      "Explore archive contains multiple manifest.json files: ",
      paste(manifest_paths, collapse = ", "),
      call. = FALSE
    )
  }

  normalizePath(dirname(manifest_paths[[1]]), winslash = "/", mustWork = TRUE)
}

#' @noRd
load_explore_input_file <- function(
  input_file,
  input_name = basename(input_file),
  temp_root = scspotlight_temp_root(),
  status = function(...) NULL,
  notify = function(...) NULL,
  diagnostic = function(message) base::message(message),
  session = NULL
) {
  unsupported_file_message <- paste(
    "Explore Mode only supports files ending in .explore-parquet.zip.",
    "Choose a scSpotlight Explore Parquet archive."
  )
  unsupported_archive_message <- paste(
    "This Explore archive uses an unsupported bundle type.",
    "Create it with a supported version of scSpotlight and try again."
  )
  invalid_archive_message <- paste(
    "The Explore archive could not be opened. It may be incomplete or damaged.",
    "Create a new scSpotlight Explore Parquet bundle and try again."
  )
  warning_message <- paste(
    "The Explore archive loaded with warnings.",
    "If data appears incomplete, create a new bundle or contact the server administrator."
  )
  show_public_error <- function(message) {
    status(message)
    notify(message, type = "error", duration = 8)
    invisible(NULL)
  }
  input_path <- if (
    is.character(input_file) && length(input_file) == 1L && nzchar(input_file)
  ) {
    input_file
  } else {
    "<invalid input path>"
  }
  extraction_root <- NULL
  retain_extraction <- FALSE
  on.exit(
    {
      if (
        !retain_extraction &&
          is.character(extraction_root) &&
          length(extraction_root) == 1L &&
          nzchar(extraction_root) &&
          dir.exists(extraction_root)
      ) {
        try(
          unlink(extraction_root, recursive = TRUE, force = TRUE),
          silent = TRUE
        )
        if (dir.exists(extraction_root)) {
          try(
            diagnostic(paste0(
              "Explore bundle cleanup failed for '",
              input_path,
              "': ",
              extraction_root
            )),
            silent = TRUE
          )
        }
      }
    },
    add = TRUE
  )

  if (
    !is.character(input_name) ||
      length(input_name) != 1L ||
      !grepl(scspotlight_explore_archive_pattern, input_name)
  ) {
    show_public_error(unsupported_file_message)
    return(NULL)
  }

  warnings <- character()
  failure_kind <- "invalid_archive"
  result <- tryCatch(
    withCallingHandlers(
      {
        status("Decompressing Explore bundle...")
        extracted <- decompress_matrix_input(
          input_name,
          input_file,
          temp_root = temp_root,
          return_extraction_details = TRUE,
          timing = function(
            phase,
            state,
            elapsed_ms = NULL,
            details = list()
          ) {
            scspotlight_benchmark_timing_event(
              session,
              phase = phase,
              state = state,
              elapsed_ms = elapsed_ms,
              details = details
            )
          }
        )
        extraction_root <- extracted$extraction_root
        bundle_root <- scspotlight_benchmark_timing_measure(
          session,
          phase = "server_bundle_locate",
          find_scspotlight_explore_bundle_root(extracted$data_dir)
        )
        if (!isTruthy(bundle_root) && !length(extracted$data_dir)) {
          bundle_root <- find_explore_manifest_candidate_root(
            extracted$extraction_root
          )
        }
        if (!isTruthy(bundle_root)) {
          stop(
            "Explore bundle manifest not found after extraction: ",
            extracted$extraction_root,
            call. = FALSE
          )
        }
        manifest <- read_scspotlight_explore_manifest(bundle_root)
        if (!is.list(manifest)) {
          stop(
            "Explore bundle manifest is missing or invalid: ",
            bundle_root,
            call. = FALSE
          )
        }
        bundle_type <- manifest$bundle_type
        explicit_bundle_type <- is.character(bundle_type) &&
          length(bundle_type) == 1L &&
          !is.na(bundle_type) &&
          nzchar(bundle_type) &&
          identical(bundle_type, trimws(bundle_type))
        if (
          explicit_bundle_type &&
            !identical(bundle_type, scspotlight_explore_bundle_type)
        ) {
          failure_kind <- "unsupported_archive"
          stop(
            "Unsupported Explore bundle type: ",
            bundle_type,
            call. = FALSE
          )
        }
        if (!identical(bundle_type, scspotlight_explore_bundle_type)) {
          stop(
            "Explore bundle manifest has a missing or malformed bundle_type: ",
            file.path(bundle_root, "manifest.json"),
            call. = FALSE
          )
        }

        status("Reading Explore bundle...")
        bundle <- scspotlight_benchmark_timing_measure(
          session,
          phase = "server_bundle_open_and_validate",
          read_scspotlight_explore_bundle(bundle_root)
        )
        list(
          object = bundle,
          assays = get_backend_assays(bundle),
          default_assay = get_backend_default_assay(bundle)
        )
      },
      warning = function(warning) {
        warning_text <- conditionMessage(warning)
        if (!warning_text %in% warnings) {
          warnings <<- c(warnings, warning_text)
          try(
            diagnostic(paste0(
              "Explore bundle load warning for '",
              input_path,
              "': ",
              warning_text
            )),
            silent = TRUE
          )
        }
        invokeRestart("muffleWarning")
      }
    ),
    error = function(error) {
      diagnostic_message <- paste0(
        "Explore bundle load failed for '",
        input_path,
        "' [",
        paste(class(error), collapse = "/"),
        "]: ",
        conditionMessage(error)
      )
      try(diagnostic(diagnostic_message), silent = TRUE)
      show_public_error(
        if (identical(failure_kind, "unsupported_archive")) {
          unsupported_archive_message
        } else {
          invalid_archive_message
        }
      )
      NULL
    }
  )

  if (!is.null(result) && length(warnings)) {
    notify(warning_message, type = "warning", duration = 12)
  }
  if (!is.null(result)) {
    retain_extraction <- TRUE
  }

  result
}

#' dataInput Server Functions
#'
#' @import Seurat
#' @import shiny
#' @importFrom readr read_tsv
#' @importFrom SeuratObject LoadSeuratRds Layers
#' @importFrom stringr str_detect
#'
#' @noRd
mod_dataInput_server <- function(
  id,
  obj,
  hvgSelectMethod,
  clusterDims,
  clusterResolution,
  geneUpdateIndicator,
  metaUpdateIndicator,
  reductionUpdateIndicator,
  analysisTransition = NULL,
  resetAnalysisUi = NULL,
  clearViewFilter = NULL
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    ## use golem_opts to parse dataDir arguments when invoking run_app()
    dataDir <- golem::get_golem_options("dataDir")
    runningMode <- normalize_running_mode(golem::get_golem_options(
      "runningMode"
    ))
    compressionFormatPattern <- "\\.zip$|\\.tar.gz$|\\.tgz$|\\.tar\\.bz2$|\\.tbz2"
    rdsFormatPattern <- "\\.rds$|\\.RDS$|\\.Rds$"
    h5adFormatPattern <- "\\.[Hh]5[Aa][Dd]$"
    supportedFileInputPattern <- if (identical(runningMode, "explore")) {
      scspotlight_explore_archive_pattern
    } else {
      paste0(
        rdsFormatPattern,
        "|",
        h5adFormatPattern,
        "|",
        compressionFormatPattern
      )
    }
    loadWarnings <- reactiveVal(character(0))

    capture_load_warnings <- function(expr) {
      result <- capture_operation_warnings(expr)
      if (length(result$warnings)) {
        loadWarnings(unique(c(loadWarnings(), result$warnings)))
      }
      result$value
    }

    show_load_warnings <- function(input_name) {
      show_captured_warnings(
        loadWarnings(),
        title = paste("Input loaded with warnings:", input_name),
        session = session
      )
      loadWarnings(character(0))
      invisible(NULL)
    }

    if (identical(runningMode, "analysis")) {
      assert_bpcells_available()
    }

    if (isTruthy(dataDir)) {
      if (!file.exists(dataDir)) {
        showNotification(
          ui = "dataDir parsed but does not exist",
          action = NULL,
          duration = NULL,
          closeButton = TRUE,
          type = "default",
          session = session
        )
      } else {
        if (
          !identical(runningMode, "explore") &&
            !is_scspotlight_explore_bundle_dir(dataDir)
        ) {
          ## set working directory to the dataDir
          ## to ensure BPCells matrix path is correct
          setwd(dataDir)
        }
        data_dir_choices <- list.files(
          path = dataDir,
          pattern = supportedFileInputPattern,
          recursive = TRUE
        )
        if (identical(runningMode, "analysis")) {
          data_dir_choices <- data_dir_choices[
            !str_detect(data_dir_choices, scspotlight_explore_archive_pattern)
          ]
        }
        updateSelectizeInput(
          session,
          inputId = "dataDirFile",
          choices = data_dir_choices,
          selected = ""
        )
      }
    }

    inputFilePath <- reactive({
      req(isTruthy(input$dataInput) || isTruthy(input$dataDirFile))
      if (isTruthy(input$dataDirFile)) {
        file.path(dataDir, input$dataDirFile)
      } else {
        input$dataInput$datapath
      }
    })

    inputFileName <- reactive({
      req(isTruthy(input$dataInput) || isTruthy(input$dataDirFile))
      if (isTruthy(input$dataDirFile)) {
        input$dataDirFile
      } else {
        input$dataInput$name
      }
    })

    observeEvent(
      list(
        inputFilePath(),
        inputFileName()
      ),
      {
        req(inputFilePath(), inputFileName())
        message("inputFilePath() is ", isolate(inputFilePath()))
        loadWarnings(character(0))
        scspotlight_benchmark_timing_event(
          session,
          phase = "server_dataset_load",
          state = "start",
          details = list(
            inputKind = if (isTruthy(input$dataDirFile)) {
              "server_data_dir"
            } else {
              "browser_upload"
            },
            inputName = basename(inputFileName())
          )
        )
        ##req(isTruthy(input$dataInput) || isTruthy(input$dataDirFile))
        waiter_show(html = waiting_screen(), color = "var(--bs-primary)")
        ## Init seuratObj
        seuratObj <- NULL
        backendAssays <- NULL
        backendDefaultAssay <- NULL
        update_load_status <- function(message) {
          waiter_update(html = waiting_screen(message))
        }
        notify_load <- function(ui, type = "default", duration = NULL) {
          showNotification(
            ui = ui,
            action = NULL,
            duration = duration,
            closeButton = TRUE,
            type = type,
            session = session
          )
        }
        if (identical(runningMode, "explore")) {
          exploreLoad <- load_explore_input_file(
            input_file = inputFilePath(),
            input_name = inputFileName(),
            temp_root = session$userData$tempDir,
            status = update_load_status,
            notify = notify_load,
            session = session
          )
          if (!isTruthy(exploreLoad)) {
            loadWarnings(character(0))
            waiter::waiter_hide()
            return(invisible(NULL))
          }
          seuratObj <- exploreLoad$object
          backendAssays <- exploreLoad$assays
          backendDefaultAssay <- exploreLoad$default_assay
        } else {
          seuratObj <- capture_load_warnings(
            load_analysis_input_file(
              input_file = inputFilePath(),
              input_name = inputFileName(),
              backend_root = file.path(session$userData$backendDir, "layers"),
              hvgSelectMethod = hvgSelectMethod(),
              nDims = clusterDims(),
              resolution = clusterResolution(),
              temp_root = session$userData$backendDir,
              status = update_load_status,
              notify = notify_load
            )
          )
        }

        ## update assay list
        if (isTruthy(seuratObj)) {
          assert_no_dense_scale_data(seuratObj)
          reset_applied <- if (!is.null(analysisTransition)) {
            analysisTransition$reset(seuratObj)
          } else {
            obj(seuratObj)
            TRUE
          }
          if (!isTRUE(reset_applied)) {
            waiter::waiter_hide()
            showNotification(
              ui = "Dataset load could not be applied while an Analysis change is in progress.",
              action = NULL,
              duration = 6,
              closeButton = TRUE,
              type = "error",
              session = session
            )
            return(invisible(NULL))
          }
          if (identical(runningMode, "analysis")) {
            backendAssays <- get_backend_assays(seuratObj)
            backendDefaultAssay <- get_backend_default_assay(seuratObj)
          }
          updateSelectizeInput(
            session = session,
            inputId = "selectAssay",
            choices = ifelse(isTruthy(seuratObj), backendAssays, ""),
            selected = ifelse(isTruthy(seuratObj), backendDefaultAssay, NULL)
          )
          if (is.function(resetAnalysisUi)) {
            resetAnalysisUi()
          }
          if (is.function(clearViewFilter)) {
            clearViewFilter()
          }
          session$sendCustomMessage(
            type = "clear_expr",
            # Invalidate queued expression work from the prior Analysis epoch.
            message = make_clear_expr_payload(geneUpdateIndicator())
          )
          if (identical(runningMode, "analysis")) {
            show_load_warnings(inputFileName())
          }
        }

        scspotlight_benchmark_timing_event(
          session,
          phase = "server_dataset_load",
          state = "end"
        )

        # Arm the browser-side initial-render handshake before transfer observers
        # can send IPC payloads for a fast local dataset.
        session$sendCustomMessage(
          type = "await_initial_plot_ready",
          message = list()
        )
        ## Update indicators
        metaUpdateIndicator(metaUpdateIndicator() + 1)
        reductionUpdateIndicator(reductionUpdateIndicator() + 1)
        geneUpdateIndicator(geneUpdateIndicator() + 1)
      },
      priority = 10
    )

    observeEvent(input$selectAssay, {
      ## Data of different assays were stored in the same metadata
      ## reductions were "independent" with assay switch
      geneUpdateIndicator(geneUpdateIndicator() + 1)
    })

    selectedAssay <- reactive({
      input$selectAssay
    })

    return(list(
      selectedAssay = selectedAssay
    ))
  })
}

#' BPCells_Read10X
#'
#' @description A modified version of the Seurat Read10X function using BPCells to read matrix
#'
#' @import Seurat
#'
#' @noRd
#'
BPCells_Read10X <- function(
  data.dir,
  gene.column = 2,
  cell.column = 1,
  unique.features = TRUE,
  strip.suffix = FALSE,
  temp_root = scspotlight_temp_root()
) {
  full.data <- list()
  has_dt <- requireNamespace("data.table", quietly = TRUE) &&
    requireNamespace("R.utils", quietly = TRUE)
  dir.create(temp_root, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_along(along.with = data.dir)) {
    run <- data.dir[i]
    if (!dir.exists(paths = run)) {
      stop("Directory provided does not exist")
    }
    barcode.loc <- file.path(run, 'barcodes.tsv')
    gene.loc <- file.path(run, 'genes.tsv')
    features.loc <- file.path(run, 'features.tsv.gz')
    matrix.loc <- file.path(run, 'matrix.mtx')
    # Flag to indicate if this data is from CellRanger >= 3.0
    pre_ver_3 <- file.exists(gene.loc)
    if (!pre_ver_3) {
      addgz <- function(s) {
        return(paste0(s, ".gz"))
      }
      barcode.loc <- addgz(s = barcode.loc)
      matrix.loc <- addgz(s = matrix.loc)
    }
    if (!file.exists(barcode.loc)) {
      stop("Barcode file missing. Expecting ", basename(path = barcode.loc))
    }
    if (!pre_ver_3 && !file.exists(features.loc)) {
      stop(
        "Gene name or features file missing. Expecting ",
        basename(path = features.loc)
      )
    }
    if (!file.exists(matrix.loc)) {
      stop(
        "Expression matrix file missing. Expecting ",
        basename(path = matrix.loc)
      )
    }
    message("Importing with BPCells...")
    data <- BPCells::import_matrix_market(
      mtx_path = matrix.loc,
      outdir = tempfile(pattern = "matrix_market_", tmpdir = temp_root),
      row_names = NULL,
      col_names = NULL,
      row_major = FALSE,
      tmpdir = temp_root,
      load_bytes = 4194304L,
      sort_bytes = 1073741824L
    )
    if (has_dt) {
      cell.barcodes <- as.data.frame(data.table::fread(
        barcode.loc,
        header = FALSE
      ))
    } else {
      cell.barcodes <- read.table(
        file = barcode.loc,
        header = FALSE,
        sep = '\t',
        row.names = NULL
      )
    }

    if (ncol(x = cell.barcodes) > 1) {
      cell.names <- cell.barcodes[, cell.column]
    } else {
      cell.names <- readLines(con = barcode.loc)
    }
    if (all(grepl(pattern = "\\-1$", x = cell.names)) & strip.suffix) {
      cell.names <- as.vector(
        x = as.character(
          x = sapply(
            X = cell.names,
            FUN = ExtractField,
            field = 1,
            delim = "-"
          )
        )
      )
    }
    if (is.null(x = names(x = data.dir))) {
      if (length(x = data.dir) < 2) {
        colnames(x = data) <- cell.names
      } else {
        colnames(x = data) <- paste0(i, "_", cell.names)
      }
    } else {
      colnames(x = data) <- paste0(names(x = data.dir)[i], "_", cell.names)
    }

    if (has_dt) {
      feature.names <- as.data.frame(data.table::fread(
        ifelse(test = pre_ver_3, yes = gene.loc, no = features.loc),
        header = FALSE
      ))
    } else {
      feature.names <- read.delim(
        file = ifelse(test = pre_ver_3, yes = gene.loc, no = features.loc),
        header = FALSE,
        stringsAsFactors = FALSE
      )
    }

    if (any(is.na(x = feature.names[, gene.column]))) {
      warning(
        'Some features names are NA. Replacing NA names with ID from the opposite column requested',
        call. = FALSE,
        immediate. = TRUE
      )
      na.features <- which(x = is.na(x = feature.names[, gene.column]))
      replacement.column <- ifelse(test = gene.column == 2, yes = 1, no = 2)
      feature.names[na.features, gene.column] <- feature.names[
        na.features,
        replacement.column
      ]
    }
    if (unique.features) {
      fcols = ncol(x = feature.names)
      if (fcols < gene.column) {
        stop(paste0(
          "gene.column was set to ",
          gene.column,
          " but feature.tsv.gz (or genes.tsv) only has ",
          fcols,
          " columns.",
          " Try setting the gene.column argument to a value <= to ",
          fcols,
          "."
        ))
      }
      rownames(x = data) <- make.unique(names = feature.names[, gene.column])
    }
    message("Finished generating matrix")
    dirPath <- tempfile(pattern = "counts_", tmpdir = temp_root)
    data <- optimize_bpcells_matrix_type(data, layer = "counts")
    BPCells::write_matrix_dir(data, dir = dirPath, overwrite = TRUE)
    mat <- BPCells::open_matrix_dir(dirPath)
    # In cell ranger 3.0, a third column specifying the type of data was added
    # and we will return each type of data as a separate matrix
    ##if (ncol(x = feature.names) > 2) {
    ##  data_types <- factor(x = feature.names$V3)
    ##  lvls <- levels(x = data_types)
    ##  if (length(x = lvls) > 1 && length(x = full.data) == 0) {
    ##    message("10X data contains more than one type and is being returned as a list containing matrices of each type.")
    ##  }
    ##  expr_name <- "Gene Expression"
    ##  if (expr_name %in% lvls) { # Return Gene Expression first
    ##    lvls <- c(expr_name, lvls[-which(x = lvls == expr_name)])
    ##  }
    ##  data <- lapply(
    ##    X = lvls,
    ##    FUN = function(l) {
    ##      return(data[data_types == l, , drop = FALSE])
    ##    }
    ##  )
    ##  names(x = data) <- lvls
    ##} else{
    ##  data <- list(data)
    ##}
    ##full.data[[length(x = full.data) + 1]] <- data
    full.data[[length(x = full.data) + 1]] <- mat
  }
  return(full.data)
  # Combine all the data from different directories into one big matrix, note this
  # assumes that all data directories essentially have the same features files
  ##list_of_data <- list()
  ##for (j in 1:length(x = full.data[[1]])) {
  ##  list_of_data[[j]] <- do.call(cbind, lapply(X = full.data, FUN = `[[`, j))
  ##  # Fix for Issue #913
  ##  list_of_data[[j]] <- as.sparse(x = list_of_data[[j]])
  ##}
  ##names(x = list_of_data) <- names(x = full.data[[1]])
  ### If multiple features, will return a list, otherwise
  ### a matrix.
  ##if (length(x = list_of_data) == 1) {
  ##  return(list_of_data[[1]])
  ##} else {
  ##  return(list_of_data)
  ##}
}

#' dataNormalized
#'
#' Check if seurat object is normalized
#'
#' @noRd
dataNormalized <- function(seuratObj) {
  ##!identical(seuratObj[["RNA"]]$counts, seuratObj[["RNA"]]$data)
  m <- SeuratObject::LayerData(
    seuratObj,
    assay = SeuratObject::DefaultAssay(seuratObj),
    layer = "data"
  )
  any(dim(m) > 0)
}

#' @noRd
analysis_waiter_update <- function(message) {
  tryCatch(
    waiter_update(html = waiting_screen(message)),
    error = function(...) invisible(NULL)
  )
}

#' HVG_exist
#'
#' Check if seurat object has HVGs stored
#'
#' @noRd
HVG_exist <- function(seuratObj) {
  length(VariableFeatures(seuratObj)) > 0
}

#' reduction_exist
#'
#' Check if seurat object has reductions
#'
#' @noRd
reduction_exist <- function(seuratObj) {
  length(Reductions(seuratObj)) > 0
}

#' validate_seuratRDS
#'
#' @importFrom SeuratObject Layers
#'
#' @noRd
validate_seuratRDS <- function(
  seuratObj,
  runningMode = "explore",
  hvgSelectMethod = "vst",
  nDims = 30,
  resolution = 1,
  backend_root = NULL
) {
  runningMode <- normalize_running_mode(runningMode)
  message("calculating mt")
  if (
    "counts" %in%
      Layers(seuratObj) &&
      !("percent.mt" %in% colnames(seuratObj[[]]))
  ) {
    seuratObj[["percent.mt"]] <- PercentageFeatureSet(
      seuratObj,
      pattern = "^(MT-|mt-)"
    )
  }
  message("calculating rp")
  if (
    "counts" %in%
      Layers(seuratObj) &&
      !("percent.rp" %in% colnames(seuratObj[[]]))
  ) {
    seuratObj[["percent.rp"]] <- PercentageFeatureSet(
      seuratObj,
      pattern = "^(RPL|RPS|Rpl|Rps)"
    )
  }

  seuratObj <- ensure_normalized_layer(
    seuratObj,
    backend_root = backend_root,
    input_label = "Input object"
  )

  if (identical(runningMode, "analysis")) {
    if (!HVG_exist(seuratObj)) {
      analysis_waiter_update("Finding HVGs...")
      seuratObj <- set_variable_features_backend(
        seuratObj,
        selection.method = hvgSelectMethod
      )
    }
    if (!reduction_exist(seuratObj)) {
      analysis_waiter_update("Calculating Reductions...")
      seuratObj <- run_memory_conserving_pca(
        seuratObj,
        npcs = max(nDims, 30L)
      )
      seuratObj <- Seurat::FindNeighbors(
        seuratObj,
        dims = 1:nDims,
        reduction = "pca"
      )
      seuratObj <- Seurat::FindClusters(seuratObj, resolution = resolution)
      seuratObj <- Seurat::RunUMAP(seuratObj, dims = 1:nDims, reduction = "pca")
    }
    seuratObj <- drop_dense_scale_data(seuratObj)
    assert_no_dense_scale_data(seuratObj)
    if (isTruthy(backend_root)) {
      seuratObj <- ensure_bpcells_backing(
        seuratObj,
        root_dir = backend_root,
        layers = NULL
      )
    }
    assert_no_dense_scale_data(seuratObj)
  }

  assert_processed_input_requirements(seuratObj, input_label = "Input object")
  message("Finished validating object requirements...")
  return(seuratObj)
}


#' decompress_matrix_input
#'
#' Function for reading compressed matrix
#'
#' @noRd
archive_entry_is_unsafe <- function(entry) {
  if (is.null(entry) || length(entry) == 0L) {
    return(TRUE)
  }

  entry <- as.character(entry)[[1]]
  if (!nzchar(entry)) {
    return(TRUE)
  }

  entry <- gsub("\\\\", "/", entry)

  # Reject absolute Unix paths, Windows drive paths, and UNC shares before
  # extraction so archive entries can only create files below the temp root.
  if (grepl("^(/|[A-Za-z]:)", entry)) {
    return(TRUE)
  }
  if (grepl("^//", entry)) {
    return(TRUE)
  }

  # Reject any parent-directory traversal segment.
  if (grepl("(^|/)\\.\\.(?=/|$)", entry, perl = TRUE)) {
    return(TRUE)
  }

  FALSE
}

scspotlight_archive_limits <- function() {
  read_limit <- function(option, default) {
    value <- suppressWarnings(as.numeric(getOption(option, default))[[1]])
    if (!is.finite(value) || value <= 0) {
      stop("Archive safety limits must be positive finite numbers.", call. = FALSE)
    }
    value
  }

  list(
    max_entries = read_limit("scSpotlight.archive.max_entries", 100000),
    max_expanded_bytes = read_limit(
      "scSpotlight.archive.max_expanded_bytes",
      100 * 1024^3
    ),
    max_compression_ratio = read_limit(
      "scSpotlight.archive.max_compression_ratio",
      1000
    )
  )
}

tar_raw_string <- function(block, start, length) {
  bytes <- block[seq.int(start, length.out = length)]
  nul <- which(bytes == as.raw(0))
  if (length(nul) > 0L) {
    bytes <- bytes[seq_len(nul[[1]] - 1L)]
  }
  if (length(bytes) == 0L) {
    return("")
  }
  rawToChar(bytes)
}

tar_octal_number <- function(block, start, length) {
  bytes <- as.integer(block[seq.int(start, length.out = length)])
  if (base::length(bytes) != length) {
    stop("Compressed tar archive is incomplete.", call. = FALSE)
  }
  if (length(bytes) > 0L && bitwAnd(bytes[[1]], 128L) != 0L) {
    # GNU tar uses base-256 fields for values that do not fit octal metadata.
    # Negative values are not valid archive member sizes.
    if (bitwAnd(bytes[[1]], 64L) != 0L) {
      stop("Compressed tar archive contains invalid size metadata.", call. = FALSE)
    }
    value <- bytes[[1]] - 128L
    if (length(bytes) > 1L) {
      for (byte in bytes[-1L]) {
        value <- value * 256 + byte
      }
    }
    if (!is.finite(value) || value < 0) {
      stop("Compressed tar archive contains invalid size metadata.", call. = FALSE)
    }
    return(value)
  }

  text <- trimws(tar_raw_string(block, start, length))
  if (!nzchar(text)) {
    return(0)
  }
  if (!grepl("^[0-7]+$", text)) {
    stop("Compressed tar archive contains invalid size metadata.", call. = FALSE)
  }
  digits <- utf8ToInt(text) - utf8ToInt("0")
  Reduce(function(total, digit) total * 8 + digit, digits, init = 0)
}

tar_field_uses_base256 <- function(block, start, length) {
  bytes <- as.integer(block[seq.int(start, length.out = length)])
  length(bytes) == length &&
    length(bytes) > 0L &&
    bitwAnd(bytes[[1]], 128L) != 0L
}

tar_header_uses_base256_numeric <- function(block) {
  numeric_fields <- list(
    c(101L, 8L),
    c(109L, 8L),
    c(117L, 8L),
    c(125L, 12L),
    c(137L, 12L),
    c(149L, 8L),
    c(330L, 8L),
    c(338L, 8L)
  )
  any(vapply(
    numeric_fields,
    function(field) tar_field_uses_base256(block, field[[1]], field[[2]]),
    logical(1)
  ))
}

validated_tar_extractor <- function() {
  tar_bin <- Sys.which("tar")
  if (!nzchar(tar_bin) && identical(.Platform$OS.type, "windows")) {
    tar_bin <- Sys.which("tar.exe")
  }
  tar_bin
}

extract_validated_tar_archive <- function(
  file_path,
  exdir,
  uses_base256_numeric = FALSE
) {
  if (!isTRUE(uses_base256_numeric)) {
    untar(file_path, exdir = exdir, tar = "internal")
    return(invisible(NULL))
  }

  tar_bin <- validated_tar_extractor()
  if (!nzchar(tar_bin)) {
    stop(
      "Compressed tar archive uses a numeric format unsupported by this system.",
      call. = FALSE
    )
  }

  # utils::untar() appends extras after the archive operand, which GNU tar
  # interprets as additional archives. Run the compatible extractor directly.
  status <- suppressWarnings(system2(
    tar_bin,
    c(
      "--no-same-owner",
      "--no-same-permissions",
      "--extract",
      paste0("--file=", shQuote(file_path)),
      "-C",
      shQuote(exdir)
    )
  ))
  if (length(status) != 1L || !is.finite(status[[1]]) || status[[1]] != 0L) {
    stop("Compressed tar archive could not be extracted.", call. = FALSE)
  }

  invisible(NULL)
}

read_tar_payload <- function(connection, size, capture = FALSE) {
  padded_size <- ceiling(size / 512) * 512
  if (padded_size == 0) {
    return(raw())
  }
  if (isTRUE(capture) && size > 1024^2) {
    stop("Compressed tar archive contains unsafe metadata.", call. = FALSE)
  }

  remaining <- padded_size
  captured <- raw()
  while (remaining > 0) {
    chunk <- readBin(connection, "raw", n = min(remaining, 1024^2))
    if (length(chunk) == 0L) {
      stop("Compressed tar archive is incomplete.", call. = FALSE)
    }
    if (isTRUE(capture)) {
      captured <- c(captured, chunk)
    }
    remaining <- remaining - length(chunk)
  }

  if (isTRUE(capture)) {
    captured[seq_len(size)]
  } else {
    raw()
  }
}

tar_payload_string <- function(payload) {
  if (length(payload) == 0L) {
    return("")
  }
  nul <- which(payload == as.raw(0))
  if (length(nul) > 0L) {
    payload <- payload[seq_len(nul[[1]] - 1L)]
  }
  sub("\n$", "", rawToChar(payload))
}

parse_pax_tar_metadata <- function(payload) {
  records <- strsplit(rawToChar(payload), "\n", fixed = TRUE)[[1]]
  records <- records[nzchar(records)]
  metadata <- list()

  for (record in records) {
    matched <- regexec("^([0-9]+) ([^=]+)=(.*)$", record, perl = TRUE)
    fields <- regmatches(record, matched)[[1]]
    if (length(fields) != 4L) {
      stop("Compressed tar archive contains unsafe metadata.", call. = FALSE)
    }

    record_size <- suppressWarnings(as.numeric(fields[[2]]))
    if (
      !is.finite(record_size) ||
        record_size != nchar(record, type = "bytes") + 1L
    ) {
      stop("Compressed tar archive contains unsafe metadata.", call. = FALSE)
    }

    key <- fields[[3]]
    if (startsWith(key, "GNU.sparse.")) {
      stop("Compressed tar archive contains unsafe metadata.", call. = FALSE)
    }
    if (key %in% c("path", "size") && !is.null(metadata[[key]])) {
      stop("Compressed tar archive contains unsafe metadata.", call. = FALSE)
    }
    if (identical(key, "size") && !grepl("^[0-9]+$", fields[[4]])) {
      stop("Compressed tar archive contains invalid size metadata.", call. = FALSE)
    }
    metadata[[key]] <- fields[[4]]
  }

  metadata
}

list_tar_archive_entries <- function(filePath) {
  limits <- scspotlight_archive_limits()
  archive_size <- file.info(filePath)$size[[1]]
  connection <- gzfile(filePath, open = "rb")
  on.exit(close(connection), add = TRUE)

  max_entries <- suppressWarnings(as.integer(min(
    floor(limits$max_entries),
    .Machine$integer.max
  )))
  if (is.na(max_entries) || max_entries < 1L) {
    stop("Compressed archive contains too many entries.", call. = FALSE)
  }
  entry_capacity <- min(max_entries, 1024L)
  entries <- character(entry_capacity)
  types <- character(entry_capacity)
  uncompressed_sizes <- numeric(entry_capacity)
  entry_count <- 0L
  member_count <- 0L
  preflight_expanded_size <- 0
  uses_base256_numeric <- FALSE
  has_global_pax_metadata <- FALSE
  pending_name <- NULL
  pending_size <- NULL

  add_preflight_bytes <- function(size) {
    if (!is.finite(size) || size < 0) {
      stop("Compressed tar archive contains invalid size metadata.", call. = FALSE)
    }
    preflight_expanded_size <<- preflight_expanded_size + size
    if (preflight_expanded_size > limits$max_expanded_bytes) {
      stop("Compressed archive exceeds the expanded-size limit.", call. = FALSE)
    }
    if (
      is.finite(archive_size) &&
        preflight_expanded_size / max(archive_size, 1) >
          limits$max_compression_ratio
    ) {
      stop("Compressed archive exceeds the compression-ratio limit.", call. = FALSE)
    }
  }

  count_tar_member <- function() {
    member_count <<- member_count + 1L
    if (member_count > max_entries) {
      stop("Compressed archive contains too many entries.", call. = FALSE)
    }
  }

  append_entry <- function(name, type, size) {
    entry_count <<- entry_count + 1L
    if (entry_count > max_entries) {
      stop("Compressed archive contains too many entries.", call. = FALSE)
    }
    if (entry_count > length(entries)) {
      next_capacity <- min(max_entries, max(length(entries) * 2L, 1024L))
      length(entries) <<- next_capacity
      length(types) <<- next_capacity
      length(uncompressed_sizes) <<- next_capacity
    }
    entries[[entry_count]] <<- name
    types[[entry_count]] <<- type
    uncompressed_sizes[[entry_count]] <<- size
  }

  repeat {
    block <- readBin(connection, "raw", n = 512L)
    if (length(block) == 0L || all(block == as.raw(0))) {
      break
    }
    if (length(block) < 512L) {
      stop("Compressed tar archive is incomplete.", call. = FALSE)
    }

    # PAX/GNU control records still consume parser work, so they count against
    # the archive member limit even though they are not extracted as files.
    count_tar_member()

    uses_base256_numeric <- uses_base256_numeric ||
      tar_header_uses_base256_numeric(block)

    name <- tar_raw_string(block, 1L, 100L)
    if (identical(tar_raw_string(block, 258L, 5L), "ustar")) {
      prefix <- tar_raw_string(block, 346L, 155L)
      if (nzchar(prefix)) {
        name <- file.path(prefix, name)
      }
    }
    size <- tar_octal_number(block, 125L, 12L)
    type_byte <- as.integer(block[[157L]])
    type_flag <- if (type_byte == 0L) "0" else rawToChar(block[[157L]])

    if (type_flag %in% c("L", "K")) {
      add_preflight_bytes(size)
      payload <- read_tar_payload(connection, size, capture = TRUE)
      if (identical(type_flag, "L")) {
        pending_name <- tar_payload_string(payload)
      }
      next
    }
    if (identical(type_flag, "x")) {
      add_preflight_bytes(size)
      metadata <- parse_pax_tar_metadata(
        read_tar_payload(connection, size, capture = TRUE)
      )
      pending_name <- metadata$path %||% pending_name
      pending_size <- if (!is.null(metadata$size)) {
        suppressWarnings(as.numeric(metadata$size))
      } else {
        pending_size
      }
      next
    }
    if (identical(type_flag, "g")) {
      add_preflight_bytes(size)
      parse_pax_tar_metadata(read_tar_payload(connection, size, capture = TRUE))
      has_global_pax_metadata <- TRUE
      next
    }

    name <- pending_name %||% name
    size <- pending_size %||% size
    pending_name <- NULL
    pending_size <- NULL
    if (!is.finite(size) || size < 0) {
      stop("Compressed tar archive contains invalid size metadata.", call. = FALSE)
    }

    type <- if (type_flag %in% c("0", "7")) {
      "file"
    } else if (identical(type_flag, "5")) {
      "directory"
    } else {
      switch(
        type_flag,
        `1` = "hardlink",
        `2` = "symlink",
        `3` = "character_device",
        `4` = "block_device",
        `6` = "fifo",
        "special"
      )
    }
    if (!type %in% c("file", "directory") || archive_entry_is_unsafe(name)) {
      stop("Compressed archive contains unsafe entries.", call. = FALSE)
    }
    # R's internal tar extractor ignores directory payload sizes. Rejecting them
    # keeps the preflight reader aligned with the extractor's header traversal.
    if (identical(type, "directory") && size != 0) {
      stop("Compressed archive contains unsafe entries.", call. = FALSE)
    }

    append_entry(name, type, size)
    add_preflight_bytes(size)
    read_tar_payload(connection, size)
  }

  if (uses_base256_numeric && has_global_pax_metadata) {
    stop("Compressed archive contains unsafe entries.", call. = FALSE)
  }

  list(
    entries = entries[seq_len(entry_count)],
    types = types[seq_len(entry_count)],
    uncompressed_sizes = uncompressed_sizes[seq_len(entry_count)],
    compressed_size = archive_size,
    preflight_expanded_size = preflight_expanded_size,
    uses_base256_numeric = uses_base256_numeric
  )
}

list_zip_archive_entries <- function(filePath) {
  zip_entries <- zip::zip_list(filePath)
  entry_names <- if ("filename" %in% names(zip_entries)) {
    zip_entries$filename
  } else if ("Name" %in% names(zip_entries)) {
    zip_entries$Name
  } else {
    character()
  }

  entry_types <- if ("type" %in% names(zip_entries)) {
    tolower(as.character(zip_entries$type))
  } else {
    rep("file", length(entry_names))
  }
  uncompressed_sizes <- if ("uncompressed_size" %in% names(zip_entries)) {
    as.numeric(zip_entries$uncompressed_size)
  } else {
    rep(NA_real_, length(entry_names))
  }
  compressed_sizes <- if ("compressed_size" %in% names(zip_entries)) {
    as.numeric(zip_entries$compressed_size)
  } else {
    rep(NA_real_, length(entry_names))
  }

  list(
    entries = entry_names,
    types = entry_types,
    uncompressed_sizes = uncompressed_sizes,
    compressed_sizes = compressed_sizes,
    compressed_size = file.info(filePath)$size[[1]]
  )
}

assert_safe_archive_entries <- function(
  archive_entries,
  archive_type = c("tar", "zip")
) {
  archive_type <- match.arg(archive_type)
  limits <- scspotlight_archive_limits()

  entries <- if (
    is.list(archive_entries) && !is.null(archive_entries$entries)
  ) {
    archive_entries$entries
  } else {
    archive_entries
  }

  entries <- as.character(entries)
  if (length(entries) == 0L) {
    stop("Compressed archive contains no extractable entries.", call. = FALSE)
  }

  if (length(entries) > limits$max_entries) {
    stop("Compressed archive contains too many entries.", call. = FALSE)
  }

  if (any(vapply(entries, archive_entry_is_unsafe, logical(1)))) {
    stop("Compressed archive contains unsafe entries.", call. = FALSE)
  }

  types <- if (is.list(archive_entries) && !is.null(archive_entries$types)) {
    tolower(as.character(archive_entries$types))
  } else {
    rep("file", length(entries))
  }
  if (
    length(types) != length(entries) ||
      any(!types %in% c("file", "regular", "directory", "dir"))
  ) {
    stop("Compressed archive contains unsafe entries.", call. = FALSE)
  }

  expanded_sizes <- if (
    is.list(archive_entries) && !is.null(archive_entries$uncompressed_sizes)
  ) {
    suppressWarnings(as.numeric(archive_entries$uncompressed_sizes))
  } else {
    rep(0, length(entries))
  }
  if (
    length(expanded_sizes) != length(entries) ||
      any(!is.finite(expanded_sizes)) ||
      any(expanded_sizes < 0)
  ) {
    stop("Compressed archive contains invalid size metadata.", call. = FALSE)
  }
  expanded_size <- sum(expanded_sizes)
  if (expanded_size > limits$max_expanded_bytes) {
    stop("Compressed archive exceeds the expanded-size limit.", call. = FALSE)
  }

  compressed_size <- if (
    is.list(archive_entries) && !is.null(archive_entries$compressed_sizes)
  ) {
    sum(suppressWarnings(as.numeric(archive_entries$compressed_sizes)))
  } else if (
    is.list(archive_entries) && !is.null(archive_entries$compressed_size)
  ) {
    suppressWarnings(as.numeric(archive_entries$compressed_size)[[1]])
  } else {
    NA_real_
  }
  if (is.finite(compressed_size) && expanded_size > 0) {
    ratio <- expanded_size / max(compressed_size, 1)
    if (ratio > limits$max_compression_ratio) {
      stop("Compressed archive exceeds the compression-ratio limit.", call. = FALSE)
    }
  }

  invisible(entries)
}

assert_safe_extracted_archive <- function(root, compressed_size) {
  limits <- scspotlight_archive_limits()
  paths <- list.files(
    root,
    recursive = TRUE,
    full.names = TRUE,
    all.files = TRUE,
    include.dirs = TRUE,
    no.. = TRUE
  )
  if (length(paths) > limits$max_entries) {
    stop("Compressed archive contains too many extracted entries.", call. = FALSE)
  }
  if (length(paths) == 0L) {
    return(invisible(NULL))
  }
  if (any(nzchar(Sys.readlink(paths)))) {
    stop("Compressed archive extracted unsafe entries.", call. = FALSE)
  }

  info <- file.info(paths)
  if (anyNA(info$isdir) || anyNA(info$size)) {
    stop("Compressed archive extraction could not be validated.", call. = FALSE)
  }
  expanded_size <- sum(info$size[!info$isdir])
  if (expanded_size > limits$max_expanded_bytes) {
    stop("Compressed archive exceeds the expanded-size limit.", call. = FALSE)
  }
  if (is.finite(compressed_size) && expanded_size > 0) {
    ratio <- expanded_size / max(compressed_size, 1)
    if (ratio > limits$max_compression_ratio) {
      stop("Compressed archive exceeds the compression-ratio limit.", call. = FALSE)
    }
  }

  invisible(NULL)
}

decompress_matrix_input <- function(
  fileName,
  filePath,
  temp_root = scspotlight_temp_root(),
  timing = NULL,
  return_extraction_details = FALSE
) {
  time_phase <- function(phase, expr, details = list()) {
    if (!is.function(timing)) {
      return(force(expr))
    }

    started <- proc.time()[["elapsed"]]
    timing(phase, "start", details = details)
    tryCatch(
      {
        value <- force(expr)
        timing(
          phase,
          "end",
          elapsed_ms = (proc.time()[["elapsed"]] - started) * 1000,
          details = details
        )
        value
      },
      error = function(error) {
        timing(
          phase,
          "error",
          elapsed_ms = (proc.time()[["elapsed"]] - started) * 1000,
          details = details
        )
        stop(error)
      }
    )
  }

  tmpMatrixDir <- NULL
  retainExtraction <- FALSE
  on.exit(
    {
      if (
        !retainExtraction &&
          is.character(tmpMatrixDir) &&
          length(tmpMatrixDir) == 1L &&
          nzchar(tmpMatrixDir) &&
          dir.exists(tmpMatrixDir)
      ) {
        try(unlink(tmpMatrixDir, recursive = TRUE, force = TRUE), silent = TRUE)
      }
    },
    add = TRUE
  )

  dir.create(temp_root, recursive = TRUE, showWarnings = FALSE)
  if (
    str_detect(fileName, "\\.tar.gz$") ||
      str_detect(fileName, "\\.tgz$") ||
      str_detect(fileName, "\\.tar.bz2$") ||
      str_detect(fileName, "\\.tbz2$")
  ) {
    archive_entries <- list_tar_archive_entries(filePath)
    assert_safe_archive_entries(
      archive_entries,
      archive_type = "tar"
    )
    tmpMatrixDir <- tempfile(pattern = "matrixDir", tmpdir = temp_root)
    dir.create(tmpMatrixDir)
    extract_validated_tar_archive(
      filePath,
      exdir = tmpMatrixDir,
      uses_base256_numeric = archive_entries$uses_base256_numeric
    )
    assert_safe_extracted_archive(
      tmpMatrixDir,
      compressed_size = archive_entries$compressed_size
    )
  } else if (str_detect(fileName, "\\.[Zz][Ii][Pp]$")) {
    if (!requireNamespace("zip", quietly = TRUE)) {
      stop("The 'zip' package is required to decompress zip archives.")
    }
    archive_entries <- time_phase(
      "server_archive_list_and_validate",
      {
        archive_entries <- list_zip_archive_entries(filePath)
        assert_safe_archive_entries(
          archive_entries,
          archive_type = "zip"
        )
        archive_entries
      }
    )
    tmpMatrixDir <- tempfile(pattern = "matrixDir", tmpdir = temp_root)
    dir.create(tmpMatrixDir)
    time_phase(
      "server_archive_extract",
      zip::unzip(zipfile = filePath, exdir = tmpMatrixDir)
    )
    assert_safe_extracted_archive(
      tmpMatrixDir,
      compressed_size = archive_entries$compressed_size
    )
  } else {
    stop("Compression format is not supported.")
  }
  subpath <- dir(tmpMatrixDir, recursive = TRUE, pattern = "*.mtx*") %>%
    dirname()
  if (length(subpath) > 0) {
    dataDir <- file.path(tmpMatrixDir, subpath)
  } else {
    explore_bundle_root <- find_scspotlight_explore_bundle_root(tmpMatrixDir)
    if (!is.null(explore_bundle_root)) {
      dataDir <- explore_bundle_root
    } else {
      ## BPCells Rds compressed tarball
      subpath <- dir(
        tmpMatrixDir,
        recursive = TRUE,
        pattern = "*.[Rr][Dd][Ss]$"
      ) %>%
        dirname()
      dataDir <- file.path(tmpMatrixDir, subpath)
    }
  }

  result <- if (isTRUE(return_extraction_details)) {
    list(
      data_dir = dataDir,
      extraction_root = tmpMatrixDir
    )
  } else {
    dataDir
  }

  retainExtraction <- isTRUE(return_extraction_details) || length(dataDir) > 0L
  result
}

#' standard_process_seurat
#'
#' Function for standard processing matrix input
#'
#' @noRd
standard_process_seurat <- function(
  seuratObj,
  normalization = TRUE,
  hvg_method = "mean.var.plot",
  ndims = 30,
  res = 0.5,
  backend_root = NULL
) {
  analysis_waiter_update("Running memory-conserving processing...")
  seuratObj <- run_memory_conserving_processing(
    seuratObj,
    normalization = normalization,
    hvg_method = hvg_method,
    ndims = ndims,
    res = res,
    npcs = max(ndims, 30L)
  )
  if (isTruthy(backend_root)) {
    seuratObj <- ensure_bpcells_backing(
      seuratObj,
      root_dir = backend_root,
      layers = NULL
    )
    seuratObj <- drop_dense_scale_data(seuratObj)
    assert_no_dense_scale_data(seuratObj)
    assert_scspotlight_backend(seuratObj)
  }
  seuratObj <- drop_dense_scale_data(seuratObj)
  assert_no_dense_scale_data(seuratObj)
  seuratObj
}

## To be copied in the UI
# mod_dataInput_ui("dataInput_1")

## To be copied in the server
# mod_dataInput_server("dataInput_1")
