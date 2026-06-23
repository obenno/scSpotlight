make_analysis_counts <- function(n_genes = 80L, n_cells = 60L) {
  set.seed(30301)
  counts <- Matrix::rsparsematrix(n_genes, n_cells, density = 0.08)
  counts@x <- abs(counts@x) + 1
  rownames(counts) <- paste0("gene", seq_len(nrow(counts)))
  colnames(counts) <- paste0("cell", seq_len(ncol(counts)))
  methods::as(counts, "dgCMatrix")
}

make_processing_fixture <- function() {
  Seurat::CreateSeuratObject(counts = make_analysis_counts())
}

make_processed_fixture <- function() {
  counts <- make_analysis_counts(n_genes = 12L, n_cells = 8L)
  object <- Seurat::CreateSeuratObject(counts = counts)
  object <- Seurat::NormalizeData(object, verbose = FALSE)
  embeddings <- matrix(
    seq_len(ncol(object) * 2L) / 10,
    nrow = ncol(object),
    ncol = 2L,
    dimnames = list(colnames(object), c("PC_1", "PC_2"))
  )
  object[["pca"]] <- Seurat::CreateDimReducObject(
    embeddings = embeddings,
    stdev = c(1, 0.5),
    assay = SeuratObject::DefaultAssay(object),
    key = "PC_"
  )
  object[["umap"]] <- Seurat::CreateDimReducObject(
    embeddings = embeddings,
    assay = SeuratObject::DefaultAssay(object),
    key = "UMAP_"
  )
  object
}

expect_no_scale_data_layers <- function(object, assays = NULL) {
  if (is.null(assays)) {
    assays <- SeuratObject::Assays(object)
  }
  for (assay in assays) {
    layers <- SeuratObject::Layers(object[[assay]])
    expect_false(
      "scale.data" %in% layers,
      info = paste("Unexpected dense scale.data layer in assay", assay)
    )
  }
}

expect_analysis_loaded_object <- function(object) {
  expect_s4_class(object, "Seurat")
  expect_true("data" %in% SeuratObject::Layers(object[[SeuratObject::DefaultAssay(object)]]))
  expect_gt(length(SeuratObject::Reductions(object)), 0)
  expect_no_scale_data_layers(object)
}

create_10x_archive <- function(parent = tempfile("tenx_fixture_")) {
  skip_if_not_installed("zip")
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  matrix_dir <- file.path(parent, "matrix")
  dir.create(matrix_dir, recursive = TRUE, showWarnings = FALSE)

  counts <- make_analysis_counts(n_genes = 45L, n_cells = 40L)
  Matrix::writeMM(counts, file.path(matrix_dir, "matrix.mtx"))
  writeLines(colnames(counts), file.path(matrix_dir, "barcodes.tsv"))
  write.table(
    data.frame(id = rownames(counts), symbol = rownames(counts)),
    file.path(matrix_dir, "genes.tsv"),
    sep = "\t",
    quote = FALSE,
    row.names = FALSE,
    col.names = FALSE
  )

  archive <- file.path(parent, "matrix.zip")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(parent)
  zip::zipr(archive, files = "matrix")
  archive
}

create_bpcells_bundle_archive <- function(parent = tempfile("bundle_fixture_")) {
  skip_if_not_installed("BPCells")
  skip_if_not_installed("zip")
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  ensure_bpcells_backing <- getFromNamespace("ensure_bpcells_backing", "scSpotlight")
  write_scspotlight_bundle <- getFromNamespace("write_scspotlight_bundle", "scSpotlight")

  object <- make_processed_fixture()
  object <- ensure_bpcells_backing(
    object,
    root_dir = file.path(parent, "source_layers"),
    layers = NULL
  )
  bundle_dir <- file.path(parent, "fixture_bundle")
  write_scspotlight_bundle(object, bundle_dir, file_name = "fixture.Rds")

  archive <- file.path(parent, "fixture_bundle.zip")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(parent)
  zip::zipr(archive, files = "fixture_bundle")
  archive
}

test_that("memory-conserving processing derives state without final dense scale.data", {
  skip_if_not_installed("Seurat")

  run_memory_conserving_processing <- getFromNamespace(
    "run_memory_conserving_processing",
    "scSpotlight"
  )
  assert_no_dense_scale_data <- getFromNamespace(
    "assert_no_dense_scale_data",
    "scSpotlight"
  )

  object <- make_processing_fixture()
  processed <- suppressWarnings(suppressMessages(
    run_memory_conserving_processing(
      object,
      normalization = TRUE,
      hvg_method = "vst",
      ndims = 2L,
      res = 0.2,
      npcs = 5L
    )
  ))

  expect_gt(length(Seurat::VariableFeatures(processed)), 0)
  expect_true("pca" %in% SeuratObject::Reductions(processed))
  expect_true("umap" %in% SeuratObject::Reductions(processed))
  expect_gt(length(SeuratObject::Graphs(processed)), 0)
  expect_true("seurat_clusters" %in% colnames(processed[[]]))
  expect_no_scale_data_layers(processed)
  expect_silent(assert_no_dense_scale_data(processed))
})

test_that("memory-conserving PCA fallback drops temporary scale.data", {
  skip_if_not_installed("Seurat")

  run_memory_conserving_pca <- getFromNamespace(
    "run_memory_conserving_pca",
    "scSpotlight"
  )
  assert_no_dense_scale_data <- getFromNamespace(
    "assert_no_dense_scale_data",
    "scSpotlight"
  )

  object <- make_processing_fixture()
  object <- Seurat::NormalizeData(object, verbose = FALSE)
  object <- Seurat::FindVariableFeatures(
    object,
    selection.method = "vst",
    nfeatures = 30L,
    verbose = FALSE
  )

  pca_object <- suppressWarnings(suppressMessages(
    run_memory_conserving_pca(object, npcs = 5L)
  ))

  expect_true("pca" %in% SeuratObject::Reductions(pca_object))
  expect_no_scale_data_layers(pca_object)
  expect_silent(assert_no_dense_scale_data(pca_object))
})

test_that("Analysis RDS loading fixture uses validation, backing, and no-dense-scale guards", {
  skip_if_not_installed("BPCells")

  load_analysis_input_file <- getFromNamespace(
    "load_analysis_input_file",
    "scSpotlight"
  )
  object_path <- tempfile("analysis_fixture_", fileext = ".Rds")
  saveRDS(make_processed_fixture(), object_path)

  loaded <- load_analysis_input_file(
    object_path,
    backend_root = tempfile("analysis_rds_layers_"),
    nDims = 2L,
    resolution = 0.2
  )

  expect_analysis_loaded_object(loaded)
  expect_silent(getFromNamespace("assert_scspotlight_backend", "scSpotlight")(loaded))
})

test_that("Analysis h5ad loading fixture uses BPCells-backed import when dependencies exist", {
  skip_if_not_installed("BPCells")
  skip_if_not_installed("rhdf5")

  load_analysis_input_file <- getFromNamespace(
    "load_analysis_input_file",
    "scSpotlight"
  )
  ensure_bpcells_backing <- getFromNamespace("ensure_bpcells_backing", "scSpotlight")

  fixture_root <- tempfile("h5ad_fixture_")
  dir.create(fixture_root, recursive = TRUE, showWarnings = FALSE)
  object <- make_processed_fixture()
  object <- ensure_bpcells_backing(
    object,
    root_dir = file.path(fixture_root, "source_layers"),
    layers = NULL
  )
  h5ad_path <- file.path(fixture_root, "fixture.h5ad")
  scSpotlight::write_h5ad_scanpy(object, h5ad_path, gzip_level = 0L)

  loaded <- load_analysis_input_file(
    h5ad_path,
    backend_root = file.path(fixture_root, "loaded_layers"),
    nDims = 2L,
    resolution = 0.2
  )

  expect_analysis_loaded_object(loaded)
  expect_silent(getFromNamespace("assert_scspotlight_backend", "scSpotlight")(loaded))
})

test_that("Analysis compressed 10x-style archive loading fixture is processable and safe", {
  skip_if_not_installed("BPCells")

  load_analysis_input_file <- getFromNamespace(
    "load_analysis_input_file",
    "scSpotlight"
  )
  archive <- create_10x_archive()

  loaded <- suppressWarnings(suppressMessages(load_analysis_input_file(
    archive,
    backend_root = tempfile("analysis_10x_layers_"),
    nDims = 2L,
    resolution = 0.2
  )))

  expect_analysis_loaded_object(loaded)
  expect_true("umap" %in% SeuratObject::Reductions(loaded))
  expect_silent(getFromNamespace("assert_scspotlight_backend", "scSpotlight")(loaded))
})

test_that("Analysis compressed BPCells bundle archive loading fixture is accepted", {
  skip_if_not_installed("BPCells")

  load_analysis_input_file <- getFromNamespace(
    "load_analysis_input_file",
    "scSpotlight"
  )
  archive <- create_bpcells_bundle_archive()

  loaded <- load_analysis_input_file(
    archive,
    backend_root = tempfile("analysis_bundle_layers_"),
    nDims = 2L,
    resolution = 0.2
  )

  expect_analysis_loaded_object(loaded)
  expect_silent(getFromNamespace("assert_scspotlight_backend", "scSpotlight")(loaded))
})

test_that("Explore parquet archives are rejected by Analysis loading", {
  load_analysis_input_file <- getFromNamespace(
    "load_analysis_input_file",
    "scSpotlight"
  )
  explore_archive <- tempfile("bad_bundle_", fileext = ".explore-parquet.zip")
  file.create(explore_archive)

  expect_error(
    load_analysis_input_file(explore_archive, backend_root = tempfile("analysis_layers_")),
    "Explore Parquet bundle"
  )
})

test_that("loading and processing source guards block high-memory Analysis regressions", {
  mod_source <- paste(readLines(testthat::test_path("..", "..", "R", "mod_dataInput.R"), warn = FALSE), collapse = "\n")
  backend_source <- paste(readLines(testthat::test_path("..", "..", "R", "fct_bpcells_backend.R"), warn = FALSE), collapse = "\n")
  guarded_source <- paste(mod_source, backend_source, sep = "\n")

  expect_false(grepl("duckdb::|DBI::dbConnect", guarded_source))
  expect_false(grepl("future_promise\\s*\\([^)]*(seuratObj|Seurat|BPCells)", guarded_source))
  expect_false(grepl("sendCustomMessage\\s*\\([^)]*toJSON", mod_source))

  expect_match(mod_source, "validate_seuratRDS", fixed = TRUE)
  expect_match(mod_source, "ensure_bpcells_backing", fixed = TRUE)
  expect_match(mod_source, "standard_process_seurat", fixed = TRUE)
  expect_match(backend_source, "drop_dense_scale_data", fixed = TRUE)
  expect_match(backend_source, "assert_no_dense_scale_data", fixed = TRUE)
})
