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
apply_cluster_update_mode <- function(
  object,
  update_mode,
  hvg_method = "vst",
  ndims = 30L,
  resolution = 0.5,
  process_fun = run_memory_conserving_processing,
  run_umap_fun = Seurat::RunUMAP,
  find_neighbors_fun = Seurat::FindNeighbors,
  find_clusters_fun = Seurat::FindClusters,
  graphs_fun = SeuratObject::Graphs,
  progress_fun = function(...) NULL
) {
  ndims <- suppressWarnings(as.integer(ndims))
  if (is.na(ndims) || ndims < 1L) {
    stop("Cluster dimensions must be a positive integer.", call. = FALSE)
  }
  resolution <- suppressWarnings(as.numeric(resolution))
  if (is.na(resolution)) {
    stop("Cluster resolution must be numeric.", call. = FALSE)
  }

  metadata_changed <- TRUE
  reduction_changed <- FALSE

  if (identical(update_mode, "Update All")) {
    progress_fun(0, message = paste("Updating HVGs...", "0/4"))
    progress_fun(1 / 4, message = paste("Updating PCA...", "1/4"))
    object <- process_fun(
      object,
      normalization = FALSE,
      hvg_method = hvg_method,
      ndims = ndims,
      res = resolution,
      npcs = max(ndims, 30L)
    )
    reduction_changed <- TRUE
  } else if (identical(update_mode, "Update nDim Only")) {
    progress_fun(0, message = paste("Updating UMAP...", "0/2"))
    object <- run_umap_fun(
      object,
      dims = seq_len(ndims),
      reduction = "pca"
    )

    progress_fun(1 / 2, message = paste("Updating Cluster...", "1/2"))
    object <- find_neighbors_fun(
      object,
      dims = seq_len(ndims),
      reduction = "pca"
    )
    object <- find_clusters_fun(
      object,
      resolution = resolution
    )
    reduction_changed <- TRUE
  } else if (identical(update_mode, "Update Res Only")) {
    assayName <- DefaultAssay(object)
    graph_names <- paste(assayName, c("nn", "snn"), sep = "_")
    if (all(graph_names %in% graphs_fun(object))) {
      progress_fun(0, message = paste("Updating Cluster...", "0/1"))
      object <- find_clusters_fun(
        object,
        resolution = resolution
      )
    } else {
      progress_fun(0, message = paste("Updating SNN...", "0/2"))
      object <- find_neighbors_fun(
        object,
        dims = seq_len(ndims),
        reduction = "pca"
      )
      progress_fun(1 / 2, message = paste("Updating Cluster...", "1/2"))
      object <- find_clusters_fun(
        object,
        resolution = resolution
      )
    }
  } else {
    stop("Unknown cluster update mode.", call. = FALSE)
  }

  object <- drop_dense_scale_data(object)
  assert_no_dense_scale_data(object)

  list(
    object = object,
    metadata_changed = metadata_changed,
    reduction_changed = reduction_changed,
    update_mode = update_mode
  )
}

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
        update_result <- apply_cluster_update_mode(
          seuratObj(),
          update_mode = input$updateClusterOpt,
          hvg_method = input$hvgSelectMethod,
          ndims = input$cluster_dims,
          resolution = input$cluster_resolution,
          progress_fun = function(amount, message = NULL) {
            incProgress(amount, message = message)
          }
        )
        seuratObj(update_result$object)

        if (isTRUE(update_result$metadata_changed)) {
          metaUpdateIndicator(metaUpdateIndicator() + 1)
        }
        if (isTRUE(update_result$reduction_changed)) {
          reductionUpdateIndicator(reductionUpdateIndicator() + 1)
        }
        message("ClusterSetting module updated cluster state")
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
