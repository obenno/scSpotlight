test_that("write_scspotlight_bundle writes loadable BPCells bundles", {
  skip_if_not_installed("BPCells")
  skip_if_not_installed("Seurat")

  write_scspotlight_bundle <- getFromNamespace("write_scspotlight_bundle", "scSpotlight")
  load_scspotlight_bundle <- getFromNamespace("load_scspotlight_bundle", "scSpotlight")
  ensure_assay5 <- getFromNamespace("ensure_assay5", "scSpotlight")
  ensure_bpcells_backing <- getFromNamespace("ensure_bpcells_backing", "scSpotlight")

  counts <- as(Matrix::Matrix(matrix(c(1, 0, 2, 3), nrow = 2), sparse = TRUE), "dgCMatrix")
  rownames(counts) <- c("g1", "g2")
  colnames(counts) <- c("c1", "c2")

  object <- Seurat::CreateSeuratObject(counts = counts)
  object <- ensure_assay5(object, assay = "RNA")
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts
  object <- ensure_bpcells_backing(
    object,
    root_dir = tempfile("bundle_backend_"),
    assays = "RNA",
    layers = c("counts", "data")
  )

  bundle_dir <- tempfile("bundle_write_")
  dir.create(bundle_dir)
  on.exit(unlink(bundle_dir, recursive = TRUE, force = TRUE), add = TRUE)

  bundle_file <- file.path(bundle_dir, "object.Rds")
  write_scspotlight_bundle(object, bundle_dir, file_name = basename(bundle_file))

  expect_true(file.exists(bundle_file))
  expect_true(file.exists(file.path(bundle_dir, "supporting", "RNA", "counts", "version")))
  expect_true(file.exists(file.path(bundle_dir, "supporting", "RNA", "data", "version")))

  loaded <- load_scspotlight_bundle(bundle_file)

  expect_s4_class(loaded, "Seurat")
  expect_setequal(SeuratObject::Layers(loaded[["RNA"]]), c("counts", "data"))
})
