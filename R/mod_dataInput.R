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
mod_dataInput_inputUI <- function(id){
    ns <- NS(id)

    dataDir <- golem::get_golem_options("dataDir")
    ##runningMode <- golem::get_golem_options("runningMode")
    ##if(isTruthy(dataDir) && runningMode == "viewer"){
    if(isTruthy(dataDir)){
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
    }else{
        tagList(
            fileInput(
                ns("dataInput"),
                tagList("Upload Input File",
                        infoIcon("Please upload a processed Seurat object (RDS), a Scanpy/AnnData h5ad file, or a compressed matrix directory (zip, tgz, tbz2)", "right")),
                multiple = FALSE,
                width = "100%",
              accept = c(
                ".rds",
                ".h5ad",
                ".zip",
                ".tar.gz", ".tgz",
                ".tar.bz2", ".tbz2"
              )
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

#' dataInput Server Functions
#'
#' @import Seurat
#' @import shiny
#' @importFrom readr read_tsv
#' @importFrom SeuratObject LoadSeuratRds Layers
#' @importFrom stringr str_detect
#'
#' @noRd
mod_dataInput_server <- function(id,
                                 obj,
                                 hvgSelectMethod,
                                 clusterDims,
                                 clusterResolution,
                                 geneUpdateIndicator,
                                 metaUpdateIndicator,
                                 reductionUpdateIndicator){
    moduleServer( id, function(input, output, session){
        ns <- session$ns

        ## use golem_opts to parse dataDir arguments when invoking run_app()
        dataDir <- golem::get_golem_options("dataDir")
        runningMode <- golem::get_golem_options("runningMode")
        compressionFormatPattern <- "\\.zip$|\\.tar.gz$|\\.tgz$|\\.tar\\.bz2$|\\.tbz2"
        rdsFormatPattern <- "\\.rds$|\\.RDS$|\\.Rds$"
        h5adFormatPattern <- "\\.[Hh]5[Aa][Dd]$"
        supportedFileInputPattern <- paste0(rdsFormatPattern, "|", h5adFormatPattern, "|", compressionFormatPattern)

        assert_bpcells_available()

        if(isTruthy(dataDir)){
            if(!file.exists(dataDir)){
                showNotification(
                    ui = "dataDir parsed but does not exist",
                    action = NULL,
                    duration = NULL,
                    closeButton = TRUE,
                    type = "default",
                    session = session
                )
            }else{
                ## set working directory to the dataDir
                ## to ensure BPCells matrix path is correct
                setwd(dataDir)
                updateSelectizeInput(
                    session,
                    inputId = "dataDirFile",
                  choices = list.files(
                    path = dataDir,
                    pattern = supportedFileInputPattern,
                    recursive = TRUE
                  ),
                  selected = ""
                )
            }
        }

        inputFilePath <- reactive({
            req(isTruthy(input$dataInput) || isTruthy(input$dataDirFile))
            if(isTruthy(input$dataDirFile)){
                file.path(dataDir, input$dataDirFile)
            }else{
                input$dataInput$datapath
            }
        })

        inputFileName <- reactive({
            req(isTruthy(input$dataInput) || isTruthy(input$dataDirFile))
            if(isTruthy(input$dataDirFile)){
                input$dataDirFile
            }else{
                input$dataInput$name
            }
        })

        observeEvent(list(
            inputFilePath(),
            inputFileName()
        ), {
            req(inputFilePath(), inputFileName())
            message("inputFilePath() is ", isolate(inputFilePath()))
            ##req(isTruthy(input$dataInput) || isTruthy(input$dataDirFile))
            waiter_show(html = waiting_screen(), color = "var(--bs-primary)")
            ## Init seuratObj
            seuratObj <- NULL
            if(str_detect(inputFileName(), rdsFormatPattern)){

                seuratObj <- load_scspotlight_bundle(inputFilePath())
                assay <- DefaultAssay(seuratObj)
                ## Convert v3 assay to v5 assay to save memory
                if(class(seuratObj[[assay]]) == "Assay"){
                    seuratObj[[assay]] <- as(seuratObj[[assay]], Class = "Assay5")
                }
                message("conversion finished...")
                hvg_method <- ifelse(isTruthy(hvgSelectMethod()), hvgSelectMethod(), "vst")
                seuratObj <- ensure_bpcells_backing(
                    seuratObj,
                    root_dir = file.path(session$userData$backendDir, "layers"),
                    layers = NULL
                )
                if(is_seurat_bpcells(seuratObj) && isTruthy(hvgSelectMethod()) && hvgSelectMethod()!="vst"){
                    showNotification(
                        ui = HTML("BPCells backend active, prefer <b>vst</b> on the <b>counts</b> layer for large datasets"),
                        action = NULL,
                        duration = 5,
                        closeButton = TRUE,
                        type = "warning",
                        session = session
                    )
                }

                seuratObj <- validate_seuratRDS(seuratObj, runningMode = runningMode,
                                                hvgSelectMethod = hvg_method,
                                                nDims = clusterDims(),
                                                resolution = clusterResolution(),
                                                backend_root = file.path(session$userData$backendDir, "layers"))
                seuratObj <- ensure_bpcells_backing(
                    seuratObj,
                    root_dir = file.path(session$userData$backendDir, "layers"),
                    layers = NULL
                )
                assert_scspotlight_backend(seuratObj)

            }else if(str_detect(inputFileName(), h5adFormatPattern)){

                waiter_update(html = waiting_screen("Importing h5ad..."))
                hvg_method <- ifelse(isTruthy(hvgSelectMethod()), hvgSelectMethod(), "vst")
                seuratObj <- import_h5ad_as_seurat_bpcells(
                    inputFilePath(),
                    backend_root = file.path(session$userData$backendDir, "layers")
                )
                if(is_seurat_bpcells(seuratObj) && isTruthy(hvgSelectMethod()) && hvgSelectMethod()!="vst"){
                    showNotification(
                        ui = HTML("BPCells backend active, prefer <b>vst</b> on the <b>counts</b> layer for large datasets"),
                        action = NULL,
                        duration = 5,
                        closeButton = TRUE,
                        type = "warning",
                        session = session
                    )
                }

                seuratObj <- validate_seuratRDS(seuratObj, runningMode = runningMode,
                                                hvgSelectMethod = hvg_method,
                                                nDims = clusterDims(),
                                                resolution = clusterResolution(),
                                                backend_root = file.path(session$userData$backendDir, "layers"))
                assert_scspotlight_backend(seuratObj)

            }else if(str_detect(inputFileName(), compressionFormatPattern)){

                waiter_update(html = waiting_screen("Decompressing..."))

                dataDir <- decompress_matrix_input(inputFileName(), inputFilePath())

                ## Check the input format, compressed matrix or BPCells Rds taball
                BPCells_Rds <- dir(dataDir, recursive=TRUE, pattern = "*.[Rr][Dd][Ss]$")

                if(length(BPCells_Rds)>0){
                    bundleRoot <- if (is_scspotlight_bundle_dir(dataDir)) {
                        dataDir
                    } else {
                        candidate_roots <- unique(dirname(file.path(dataDir, BPCells_Rds)))
                        matched_root <- candidate_roots[vapply(candidate_roots, is_scspotlight_bundle_dir, logical(1))]
                        if (!length(matched_root)) {
                            stop("Compressed RDS bundle detected, but manifest.json is missing or invalid")
                        }
                        matched_root[[1]]
                    }
                    bundleRds <- find_scspotlight_bundle_rds(bundleRoot)
                    seuratObj <- load_scspotlight_bundle(bundleRds)
                    if(isTruthy(hvgSelectMethod()) && hvgSelectMethod()!="vst"){
                        showNotification(
                            ui = HTML("BPCells enabled, enforce to use <b>vst</b> method and <b>counts</b> layer"),
                            action = NULL,
                            duration = 5,
                            closeButton = TRUE,
                            type = "warning",
                            session = session
                        )
                    }
                    seuratObj <- validate_seuratRDS(seuratObj, runningMode = runningMode,
                                                    hvgSelectMethod = "vst",
                                                    nDims = clusterDims(),
                                                    resolution = clusterResolution(),
                                                    backend_root = file.path(session$userData$backendDir, "layers"))
                    assert_scspotlight_backend(seuratObj)
                }else{
                    waiter_update(html = waiting_screen("Reading Matrix..."))
                    counts <- BPCells_Read10X(
                        dataDir,
                        temp_root = session$userData$backendDir
                    )
                    hvg_method <- ifelse(isTruthy(hvgSelectMethod()), hvgSelectMethod(), "vst")
                    if(isTruthy(hvgSelectMethod()) && hvgSelectMethod()!="vst"){
                        showNotification(
                            ui = HTML("BPCells backend active, prefer <b>vst</b> on the <b>counts</b> layer for large datasets"),
                            action = NULL,
                            duration = 5,
                            closeButton = TRUE,
                            type = "warning",
                            session = session
                        )
                    }

                    waiter_update(html = waiting_screen("Creating seuratObj..."))
                    seuratObj <- CreateSeuratObject(counts = counts, min.cells = 1) # remove genes with no expression value

                    waiter_update(html = waiting_screen("Calculating percent.mt..."))

                    seuratObj[["percent.mt"]] <- PercentageFeatureSet(seuratObj, pattern = "^(MT-|mt-)")
                    seuratObj[["percent.rp"]] <- PercentageFeatureSet(seuratObj, pattern = "^(RPL|RPS|Rpl|Rps)")

                    seuratObj <- standard_process_seurat(seuratObj, hvg_method = hvg_method,
                                                         ndims = clusterDims(), res = clusterResolution(),
                                                         backend_root = file.path(session$userData$backendDir, "layers"))

                }
            }else{
                waiter_update(html = waiting_screen("Input format not supported, please reload the page..."))
                stop("Input format not supported")
            }

            ## update assay list
            if(isTruthy(seuratObj)){
                updateSelectizeInput(
                    session = session,
                    inputId = "selectAssay",
                    choices = ifelse(isTruthy(seuratObj), Assays(seuratObj), ""),
                    selected = ifelse(isTruthy(seuratObj), DefaultAssay(seuratObj), NULL)
                )
                obj(seuratObj)
            }


            ## Update indicators
            metaUpdateIndicator(metaUpdateIndicator()+1)
            reductionUpdateIndicator(reductionUpdateIndicator()+1)
            geneUpdateIndicator(geneUpdateIndicator()+1)
            waiter_hide()
        }, priority = 10)

        observeEvent(input$selectAssay,{
            ## Data of different assays were stored in the same metadata
            ## reductions were "independent" with assay switch
            geneUpdateIndicator(geneUpdateIndicator()+1)
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
  temp_root = tempdir()
) {
  full.data <- list()
  has_dt <- requireNamespace("data.table", quietly = TRUE) && requireNamespace("R.utils", quietly = TRUE)
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
    if (!pre_ver_3 && !file.exists(features.loc) ) {
      stop("Gene name or features file missing. Expecting ", basename(path = features.loc))
    }
    if (!file.exists(matrix.loc)) {
      stop("Expression matrix file missing. Expecting ", basename(path = matrix.loc))
    }
    message("Importing with BPCells...")
    data <- BPCells::import_matrix_market(
        mtx_path = matrix.loc,
        outdir = tempfile(pattern = "matrix_market_", tmpdir = temp_root),
        row_names = NULL,
        col_names = NULL,
        row_major = FALSE,
        tmpdir = tempdir(),
        load_bytes = 4194304L,
        sort_bytes = 1073741824L
    )
    if (has_dt) {
      cell.barcodes <- as.data.frame(data.table::fread(barcode.loc, header = FALSE))
    } else {
      cell.barcodes <- read.table(file = barcode.loc, header = FALSE, sep = '\t', row.names = NULL)
    }

    if (ncol(x = cell.barcodes) > 1) {
      cell.names <- cell.barcodes[, cell.column]
    } else {
      cell.names <- readLines(con = barcode.loc)
    }
    if (all(grepl(pattern = "\\-1$", x = cell.names)) & strip.suffix) {
      cell.names <- as.vector(x = as.character(x = sapply(
        X = cell.names,
        FUN = ExtractField,
        field = 1,
        delim = "-"
      )))
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
      feature.names <- as.data.frame(data.table::fread(ifelse(test = pre_ver_3, yes = gene.loc, no = features.loc), header = FALSE))
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
      feature.names[na.features, gene.column] <- feature.names[na.features, replacement.column]
    }
    if (unique.features) {
      fcols = ncol(x = feature.names)
      if (fcols < gene.column) {
        stop(paste0("gene.column was set to ", gene.column,
                    " but feature.tsv.gz (or genes.tsv) only has ", fcols, " columns.",
                    " Try setting the gene.column argument to a value <= to ", fcols, "."))
      }
      rownames(x = data) <- make.unique(names = feature.names[, gene.column])
    }
    message("Finished generating matrix")
    dirPath <- tempfile(pattern = "counts_", tmpdir = temp_root)
    data <- optimize_bpcells_matrix_type(data, layer = "counts")
    BPCells::write_matrix_dir(data, dir=dirPath, overwrite = TRUE)
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
dataNormalized <- function(seuratObj){
    ##!identical(seuratObj[["RNA"]]$counts, seuratObj[["RNA"]]$data)
    m <- GetAssayData(seuratObj, assay = NULL, layer = "data")
    any(dim(m) > 0)
}

#' HVG_exist
#'
#' Check if seurat object has HVGs stored
#'
#' @noRd
HVG_exist <- function(seuratObj){
    length(VariableFeatures(seuratObj))>0
}

#' reduction_exist
#'
#' Check if seurat object has reductions
#'
#' @noRd
reduction_exist <- function(seuratObj){
    length(Reductions(seuratObj)) > 0
}

#' validate_seuratRDS
#'
#' @importFrom SeuratObject Layers
#' 
#' @noRd
validate_seuratRDS <- function(seuratObj,
                               runningMode = "viewer",
                               hvgSelectMethod = "vst",
                               nDims = 30,
                               resolution = 1,
                               backend_root = NULL){
    seuratObj <- ensure_normalized_layer(
        seuratObj,
        backend_root = backend_root,
        input_label = "Input object"
    )
    assert_processed_input_requirements(seuratObj, input_label = "Input object")
    message("Finished validating object requirements...")
    return(seuratObj)
}


#' decompress_matrix_input
#'
#' Function for reading compressed matrix
#'
#' @noRd
decompress_matrix_input <- function(fileName, filePath){
    if(str_detect(fileName, "\\.tar.gz$") || str_detect(fileName, "\\.tgz$") ||
       str_detect(fileName, "\\.tar.bz2$") || str_detect(fileName, "\\.tbz2$")){
        tmpMatrixDir <- tempfile(pattern = "matrixDir")
        dir.create(tmpMatrixDir)
        untar(tarfile = filePath, exdir = tmpMatrixDir)
    }else if(str_detect(fileName, "\\.zip$")){
        tmpMatrixDir <- tempfile(pattern = "matrixDir")
        dir.create(tmpMatrixDir)
        unzip(zipfile = filePath, exdir = tmpMatrixDir)
    }else{
        stop("Compression format is not supported.")
    }
    subpath <- dir(tmpMatrixDir, recursive=TRUE, pattern = "*.mtx*") %>%
        dirname()
    if(length(subpath)>0){
        dataDir <- file.path(tmpMatrixDir, subpath)
    }else{
        ## BPCells Rds compressed tarball
        subpath <- dir(tmpMatrixDir, recursive=TRUE, pattern = "*.[Rr][Dd][Ss]$") %>%
            dirname()
        dataDir <- file.path(tmpMatrixDir, subpath)
    }

    return(dataDir)
}

#' standard_process_seurat
#'
#' Function for standard processing matrix input
#'
#' @noRd
standard_process_seurat <- function(seuratObj, normalization = TRUE,
                                    hvg_method = "mean.var.plot", ndims = 30, res = 0.5,
                                    backend_root = NULL){
    waiter_update(html = waiting_screen("Running memory-conserving processing..."))
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
        assert_scspotlight_backend(seuratObj)
    }
    seuratObj
}

## To be copied in the UI
# mod_dataInput_ui("dataInput_1")

## To be copied in the server
# mod_dataInput_server("dataInput_1")
