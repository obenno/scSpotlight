make_analysis_contract_object <- function() {
  counts <- Matrix::Matrix(
    c(
      1, 0, 2,
      0, 3, 0,
      4, 0, 5,
      0, 6, 1
    ),
    nrow = 3,
    sparse = TRUE
  )
  rownames(counts) <- c("GeneA", "GeneB", "GeneC")
  colnames(counts) <- paste0("Cell", seq_len(ncol(counts)))

  object <- Seurat::CreateSeuratObject(counts = counts)
  object <- getFromNamespace("ensure_assay5", "scSpotlight")(
    object,
    assay = "RNA"
  )
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts
  object$cluster <- factor(c("alpha", "beta", "alpha", "gamma"))
  object$quality <- c(0.1, Inf, NaN, 0.4)

  object[["umap"]] <- Seurat::CreateDimReducObject(
    embeddings = matrix(
      c(
        1, 2, 3, 4,
        5, 6, 7, 8
      ),
      nrow = 4,
      dimnames = list(colnames(counts), c("UMAP_1", "UMAP_2"))
    ),
    key = "UMAP_",
    assay = "RNA"
  )
  object[["pca"]] <- Seurat::CreateDimReducObject(
    embeddings = matrix(
      c(
        11, 12, 13, 14,
        21, 22, 23, 24
      ),
      nrow = 4,
      dimnames = list(colnames(counts), c("PC_1", "PC_2"))
    ),
    stdev = c(2.5, 1.25),
    key = "PC_",
    assay = "RNA"
  )

  object
}

test_that("Analysis Mode backend helpers expose Seurat/BPCells seams", {
  skip_if_not_installed("Seurat")

  get_backend_metadata <- getFromNamespace("get_backend_metadata", "scSpotlight")
  get_backend_features <- getFromNamespace("get_backend_features", "scSpotlight")
  get_backend_reduction_names <- getFromNamespace(
    "get_backend_reduction_names",
    "scSpotlight"
  )
  get_backend_reduction <- getFromNamespace(
    "get_backend_reduction",
    "scSpotlight"
  )
  get_backend_expr <- getFromNamespace("get_backend_expr", "scSpotlight")
  get_backend_pca_stdev <- getFromNamespace(
    "get_backend_pca_stdev",
    "scSpotlight"
  )

  object <- make_analysis_contract_object()

  metadata <- get_backend_metadata(object, cols = c("cluster", "quality"))
  expect_equal(rownames(metadata), colnames(object))
  expect_equal(as.character(metadata$cluster), c("alpha", "beta", "alpha", "gamma"))
  expect_equal(metadata$quality, c(0.1, Inf, NaN, 0.4))

  expect_equal(
    get_backend_features(object, assay = "RNA", layer = "data"),
    c("GeneA", "GeneB", "GeneC")
  )
  expect_equal(get_backend_reduction_names(object), c("umap", "pca"))

  umap <- get_backend_reduction(object, "umap")
  expect_identical(names(umap), c("X", "Y"))
  expect_equal(umap$X, c(1, 2, 3, 4))
  expect_equal(umap$Y, c(5, 6, 7, 8))

  expect_equal(get_backend_pca_stdev(object), c(2.5, 1.25))
  expect_equal(
    get_backend_expr(object, assay = "RNA", features = "GeneB", layer = "data")$GeneB,
    c(0, 3, 0, 6)
  )
})

test_that("Analysis Mode transfer adapters write Arrow IPC without mirrored DuckDB runtime", {
  skip_if_not_installed("Seurat")
  skip_if_not_installed("arrow")
  skip_if_not_installed("BPCells")

  ensure_bpcells_backing <- getFromNamespace(
    "ensure_bpcells_backing",
    "scSpotlight"
  )
  prepare_backend_metadata_transfer <- getFromNamespace(
    "prepare_backend_metadata_transfer",
    "scSpotlight"
  )
  write_backend_metadata_transfer <- getFromNamespace(
    "write_backend_metadata_transfer",
    "scSpotlight"
  )
  prepare_backend_reduction_transfer <- getFromNamespace(
    "prepare_backend_reduction_transfer",
    "scSpotlight"
  )
  write_backend_reduction_transfer <- getFromNamespace(
    "write_backend_reduction_transfer",
    "scSpotlight"
  )
  write_backend_pca_stdev_transfer <- getFromNamespace(
    "write_backend_pca_stdev_transfer",
    "scSpotlight"
  )
  prepare_backend_expression_transfer <- getFromNamespace(
    "prepare_backend_expression_transfer",
    "scSpotlight"
  )
  write_backend_expression_transfer <- getFromNamespace(
    "write_backend_expression_transfer",
    "scSpotlight"
  )

  object <- make_analysis_contract_object()
  work_dir <- tempfile("analysis_contract_")
  backend_root <- file.path(work_dir, "backend")
  transfer_dir <- file.path(work_dir, "transfer")
  dir.create(file.path(transfer_dir, "meta"), recursive = TRUE)
  dir.create(file.path(transfer_dir, "reduction"), recursive = TRUE)
  dir.create(file.path(transfer_dir, "expr"), recursive = TRUE)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  object <- ensure_bpcells_backing(
    object,
    root_dir = backend_root,
    assays = "RNA",
    layers = "data"
  )

  metadata_transfer <- prepare_backend_metadata_transfer(
    object,
    dir_path = file.path(transfer_dir, "meta"),
    meta_version = 1L,
    cols = c("cluster", "quality"),
    resource_prefix = "data-test-session"
  )
  expect_equal(metadata_transfer$backend, "data_frame")
  metadata_payload <- write_backend_metadata_transfer(metadata_transfer)
  metadata_table <- arrow::read_ipc_stream(metadata_transfer$filePath)
  expect_equal(metadata_payload$cols, c("cluster", "quality"))
  expect_equal(as.vector(metadata_table$cluster), c("alpha", "beta", "alpha", "gamma"))
  expect_equal(as.numeric(metadata_table$quality), c(0.1, NA, NA, 0.4))
  expect_equal(as.integer(metadata_table$cells), 0:(ncol(object) - 1L))

  reduction_transfer <- prepare_backend_reduction_transfer(
    object,
    reduction_name = "umap",
    dir_path = file.path(transfer_dir, "reduction"),
    reduction_version = 2L,
    resource_prefix = "data-test-session"
  )
  expect_equal(reduction_transfer$backend, "data_frame")
  reduction_payload <- write_backend_reduction_transfer(reduction_transfer)
  reduction_table <- arrow::read_ipc_stream(reduction_transfer$filePath)
  expect_equal(reduction_payload$reductionName, "umap")
  expect_identical(names(reduction_table), c("X", "Y"))
  expect_equal(as.numeric(reduction_table$X), c(1, 2, 3, 4))
  expect_equal(as.numeric(reduction_table$Y), c(5, 6, 7, 8))

  pca_payload <- write_backend_pca_stdev_transfer(
    object,
    dir_path = file.path(transfer_dir, "reduction"),
    reduction_version = 3L,
    resource_prefix = "data-test-session"
  )
  expect_false(is.null(pca_payload$stdevFile))
  pca_table <- arrow::read_ipc_stream(
    file.path(transfer_dir, "reduction", pca_payload$stdevFile)
  )
  expect_identical(names(pca_table), "stdev")
  expect_equal(as.numeric(pca_table$stdev), c(2.5, 1.25))

  object_without_pca <- object
  object_without_pca[["pca"]] <- NULL
  pca_missing_payload <- write_backend_pca_stdev_transfer(
    object_without_pca,
    dir_path = file.path(transfer_dir, "reduction"),
    reduction_version = 4L,
    resource_prefix = "data-test-session"
  )
  expect_null(pca_missing_payload$stdevFile)

  expression_transfer <- prepare_backend_expression_transfer(
    object,
    assay = "RNA",
    feature = "GeneC",
    dir_path = file.path(transfer_dir, "expr"),
    expr_version = 5L,
    backend_root = backend_root,
    resource_prefix = "data-test-session"
  )
  expect_equal(expression_transfer$backend, "bpcells")
  expect_setequal(
    names(expression_transfer),
    c("backend", "matrix_dir", "feature", "assay", "layer", "output_file", "payload")
  )
  expect_true(dir.exists(expression_transfer$matrix_dir))
  expect_equal(expression_transfer$feature, "GeneC")
  expect_equal(expression_transfer$assay, "RNA")
  expect_equal(expression_transfer$layer, "data")
  expect_false(any(c("object", "seuratObj", "data") %in% names(expression_transfer)))
  expect_false(any(c("query_plan", "duckdb") %in% names(expression_transfer)))
  expect_identical(
    names(expression_transfer$payload),
    c("geneName", "assay", "exprVersion", "exprFile", "resourcePrefix")
  )
  expect_equal(expression_transfer$payload$exprFile, basename(expression_transfer$output_file))
  expect_false(any(grepl("/", unlist(expression_transfer$payload), fixed = TRUE)))

  expression_payload <- write_backend_expression_transfer(expression_transfer)
  expression_table <- arrow::read_ipc_stream(expression_transfer$output_file)
  expect_equal(expression_payload$geneName, "GeneC")
  expect_equal(as.numeric(expression_table$expr), c(2, 0, 5, 1))
})

test_that("Analysis Mode source guards keep futures path-based and DuckDB-free", {
  adapter_path <- test_path("..", "..", "R", "fct_backend_transfer_adapter.R")
  input_feature_path <- test_path("..", "..", "R", "mod_InputFeature.R")
  skip_if_not(file.exists(adapter_path))
  skip_if_not(file.exists(input_feature_path))

  adapter_source <- readLines(adapter_path, warn = FALSE)
  input_feature_source <- readLines(input_feature_path, warn = FALSE)

  expect_false(any(grepl(
    "DBI::dbConnect|duckdb::duckdb|query_duck",
    adapter_source
  )))
  expect_false(any(grepl(
    "DBI::dbConnect|duckdb::duckdb|query_duck",
    input_feature_source
  )))

  process_start <- grep(
    "process_next_expression_transfer <- function",
    input_feature_source,
    fixed = TRUE
  )[[1]]
  invoke_start <- grep(
    "invoke_expression_transfer <- function",
    input_feature_source,
    fixed = TRUE
  )[[1]]
  promise_body_source <- input_feature_source[seq(process_start, invoke_start - 1L)]
  invoke_source <- input_feature_source[seq(invoke_start, length(input_feature_source))]

  expect_true(any(grepl("future_promise", promise_body_source, fixed = TRUE)))
  expect_false(any(grepl("seuratObj\\(\\)", promise_body_source)))
  expect_false(any(grepl(
    "prepare_backend_expression_transfer",
    promise_body_source,
    fixed = TRUE
  )))
  expect_true(any(grepl(
    "prepare_backend_expression_transfer",
    invoke_source,
    fixed = TRUE
  )))
})
