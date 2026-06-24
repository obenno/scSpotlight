make_subset_counts <- function(n_genes = 6L, n_cells = 5L) {
  counts <- matrix(
    seq_len(n_genes * n_cells),
    nrow = n_genes,
    dimnames = list(
      paste0("Gene", seq_len(n_genes)),
      paste0("Cell", seq_len(n_cells))
    )
  )
  Matrix::Matrix(counts, sparse = TRUE)
}

make_subset_object <- function() {
  object <- Seurat::CreateSeuratObject(counts = make_subset_counts())
  object$cluster <- factor(c("A", "B", "A", "B", "A"))
  object <- Seurat::NormalizeData(object, verbose = FALSE)
  SeuratObject::LayerData(
    object,
    assay = SeuratObject::DefaultAssay(object),
    layer = "scale.data"
  ) <- matrix(
    0,
    nrow = length(SeuratObject::Features(object)),
    ncol = ncol(object),
    dimnames = list(SeuratObject::Features(object), colnames(object))
  )
  object
}

expect_subset_indicator_values <- function(gene, meta, reduction, expected) {
  expect_identical(shiny::isolate(gene()), expected)
  expect_identical(shiny::isolate(meta()), expected)
  expect_identical(shiny::isolate(reduction()), expected)
}

test_that("subset switch rejects empty, invalid, and stale selections without mutation", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  original_value <- shiny::reactiveVal(NULL)
  selected_cells <- shiny::reactiveVal(character(0))
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)

  testServer(
    mod_SubsetCells_server,
    args = list(
      seuratObj = seurat_value,
      seuratObj_orig = original_value,
      selectedCells = selected_cells,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator
    ),
    {
      session$setInputs(subsetData = TRUE)
      expect_identical(colnames(seurat_value()), colnames(object))
      expect_null(original_value())
      expect_subset_indicator_values(gene_indicator, meta_indicator, reduction_indicator, 0)

      selected_cells(c("missing-cell", "also-missing"))
      session$setInputs(subsetData = FALSE)
      session$setInputs(subsetData = TRUE)
      expect_identical(colnames(seurat_value()), colnames(object))
      expect_null(original_value())
      expect_subset_indicator_values(gene_indicator, meta_indicator, reduction_indicator, 0)
    }
  )
})

test_that("valid subset stores the original once, preserves cell order, drops scale.data, and refreshes indicators", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  original_value <- shiny::reactiveVal(NULL)
  selected_cells <- shiny::reactiveVal(c("Cell5", "Cell2", "missing", "Cell2"))
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)
  assert_no_dense_scale_data <- getFromNamespace(
    "assert_no_dense_scale_data",
    "scSpotlight"
  )

  testServer(
    mod_SubsetCells_server,
    args = list(
      seuratObj = seurat_value,
      seuratObj_orig = original_value,
      selectedCells = selected_cells,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator
    ),
    {
      session$setInputs(subsetData = TRUE)
      expect_identical(colnames(seurat_value()), c("Cell2", "Cell5"))
      expect_identical(colnames(original_value()), colnames(object))
      expect_silent(assert_no_dense_scale_data(seurat_value()))
      expect_subset_indicator_values(gene_indicator, meta_indicator, reduction_indicator, 1)

      stored_original <- original_value()
      selected_cells(c("Cell2"))
      session$setInputs(subsetData = TRUE)
      expect_identical(original_value(), stored_original)
      expect_identical(colnames(seurat_value()), c("Cell2", "Cell5"))
      expect_subset_indicator_values(gene_indicator, meta_indicator, reduction_indicator, 1)
    }
  )
})

test_that("restore replaces subset state with original, clears backup, and repeated off toggles are safe", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  original_value <- shiny::reactiveVal(NULL)
  selected_cells <- shiny::reactiveVal(c("Cell1", "Cell3"))
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)

  testServer(
    mod_SubsetCells_server,
    args = list(
      seuratObj = seurat_value,
      seuratObj_orig = original_value,
      selectedCells = selected_cells,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator
    ),
    {
      session$setInputs(subsetData = TRUE)
      expect_identical(colnames(seurat_value()), c("Cell1", "Cell3"))
      expect_false(is.null(original_value()))
      expect_subset_indicator_values(gene_indicator, meta_indicator, reduction_indicator, 1)

      session$setInputs(subsetData = FALSE)
      expect_identical(colnames(seurat_value()), colnames(object))
      expect_null(original_value())
      expect_subset_indicator_values(gene_indicator, meta_indicator, reduction_indicator, 2)

      session$setInputs(subsetData = FALSE)
      expect_identical(colnames(seurat_value()), colnames(object))
      expect_null(original_value())
      expect_subset_indicator_values(gene_indicator, meta_indicator, reduction_indicator, 2)
    }
  )
})
