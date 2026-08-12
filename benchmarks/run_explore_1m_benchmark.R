source(file.path("benchmarks", "explore_1m_helpers.R"))

devtools::load_all(".", quiet = TRUE, export_all = FALSE)

read_explore_bundle <- getFromNamespace(
  "read_scspotlight_explore_bundle",
  "scSpotlight"
)
prepare_metadata_transfer <- getFromNamespace(
  "prepare_backend_metadata_transfer",
  "scSpotlight"
)
write_metadata_transfer <- getFromNamespace(
  "write_backend_metadata_transfer",
  "scSpotlight"
)
prepare_reduction_transfer <- getFromNamespace(
  "prepare_backend_reduction_transfer",
  "scSpotlight"
)
write_reduction_transfer <- getFromNamespace(
  "write_backend_reduction_transfer",
  "scSpotlight"
)
prepare_expression_transfer <- getFromNamespace(
  "prepare_backend_expression_transfer",
  "scSpotlight"
)
write_expression_transfer <- getFromNamespace(
  "write_backend_expression_transfer",
  "scSpotlight"
)

cell_count <- benchmark_cell_count()
if (cell_count < 1000000L) {
  stop("The committed benchmark command requires at least 1,000,000 cells.")
}

force_rebuild <- identical(tolower(Sys.getenv("SCSPOTLIGHT_BENCHMARK_REBUILD")), "true")
paths <- benchmark_write_structural_explore_bundle(
  cell_count = cell_count,
  force = force_rebuild
)
result_file <- benchmark_default_results_file()
dir.create(dirname(result_file), recursive = TRUE, showWarnings = FALSE)

bundle_load <- benchmark_elapsed(function() {
  read_explore_bundle(paths$bundle_dir)
})
bundle <- bundle_load$value
transfer_dir <- file.path(paths$root, "transfers")
dir.create(transfer_dir, recursive = TRUE, showWarnings = FALSE)

benchmark_transfer <- function(kind, iterations, create_transfer) {
  write_transfer <- switch(
    kind,
    metadata = write_metadata_transfer,
    reduction = write_reduction_transfer,
    expression = write_expression_transfer,
    stop("Unsupported benchmark transfer kind: ", kind, call. = FALSE)
  )
  samples <- vector("list", iterations)
  for (iteration in seq_len(iterations)) {
    transfer <- create_transfer(iteration)
    measurement <- benchmark_elapsed(function() {
      write_transfer(transfer)
    })
    output_file <- if (!is.null(transfer$filePath)) {
      transfer$filePath
    } else {
      transfer$output_file
    }
    samples[[iteration]] <- list(
      elapsed_ms = measurement$elapsed_ms,
      output_bytes = unname(file.info(output_file)$size),
      rss_before_kb = measurement$rss_before_kb,
      rss_after_kb = measurement$rss_after_kb,
      hwm_after_kb = measurement$hwm_after_kb
    )
    unlink(output_file)
  }

  list(
    method = "production DuckDB query plus chunked Arrow IPC writer",
    summary_ms = benchmark_summary(vapply(samples, `[[`, numeric(1), "elapsed_ms")),
    samples = samples
  )
}

metadata <- benchmark_transfer(
  kind = "metadata",
  iterations = 3L,
  create_transfer = function(iteration) {
    prepare_metadata_transfer(
      bundle,
      dir_path = transfer_dir,
      meta_version = iteration
    )
  }
)

reduction <- benchmark_transfer(
  kind = "reduction",
  iterations = 3L,
  create_transfer = function(iteration) {
    prepare_reduction_transfer(
      bundle,
      reduction_name = "umap",
      dir_path = transfer_dir,
      reduction_version = iteration
    )
  }
)

expression <- benchmark_transfer(
  kind = "expression",
  iterations = 3L,
  create_transfer = function(iteration) {
    prepare_expression_transfer(
      bundle,
      assay = "RNA",
      feature = "BENCHMARK_GENE",
      dir_path = transfer_dir,
      expr_version = iteration
    )
  }
)

payload <- list(
  schema_version = 1L,
  command = "pixi run benchmark-explore-1m",
  provenance = c(
    benchmark_git_provenance(),
    list(
    fixture_generator = "benchmarks/explore_1m_helpers.R",
    artifact_kind = "synthetic_structural_workload",
    biological_representativeness = "not claimed"
    )
  ),
  workload = list(
    fixture_kind = "synthetic_structural_workload",
    biological_representativeness = "not claimed",
    cell_count = cell_count,
    feature_count = 2L,
    selected_gene = "BENCHMARK_GENE",
    selected_gene_nonzero_cells = length(seq.int(0L, cell_count - 1L, by = 20L)),
    reduction = "umap",
    storage = "Explore Parquet bundle with zstd-compressed Parquet files"
  ),
  environment = benchmark_environment(),
  artifact = list(
    archive_bytes = unname(file.info(paths$archive)$size),
    archive_md5 = benchmark_file_md5(paths$archive),
    bundle_bytes = sum(file.info(list.files(paths$bundle_dir, recursive = TRUE, full.names = TRUE))$size, na.rm = TRUE)
  ),
  server_direct = list(
    bundle_open_and_validation_ms = bundle_load$elapsed_ms,
    bundle_open_rss_before_kb = bundle_load$rss_before_kb,
    bundle_open_rss_after_kb = bundle_load$rss_after_kb,
    bundle_open_hwm_after_kb = bundle_load$hwm_after_kb,
    metadata_query_to_ipc = metadata,
    reduction_query_to_ipc = reduction,
    selected_gene_expression_query_to_ipc = expression
  ),
  browser = NULL
)

jsonlite::write_json(payload, result_file, auto_unbox = TRUE, pretty = TRUE, null = "null")
cat("Wrote direct 1M benchmark metrics to ", result_file, "\n", sep = "")
