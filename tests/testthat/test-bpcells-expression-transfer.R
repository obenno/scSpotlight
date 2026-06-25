test_that("BPCells expression transfer writes chunked Arrow IPC", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("BPCells")
  skip_if_not_installed("Seurat")

  ensure_assay5 <- getFromNamespace("ensure_assay5", "scSpotlight")
  ensure_bpcells_backing <- getFromNamespace(
    "ensure_bpcells_backing",
    "scSpotlight"
  )
  extract_bpcells_expr_to_ipc <- getFromNamespace(
    "extract_bpcells_expr_to_ipc",
    "scSpotlight"
  )

  counts <- Matrix::Matrix(
    matrix(
      c(
        1,
        0,
        3,
        0,
        2,
        4,
        5,
        0,
        6,
        0,
        7,
        8
      ),
      nrow = 3
    ),
    sparse = TRUE
  )
  rownames(counts) <- c("g1", "g2", "g3")
  colnames(counts) <- paste0("c", seq_len(ncol(counts)))

  object <- Seurat::CreateSeuratObject(counts = counts)
  object <- ensure_assay5(object, assay = "RNA")
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts

  backend_root <- tempfile("bp_expr_backend_")
  object <- ensure_bpcells_backing(
    object,
    root_dir = backend_root,
    assays = "RNA",
    layers = "data"
  )
  on.exit(unlink(backend_root, recursive = TRUE, force = TRUE), add = TRUE)

  matrix_dir <- file.path(backend_root, "RNA", "data")
  output_file <- tempfile("bp_expr_", fileext = ".arrow")
  on.exit(unlink(output_file, force = TRUE), add = TRUE)

  extract_bpcells_expr_to_ipc(
    matrix_dir = matrix_dir,
    feature = "g2",
    output_file = output_file,
    chunk_size = 2L
  )

  expression_table <- arrow::read_ipc_stream(output_file)
  expect_identical(names(expression_table), "expr")
  expect_equal(as.numeric(expression_table$expr), as.numeric(counts["g2", ]))
})

test_that("BPCells expression IPC writer keeps chunked float32 contract", {
  bpcells_backend_path <- test_path("..", "..", "R", "fct_bpcells_backend.R")
  skip_if_not(file.exists(bpcells_backend_path))

  bpcells_backend_source <- readLines(bpcells_backend_path, warn = FALSE)
  extract_start <- grep(
    "extract_bpcells_expr_to_ipc <- function",
    bpcells_backend_source,
    fixed = TRUE
  )[[1]]
  next_symbol <- grep(
    "^bp_write_cached_matrix <- function",
    bpcells_backend_source
  )[[1]]
  extract_source <- bpcells_backend_source[seq(extract_start, next_symbol - 1L)]

  expect_true(any(grepl("BPCells::open_matrix_dir(matrix_dir)", extract_source, fixed = TRUE)))
  expect_true(any(grepl("RecordBatchStreamWriter", extract_source, fixed = TRUE)))
  expect_true(any(grepl("arrow::schema(expr = arrow::float32())", extract_source, fixed = TRUE)))
  expect_true(any(grepl("while (chunk_start <= cell_count)", extract_source, fixed = TRUE)))
  expect_true(any(grepl("extract_expr_slice", extract_source, fixed = TRUE)))
  expect_false(any(grepl("as.matrix", extract_source, fixed = TRUE)))
})

test_that("InputFeature expression exports use path-based futures", {
  mod_input_feature_path <- test_path("..", "..", "R", "mod_InputFeature.R")
  skip_if_not(file.exists(mod_input_feature_path))
  mod_input_feature_source <- readLines(mod_input_feature_path, warn = FALSE)
  process_start <- grep(
    "process_next_expression_transfer <- function",
    mod_input_feature_source,
    fixed = TRUE
  )[[1]]
  invoke_start <- grep(
    "invoke_expression_transfer <- function",
    mod_input_feature_source,
    fixed = TRUE
  )[[1]]
  expression_export_source <- mod_input_feature_source[
    seq(process_start, invoke_start - 1L)
  ]
  invoke_source <- mod_input_feature_source[seq(invoke_start, length(mod_input_feature_source))]

  expect_true(any(grepl("expression_queue <- list()", mod_input_feature_source, fixed = TRUE)))
  expect_true(any(grepl("expression_active <- FALSE", mod_input_feature_source, fixed = TRUE)))
  expect_true(any(grepl("queued_expression_keys <- character()", mod_input_feature_source, fixed = TRUE)))
  expect_true(any(grepl("expression_active || !length(expression_queue)", expression_export_source, fixed = TRUE)))
  expect_true(any(grepl("future_promise", expression_export_source)))
  expect_true(any(grepl("write_backend_expression_transfer(job$transfer)", expression_export_source, fixed = TRUE)))
  expect_true(any(grepl("make_transfer_error_payload", expression_export_source, fixed = TRUE)))
  expect_true(any(grepl("payload_type = \"expression\"", expression_export_source, fixed = TRUE)))
  expect_false(any(grepl("seuratObj\\(\\)", expression_export_source)))
  expect_false(any(grepl("prepare_backend_expression_transfer", expression_export_source)))
  expect_true(any(grepl("cacheKey %in% queued_expression_keys", invoke_source, fixed = TRUE)))
  expect_true(any(grepl("expression_queue <<- c(expression_queue", invoke_source, fixed = TRUE)))
  expect_true(any(grepl("queued_expression_keys <<- unique", invoke_source, fixed = TRUE)))
  expect_true(any(grepl("input$cacheMissFeature", invoke_source, fixed = TRUE)))
  expect_true(any(grepl("create_sparkline = FALSE", invoke_source, fixed = TRUE)))
})

test_that("InputFeature expression failures keep raw paths out of notifications", {
  mod_input_feature_path <- test_path("..", "..", "R", "mod_InputFeature.R")
  skip_if_not(file.exists(mod_input_feature_path))
  mod_input_feature_source <- readLines(mod_input_feature_path, warn = FALSE)

  expect_true(any(grepl(
    "Expression export failed. Retry transfer or choose another feature.",
    mod_input_feature_source,
    fixed = TRUE
  )))
  expect_true(any(grepl(
    "Expression extraction failed. Retry transfer or choose another feature.",
    mod_input_feature_source,
    fixed = TRUE
  )))

  expect_false(any(grepl(
    "Expression export failed:\", conditionMessage(error)",
    mod_input_feature_source,
    fixed = TRUE
  )))

  extraction_failure_lines <- grep(
    "Expression extraction failed:",
    mod_input_feature_source,
    fixed = TRUE
  )
  for (line in extraction_failure_lines) {
    window <- mod_input_feature_source[line:min(length(mod_input_feature_source), line + 3L)]
    expect_false(any(grepl("conditionMessage", window, fixed = TRUE)))
  }
})
