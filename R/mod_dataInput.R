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
    runningMode <- golem::get_golem_options("runningMode")
    if(isTruthy(dataDir) && runningMode == "viewer"){
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
            tagAppendAttributes(class = c("mb-1"))
        )
    }
}

#' @importFrom DT DTOutput
#'
#' @noRd
##mod_dataInput_outputUI <- function(id){
##  tagList(
##      div("out")
##  )
##}

#' dataInput Server Functions
#'
#' @import Seurat
#' @import BPCells
#' @import shiny
#' @importFrom readr read_tsv
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
                                         pattern = "\\.rds$|\\.zip$|\\.tar.gz$|\\.tgz$|\\.tar\\.bz2$|\\.tbz2",
                                         recursive = TRUE),
                    selected = ""
                )
            }
        }

        inputFile <- reactive({
            req(isTruthy(input$dataInput) || isTruthy(input$dataDirFile))
            if(isTruthy(input$dataDirFile)){
                file.path(dataDir, input$dataDirFile)
            }else{
                input$dataInput$datapath
            }
        })

        observeEvent(inputFile(), {
          req(isTruthy(input$dataInput) || isTruthy(input$dataDirFile))
          waiter_show(html = waiting_screen(), color = "var(--bs-primary)")

          if(str_detect(inputFile(), "\\.[Rr][Dd][Ss]$")){

              seuratObj <- readRDS(inputFile())
              ##DefaultAssay(seuratObj) <- "RNA"
              assay <- DefaultAssay(seuratObj)
              ## Convert v3 assay to v5 assay to save memory
              seuratObj[[assay]] <- as(seuratObj[[assay]], Class = "Assay5")
              seuratObj[["percent.mt"]] <- PercentageFeatureSet(seuratObj, pattern = "^(MT-|mt-)")
              seuratObj[["percent.rp"]] <- PercentageFeatureSet(seuratObj, pattern = "^(RPL|RPS|Rpl|Rps)")

              ## Added rds verify code
              if(!dataNormalized(seuratObj)){
                  showNotification(
                      ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                                   role = "status",
                                   span(class = "sr-only", "Loading...")),
                               "Normalizing Data..."),
                      action = NULL,
                      duration = NULL,
                      closeButton = FALSE,
                      type = "default",
                      id = "dataInput_normalizeData",
                      session = session
                  )
                  seuratObj <- NormalizeData(seuratObj)
                  removeNotification(id = "dataInput_normalizeData", session = session)
              }
              if(!HVG_exist(seuratObj)){
                  showNotification(
                      ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                                   role = "status",
                                   span(class = "sr-only", "Loading...")),
                               "Finding HVGs..."),
                      action = NULL,
                      duration = NULL,
                      closeButton = FALSE,
                      type = "default",
                      id = "dataInput_HVGs",
                      session = session
                  )
                  if(input$hvgSelectMethod == "vst"){
                      seuratObj <- FindVariableFeatures(seuratObj, selection.method = hvgSelectMethod(), layer = "counts")
                  }else{
                      seuratObj <- FindVariableFeatures(seuratObj, selection.method = hvgSelectMethod(), layer = "data")
                  }
                  removeNotification(id = "dataInput_HVGs", session = session)
              }
              if(!dataScaled(seuratObj)){
                  showNotification(
                      ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                                   role = "status",
                                   span(class = "sr-only", "Loading...")),
                               "Scaling Data..."),
                      action = NULL,
                      duration = NULL,
                      closeButton = FALSE,
                      type = "default",
                      id = "dataInput_scaling",
                      session = session
                  )
                  seuratObj <- ScaleData(seuratObj)
                  removeNotification(id = "dataInput_scaling", session = session)
              }
              if(!reduction_exist(seuratObj)){
                  showNotification(
                      ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                                   role = "status",
                                   span(class = "sr-only", "Loading...")),
                               "Calculating Reductions..."),
                      action = NULL,
                      duration = NULL,
                      closeButton = FALSE,
                      type = "default",
                      id = "dataInput_reduction",
                      session = session
                  )
                  seuratObj <- RunPCA(seuratObj)
                  seuratObj <- FindNeighbors(seuratObj, dims = 1:clusterDims())
                  seuratObj <- FindClusters(seuratObj, resolution = clusterResolution())
                  seuratObj <- RunUMAP(seuratObj, dims = 1:clusterDims())
                  removeNotification(id = "dataInput_reduction", session = session)
              }
          }else{
              withProgress({
                  setProgress(0, message = paste("Decompressing:", "0/4"))
                  dataDir <- decompress_matrix_input(basename(inputFile()), inputFile())

                  incProgress(1/4, message = paste("Reading Matrix", "1/4"))
                  counts <- Read10X(dataDir)
                  ## use sparse matrix in memory for now
                  ##if(input$BPCells){
                  ##    counts <- import_matrix_market_10x(dataDir)
                  ##}else{
                  ##    counts <- Read10X(dataDir)
                  ##}

                  incProgress(1/4, message = paste("Creating seuratObj", "2/4"))
                  seuratObj <- CreateSeuratObject(counts = counts, min.cells = 1) # remove genes with no expression value

                  incProgress(1/4, message = paste("Calculating percent.mt", "3/4"))
                  ##DefaultAssay(seuratObj) <- "RNA"
                  seuratObj[["percent.mt"]] <- PercentageFeatureSet(seuratObj, pattern = "^(MT-|mt-)")
                  seuratObj[["percent.rp"]] <- PercentageFeatureSet(seuratObj, pattern = "^(RPL|RPS|Rpl|Rps)")
              })
              seuratObj <- standard_process_seurat(seuratObj, hvg_method = hvgSelectMethod(), ndims = clusterDims(), res = clusterResolution())
          }

          ## update assay list
          updateSelectInput(
              session = session,
              inputId = "selectAssay",
              choices = Assays(seuratObj),
              selected = DefaultAssay(seuratObj)
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
        subpath <- dir(tmpMatrixDir, recursive=TRUE, pattern = "*.mtx*") %>%
            dirname()
        dataDir <- file.path(tmpMatrixDir, subpath)
    }else if(str_detect(fileName, "\\.tar.bz2$") | str_detect(fileName, "\\.tbz2$")){
        tmpMatrixDir <- tempfile(pattern = "matrixDir")
        system2("mkdir", c("-p", tmpMatrixDir))
        system2("tar", c("xvjf", filePath, "-C", tmpMatrixDir))
        subpath <- dir(tmpMatrixDir, recursive=TRUE, pattern = "*.mtx*") %>%
            dirname()
        dataDir <- file.path(tmpMatrixDir, subpath)
    }else if(str_detect(fileName, "\\.zip$")){
        tmpMatrixDir <- tempfile(pattern = "matrixDir")
        system2("mkdir", c("-p", tmpMatrixDir))
        system2("unzip", c("-d", tmpMatrixDir, filePath))
        subpath <- dir(tmpMatrixDir, recursive=TRUE, pattern = "*.mtx*") %>%
            dirname()
        dataDir <- file.path(tmpMatrixDir, subpath)
    }else{
        stop("Compression format is not supported.")
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
    withProgress({
        setProgress(0, message = paste("Normalizing Data...", "0/6"))
        if(normalization){
            seuratObj <- seuratObj %>%
                NormalizeData()
        }

        incProgress(1/6, message = paste("Finding Variable Features...", "1/6"))
        ## FindVariableFeatures has to define layer parameter to use BPCells
        if(hvg_method == "vst"){
            seuratObj <- FindVariableFeatures(seuratObj, selection.method = hvg_method, layer = "counts")
        }else{
            seuratObj <- FindVariableFeatures(seuratObj, selection.method = hvg_method, layer = "data")
        }

        incProgress(1/6, message = paste("Scaling Data...", "2/6"))
        seuratObj <- ScaleData(seuratObj)

        incProgress(1/6, message = paste("Running PCA...", "3/6"))
        seuratObj <- RunPCA(seuratObj)

        incProgress(1/6, message = paste("Finding Neighbours...", "4/6"))
        seuratObj <- FindNeighbors(seuratObj, dims = 1:ndims)
        seuratObj <- FindClusters(seuratObj, resolution = res)

        incProgress(1/6, message = paste("Calculating UMAP...", "5/6"))
        seuratObj <- RunUMAP(seuratObj, dims = 1:ndims)
    })
    return(seuratObj)
}

## To be copied in the UI
# mod_dataInput_ui("dataInput_1")

## To be copied in the server
# mod_dataInput_server("dataInput_1")
