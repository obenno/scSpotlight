test_that("Explore Cell identity is independent of Arrow batch boundaries", {
  skip_if_not_installed("arrow")
  cell_ids <- c("c1", "cell-two", "三", "last", "é")
  cells_path <- tempfile(fileext = ".parquet")
  on.exit(unlink(cells_path), add = TRUE)
  arrow::write_parquet(
    data.frame(cell_idx = seq_along(cell_ids) - 1L, cell_id = cell_ids),
    cells_path,
    chunk_size = 2L
  )

  expected <- scspotlight_cell_identity(cell_ids)
  for (chunk_size in c(1L, 2L, 3L, 5L)) {
    expect_identical(
      scspotlight_explore_cells_identity(
        cells_path,
        expected_cell_count = length(cell_ids),
        chunk_size = chunk_size
      ),
      expected
    )
  }
  expect_false(identical(expected, scspotlight_cell_identity(rev(cell_ids))))
})

test_that("Explore bundles round-trip backend queries", {
  skip_if_not_installed("Seurat")
  skip_if_not_installed("arrow")

  write_scspotlight_explore_bundle <- getFromNamespace(
    "write_scspotlight_explore_bundle",
    "scSpotlight"
  )
  read_scspotlight_explore_bundle <- getFromNamespace(
    "read_scspotlight_explore_bundle",
    "scSpotlight"
  )
  get_backend_assays <- getFromNamespace("get_backend_assays", "scSpotlight")
  get_backend_default_assay <- getFromNamespace(
    "get_backend_default_assay",
    "scSpotlight"
  )
  get_backend_features <- getFromNamespace(
    "get_backend_features",
    "scSpotlight"
  )
  get_backend_metadata <- getFromNamespace(
    "get_backend_metadata",
    "scSpotlight"
  )
  get_backend_reduction_names <- getFromNamespace(
    "get_backend_reduction_names",
    "scSpotlight"
  )
  get_backend_reduction <- getFromNamespace(
    "get_backend_reduction",
    "scSpotlight"
  )
  get_backend_expr <- getFromNamespace("get_backend_expr", "scSpotlight")

  counts <- Matrix::Matrix(
    c(
      1,
      0,
      3,
      0,
      2,
      0,
      5,
      0,
      4
    ),
    nrow = 3,
    sparse = TRUE
  )
  rownames(counts) <- c("g1", "g2", "g3")
  colnames(counts) <- c("c1", "c2", "c3")

  object <- Seurat::CreateSeuratObject(counts = counts)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts
  object$cluster <- c("a", "b", "a")
  object[["umap"]] <- Seurat::CreateDimReducObject(
    embeddings = matrix(
      c(1, 2, 3, 4, 5, 6),
      nrow = 3,
      dimnames = list(colnames(counts), c("UMAP_1", "UMAP_2"))
    ),
    key = "UMAP_",
    assay = "RNA"
  )

  bundle_dir <- tempfile("explore_bundle_")
  dir.create(bundle_dir)
  on.exit(unlink(bundle_dir, recursive = TRUE, force = TRUE), add = TRUE)

  write_scspotlight_explore_bundle(object, bundle_dir, block_size = 2L)
  bundle <- read_scspotlight_explore_bundle(bundle_dir)

  expect_s3_class(bundle, "scspotlight_explore_bundle")
  expect_equal(bundle$manifest$schema_version, 2L)
  expect_identical(
    bundle$manifest$expression_layout,
    "feature_row_groups_v1"
  )
  expect_match(bundle$cell_identity, "^[0-9a-f]{32}$")
  expect_equal(get_backend_assays(bundle), "RNA")
  expect_equal(get_backend_default_assay(bundle), "RNA")
  expect_equal(get_backend_features(bundle), c("g1", "g2", "g3"))
  expect_equal(
    get_backend_metadata(bundle, cols = "cluster")$cluster,
    c("a", "b", "a")
  )
  expect_equal(get_backend_reduction_names(bundle), "umap")
  expect_equal(get_backend_reduction(bundle, "umap")$X, c(1, 2, 3))
  expect_equal(get_backend_expr(bundle, features = "g3")$g3, c(3, 0, 4))

  invalid_manifest <- bundle$manifest
  invalid_manifest$expression_layout <- "unsupported_layout"
  jsonlite::write_json(
    invalid_manifest,
    file.path(bundle_dir, "manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  expect_error(
    read_scspotlight_explore_bundle(bundle_dir),
    "Unsupported Explore expression layout"
  )

  future_manifest <- bundle$manifest
  future_manifest$schema_version <- 3L
  jsonlite::write_json(
    future_manifest,
    file.path(bundle_dir, "manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  expect_error(
    read_scspotlight_explore_bundle(bundle_dir),
    "Unsupported Explore bundle schema version"
  )

  incomplete_manifest <- bundle$manifest
  incomplete_manifest$cell_identity <- NULL
  jsonlite::write_json(
    incomplete_manifest,
    file.path(bundle_dir, "manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
  expect_error(
    read_scspotlight_explore_bundle(bundle_dir),
    "valid cell_identity"
  )

  tampered_manifest <- bundle$manifest
  tampered_manifest$cell_identity <- "00000000000000000000000000000000"
  jsonlite::write_json(
    tampered_manifest,
    file.path(bundle_dir, "manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  expect_error(
    read_scspotlight_explore_bundle(bundle_dir),
    "does not match canonical Cell IDs"
  )
})

test_that("Explore bundle writer streams bounded expression chunks", {
  explore_bundle_path <- scspotlight_test_source_path(
    "R",
    "fct_explore_bundle.R"
  )
  skip_if_not(file.exists(explore_bundle_path))

  source_lines <- readLines(explore_bundle_path, warn = FALSE)
  writer_start <- grep(
    "write_scspotlight_explore_bundle <- function",
    source_lines,
    fixed = TRUE
  )[[1]]
  next_symbol <- grep(
    "^read_explore_conversion_source <- function",
    source_lines
  )[[1]]
  writer_source <- source_lines[seq(writer_start, next_symbol - 1L)]

  expect_false(any(grepl(
    "order(block_df\\$feature_idx, block_df\\$cell_idx)",
    writer_source
  )))
  expect_false(any(grepl(
    "block_mat <- mat\\[row_idx, , drop = FALSE\\]",
    writer_source
  )))
  expect_match(
    paste(writer_source, collapse = "\n"),
    "explore_write_expression_block(",
    fixed = TRUE
  )
  expect_match(
    paste(writer_source, collapse = "\n"),
    "cell_chunk_size = expression_cell_chunk_size",
    fixed = TRUE
  )
  expression_start <- grep(
    "progress(message = \"Writing expression blocks\")",
    writer_source,
    fixed = TRUE
  )[[1]]
  expect_match(
    paste(writer_source[seq_len(expression_start + 4L)], collapse = "\n"),
    "rm(feature_blocks, object)",
    fixed = TRUE
  )

  writer_helper_start <- grep(
    "explore_write_expression_block <- function",
    source_lines,
    fixed = TRUE
  )[[1]]
  writer_helper_end <- grep(
    "^explore_empty_expression_frame <- function",
    source_lines
  )[[1]]
  writer_helper_source <- source_lines[
    seq(writer_helper_start, writer_helper_end - 1L)
  ]
  expect_match(
    paste(writer_helper_source, collapse = "\n"),
    "row_group_size = scspotlight_expression_export_row_group_size",
    fixed = TRUE
  )
  expect_match(
    paste(writer_helper_source, collapse = "\n"),
    "for (cell_start in seq.int(1L, cell_count, by = cell_chunk_size))",
    fixed = TRUE
  )
  expect_match(
    paste(writer_helper_source, collapse = "\n"),
    "arrow::Table$create",
    fixed = TRUE
  )
  expect_match(
    paste(writer_helper_source, collapse = "\n"),
    "rm(sparse_summary, feature_chunk)",
    fixed = TRUE
  )
  expect_match(
    paste(writer_helper_source, collapse = "\n"),
    "append_feature_rows",
    fixed = TRUE
  )
  expect_match(
    paste(writer_helper_source, collapse = "\n"),
    "row_group_size - buffered_rows",
    fixed = TRUE
  )
  expect_false(any(grepl(
    "Class = \"TsparseMatrix\"",
    writer_helper_source,
    fixed = TRUE
  )))
  expect_match(
    paste(writer_helper_source, collapse = "\n"),
    "temporary_path",
    fixed = TRUE
  )
  expect_match(
    paste(writer_helper_source, collapse = "\n"),
    "file.rename(temporary_path, path)",
    fixed = TRUE
  )

  conversion_start <- grep(
    "convert_to_explore_bundle <- function",
    source_lines,
    fixed = TRUE
  )[[1]]
  conversion_source <- source_lines[seq(conversion_start, length(source_lines))]
  expect_match(
    paste(conversion_source, collapse = "\n"),
    "object = ensure_normalized_layer(",
    fixed = TRUE
  )
  expect_false(any(grepl(
    "^  object <- read_explore_conversion_source",
    conversion_source
  )))
})

test_that("Explore sparse summaries preserve dgCMatrix coordinates", {
  explore_sparse_summary <- getFromNamespace(
    "explore_sparse_summary",
    "scSpotlight"
  )
  mat <- Matrix::sparseMatrix(
    i = c(3L, 1L, 2L, 1L, 3L),
    j = c(1L, 1L, 2L, 4L, 4L),
    x = c(2, 1, 3, 4, 5),
    dims = c(3L, 4L)
  )

  expect_equal(
    explore_sparse_summary(mat),
    data.frame(
      i = c(1L, 3L, 2L, 1L, 3L),
      j = c(1L, 1L, 2L, 4L, 4L),
      x = c(1, 2, 3, 4, 5)
    )
  )
})

test_that("Explore expression row groups are feature-oriented", {
  skip_if_not_installed("arrow")

  explore_write_expression_block <- getFromNamespace(
    "explore_write_expression_block",
    "scSpotlight"
  )
  mat <- Matrix::Matrix(
    c(
      1,
      0,
      3,
      0,
      2,
      0,
      5,
      0,
      4,
      0,
      6,
      0,
      7,
      0,
      8
    ),
    nrow = 3,
    sparse = TRUE
  )
  path <- tempfile("explore_expression_chunk_", fileext = ".parquet")
  on.exit(unlink(path, force = TRUE), add = TRUE)

  explore_write_expression_block(
    mat = mat,
    row_idx = c(1L, 3L),
    path = path,
    cell_chunk_size = 2L,
    feature_batch_size = 1L,
    row_group_size = 2L
  )

  actual <- as.data.frame(arrow::read_parquet(path))
  expected <- data.frame(
    feature_idx = c(0L, 0L, 0L, 2L, 2L, 2L),
    cell_idx = c(0L, 2L, 4L, 0L, 2L, 4L),
    value = c(1, 5, 7, 3, 4, 8)
  )
  expect_equal(actual, expected)

  reader <- arrow::ParquetFileReader$create(path)
  row_groups <- lapply(
    seq.int(0L, reader$num_row_groups - 1L),
    function(row_group) {
      values <- as.data.frame(reader$ReadRowGroup(row_group))
      expect_length(unique(values$feature_idx), 1L)
      expect_true(all(diff(values$cell_idx) >= 0L))
      values
    }
  )
  expect_equal(
    vapply(row_groups, function(values) values$feature_idx[[1]], integer(1)),
    c(0L, 0L, 2L, 2L)
  )
  expect_equal(
    vapply(row_groups, nrow, integer(1)),
    c(2L, 1L, 2L, 1L)
  )
})

test_that("Explore expression block failures preserve destinations and clean up", {
  skip_if_not_installed("arrow")

  explore_write_expression_block <- getFromNamespace(
    "explore_write_expression_block",
    "scSpotlight"
  )
  work_dir <- tempfile("explore_expression_atomic_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  path <- file.path(work_dir, "block_00000.parquet")
  writeLines("existing complete destination", path)
  mat <- Matrix::Matrix(c(1, 0, 0, 2), nrow = 2, sparse = TRUE)

  expect_error(
    explore_write_expression_block(
      mat = mat,
      row_idx = seq_len(nrow(mat)),
      path = path,
      compression = "not-a-codec"
    )
  )
  expect_identical(readLines(path, warn = FALSE), "existing complete destination")
  expect_length(
    list.files(work_dir, pattern = "\\.tmp$", all.files = TRUE),
    0L
  )
})

test_that("Explore bundle root discovery finds archives after extraction", {
  skip_if_not_installed("Seurat")
  skip_if_not_installed("arrow")

  write_scspotlight_explore_bundle <- getFromNamespace(
    "write_scspotlight_explore_bundle",
    "scSpotlight"
  )
  find_scspotlight_explore_bundle_root <- getFromNamespace(
    "find_scspotlight_explore_bundle_root",
    "scSpotlight"
  )
  decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  create_bundle_archive <- getFromNamespace(
    "create_bundle_archive",
    "scSpotlight"
  )

  counts <- Matrix::Matrix(matrix(c(1, 2, 3, 1), nrow = 2), sparse = TRUE)
  rownames(counts) <- c("g1", "g2")
  colnames(counts) <- c("c1", "c2")

  object <- Seurat::CreateSeuratObject(counts = counts)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts
  object[["umap"]] <- Seurat::CreateDimReducObject(
    embeddings = matrix(
      c(1, 2, 3, 4),
      nrow = 2,
      dimnames = list(colnames(counts), c("UMAP_1", "UMAP_2"))
    ),
    key = "UMAP_",
    assay = "RNA"
  )

  work_dir <- tempfile("explore_archive_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
  bundle_dir <- file.path(work_dir, "source")
  write_scspotlight_explore_bundle(object, bundle_dir)

  archive <- file.path(work_dir, "source.zip")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(work_dir)
  create_bundle_archive(archive, "source")

  extract_dir <- decompress_matrix_input(basename(archive), archive)

  expect_equal(
    basename(find_scspotlight_explore_bundle_root(extract_dir)),
    "source"
  )
})

test_that("convert_to_explore_bundle writes a loadable zip archive", {
  skip_if_not_installed("Seurat")
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  convert_to_explore_bundle <- getFromNamespace(
    "convert_to_explore_bundle",
    "scSpotlight"
  )
  read_scspotlight_explore_bundle <- getFromNamespace(
    "read_scspotlight_explore_bundle",
    "scSpotlight"
  )
  find_scspotlight_explore_bundle_root <- getFromNamespace(
    "find_scspotlight_explore_bundle_root",
    "scSpotlight"
  )
  get_backend_expr <- getFromNamespace("get_backend_expr", "scSpotlight")

  counts <- Matrix::Matrix(
    c(
      1,
      0,
      3,
      4,
      2,
      0,
      5,
      1,
      4
    ),
    nrow = 3,
    sparse = TRUE
  )
  rownames(counts) <- c("g1", "g2", "g3")
  colnames(counts) <- c("c1", "c2", "c3")

  object <- Seurat::CreateSeuratObject(counts = counts)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts
  object[["umap"]] <- Seurat::CreateDimReducObject(
    embeddings = matrix(
      c(1, 2, 3, 4, 5, 6),
      nrow = 3,
      dimnames = list(colnames(counts), c("UMAP_1", "UMAP_2"))
    ),
    key = "UMAP_",
    assay = "RNA"
  )

  work_dir <- tempfile("explore_convert_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  input_file <- file.path(work_dir, "object.Rds")
  output_file <- file.path(work_dir, "object.explore-parquet.zip")
  saveRDS(object, input_file)

  expect_equal(
    normalizePath(
      convert_to_explore_bundle(input_file, output_file, block_size = 2L),
      winslash = "/"
    ),
    normalizePath(output_file, winslash = "/", mustWork = FALSE)
  )
  expect_true(file.exists(output_file))

  extract_dir <- file.path(work_dir, "extract")
  dir.create(extract_dir)
  unzip(output_file, exdir = extract_dir)
  bundle <- read_scspotlight_explore_bundle(
    find_scspotlight_explore_bundle_root(extract_dir)
  )

  expect_equal(get_backend_expr(bundle, features = "g2")$g2, c(0, 2, 1))
})

test_that("convert_to_explore_bundle uses Explore Parquet archive suffix", {
  skip_if_not_installed("Seurat")
  skip_if_not_installed("arrow")

  convert_to_explore_bundle <- getFromNamespace(
    "convert_to_explore_bundle",
    "scSpotlight"
  )

  counts <- Matrix::Matrix(c(1, 0, 2, 1, 0, 1), nrow = 2, sparse = TRUE)
  rownames(counts) <- c("g1", "g2")
  colnames(counts) <- c("c1", "c2", "c3")
  object <- Seurat::CreateSeuratObject(counts = counts)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts
  object[["umap"]] <- Seurat::CreateDimReducObject(
    embeddings = matrix(
      c(1, 2, 3, 4, 5, 6),
      nrow = 3,
      dimnames = list(colnames(counts), c("UMAP_1", "UMAP_2"))
    ),
    key = "UMAP_",
    assay = "RNA"
  )

  work_dir <- tempfile("explore_suffix_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  input_file <- file.path(work_dir, "object.Rds")
  saveRDS(object, input_file)

  output_file <- convert_to_explore_bundle(input_file, block_size = 2L)
  expect_match(basename(output_file), "\\.explore-parquet\\.zip$")
  expect_true(file.exists(output_file))
  expect_error(
    convert_to_explore_bundle(
      input_file,
      file.path(work_dir, "object-explore.zip"),
      block_size = 2L
    ),
    "output_file must end with .explore-parquet.zip",
    fixed = TRUE
  )
})

test_that("backend transfer adapter writes Explore bundle IPC payloads", {
  skip_if_not_installed("Seurat")
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  write_scspotlight_explore_bundle <- getFromNamespace(
    "write_scspotlight_explore_bundle",
    "scSpotlight"
  )
  read_scspotlight_explore_bundle <- getFromNamespace(
    "read_scspotlight_explore_bundle",
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
  extract_explore_metadata_to_ipc <- getFromNamespace(
    "extract_explore_metadata_to_ipc",
    "scSpotlight"
  )
  write_backend_pca_stdev_transfer <- getFromNamespace(
    "write_backend_pca_stdev_transfer",
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
  prepare_backend_expression_transfer <- getFromNamespace(
    "prepare_backend_expression_transfer",
    "scSpotlight"
  )
  write_backend_expression_transfer <- getFromNamespace(
    "write_backend_expression_transfer",
    "scSpotlight"
  )
  extract_explore_query_expr_to_ipc <- getFromNamespace(
    "extract_explore_query_expr_to_ipc",
    "scSpotlight"
  )

  counts <- Matrix::Matrix(
    c(
      1,
      0,
      3,
      4,
      2,
      0,
      5,
      1,
      4
    ),
    nrow = 3,
    sparse = TRUE
  )
  rownames(counts) <- c("g1", "g2", "g3")
  colnames(counts) <- c("c1", "c2", "c3")

  object <- Seurat::CreateSeuratObject(counts = counts)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts
  object$cluster <- c("a", "b", "a")
  object[["pca"]] <- Seurat::CreateDimReducObject(
    embeddings = matrix(
      c(1, 2, 3, 4, 5, 6),
      nrow = 3,
      dimnames = list(colnames(counts), c("PC_1", "PC_2"))
    ),
    stdev = c(2, 1),
    key = "PC_",
    assay = "RNA"
  )

  work_dir <- tempfile("explore_adapter_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
  bundle_dir <- file.path(work_dir, "bundle")
  transfer_dir <- file.path(work_dir, "transfer")
  dir.create(file.path(transfer_dir, "meta"), recursive = TRUE)
  dir.create(file.path(transfer_dir, "reduction"), recursive = TRUE)
  dir.create(file.path(transfer_dir, "expr"), recursive = TRUE)

  write_scspotlight_explore_bundle(object, bundle_dir, block_size = 2L)
  bundle <- read_scspotlight_explore_bundle(bundle_dir)

  meta_transfer <- prepare_backend_metadata_transfer(
    bundle,
    file.path(transfer_dir, "meta"),
    meta_version = 1L,
    cols = "cluster",
    resource_prefix = "data-test-session"
  )
  expect_equal(meta_transfer$backend, "explore_bundle")
  expect_null(meta_transfer$data)
  expect_true(file.exists(meta_transfer$metadata_path))
  cells_path <- file.path(bundle_dir, "cells.parquet")
  cells_backup <- paste0(cells_path, ".backup")
  expect_true(file.rename(cells_path, cells_backup))
  meta_payload <- write_backend_metadata_transfer(meta_transfer)
  expect_true(file.rename(cells_backup, cells_path))
  meta_table <- arrow::read_ipc_stream(meta_transfer$filePath)
  expect_identical(meta_payload$cols, list("cluster"))
  expect_match(meta_payload$cellIdentity, "^[0-9a-f]{32}$")
  expect_equal(as.vector(meta_table$cluster), c("a", "b", "a"))
  expect_false("cells" %in% names(meta_table))

  chunked_meta_file <- file.path(transfer_dir, "meta", "chunked_meta")
  extract_explore_metadata_to_ipc(
    metadata_path = meta_transfer$metadata_path,
    output_file = chunked_meta_file,
    cols = "cluster",
    chunk_size = 2L
  )
  chunked_meta_table <- arrow::read_ipc_stream(chunked_meta_file)
  expect_equal(as.vector(chunked_meta_table$cluster), c("a", "b", "a"))
  expect_equal(as.character(chunked_meta_table$cells), c("c1", "c2", "c3"))

  pca_payload <- write_backend_pca_stdev_transfer(
    bundle,
    file.path(transfer_dir, "reduction"),
    reduction_version = 1L,
    resource_prefix = "data-test-session"
  )
  pca_table <- arrow::read_ipc_stream(
    file.path(transfer_dir, "reduction", pca_payload$stdevFile)
  )
  expect_equal(as.numeric(pca_table$stdev), c(2, 1))

  reduction_transfer <- prepare_backend_reduction_transfer(
    bundle,
    reduction_name = "pca",
    dir_path = file.path(transfer_dir, "reduction"),
    reduction_version = 1L,
    resource_prefix = "data-test-session",
    transfer_attempt_id = 1L
  )
  expect_equal(reduction_transfer$backend, "explore_bundle")
  expect_null(reduction_transfer$data)
  expect_true(file.exists(reduction_transfer$reduction_path))
  expect_equal(reduction_transfer$x_col, "PC_1")
  expect_equal(reduction_transfer$y_col, "PC_2")
  reduction_payload <- write_backend_reduction_transfer(reduction_transfer)
  reduction_table <- arrow::read_ipc_stream(reduction_transfer$filePath)
  expect_equal(reduction_payload$reductionName, "pca")
  expect_equal(as.numeric(reduction_table$X), c(1, 2, 3))
  expect_equal(as.numeric(reduction_table$Y), c(4, 5, 6))

  expression_transfer <- prepare_backend_expression_transfer(
    bundle,
    assay = "RNA",
    feature = "g2",
    dir_path = file.path(transfer_dir, "expr"),
    expr_version = 1L,
    resource_prefix = "data-test-session"
  )
  expect_equal(expression_transfer$backend, "explore_bundle")
  expect_setequal(
    names(expression_transfer),
    c(
      "backend",
      "feature",
      "assay",
      "block_path",
      "feature_idx",
      "cell_count",
      "output_file",
      "payload"
    )
  )
  expect_false(any(
    c(
      "bundle",
      "data",
      "connection",
      "con",
      "dbi",
      "block_paths",
      "expression_blocks",
      "expr",
      "vector"
    ) %in%
      names(expression_transfer)
  ))
  expect_true(file.exists(expression_transfer$block_path))
  expect_equal(expression_transfer$feature_idx, 1L)
  expect_equal(expression_transfer$cell_count, 3L)
  expect_identical(
    names(expression_transfer$payload),
    c("geneName", "assay", "exprVersion", "exprFile", "resourcePrefix")
  )
  expect_equal(
    expression_transfer$payload$exprFile,
    basename(expression_transfer$output_file)
  )
  expect_false(any(grepl(
    "/",
    unlist(expression_transfer$payload),
    fixed = TRUE
  )))
  expression_payload <- write_backend_expression_transfer(expression_transfer)
  expression_table <- arrow::read_ipc_stream(expression_transfer$output_file)
  expect_identical(
    names(expression_payload),
    c("geneName", "assay", "exprVersion", "exprFile", "resourcePrefix")
  )
  expect_equal(expression_payload$geneName, "g2")
  expect_identical(names(expression_table), "expr")
  expect_equal(as.numeric(expression_table$expr), c(0, 2, 1))

  chunked_expression_file <- file.path(transfer_dir, "expr", "chunked_expr")
  extract_explore_query_expr_to_ipc(
    block_path = expression_transfer$block_path,
    feature_idx = expression_transfer$feature_idx,
    cell_count = expression_transfer$cell_count,
    output_file = chunked_expression_file,
    chunk_size = 2L
  )
  chunked_expression_table <- arrow::read_ipc_stream(chunked_expression_file)
  expect_equal(as.numeric(chunked_expression_table$expr), c(0, 2, 1))
})

test_that("Explore expression transfer resources are scoped and closed", {
  explore_bundle_path <- scspotlight_test_source_path(
    "R",
    "fct_explore_bundle.R"
  )
  adapter_path <- scspotlight_test_source_path(
    "R",
    "fct_backend_transfer_adapter.R"
  )
  skip_if_not(file.exists(explore_bundle_path))
  skip_if_not(file.exists(adapter_path))

  explore_source <- readLines(explore_bundle_path, warn = FALSE)
  extract_start <- grep(
    "extract_explore_query_expr_to_ipc <- function",
    explore_source,
    fixed = TRUE
  )[[1]]
  next_symbol <- grep(
    "^extract_explore_bundle_expr_to_ipc <- function",
    explore_source
  )[[1]]
  extract_source <- explore_source[seq(extract_start, next_symbol - 1L)]

  expect_true(any(grepl(
    "DBI::dbConnect(duckdb::duckdb(), dbdir = \":memory:\")",
    extract_source,
    fixed = TRUE
  )))
  expect_true(any(grepl(
    "DBI::dbDisconnect(con, shutdown = TRUE)",
    extract_source,
    fixed = TRUE
  )))
  expect_true(any(grepl("DBI::dbClearResult", extract_source, fixed = TRUE)))
  expect_true(any(grepl("WHERE feature_idx", extract_source, fixed = TRUE)))
  expect_true(any(grepl(
    "arrow::schema(expr = arrow::float32())",
    extract_source,
    fixed = TRUE
  )))
  expect_false(any(grepl(
    "explore_bundle_expr_vector",
    extract_source,
    fixed = TRUE
  )))

  adapter_source <- readLines(adapter_path, warn = FALSE)
  prepare_start <- grep(
    "prepare_backend_expression_transfer <- function",
    adapter_source,
    fixed = TRUE
  )[[1]]
  write_start <- grep(
    "write_backend_expression_transfer <- function",
    adapter_source,
    fixed = TRUE
  )[[1]]
  prepare_source <- adapter_source[seq(prepare_start, write_start - 1L)]
  expect_true(any(grepl(
    "explore_bundle_expression_query_plan",
    prepare_source,
    fixed = TRUE
  )))
  expect_false(any(grepl(
    "extract_explore_bundle_expr_to_ipc",
    prepare_source,
    fixed = TRUE
  )))
})

test_that("Explore expression transfer streams dense chunks from sparse rows", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  extract_explore_query_expr_to_ipc <- getFromNamespace(
    "extract_explore_query_expr_to_ipc",
    "scSpotlight"
  )

  work_dir <- tempfile("explore_expr_chunks_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  block_path <- file.path(work_dir, "block_00000.parquet")
  arrow::write_parquet(
    data.frame(
      feature_idx = c(1L, 1L, 1L),
      cell_idx = c(0L, 3L, 6L),
      value = c(2, 4, 6)
    ),
    block_path
  )

  output_file <- file.path(work_dir, "expr.arrow")
  extract_explore_query_expr_to_ipc(
    block_path = block_path,
    feature_idx = 1L,
    cell_count = 7L,
    output_file = output_file,
    chunk_size = 3L
  )

  expression_table <- arrow::read_ipc_stream(output_file)
  expect_equal(as.numeric(expression_table$expr), c(2, 0, 0, 4, 0, 0, 6))
})

test_that("Explore expression transfer validates and extracts in one selected scan", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  extract_explore_query_expr_to_ipc <- getFromNamespace(
    "extract_explore_query_expr_to_ipc",
    "scSpotlight"
  )

  work_dir <- tempfile("explore_expr_single_scan_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  block_path <- file.path(work_dir, "block_00000.parquet")
  arrow::write_parquet(
    data.frame(
      feature_idx = c(0L, 1L, 1L),
      cell_idx = c(1L, 0L, 3L),
      value = c(9, 2, 4)
    ),
    block_path
  )

  selected_scan_count <- 0L
  inside_get_query <- FALSE
  original_get_query <- DBI::dbGetQuery
  original_send_query <- DBI::dbSendQuery
  is_selected_expression_query <- function(statement) {
    grepl("read_parquet", statement, fixed = TRUE) &&
      grepl("WHERE", statement, fixed = TRUE) &&
      grepl("feature_idx", statement, fixed = TRUE)
  }
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (is_selected_expression_query(statement)) {
        selected_scan_count <<- selected_scan_count + 1L
      }
      previous_inside <- inside_get_query
      inside_get_query <<- TRUE
      on.exit(inside_get_query <<- previous_inside, add = TRUE)
      original_get_query(conn, statement, ...)
    },
    dbSendQuery = function(conn, statement, ...) {
      if (!inside_get_query && is_selected_expression_query(statement)) {
        selected_scan_count <<- selected_scan_count + 1L
      }
      original_send_query(conn, statement, ...)
    },
    .package = "DBI"
  )

  output_file <- file.path(work_dir, "expr.arrow")
  extract_explore_query_expr_to_ipc(
    block_path = block_path,
    feature_idx = 1L,
    cell_count = 4L,
    output_file = output_file,
    chunk_size = 2L
  )

  expect_equal(selected_scan_count, 1L)
  expression_table <- arrow::read_ipc_stream(output_file)
  expect_equal(as.numeric(expression_table$expr), c(2, 0, 0, 4))
})

test_that("Explore transfers reject malformed reduction and expression cell indexes", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  extract_explore_reduction_to_ipc <- getFromNamespace(
    "extract_explore_reduction_to_ipc",
    "scSpotlight"
  )
  extract_explore_query_expr_to_ipc <- getFromNamespace(
    "extract_explore_query_expr_to_ipc",
    "scSpotlight"
  )

  work_dir <- tempfile("explore_invalid_transfer_indexes_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  reduction_path <- file.path(work_dir, "reduction.parquet")
  arrow::write_parquet(
    data.frame(
      cell_idx = c(0L, 0L, 2L),
      UMAP_1 = c(1, 2, 3),
      UMAP_2 = c(4, 5, 6)
    ),
    reduction_path
  )
  expect_error(
    extract_explore_reduction_to_ipc(
      reduction_path = reduction_path,
      x_col = "UMAP_1",
      y_col = "UMAP_2",
      output_file = file.path(work_dir, "reduction.arrow"),
      expected_cell_count = 3L
    ),
    "dense, unique cell_idx",
    fixed = TRUE
  )

  expression_path <- file.path(work_dir, "block_00000.parquet")
  arrow::write_parquet(
    data.frame(
      feature_idx = c(1L, 1L, 1L),
      cell_idx = c(0L, 0L, 3L),
      value = c(1, 2, 3)
    ),
    expression_path
  )
  expression_output <- file.path(work_dir, "expr.arrow")
  expect_error(
    extract_explore_query_expr_to_ipc(
      block_path = expression_path,
      feature_idx = 1L,
      cell_count = 3L,
      output_file = expression_output
    ),
    "duplicate, invalid, or non-finite",
    fixed = TRUE
  )
  expect_false(file.exists(expression_output))
})

test_that("Explore metadata transfer keeps categorical schemas stable across chunks", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  extract_explore_metadata_to_ipc <- getFromNamespace(
    "extract_explore_metadata_to_ipc",
    "scSpotlight"
  )

  work_dir <- tempfile("explore_meta_chunks_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  metadata_path <- file.path(work_dir, "metadata.parquet")
  arrow::write_parquet(
    data.frame(
      cluster = c("a", "b", "c", "a"),
      sample = c("s1", "s1", "s2", "s3"),
      nCount = c(1, 2, 3, 4),
      .scspotlight_cell_idx = 0:3,
      check.names = FALSE,
      stringsAsFactors = FALSE
    ),
    metadata_path
  )
  arrow::write_parquet(
    data.frame(
      cell_idx = 0:3,
      cell_id = c("cell-a", "cell-b", "cell-c", "cell-d")
    ),
    file.path(work_dir, "cells.parquet")
  )

  output_file <- file.path(work_dir, "metadata.arrow")
  extract_explore_metadata_to_ipc(
    metadata_path = metadata_path,
    output_file = output_file,
    chunk_size = 2L
  )

  metadata_table <- arrow::read_ipc_stream(output_file)
  expect_equal(as.vector(metadata_table$cluster), c("a", "b", "c", "a"))
  expect_equal(as.vector(metadata_table$sample), c("s1", "s1", "s2", "s3"))
  expect_equal(as.numeric(metadata_table$nCount), c(1, 2, 3, 4))
  expect_equal(
    as.character(metadata_table$cells),
    c("cell-a", "cell-b", "cell-c", "cell-d")
  )
})

test_that("Explore metadata transfer streams canonical indexes without a join", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  stream_canonical_metadata <- getFromNamespace(
    "try_extract_canonical_explore_metadata_to_ipc",
    "scSpotlight"
  )

  work_dir <- tempfile("explore_canonical_metadata_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  metadata_path <- file.path(work_dir, "metadata.parquet")
  arrow::write_parquet(
    data.frame(
      cluster = c("b", "a", "b", "c"),
      flag = c(TRUE, FALSE, NA, TRUE),
      nCount = c(1, Inf, NaN, 4),
      .scspotlight_cell_idx = 0:3,
      check.names = FALSE,
      stringsAsFactors = FALSE
    ),
    metadata_path
  )
  cells_path <- file.path(work_dir, "cells.parquet")
  arrow::write_parquet(
    data.frame(
      cell_idx = 0:3,
      cell_id = c("cell-a", "cell-b", "cell-c", "cell-d")
    ),
    cells_path
  )

  output_file <- file.path(work_dir, "metadata.arrow")
  expect_true(stream_canonical_metadata(
    metadata_path = metadata_path,
    cells_path = cells_path,
    output_file = output_file,
    selected_cols = c("cluster", "flag", "nCount"),
    chunk_size = 2L,
    expected_cell_count = 4L
  ))

  metadata_table <- arrow::read_ipc_stream(output_file)
  expect_s3_class(metadata_table$cluster, "factor")
  expect_equal(as.vector(metadata_table$cluster), c("b", "a", "b", "c"))
  expect_s3_class(metadata_table$flag, "factor")
  expect_equal(
    as.character(metadata_table$flag),
    c("TRUE", "FALSE", NA, "TRUE")
  )
  expect_equal(as.numeric(metadata_table$nCount), c(1, NA, NA, 4))
  expect_type(metadata_table$cells, "character")
  expect_equal(
    as.character(metadata_table$cells),
    c("cell-a", "cell-b", "cell-c", "cell-d")
  )
})

test_that("Explore metadata transfer falls back when physical order is not canonical", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  stream_canonical_metadata <- getFromNamespace(
    "try_extract_canonical_explore_metadata_to_ipc",
    "scSpotlight"
  )

  work_dir <- tempfile("explore_reordered_metadata_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  metadata_path <- file.path(work_dir, "metadata.parquet")
  arrow::write_parquet(
    data.frame(
      cluster = c("late", "early", "middle"),
      .scspotlight_cell_idx = c(2L, 0L, 1L),
      check.names = FALSE,
      stringsAsFactors = FALSE
    ),
    metadata_path
  )
  cells_path <- file.path(work_dir, "cells.parquet")
  arrow::write_parquet(
    data.frame(
      cell_idx = 0:2,
      cell_id = c("cell-0", "cell-1", "cell-2")
    ),
    cells_path
  )

  output_file <- file.path(work_dir, "metadata.arrow")
  expect_false(stream_canonical_metadata(
    metadata_path = metadata_path,
    cells_path = cells_path,
    output_file = output_file,
    selected_cols = "cluster",
    chunk_size = 2L,
    expected_cell_count = 3L
  ))
  expect_false(file.exists(output_file))
})

test_that("Explore metadata transfer rejects invalid canonical cell indexes", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  extract_explore_metadata_to_ipc <- getFromNamespace(
    "extract_explore_metadata_to_ipc",
    "scSpotlight"
  )

  work_dir <- tempfile("explore_invalid_cells_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  metadata_path <- file.path(work_dir, "metadata.parquet")
  arrow::write_parquet(
    data.frame(
      cluster = c("a", "b"),
      .scspotlight_cell_idx = c(0L, 1L),
      check.names = FALSE,
      stringsAsFactors = FALSE
    ),
    metadata_path
  )
  arrow::write_parquet(
    data.frame(
      cell_idx = c(0L, 0L),
      cell_id = c("cell-a", "cell-b")
    ),
    file.path(work_dir, "cells.parquet")
  )

  expect_error(
    extract_explore_metadata_to_ipc(
      metadata_path,
      file.path(work_dir, "metadata.arrow")
    ),
    "dense, unique cell_idx",
    fixed = TRUE
  )
})

test_that("Explore transfers preserve explicit cell order", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  extract_explore_metadata_to_ipc <- getFromNamespace(
    "extract_explore_metadata_to_ipc",
    "scSpotlight"
  )
  extract_explore_reduction_to_ipc <- getFromNamespace(
    "extract_explore_reduction_to_ipc",
    "scSpotlight"
  )

  work_dir <- tempfile("explore_order_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  metadata_path <- file.path(work_dir, "metadata.parquet")
  arrow::write_parquet(
    data.frame(
      cluster = c("late", "early", "middle"),
      .scspotlight_cell_idx = c(2L, 0L, 1L),
      check.names = FALSE,
      stringsAsFactors = FALSE
    ),
    metadata_path
  )
  arrow::write_parquet(
    data.frame(
      cell_idx = 0:2,
      cell_id = c("cell-0", "cell-1", "cell-2")
    ),
    file.path(work_dir, "cells.parquet")
  )
  metadata_output <- file.path(work_dir, "metadata.arrow")
  extract_explore_metadata_to_ipc(metadata_path, metadata_output)
  metadata_table <- arrow::read_ipc_stream(metadata_output)

  expect_equal(as.vector(metadata_table$cluster), c("early", "middle", "late"))
  expect_equal(
    as.character(metadata_table$cells),
    c("cell-0", "cell-1", "cell-2")
  )
  expect_false(".scspotlight_cell_idx" %in% names(metadata_table))

  reduction_path <- file.path(work_dir, "reduction.parquet")
  arrow::write_parquet(
    data.frame(
      cell_idx = c(2L, 0L, 1L),
      UMAP_1 = c(30, 10, 20),
      UMAP_2 = c(300, 100, 200),
      check.names = FALSE
    ),
    reduction_path
  )
  reduction_output <- file.path(work_dir, "reduction.arrow")
  extract_explore_reduction_to_ipc(
    reduction_path = reduction_path,
    x_col = "UMAP_1",
    y_col = "UMAP_2",
    output_file = reduction_output
  )
  reduction_table <- arrow::read_ipc_stream(reduction_output)

  expect_equal(as.numeric(reduction_table$X), c(10, 20, 30))
  expect_equal(as.numeric(reduction_table$Y), c(100, 200, 300))
})

test_that("Explore bundle loader rejects incomplete bundles", {
  skip_if_not_installed("arrow")

  read_scspotlight_explore_bundle <- getFromNamespace(
    "read_scspotlight_explore_bundle",
    "scSpotlight"
  )
  bundle_type <- getFromNamespace(
    "scspotlight_explore_bundle_type",
    "scSpotlight"
  )

  bundle_dir <- tempfile("explore_incomplete_")
  dir.create(bundle_dir)
  on.exit(unlink(bundle_dir, recursive = TRUE, force = TRUE), add = TRUE)

  jsonlite::write_json(
    list(
      bundle_type = bundle_type,
      schema_version = 1L,
      cell_count = 1L,
      feature_count = 1L,
      assay = "RNA",
      default_assay = "RNA",
      assays = list(list(name = "RNA", layers = list("data"))),
      reductions = "umap"
    ),
    file.path(bundle_dir, "manifest.json"),
    auto_unbox = TRUE
  )
  arrow::write_parquet(
    data.frame(cell_idx = 0L, cell_id = "c1"),
    file.path(bundle_dir, "cells.parquet")
  )
  arrow::write_parquet(
    data.frame(
      feature_idx = 0L,
      feature = "g1",
      assay = "RNA",
      layer = "data",
      block = 0L
    ),
    file.path(bundle_dir, "features.parquet")
  )
  dir.create(file.path(bundle_dir, "expression"))
  arrow::write_parquet(
    data.frame(
      feature_idx = integer(),
      cell_idx = integer(),
      value = numeric()
    ),
    file.path(bundle_dir, "expression", "block_00000.parquet")
  )

  expect_error(
    read_scspotlight_explore_bundle(bundle_dir),
    "metadata.parquet"
  )

  arrow::write_parquet(
    data.frame(cluster = "a", .scspotlight_cell_idx = 0L, check.names = FALSE),
    file.path(bundle_dir, "metadata.parquet")
  )
  expect_error(
    read_scspotlight_explore_bundle(bundle_dir),
    "umap"
  )
})

test_that("Explore bundle load probes each metadata and reduction schema once", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  read_scspotlight_explore_bundle <- getFromNamespace(
    "read_scspotlight_explore_bundle",
    "scSpotlight"
  )
  original_explore_parquet_columns <- getFromNamespace(
    "explore_parquet_columns",
    "scSpotlight"
  )
  bundle_type <- getFromNamespace(
    "scspotlight_explore_bundle_type",
    "scSpotlight"
  )

  bundle_dir <- tempfile("explore_schema_probe_")
  dir.create(bundle_dir)
  dir.create(file.path(bundle_dir, "reductions"))
  dir.create(file.path(bundle_dir, "expression"))
  on.exit(unlink(bundle_dir, recursive = TRUE, force = TRUE), add = TRUE)

  jsonlite::write_json(
    list(
      bundle_type = bundle_type,
      schema_version = 1L,
      cell_count = 2L,
      feature_count = 1L,
      assay = "RNA",
      default_assay = "RNA",
      assays = list(list(name = "RNA", layers = list("data"))),
      reductions = c("umap", "tsne")
    ),
    file.path(bundle_dir, "manifest.json"),
    auto_unbox = TRUE
  )
  arrow::write_parquet(
    data.frame(cell_idx = 0:1, cell_id = c("c1", "c2")),
    file.path(bundle_dir, "cells.parquet")
  )
  arrow::write_parquet(
    data.frame(
      cluster = c("a", "b"),
      .scspotlight_cell_idx = 0:1,
      check.names = FALSE
    ),
    file.path(bundle_dir, "metadata.parquet")
  )
  arrow::write_parquet(
    data.frame(
      feature_idx = 0L,
      feature = "g1",
      assay = "RNA",
      layer = "data",
      block = 0L
    ),
    file.path(bundle_dir, "features.parquet")
  )
  arrow::write_parquet(
    data.frame(
      cell_idx = 0:1,
      UMAP_1 = c(1, 2),
      UMAP_2 = c(3, 4)
    ),
    file.path(bundle_dir, "reductions", "umap.parquet")
  )
  arrow::write_parquet(
    data.frame(
      cell_idx = 0:1,
      tSNE_1 = c(5, 6),
      tSNE_2 = c(7, 8)
    ),
    file.path(bundle_dir, "reductions", "tsne.parquet")
  )
  arrow::write_parquet(
    data.frame(
      feature_idx = integer(),
      cell_idx = integer(),
      value = numeric()
    ),
    file.path(bundle_dir, "expression", "block_00000.parquet")
  )

  schema_probe_paths <- character()
  testthat::local_mocked_bindings(
    explore_parquet_columns = function(path) {
      schema_probe_paths <<- c(
        schema_probe_paths,
        normalizePath(path, winslash = "/", mustWork = TRUE)
      )
      original_explore_parquet_columns(path)
    },
    .package = "scSpotlight"
  )

  bundle <- read_scspotlight_explore_bundle(bundle_dir)
  schema_probe_files <- basename(schema_probe_paths)

  expect_s3_class(bundle, "scspotlight_explore_bundle")
  expect_equal(sum(schema_probe_files == "metadata.parquet"), 1L)
  expect_equal(sum(schema_probe_files == "umap.parquet"), 1L)
  expect_equal(sum(schema_probe_files == "tsne.parquet"), 1L)
})
