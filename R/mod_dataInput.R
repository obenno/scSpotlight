#' dataInput UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList fileInput
#' @importFrom shinyWidgets prettySwitch
#'
mod_dataInput_inputUI <- function(id){
    ns <- NS(id)

    dataDir <- golem::get_golem_options("dataDir")
    ##runningMode <- golem::get_golem_options("runningMode")
    ##if(isTruthy(dataDir) && runningMode == "viewer"){
    if(isTruthy(dataDir)){
        tagList(
            selectInput(
                ns("dataDirFile"),
                label = "Choose a RDS input file",
                choices = "",
                selected = NULL,
                multiple = FALSE,
                selectize = TRUE
            ),
            selectInput(
                ns("selectAssay"),
                "Switch Assays",
                choices = "",
                selected = NULL,
                multiple = FALSE,
                selectize = TRUE,
                width = NULL
            ) %>%
            tagAppendAttributes(class = c("mb-1"))
        )
    }else{
        tagList(
            fileInput(
                ns("dataInput"),
                tagList("Upload Input File",
                        infoIcon("Please upload processed seuratObj (RDS), or compressed matrix directory (zip, tgz, tbz2)", "right")),
                multiple = FALSE,
                width = "100%",
                accept = c(##".h5seurat", ".h5Seurat", ".H5Seurat", "H5seurat",
                    ".rds", "Rds", "RDS",
                    ".zip",
                    "tar.gz", "tgz",
                    "tar.bz2", "tbz2"
                )
            ),
            selectInput(
                ns("selectAssay"),
                "Switch Assays",
                choices = "",
                selected = NULL,
                multiple = FALSE,
                selectize = TRUE,
                width = NULL
            ) %>%
            tagAppendAttributes(class = c("mb-1")),
            span(
                "Enable BPCells", style = "display: inline-block; margin-bottom: 0.5rem",
                infoIcon("This will use BPCells as the backend to store sparse matrix in seurat object.", "right")
            ),
            switchInput(
                inputId = ns("enableBPCells"),
                label = NULL,
                size = "mini",
                value = FALSE
            )
        )
    }
}

#' dataInput Server Functions
#'
#' @import Seurat
#' @import BPCells
#' @import shiny
#' @importFrom readr read_tsv
#' @importFrom shinyWidgets updateSwitchInput
#' @importFrom SeuratObject LoadSeuratRds Layers
#' @importFrom stringr str_detect
#'
#' @noRd
mod_dataInput_server <- function(id,
                                 obj,
                                 hvgSelectMethod,
                                 clusterDims,
                                 clusterResolution,
                                 scatterReductionIndicator,
                                 scatterColorIndicator,
                                 objIndicator){
    moduleServer( id, function(input, output, session){
        ns <- session$ns

        ## use golem_opts to parse dataDir arguments when invoking run_app()
        dataDir <- golem::get_golem_options("dataDir")
        runningMode <- golem::get_golem_options("runningMode")
        compressionFormatPattern <- "\\.zip$|\\.tar.gz$|\\.tgz$|\\.tar\\.bz2$|\\.tbz2"
        rdsFormatPattern <- "\\.rds$|\\.RDS$|\\.Rds$"
        if(runningMode == "processing"){
            supportedFileInputPattern <- paste0(rdsFormatPattern, "|", compressionFormatPattern)
        }else{
            supportedFileInputPattern <- rdsFormatPattern
        }
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
                updateSelectInput(
                    session,
                    inputId = "dataDirFile",
                    choices = list.files(path = dataDir,
                                         pattern = supportedFileInputPattern,
                                         recursive = TRUE),
                    selected = ""
                )
            }
        }

        ## Check if BPCells was installed
        observe({
            if(input$enableBPCells &&
               !isTruthy(rlang::is_installed("BPCells"))){

                ## update switchInput to false and shoot a notification
                updateSwitchInput(
                    session,
                    inputId = "enableBPCells",
                    value = FALSE
                )
                showNotification(
                    ui = "Please install BPCells package to enable this function",
                    action = NULL,
                    duration = 5,
                    closeButton = TRUE,
                    type = "error",
                    session = session
                )
            }
        }, priority = 200)

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

        observeEvent(list(inputFilePath(), inputFileName()), {
            req(isTruthy(input$dataInput) || isTruthy(input$dataDirFile))
            waiter_show(html = waiting_screen(), color = "var(--bs-primary)")
            ## Init seuratObj
            seuratObj <- NULL
            if(str_detect(inputFileName(), rdsFormatPattern)){

                seuratObj <- LoadSeuratRds(inputFilePath())
                assay <- DefaultAssay(seuratObj)
                ## Convert v3 assay to v5 assay to save memory
                if(class(seuratObj[[assay]]) == "Assay"){
                    seuratObj[[assay]] <- as(seuratObj[[assay]], Class = "Assay5")
                }
                if(input$enableBPCells){
                    ## converting counts and data layer to BPCells matrix
                    if("counts" %in% Layers(seuratObj) &&
                       class(seuratObj[[assay]]$counts) == "dgCMatrix"){
                        bp_dir <- file.path(tempdir(), "BPCells_matrix")
                        if(!dir.exists(bp_dir)){ dir.create(bp_dir) }
                        seuratObj[[assay]]$counts <- write_matrix_dir(
                            seuratObj[[assay]]$counts,
                            dir = file.path(bp_dir, "counts"),
                            overwrite = TRUE
                        )
                    }
                    if("data" %in% Layers(seuratObj) &&
                       class(seuratObj[[assay]]$data) == "dgCMatrix"){
                        bp_dir <- file.path(tempdir(), "BPCells_matrix")
                        if(!dir.exists(bp_dir)){ dir.create(bp_dir) }
                        seuratObj[[assay]]$data <- write_matrix_dir(
                            seuratObj[[assay]]$data,
                            dir = file.path(bp_dir, "data"),
                            overwrite = TRUE
                        )
                    }
                    hvg_method <- "vst"
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
                }else{
                    hvg_method <- ifelse(isTruthy(hvgSelectMethod()), hvgSelectMethod(), "vst")
                }

                seuratObj <- validate_seuratRDS(seuratObj, runningMode = runningMode,
                                                hvgSelectMethod = hvg_method,
                                                nDims = clusterDims(),
                                                resolution = clusterResolution())

            }else if(str_detect(inputFileName(), compressionFormatPattern)){

                waiter_update(html = waiting_screen("Decompressing..."))

                dataDir <- decompress_matrix_input(inputFileName(), inputFilePath())

                ## Check the input format, compressed matrix or BPCells Rds taball
                BPCells_Rds <- dir(dataDir, recursive=TRUE, pattern = "*.[Rr][Dd][Ss]$")

                if(length(BPCells_Rds)>0){
                    if(rlang::is_installed("BPCells")){
                        if(!isTruthy(input$enableBPCells)){
                            updateSwitchInput(
                                session,
                                inputId = "enableBPCells",
                                value = TRUE
                            )
                            showNotification(
                                ui = HTML("Rds in compressed files detected, auto enable BPCells"),
                                action = NULL,
                                duration = 5,
                                closeButton = TRUE,
                                type = "warning",
                                session = session
                            )
                        }
                        setwd(file.path(dataDir, dirname(BPCells_Rds)))
                        message("setting working dir to ", dataDir)
                        seuratObj <- LoadSeuratRds(file.path(dataDir, BPCells_Rds))
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
                                                        resolution = clusterResolution())
                    }else{
                        waiter_update(html = waiting_screen("Rds in tarball deteced, please ensure BPCells is installed"))
                        stop("BPCells not installed...")
                    }
                }else{
                    waiter_update(html = waiting_screen("Reading Matrix..."))
                    ## use sparse matrix in memory for now
                    if(input$enableBPCells){
                        counts <- BPCells_Read10X(dataDir)
                        hvg_method <- "vst"
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
                    }else{
                        counts <- Read10X(dataDir)
                        hvg_method <- ifelse(isTruthy(hvgSelectMethod()), hvgSelectMethod(), "vst")
                    }

                    waiter_update(html = waiting_screen("Creating seuratObj..."))
                    seuratObj <- CreateSeuratObject(counts = counts, min.cells = 1) # remove genes with no expression value

                    waiter_update(html = waiting_screen("Calculating percent.mt..."))

                    seuratObj[["percent.mt"]] <- PercentageFeatureSet(seuratObj, pattern = "^(MT-|mt-)")
                    seuratObj[["percent.rp"]] <- PercentageFeatureSet(seuratObj, pattern = "^(RPL|RPS|Rpl|Rps)")

                    seuratObj <- standard_process_seurat(seuratObj, hvg_method = hvg_method,
                                                         ndims = clusterDims(), res = clusterResolution())
                }
            }else{
                waiter_update(html = waiting_screen("Input format not supported, please reload the page..."))
                stop("Input format not supported")
            }

            ## update assay list
            updateSelectInput(
                session = session,
                inputId = "selectAssay",
                choices = ifelse(isTruthy(seuratObj), Assays(seuratObj), ""),
                selected = ifelse(isTruthy(seuratObj), DefaultAssay(seuratObj), NULL)
            )
            waiter_hide()
            message("dataInput module increased scatter indicator")
            scatterReductionIndicator(scatterReductionIndicator()+1)
            scatterColorIndicator(scatterColorIndicator()+1)
            obj(seuratObj)

        })

        selectedAssay <- reactive({
            input$selectAssay
        })

        return(selectedAssay)

    })
}

#' BPCells_Read10X
#'
#' @description A modified version of the Seurat Read10X function using BPCells to read matrix
#'
#' @import BPCells
#' @import Seurat
#'
#' @noRd
#' 
BPCells_Read10X <- function(
  data.dir,
  gene.column = 2,
  cell.column = 1,
  unique.features = TRUE,
  strip.suffix = FALSE
) {
  full.data <- list()
  has_dt <- requireNamespace("data.table", quietly = TRUE) && requireNamespace("R.utils", quietly = TRUE)
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
        outdir = tempfile("matrix_market"),
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
    dirPath <- tempfile(pattern = "counts_")
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

#' dataScaled
#'
#' Check if seurat object is scaled
#'
#' @noRd
dataScaled <- function(seuratObj){
    m <- GetAssayData(seuratObj, assay = NULL, layer = "scale.data")
    any(dim(m) > 0)
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
                               resolution = 1){
    message("calculating mt")
    if("counts" %in% Layers(seuratObj) &&
       !("percent.mt" %in% colnames(seuratObj[[]]))){
        seuratObj[["percent.mt"]] <- PercentageFeatureSet(seuratObj, pattern = "^(MT-|mt-)")
    }
    message("calculating rp")
    if("counts" %in% Layers(seuratObj) &&
       !("percent.rp" %in% colnames(seuratObj[[]]))){
        seuratObj[["percent.rp"]] <- PercentageFeatureSet(seuratObj, pattern = "^(RPL|RPS|Rpl|Rps)")
    }

    ## Added rds verify code
    if(!dataNormalized(seuratObj)){
        waiter_update(html = waiting_screen("Normalizing Data..."))
        seuratObj <- NormalizeData(seuratObj)
    }
    if(!HVG_exist(seuratObj) && runningMode == "processing"){
        waiter_update(html = waiting_screen("Finding HVGs..."))
        if(hvgSelectMethod == "vst"){
            layer <- "counts"
        }else{
            layer <- "data"
        }
        seuratObj <- FindVariableFeatures(seuratObj, selection.method = hvgSelectMethod, layer = layer)
    }
    if(!dataScaled(seuratObj) && runningMode == "processing"){
        waiter_update(html = waiting_screen("Scaling Data..."))
        seuratObj <- ScaleData(seuratObj)
    }
    if(!reduction_exist(seuratObj) &&
       runningMode == "processing"){
        waiter_update(html = waiting_screen("Calculating Reductions..."))
        seuratObj <- RunPCA(seuratObj)
        seuratObj <- FindNeighbors(seuratObj, dims = 1:nDims)
        seuratObj <- FindClusters(seuratObj, resolution = resolution)
        seuratObj <- RunUMAP(seuratObj, dims = 1:nDims)
    }
    message("Finished validating object...")
    return(seuratObj)
}


#' decompress_matrix_input
#'
#' Function for reading compressed matrix
#'
#' @noRd
decompress_matrix_input <- function(fileName, filePath){
    if(str_detect(fileName, "\\.tar.gz$") | str_detect(fileName, "\\.tgz$")){
        tmpMatrixDir <- tempfile(pattern = "matrixDir")
        system2("mkdir", c("-p", tmpMatrixDir))
        system2("tar", c("xvzf", filePath, "-C", tmpMatrixDir))
    }else if(str_detect(fileName, "\\.tar.bz2$") | str_detect(fileName, "\\.tbz2$")){
        tmpMatrixDir <- tempfile(pattern = "matrixDir")
        system2("mkdir", c("-p", tmpMatrixDir))
        system2("tar", c("xvjf", filePath, "-C", tmpMatrixDir))
    }else if(str_detect(fileName, "\\.zip$")){
        tmpMatrixDir <- tempfile(pattern = "matrixDir")
        system2("mkdir", c("-p", tmpMatrixDir))
        system2("unzip", c("-d", tmpMatrixDir, filePath))
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
                                    hvg_method = "mean.var.plot", ndims = 30, res = 0.5){
    ##withProgress({
    ##setProgress(0, message = paste("Normalizing Data...", "0/6"))
    waiter_update(html = waiting_screen("Normalizing Data..."))
    if(normalization){
        seuratObj <- seuratObj %>%
            NormalizeData()
    }

    ##incProgress(1/6, message = paste("Finding Variable Features...", "1/6"))
    waiter_update(html = waiting_screen("Finding Variable Features..."))
    ## FindVariableFeatures has to define layer parameter to use BPCells
    if(hvg_method == "vst"){
        seuratObj <- FindVariableFeatures(seuratObj, selection.method = hvg_method, layer = "counts")
    }else{
        seuratObj <- FindVariableFeatures(seuratObj, selection.method = hvg_method, layer = "data")
    }

    ##incProgress(1/6, message = paste("Scaling Data...", "2/6"))
    waiter_update(html = waiting_screen("Scaling Data..."))
    seuratObj <- ScaleData(seuratObj)

    ##incProgress(1/6, message = paste("Running PCA...", "3/6"))
    waiter_update(html = waiting_screen("Running PCA..."))
    seuratObj <- RunPCA(seuratObj)

    ##incProgress(1/6, message = paste("Finding Neighbours...", "4/6"))
    waiter_update(html = waiting_screen("Finding Neighbours..."))
    seuratObj <- FindNeighbors(seuratObj, dims = 1:ndims)
    seuratObj <- FindClusters(seuratObj, resolution = res)

    ##incProgress(1/6, message = paste("Calculating UMAP...", "5/6"))
    waiter_update(html = waiting_screen("Calculating UMAP..."))
    seuratObj <- RunUMAP(seuratObj, dims = 1:ndims)
    ##})
    return(seuratObj)
}

## To be copied in the UI
# mod_dataInput_ui("dataInput_1")

## To be copied in the server
# mod_dataInput_server("dataInput_1")
