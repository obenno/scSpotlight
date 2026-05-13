#' ClusterSetting UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
#' @importFrom shinyWidgets sliderTextInput prettyRadioButtons
mod_ClusterSetting_ui <- function(id) {
  ns <- NS(id)
  tagList(
    selectizeInput(
      inputId = ns("hvgSelectMethod"),
      label = "HVG Selection Method",
      choices = c("vst", "mean.var.plot", "dispersion"),
      selected = "vst",
      multiple = FALSE,
      options = list(dropdownParent = "body"),
      width = NULL
    ),
    shinyWidgets::sliderTextInput(
      inputId = ns("cluster_dims"),
      label = "Choose number of dims",
      selected = 30,
      choices = seq(10, 100, by = 10),
      grid = TRUE
    ),
    numericInput(
      inputId = ns("cluster_resolution"),
      label = "Cluster resolution",
      value = 0.5,
      step = 0.1
    ),
    prettyRadioButtons(
      inputId = ns("updateClusterOpt"),
      label = "",
      choices = c("Update All", "Update nDim Only", "Update Res Only"),
      selected = "Update Res Only",
      icon = icon("check"),
      bigger = TRUE,
      status = "primary",
      animation = "pulse"
    ),
    actionButton(
      inputId = ns("updateCluster"),
      label = "Update Cluster",
      icon = icon("code-compare"),
      style = "width:200px",
      class = "border border-1 border-primary shadow"
    )
  )
}

#' ClusterSetting Server Functions
#'
#' @importFrom SeuratObject Graphs
#' @importFrom tibble rownames_to_column
#'
#' @noRd
mod_ClusterSetting_server <- function(
  id,
  seuratObj,
  selectedAssay,
  metaUpdateIndicator,
  reductionUpdateIndicator
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    ## Update UMAP/TSNE reduction
    observeEvent(input$updateCluster, {
      req(seuratObj())
      withProgress({
        if (input$updateClusterOpt == "Update All") {
          incProgress(0, message = paste("Updating HVGs...", "0/4"))
          obj <- seuratObj()
          incProgress(1 / 4, message = paste("Updating PCA...", "1/4"))
          obj <- run_memory_conserving_processing(
            obj,
            normalization = FALSE,
            hvg_method = input$hvgSelectMethod,
            ndims = input$cluster_dims,
            res = input$cluster_resolution,
            npcs = max(input$cluster_dims, 30)
          )

          message(
            "ClusterSetting module increased meta and reduction indicator"
          )
          metaUpdateIndicator(metaUpdateIndicator() + 1)
          reductionUpdateIndicator(reductionUpdateIndicator() + 1)
        } else if (input$updateClusterOpt == "Update nDim Only") {
          incProgress(0, message = paste("Updating UMAP...", "0/2"))
          obj <- Seurat::RunUMAP(
            seuratObj(),
            dims = 1:input$cluster_dims,
            reduction = "pca"
          )

          incProgress(1 / 2, message = paste("Updating Cluster...", "1/2"))
          obj <- Seurat::FindNeighbors(
            obj,
            dims = 1:input$cluster_dims,
            reduction = "pca"
          )
          obj <- Seurat::FindClusters(
            obj,
            resolution = input$cluster_resolution
          )

          message(
            "ClusterSetting module increased meta and reduction indicator"
          )
          metaUpdateIndicator(metaUpdateIndicator() + 1)
          reductionUpdateIndicator(reductionUpdateIndicator() + 1)
        } else {
          obj <- seuratObj()
          assayName <- DefaultAssay(obj)
          graph_names <- paste(assayName, c("nn", "snn"), sep = "_")
          if (all(graph_names %in% Graphs(obj))) {
            incProgress(0, message = paste("Updating Cluster...", "0/1"))
            obj <- Seurat::FindClusters(
              obj,
              resolution = input$cluster_resolution
            )
          } else {
            incProgress(0, message = paste("Updating SNN...", "0/2"))
            obj <- Seurat::FindNeighbors(
              obj,
              dims = 1:input$cluster_dims,
              reduction = "pca"
            )
            incProgress(1 / 2, message = paste("Updating Cluster...", "1/2"))
            obj <- Seurat::FindClusters(
              obj,
              resolution = input$cluster_resolution
            )
          }

          message(
            "ClusterSetting module increased meta and reduction indicator"
          )
          metaUpdateIndicator(metaUpdateIndicator() + 1)
        }
        seuratObj(obj)
      })
    })

    clusterResolution <- reactive({
      input$cluster_resolution
    })

    clusterDims <- reactive({
      input$cluster_dims
    })

    hvgSelectMethod <- reactive({
      input$hvgSelectMethod
    })

    list(
      seuratObj = seuratObj,
      hvgSelectMethod = hvgSelectMethod,
      clusterDims = clusterDims,
      clusterResolution = clusterResolution
    )
  })
}

## To be copied in the UI
# mod_ClusterSetting_ui("ClusterSetting_1")

## To be copied in the server
# mod_ClusterSetting_server("ClusterSetting_1")
