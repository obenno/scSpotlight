benchmark_source_root <- Sys.getenv("SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT", getwd())
benchmark_explore_helpers_file <- file.path(
  benchmark_source_root,
  "benchmarks",
  "explore_1m_helpers.R"
)
if (!file.exists(benchmark_explore_helpers_file)) {
  stop(
    "Unable to locate benchmarks/explore_1m_helpers.R. Set SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT.",
    call. = FALSE
  )
}
source(benchmark_explore_helpers_file)

benchmark_real_h5ad_url <- paste0(
  "https://datasets.cellxgene.cziscience.com/",
  "aa6ebee3-68cc-41b4-80b2-5ef5c3317e14.h5ad"
)
benchmark_real_h5ad_filename <- "aa6ebee3-68cc-41b4-80b2-5ef5c3317e14.h5ad"
benchmark_real_h5ad_expected_bytes <- 9663215939
benchmark_max_rss_limit_bytes <- 6000000000

benchmark_temp_root <- function() {
  root <- Sys.getenv("SCSPOTLIGHT_TEMP_ROOT", "")
  if (!nzchar(trimws(root))) {
    root <- file.path(getwd(), "benchmarks", ".tmp")
  }
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

benchmark_real_h5ad_root <- function() {
  root <- Sys.getenv(
    "SCSPOTLIGHT_REAL_H5AD_ROOT",
    file.path(benchmark_temp_root(), "cellxgene-h5ad")
  )
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

benchmark_real_h5ad_paths <- function() {
  root <- benchmark_real_h5ad_root()
  run_id <- Sys.getenv("SCSPOTLIGHT_REAL_H5AD_RUN_ID", "latest")
  run_id <- trimws(run_id)
  if (!grepl("^[A-Za-z0-9_.-]+$", run_id)) {
    stop("SCSPOTLIGHT_REAL_H5AD_RUN_ID must contain only letters, digits, _, ., or -.")
  }

  source_file <- Sys.getenv(
    "SCSPOTLIGHT_REAL_H5AD_FILE",
    file.path(root, "source", benchmark_real_h5ad_filename)
  )
  run_root <- file.path(root, "runs", run_id)
  list(
    root = root,
    source_file = normalizePath(source_file, winslash = "/", mustWork = FALSE),
    run_root = normalizePath(run_root, winslash = "/", mustWork = FALSE),
    processing_root = file.path(run_root, "processing"),
    browser_root = file.path(run_root, "browser"),
    descriptor_file = file.path(run_root, "artifact.json"),
    results_file = file.path(run_root, "results.json"),
    pid_file = file.path(run_root, "shiny-server.pid")
  )
}

benchmark_assert_real_h5ad_file <- function(path) {
  if (!file.exists(path)) {
    stop("Real CellxGene h5ad artifact is missing: ", path, call. = FALSE)
  }

  actual_bytes <- unname(file.info(path)$size)
  if (!identical(as.numeric(actual_bytes), benchmark_real_h5ad_expected_bytes)) {
    stop(
      "Real CellxGene h5ad artifact is incomplete or unexpected: expected ",
      benchmark_real_h5ad_expected_bytes,
      " bytes, found ",
      actual_bytes,
      ".",
      call. = FALSE
    )
  }

  invisible(normalizePath(path, winslash = "/", mustWork = TRUE))
}

benchmark_kb_to_bytes <- function(value) {
  value <- suppressWarnings(as.numeric(value))
  if (!is.finite(value)) {
    return(NA_real_)
  }
  value * 1024
}

benchmark_rss_limit_bytes <- function() {
  configured <- suppressWarnings(as.numeric(Sys.getenv(
    "SCSPOTLIGHT_RSS_LIMIT_BYTES",
    as.character(benchmark_max_rss_limit_bytes)
  )))
  if (
    !is.finite(configured) ||
      configured <= 0 ||
      configured > benchmark_max_rss_limit_bytes
  ) {
    stop(
      "SCSPOTLIGHT_RSS_LIMIT_BYTES must be a positive value no greater than ",
      benchmark_max_rss_limit_bytes,
      ".",
      call. = FALSE
    )
  }
  configured
}

benchmark_rss_gate <- function(peak_kb, limit_bytes = benchmark_rss_limit_bytes()) {
  peak_bytes <- benchmark_kb_to_bytes(peak_kb)
  list(
    metric = "Linux VmHWM",
    peak_bytes = peak_bytes,
    limit_bytes = limit_bytes,
    passed = is.finite(peak_bytes) && peak_bytes < limit_bytes
  )
}

benchmark_scspotlight_function <- function(name) {
  getFromNamespace(name, "scSpotlight")
}

benchmark_null_coalesce <- function(x, y) {
  if (is.null(x)) y else x
}

benchmark_h5ad_schema <- function(path) {
  h5ls <- rhdf5::h5ls(path, recursive = TRUE)
  h5ad_read_attrs <- benchmark_scspotlight_function("h5ad_read_attrs")
  h5ad_path_exists <- benchmark_scspotlight_function("h5ad_path_exists")
  root_attrs <- h5ad_read_attrs(path, "/")
  group_children <- function(group) {
    as.character(h5ls$name[h5ls$group == group])
  }

  list(
    root_encoding_type = as.character(
      benchmark_null_coalesce(root_attrs[["encoding-type"]], NA_character_)
    ),
    root_encoding_version = as.character(
      benchmark_null_coalesce(root_attrs[["encoding-version"]], NA_character_)
    ),
    matrix_groups = c(
      if (h5ad_path_exists(h5ls, "X")) "X",
      if (h5ad_path_exists(h5ls, "raw/X")) "raw/X",
      paste0("layers/", group_children("/layers"))
    ),
    obsm = group_children("/obsm"),
    obs_columns = group_children("/obs"),
    var_columns = group_children("/var")
  )
}

benchmark_select_real_h5ad_feature <- function(object, assay = NULL) {
  assay <- benchmark_null_coalesce(assay, SeuratObject::DefaultAssay(object))
  get_backend_features <- benchmark_scspotlight_function("get_backend_features")
  features <- get_backend_features(object, assay = assay)
  preferred <- c("MALAT1", "Malat1", "ACTB", "Actb", "GAPDH", "Gapdh")
  selected <- preferred[preferred %in% features]
  if (length(selected)) {
    return(selected[[1]])
  }

  if (!length(features)) {
    stop("The real h5ad artifact contains no selectable features.", call. = FALSE)
  }
  as.character(features[[1]])
}

benchmark_select_real_h5ad_reduction <- function(object) {
  get_backend_reduction_names <- benchmark_scspotlight_function(
    "get_backend_reduction_names"
  )
  reductions <- get_backend_reduction_names(object)
  preferred <- c("umap", "tsne", "pca")
  selected <- preferred[preferred %in% reductions]
  if (length(selected)) {
    return(selected[[1]])
  }

  if (!length(reductions)) {
    stop("The real h5ad artifact contains no plotting reduction.", call. = FALSE)
  }
  as.character(reductions[[1]])
}

benchmark_transfer_measurement <- function(prepare_transfer, write_transfer) {
  transfer <- prepare_transfer()
  measurement <- benchmark_elapsed(function() write_transfer(transfer))
  output_file <- benchmark_null_coalesce(
    transfer$filePath,
    transfer$output_file
  )
  output_bytes <- if (file.exists(output_file)) {
    unname(file.info(output_file)$size)
  } else {
    NA_real_
  }
  unlink(output_file)

  list(
    backend = transfer$backend,
    elapsed_ms = measurement$elapsed_ms,
    output_bytes = output_bytes,
    rss_before_kb = measurement$rss_before_kb,
    rss_after_kb = measurement$rss_after_kb,
    hwm_after_kb = measurement$hwm_after_kb
  )
}

benchmark_write_real_h5ad_result <- function(payload, paths) {
  dir.create(dirname(paths$results_file), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    payload,
    paths$results_file,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
  invisible(paths$results_file)
}
