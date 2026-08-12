make_view_filter_object <- function(include_percent_mt = TRUE) {
  counts <- methods::as(
    Matrix::Matrix(
      matrix(c(5, 1, 0, 3, 2, 4, 1, 0), nrow = 2),
      sparse = TRUE
    ),
    "dgCMatrix"
  )
  rownames(counts) <- c("GeneA", "GeneB")
  colnames(counts) <- c("cell1", "cell2", "cell3", "cell4")

  object <- Seurat::CreateSeuratObject(counts = counts)
  object[["nFeature_RNA"]] <- stats::setNames(
    c(100, 300, 300, 400),
    colnames(object)
  )
  if (isTRUE(include_percent_mt)) {
    object[["percent.mt"]] <- stats::setNames(
      c(5, 40, 55, NA_real_),
      colnames(object)
    )
  }
  object$cluster <- factor(c("A", "A", "B", "B"))
  object
}

test_that("View Filter predicates resolve visible cells without mutating the Analysis", {
  skip_if_not_installed("Seurat")

  new_view_filter_spec <- getFromNamespace(
    "new_view_filter_spec",
    "scSpotlight"
  )
  resolve_view_filter_cells <- getFromNamespace(
    "resolve_view_filter_cells",
    "scSpotlight"
  )

  object <- make_view_filter_object()
  before_cells <- colnames(object)
  before_metadata <- object[[]]
  view_filter <- new_view_filter_spec(
    object = object,
    assay = "RNA",
    n_feature_min = 150,
    n_feature_max = 350,
    percent_mt_max = 50
  )

  expect_equal(
    view_filter,
    list(
      nFeature = list(column = "nFeature_RNA", min = 150, max = 350),
      percentMt = list(column = "percent.mt", max = 50)
    )
  )
  expect_identical(resolve_view_filter_cells(object, view_filter), "cell2")
  expect_identical(colnames(object), before_cells)
  expect_equal(object[[]], before_metadata)
})

test_that("View Filter rejects unavailable QC metadata without adding it", {
  skip_if_not_installed("Seurat")

  new_view_filter_spec <- getFromNamespace(
    "new_view_filter_spec",
    "scSpotlight"
  )

  object <- make_view_filter_object(include_percent_mt = FALSE)

  expect_error(
    new_view_filter_spec(
      object = object,
      assay = "RNA",
      n_feature_min = 150,
      n_feature_max = 350,
      percent_mt_max = 50
    ),
    "requires the selected assay QC metadata",
    fixed = TRUE
  )
  expect_false("percent.mt" %in% colnames(object[[]]))
})

test_that("Filter Cells module changes only temporary View Filter state", {
  skip_if_not_installed("Seurat")

  object <- make_view_filter_object()
  seurat_value <- shiny::reactiveVal(object)
  view_filter <- shiny::reactiveVal(NULL)
  updates <- 0L
  set_view_filter <- function(next_filter) {
    if (identical(shiny::isolate(view_filter()), next_filter)) {
      return(invisible(FALSE))
    }
    view_filter(next_filter)
    updates <<- updates + 1L
    invisible(TRUE)
  }

  testServer(
    mod_FilterCell_server,
    args = list(
      seuratObj = seurat_value,
      selectedAssay = shiny::reactive("RNA"),
      setViewFilter = set_view_filter
    ),
    {
      session$setInputs(
        nFeature_min = 150,
        nFeature_max = 350,
        percent.mt_max = 50
      )
      session$setInputs(filter_cell = 1)

      expect_identical(colnames(shiny::isolate(seurat_value())), colnames(object))
      expect_equal(shiny::isolate(view_filter()), list(
        nFeature = list(column = "nFeature_RNA", min = 150, max = 350),
        percentMt = list(column = "percent.mt", max = 50)
      ))
      expect_identical(updates, 1L)

      session$setInputs(clear_view_filter = 1)
      expect_null(shiny::isolate(view_filter()))
      expect_identical(updates, 2L)
    }
  )
})

test_that("stale filtered lasso selections cannot become a Subset", {
  skip_if_not_installed("Seurat")

  object <- make_view_filter_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- getFromNamespace(
    "new_analysis_transition_controller",
    "scSpotlight"
  )(seurat_value)
  metadata_version <- shiny::reactiveVal(1L)
  view_filter <- shiny::reactiveVal(list(
    nFeature = list(column = "nFeature_RNA", min = 150, max = 350),
    percentMt = list(column = "percent.mt", max = 50)
  ))
  view_filter_version <- shiny::reactiveVal(2L)
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)

  testServer(
    mod_AssignCellCluster_server,
    args = list(
      seuratObj = seurat_value,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator,
      analysisTransition = analysis_transition,
      currentMetadataVersion = metadata_version,
      currentGroupBy = shiny::reactive("cluster"),
      currentSplitBy = shiny::reactive("None"),
      currentViewFilter = view_filter,
      currentViewFilterVersion = view_filter_version
    ),
    {
      session$setInputs(
        selectedCellsPayload = list(
          cells = "cell1",
          metaVersion = 1L,
          analysisVersion = 0L,
          analysisLineageId = 1L,
          viewFilterVersion = 1L
        )
      )
      session$setInputs("subsetCells-subsetData" = TRUE)

      expect_identical(colnames(shiny::isolate(seurat_value())), colnames(object))
      expect_identical(analysis_transition$version(), 0L)
      expect_identical(shiny::isolate(gene_indicator()), 0)
      expect_identical(shiny::isolate(meta_indicator()), 0)
      expect_identical(shiny::isolate(reduction_indicator()), 0)
    }
  )
})

test_that("safe subset helper preserves source order for selected cells", {
  skip_if_not_installed("Seurat")

  safe_subset_seurat_object <- getFromNamespace(
    "safe_subset_seurat_object",
    "scSpotlight"
  )

  counts <- methods::as(
    Matrix::Matrix(matrix(c(1, 0, 2, 3, 4, 0), nrow = 2), sparse = TRUE),
    "dgCMatrix"
  )
  rownames(counts) <- c("GeneA", "GeneB")
  colnames(counts) <- c("cell1", "cell2", "cell3")

  object <- Seurat::CreateSeuratObject(counts = counts)
  SeuratObject::LayerData(object, assay = "RNA", layer = "scale.data") <- matrix(
    0,
    nrow = nrow(object),
    ncol = ncol(object),
    dimnames = list(rownames(object), colnames(object))
  )

  filtered <- safe_subset_seurat_object(
    object,
    cells = c("cell3", "stale", "cell1"),
    input_label = "Selected cells"
  )

  expect_identical(colnames(filtered), c("cell1", "cell3"))
  expect_false("scale.data" %in% SeuratObject::Layers(filtered[["RNA"]]))
  expect_error(
    safe_subset_seurat_object(
      object,
      cells = c("stale", "missing"),
      input_label = "Selected cells"
    ),
    "Selected cells did not match any cells",
    fixed = TRUE
  )
})
