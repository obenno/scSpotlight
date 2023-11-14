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
mod_ClusterSetting_ui <- function(id){
  ns <- NS(id)
  tagList(
      selectInput(
          inputId = ns("hvgSelectMethod"),
          label = "HVG Selection Method",
          choices = c("vst", "mean.var.plot", "dispersion"),
          selected = "vst",
          multiple = FALSE,
          selectize = TRUE,
          width = NULL
      ),
      shinyWidgets::sliderTextInput(
          inputId = ns("cluster_dims"),
          label = "Choose number of dims",
          selected = 30,
          choices = seq(10, 100, by=10),
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
#' @noRd 
mod_ClusterSetting_server <- function(id,
                                      seuratObj){
  moduleServer( id, function(input, output, session){
    ns <- session$ns
    ## Update UMAP/TSNE reduction
    observeEvent(input$updateCluster, {
        req(seuratObj())
        withProgress({

            if(input$updateClusterOpt == "Update All"){
                incProgress(0, message = paste("Updating HVGs...", "0/4"))
                obj <- seuratObj()
                if(input$hvgSelectMethod == "vst"){
                    obj <- FindVariableFeatures(obj, selection.method = input$hvgSelectMethod, layer = "counts")
                }else{
                    obj <- FindVariableFeatures(obj, selection.method = input$hvgSelectMethod, layer = "data")
                }

                incProgress(1/4, message = paste("Updating PCA...", "1/4"))
                obj <- ScaleData(obj)
                obj <- RunPCA(obj)

                incProgress(1/4, message = paste("Updating UMAP...", "2/4"))
                obj <- RunUMAP(obj, dims = 1:input$cluster_dims)

                incProgress(1/4, message = paste("Updating Cluster...", "3/4"))
                obj <- FindNeighbors(obj, dims = 1:input$cluster_dims)
                obj <- FindClusters(obj, resolution = input$cluster_resolution)

            }else if(input$updateClusterOpt == "Update nDim Only"){
                incProgress(0, message = paste("Updating UMAP...", "0/2"))
                obj <- RunUMAP(seuratObj(), dims = 1:input$cluster_dims)

                incProgress(1/2, message = paste("Updating Cluster...", "1/2"))
                obj <- FindNeighbors(obj, dims = 1:input$cluster_dims)
                obj <- FindClusters(obj, resolution = input$cluster_resolution)
            }else{
                obj <- seuratObj()
                assayName <- DefaultAssay(obj)
                graph_names <- paste(assayName, c("nn", "snn"), sep = "_")
                if(all(graph_names %in% Graphs(obj))){
                    incProgress(0, message = paste("Updating Cluster...", "0/1"))
                    obj <- FindClusters(obj, resolution = input$cluster_resolution)
                }else{
                    incProgress(0, message = paste("Updating SNN...", "0/2"))
                    obj <- FindNeighbors(obj, dims = 1:input$cluster_dims)
                    incProgress(1/2, message = paste("Updating Cluster...", "1/2"))
                    obj <- FindClusters(obj, resolution = input$cluster_resolution)
                }
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
