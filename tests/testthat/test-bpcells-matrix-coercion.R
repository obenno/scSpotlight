test_that("ensure_bpcells_backing accepts non-dgC sparse layers", {
  skip_if_not_installed("BPCells")
  skip_if_not_installed("Seurat")

  ensure_assay5 <- getFromNamespace("ensure_assay5", "scSpotlight")
  ensure_bpcells_backing <- getFromNamespace(
    "ensure_bpcells_backing",
    "scSpotlight"
  )

  sparse_triplet <- methods::as(
    Matrix::Matrix(matrix(c(1, 0, 2, 3), nrow = 2), sparse = TRUE),
    "dgTMatrix"
  )
  rownames(sparse_triplet) <- c("g1", "g2")
  colnames(sparse_triplet) <- c("c1", "c2")

  counts <- methods::as(sparse_triplet, "dgCMatrix")

  object <- Seurat::CreateSeuratObject(counts = counts)
  object <- ensure_assay5(object, assay = "RNA")
  SeuratObject::LayerData(
    object,
    assay = "RNA",
    layer = "data"
  ) <- sparse_triplet

  object <- ensure_bpcells_backing(
    object,
    root_dir = tempfile("bp_coerce_")
  )

  expect_true(inherits(
    SeuratObject::LayerData(object, assay = "RNA", layer = "counts"),
    "IterableMatrix"
  ))
  expect_true(inherits(
    SeuratObject::LayerData(object, assay = "RNA", layer = "data"),
    "IterableMatrix"
  ))
})

test_that("coerce_bpcells_source_matrix rejects unsupported inputs clearly", {
  coerce_bpcells_source_matrix <- getFromNamespace(
    "coerce_bpcells_source_matrix",
    "scSpotlight"
  )

  expect_error(
    coerce_bpcells_source_matrix(data.frame(x = 1)),
    "Unsupported matrix class for BPCells conversion"
  )
})

test_that("ensure_bpcells_backing converts all app-state assay layers when requested", {
  skip_if_not_installed("BPCells")
  skip_if_not_installed("Seurat")

  ensure_bpcells_backing <- getFromNamespace(
    "ensure_bpcells_backing",
    "scSpotlight"
  )
  assert_no_dense_scale_data <- getFromNamespace(
    "assert_no_dense_scale_data",
    "scSpotlight"
  )

  counts <- Matrix::Matrix(
    matrix(c(1, 0, 2, 0, 3, 4, 0, 5, 6), nrow = 3),
    sparse = TRUE
  )
  rownames(counts) <- paste0("gene", seq_len(nrow(counts)))
  colnames(counts) <- paste0("cell", seq_len(ncol(counts)))

  object <- Seurat::CreateSeuratObject(counts = counts)
  object <- Seurat::NormalizeData(object, verbose = FALSE)
  object <- ensure_bpcells_backing(
    object,
    root_dir = tempfile("bp_all_layers_"),
    layers = NULL
  )

  for (layer in SeuratObject::Layers(object[["RNA"]])) {
    expect_true(inherits(
      SeuratObject::LayerData(object, assay = "RNA", layer = layer),
      "IterableMatrix"
    ))
  }
  expect_silent(assert_no_dense_scale_data(object))
})
