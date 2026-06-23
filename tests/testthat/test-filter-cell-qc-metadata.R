test_that("filter cell QC helper computes missing percent.mt", {
  skip_if_not_installed("Seurat")

  ensure_filter_cell_qc_metadata <- getFromNamespace(
    "ensure_filter_cell_qc_metadata",
    "scSpotlight"
  )

  counts <- methods::as(
    Matrix::Matrix(matrix(c(5, 1, 0, 3), nrow = 2), sparse = TRUE),
    "dgCMatrix"
  )
  rownames(counts) <- c("MT-CO1", "GeneA")
  colnames(counts) <- c("cell1", "cell2")

  object <- Seurat::CreateSeuratObject(counts = counts)

  object <- ensure_filter_cell_qc_metadata(object)

  expect_true("percent.mt" %in% colnames(object[[]]))
  expect_equal(unname(object[[]][, "percent.mt"]), c(5 / 6 * 100, 0))
})

test_that("filter cell QC helper preserves existing percent.mt", {
  skip_if_not_installed("Seurat")

  ensure_filter_cell_qc_metadata <- getFromNamespace(
    "ensure_filter_cell_qc_metadata",
    "scSpotlight"
  )

  counts <- methods::as(
    Matrix::Matrix(matrix(c(1, 0, 2, 3), nrow = 2), sparse = TRUE),
    "dgCMatrix"
  )
  rownames(counts) <- c("GeneA", "GeneB")
  colnames(counts) <- c("cell1", "cell2")

  object <- Seurat::CreateSeuratObject(counts = counts)
  object[["percent.mt"]] <- stats::setNames(c(17, 17), c("cell1", "cell2"))

  object <- ensure_filter_cell_qc_metadata(object)

  expect_equal(unname(object[[]][, "percent.mt"]), c(17, 17))
})

test_that("filter cell QC helper recomputes percent.mt when assay changes", {
  skip_if_not_installed("Seurat")

  ensure_filter_cell_qc_metadata <- getFromNamespace(
    "ensure_filter_cell_qc_metadata",
    "scSpotlight"
  )

  rna_counts <- methods::as(
    Matrix::Matrix(matrix(c(5, 1, 0, 3), nrow = 2), sparse = TRUE),
    "dgCMatrix"
  )
  rownames(rna_counts) <- c("MT-CO1", "GeneA")
  colnames(rna_counts) <- c("cell1", "cell2")

  adt_counts <- methods::as(
    Matrix::Matrix(matrix(c(0, 2, 5, 1), nrow = 2), sparse = TRUE),
    "dgCMatrix"
  )
  rownames(adt_counts) <- c("MT-ADT", "MarkerA")
  colnames(adt_counts) <- c("cell1", "cell2")

  object <- Seurat::CreateSeuratObject(counts = rna_counts)
  object[["ADT"]] <- SeuratObject::CreateAssay5Object(counts = adt_counts)

  object <- ensure_filter_cell_qc_metadata(object, assay = "RNA")
  expect_equal(unname(object[[]][, "percent.mt"]), c(5 / 6 * 100, 0))

  object <- ensure_filter_cell_qc_metadata(object, assay = "ADT")
  expect_equal(unname(object[[]][, "percent.mt"]), c(0, 5 / 6 * 100))
})

test_that("safe subset helper rejects stale filter selections before empty Seurat subsets", {
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
    input_label = "Filter selection"
  )

  expect_identical(colnames(filtered), c("cell1", "cell3"))
  expect_false("scale.data" %in% SeuratObject::Layers(filtered[["RNA"]]))
  expect_error(
    safe_subset_seurat_object(
      object,
      cells = c("stale", "missing"),
      input_label = "Filter selection"
    ),
    "Filter selection did not match any cells",
    fixed = TRUE
  )
})
