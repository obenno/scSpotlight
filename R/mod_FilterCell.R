#' FilterCell UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
#' @importFrom shinyWidgets sliderTextInput
#'
mod_FilterCell_ui <- function(id) {
  ns <- NS(id)
  tagList(
    cellFiltering_settings <- list(
      shinyWidgets::sliderTextInput(
        inputId = ns("min.cells"),
        label = "Features observed in at least below number of cells:",
        choices = seq(1, 20, by = 1),
        selected = 3,
        grid = TRUE
      ),
      shinyWidgets::sliderTextInput(
        inputId = ns("min.features"),
        label = "Cells containing at least below number of features:",
        choices = seq(50, 500, by = 50),
        selected = 200,
        grid = TRUE
      ),
      numericInput(
        inputId = ns("nFeature_min"),
        label = "nFeature min value",
        value = 200,
        step = 100
      ),
      numericInput(
        inputId = ns("nFeature_max"),
        label = "nFeature max value",
        value = 20000,
        step = 100
      ),
      numericInput(
        inputId = ns("percent.mt_max"),
        label = "Mitochondrial nCount Percentage cutoff",
        value = 50,
        step = 5
      ),
      actionButton(
        inputId = ns("filter_cell"),
        label = "Filter Cells",
        icon = icon("filter"),
        style = "width:200px",
        class = "border border-1 border-primary shadow"
      )
    )
  )
}

#' FilterCell Server Functions
#'
#' @importFrom scales label_comma
#' @importFrom SeuratObject Cells Features Reductions
#' @importFrom DBI dbConnect dbDisconnect
#' @importFrom tibble rownames_to_column
#'
#' @noRd
ensure_filter_cell_qc_metadata <- function(
  object,
  assay = NULL,
  force = FALSE
) {
  assay <- assay %||% DefaultAssay(object)

  misc <- slot(object, "misc")
  cached_assay <- misc$scSpotlight$filterCell$percentMtAssay %||% NULL

  if (
    !isTRUE(force) &&
      "percent.mt" %in% colnames(object[[]]) &&
      is.null(cached_assay)
  ) {
    misc$scSpotlight <- misc$scSpotlight %||% list()
    misc$scSpotlight$filterCell <- misc$scSpotlight$filterCell %||% list()
    misc$scSpotlight$filterCell$percentMtAssay <- assay
    slot(object, "misc") <- misc
    return(object)
  }

  if (
    !isTRUE(force) &&
      "percent.mt" %in% colnames(object[[]]) &&
      identical(cached_assay, assay)
  ) {
    return(object)
  }

  percent_mt <- tryCatch(
    Seurat::PercentageFeatureSet(object, assay = assay, pattern = "^(MT-|mt-)"),
    error = function(...) {
      stats::setNames(
        rep(0, length(SeuratObject::Cells(object))),
        SeuratObject::Cells(object)
      )
    }
  )

  object[["percent.mt"]] <- percent_mt
  misc$scSpotlight <- misc$scSpotlight %||% list()
  misc$scSpotlight$filterCell <- misc$scSpotlight$filterCell %||% list()
  misc$scSpotlight$filterCell$percentMtAssay <- assay
  slot(object, "misc") <- misc
  object
}

#' @noRd
mod_FilterCell_server <- function(
  id,
  seuratObj,
  selectedAssay,
  hvgSelectMethod,
  clusterDims,
  clusterResolution,
  geneUpdateIndicator,
  metaUpdateIndicator,
  reductionUpdateIndicator
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    observeEvent(input$filter_cell, {
      req(seuratObj())
      withProgress(message = "Filtering Cells & Updating Reductions...", {
        obj <- ensure_filter_cell_qc_metadata(
          seuratObj(),
          assay = selectedAssay()
        )
        nGeneColName <- paste0("nFeature_", selectedAssay())
        selectedCells <- obj[[]] %>%
          filter(
            !!as.symbol(nGeneColName) > input$nFeature_min,
            !!as.symbol(nGeneColName) < input$nFeature_max,
            percent.mt < input$percent.mt_max
          ) %>%
          rownames()
        obj <- subset(obj, cells = selectedCells)
        obj <- standard_process_seurat(
          obj,
          normalization = FALSE,
          hvg_method = hvgSelectMethod(),
          ndims = clusterDims(),
          res = clusterResolution(),
          backend_root = file.path(session$userData$backendDir, "layers")
        )
        seuratObj(obj)
      })

      nCells <- length(Cells(seuratObj()))
      showNotification(
        ui = paste0(scales::label_comma()(nCells), " Cells Left."),
        action = NULL,
        duration = 5,
        closeButton = TRUE,
        type = "message",
        session = session
      )

      message("FilterCell module updated metadata and reduction")
      geneUpdateIndicator(geneUpdateIndicator() + 1)
      metaUpdateIndicator(metaUpdateIndicator() + 1)
      reductionUpdateIndicator(reductionUpdateIndicator() + 1)
    })
  })
}

## To be copied in the UI
# mod_FilterCell_ui("FilterCell_1")

## To be copied in the server
# mod_FilterCell_server("FilterCell_1")
