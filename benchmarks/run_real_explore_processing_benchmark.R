source(file.path("benchmarks", "real_explore_helpers.R"))

devtools::load_all(".", quiet = TRUE, export_all = FALSE)

convert_to_explore_bundle <- benchmark_scspotlight_function(
  "convert_to_explore_bundle"
)
decompress_matrix_input <- benchmark_scspotlight_function(
  "decompress_matrix_input"
)
read_explore_bundle <- benchmark_scspotlight_function(
  "read_scspotlight_explore_bundle"
)
prepare_backend_expression_transfer <- benchmark_scspotlight_function(
  "prepare_backend_expression_transfer"
)
write_backend_expression_transfer <- benchmark_scspotlight_function(
  "write_backend_expression_transfer"
)
get_backend_cell_count <- benchmark_scspotlight_function("get_backend_cell_count")
get_backend_features <- benchmark_scspotlight_function("get_backend_features")
get_backend_reduction_names <- benchmark_scspotlight_function(
  "get_backend_reduction_names"
)

paths <- benchmark_real_explore_paths()
source_file <- benchmark_assert_real_h5ad_file(paths$source_file)
if (
  file.exists(paths$archive_file) ||
    file.exists(paths$descriptor_file) ||
    file.exists(paths$results_file)
) {
  stop(
    "Real Explore benchmark output already exists for this run ID. Choose a new SCSPOTLIGHT_REAL_EXPLORE_RUN_ID.",
    call. = FALSE
  )
}

dir.create(paths$run_root, recursive = TRUE, showWarnings = FALSE)
dir.create(paths$processing_root, recursive = TRUE, showWarnings = FALSE)

baseline <- benchmark_read_proc_status()
conversion_measurement <- benchmark_elapsed(function() {
  convert_to_explore_bundle(
    input_file = source_file,
    output_file = paths$archive_file
  )
})
if (!file.exists(paths$archive_file)) {
  stop("Real Explore conversion did not create its archive.", call. = FALSE)
}

bundle_load_measurement <- benchmark_elapsed(function() {
  extracted_root <- decompress_matrix_input(
    fileName = basename(paths$archive_file),
    filePath = paths$archive_file,
    temp_root = file.path(paths$processing_root, "archive-extract")
  )
  list(
    root = extracted_root,
    bundle = read_explore_bundle(extracted_root)
  )
})
bundle <- bundle_load_measurement$value$bundle
assay <- as.character(bundle$manifest$default_assay %||% bundle$manifest$assay)
features <- get_backend_features(bundle, assay = assay)
selected_gene <- benchmark_real_explore_selected_gene
if (!selected_gene %in% features) {
  stop(
    "The real Explore bundle does not contain the selected comparison gene: ",
    selected_gene,
    call. = FALSE
  )
}
reductions <- get_backend_reduction_names(bundle)
selected_reduction <- "umap"
if (!selected_reduction %in% reductions) {
  stop("The real Explore bundle does not contain the UMAP reduction.", call. = FALSE)
}

transfer_dir <- file.path(paths$processing_root, "transfers")
dir.create(transfer_dir, recursive = TRUE, showWarnings = FALSE)
expression_samples <- lapply(seq_len(3L), function(iteration) {
  benchmark_transfer_measurement(
    prepare_transfer = function() {
      prepare_backend_expression_transfer(
        bundle,
        assay = assay,
        feature = selected_gene,
        dir_path = transfer_dir,
        expr_version = iteration
      )
    },
    write_transfer = write_backend_expression_transfer
  )
})
expression_elapsed_ms <- vapply(
  expression_samples,
  `[[`,
  numeric(1),
  "elapsed_ms"
)

final_status <- benchmark_read_proc_status()
rss_limit_bytes <- benchmark_rss_limit_bytes()
processing_gate <- benchmark_rss_gate(
  final_status$hwm_kb,
  limit_bytes = rss_limit_bytes
)
feature_record <- bundle$features[
  bundle$features$feature == selected_gene & bundle$features$assay == assay,
  ,
  drop = FALSE
]
descriptor <- list(
  source_url = benchmark_real_h5ad_url,
  source_filename = basename(source_file),
  source_bytes = unname(file.info(source_file)$size),
  source_md5 = benchmark_file_md5(source_file),
  archive_filename = basename(paths$archive_file),
  archive_bytes = unname(file.info(paths$archive_file)$size),
  archive_md5 = benchmark_file_md5(paths$archive_file),
  bundle_bytes = sum(file.info(list.files(
    bundle$root,
    recursive = TRUE,
    full.names = TRUE
  ))$size, na.rm = TRUE),
  cell_count = get_backend_cell_count(bundle),
  feature_count = length(features),
  expression_block_count = length(unique(as.integer(bundle$features$block))),
  assay = assay,
  selected_reduction = selected_reduction,
  selected_gene = selected_gene,
  selected_gene_block = as.integer(feature_record$block[[1]]),
  reductions = reductions
)
jsonlite::write_json(
  descriptor,
  paths$descriptor_file,
  auto_unbox = TRUE,
  pretty = TRUE,
  null = "null"
)

payload <- list(
  schema_version = 1L,
  command = "pixi run benchmark-real-explore",
  provenance = c(
    benchmark_git_provenance(),
    list(
      artifact_kind = "cellxgene_real_explore_bundle",
      biological_representativeness = "Full Explore archive generated from the real CellxGene H5AD comparison artifact",
      source_url = benchmark_real_h5ad_url,
      source_filename = basename(source_file),
      source_bytes = descriptor$source_bytes,
      source_md5 = descriptor$source_md5
    )
  ),
  workload = list(
    input = "Full Explore Parquet archive converted from the native CellxGene AnnData H5AD",
    cell_count = descriptor$cell_count,
    feature_count = descriptor$feature_count,
    expression_block_count = descriptor$expression_block_count,
    assay = assay,
    selected_reduction = selected_reduction,
    selected_gene = selected_gene,
    selected_gene_block = descriptor$selected_gene_block,
    storage = "zstd-compressed feature-block Parquet files queried with DuckDB and streamed as Arrow IPC"
  ),
  environment = benchmark_environment(),
  artifact = descriptor,
  processing = list(
    method = "Fresh Pixi-managed R process; Linux VmHWM records full H5AD-to-Explore conversion, archive extraction and validation, and production DuckDB expression transfers.",
    baseline_rss_kb = baseline$rss_kb,
    conversion_to_full_archive = list(
      elapsed_ms = conversion_measurement$elapsed_ms,
      rss_before_kb = conversion_measurement$rss_before_kb,
      rss_after_kb = conversion_measurement$rss_after_kb,
      hwm_after_kb = conversion_measurement$hwm_after_kb,
      archive_bytes = descriptor$archive_bytes
    ),
    archive_unpack_and_validation = list(
      elapsed_ms = bundle_load_measurement$elapsed_ms,
      rss_before_kb = bundle_load_measurement$rss_before_kb,
      rss_after_kb = bundle_load_measurement$rss_after_kb,
      hwm_after_kb = bundle_load_measurement$hwm_after_kb
    ),
    selected_gene_expression_query_to_ipc = list(
      method = "Production DuckDB query plus chunked Arrow IPC writer against the selected gene's full real-data feature block.",
      summary_ms = benchmark_summary(expression_elapsed_ms),
      samples = expression_samples
    ),
    final_process_rss_kb = final_status$rss_kb,
    final_process_hwm_kb = final_status$hwm_kb,
    rss_gate = processing_gate
  ),
  browser = NULL,
  acceptance = list(
    rss_limit_bytes = rss_limit_bytes,
    processing_rss_under_limit = processing_gate$passed,
    browser_visualization_rss_under_limit = NULL,
    real_explore_evidence_status = "pending_browser_visualization"
  )
)
benchmark_write_real_h5ad_result(payload, paths)

if (!isTRUE(processing_gate$passed)) {
  stop(
    "Real Explore processing exceeded the ",
    rss_limit_bytes,
    " byte RSS limit; raw results were written to ",
    paths$results_file,
    call. = FALSE
  )
}

cat("Wrote real Explore processing metrics to ", paths$results_file, "\n", sep = "")
