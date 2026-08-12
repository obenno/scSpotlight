source(file.path("benchmarks", "real_h5ad_helpers.R"))

devtools::load_all(".", quiet = TRUE, export_all = FALSE)

load_analysis_input_file <- benchmark_scspotlight_function("load_analysis_input_file")
prepare_backend_metadata_transfer <- benchmark_scspotlight_function(
  "prepare_backend_metadata_transfer"
)
write_backend_metadata_transfer <- benchmark_scspotlight_function(
  "write_backend_metadata_transfer"
)
prepare_backend_reduction_transfer <- benchmark_scspotlight_function(
  "prepare_backend_reduction_transfer"
)
write_backend_reduction_transfer <- benchmark_scspotlight_function(
  "write_backend_reduction_transfer"
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

paths <- benchmark_real_h5ad_paths()
source_file <- benchmark_assert_real_h5ad_file(paths$source_file)
dir.create(paths$processing_root, recursive = TRUE, showWarnings = FALSE)

schema <- benchmark_h5ad_schema(source_file)
baseline <- benchmark_read_proc_status()
load_measurement <- benchmark_elapsed(function() {
  load_analysis_input_file(
    input_file = source_file,
    input_name = basename(source_file),
    backend_root = file.path(paths$processing_root, "backend"),
    hvgSelectMethod = "vst",
    nDims = 30L,
    resolution = 1,
    temp_root = paths$processing_root
  )
})
object <- load_measurement$value
assay <- SeuratObject::DefaultAssay(object)
selected_reduction <- benchmark_select_real_h5ad_reduction(object)
selected_gene <- benchmark_select_real_h5ad_feature(object, assay = assay)
transfer_dir <- file.path(paths$processing_root, "transfers")
dir.create(transfer_dir, recursive = TRUE, showWarnings = FALSE)

metadata_transfer <- benchmark_transfer_measurement(
  prepare_transfer = function() {
    prepare_backend_metadata_transfer(
      object,
      dir_path = transfer_dir,
      meta_version = 1L
    )
  },
  write_transfer = write_backend_metadata_transfer
)
reduction_transfer <- benchmark_transfer_measurement(
  prepare_transfer = function() {
    prepare_backend_reduction_transfer(
      object,
      reduction_name = selected_reduction,
      dir_path = transfer_dir,
      reduction_version = 1L
    )
  },
  write_transfer = write_backend_reduction_transfer
)
expression_transfer <- benchmark_transfer_measurement(
  prepare_transfer = function() {
    prepare_backend_expression_transfer(
      object,
      assay = assay,
      feature = selected_gene,
      dir_path = transfer_dir,
      expr_version = 1L,
      backend_root = file.path(paths$processing_root, "backend")
    )
  },
  write_transfer = write_backend_expression_transfer
)

final_status <- benchmark_read_proc_status()
rss_limit_bytes <- benchmark_rss_limit_bytes()
processing_gate <- benchmark_rss_gate(
  final_status$hwm_kb,
  limit_bytes = rss_limit_bytes
)
descriptor <- list(
  source_url = benchmark_real_h5ad_url,
  source_filename = basename(source_file),
  source_bytes = unname(file.info(source_file)$size),
  source_md5 = benchmark_file_md5(source_file),
  cell_count = get_backend_cell_count(object),
  feature_count = length(get_backend_features(object, assay = assay)),
  assay = assay,
  selected_reduction = selected_reduction,
  selected_gene = selected_gene,
  reductions = get_backend_reduction_names(object),
  h5ad_schema = schema
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
  command = "pixi run benchmark-real-h5ad",
  provenance = c(
    benchmark_git_provenance(),
    list(
      artifact_kind = "cellxgene_real_h5ad",
      biological_representativeness = "CellxGene source artifact requested for issue #27",
      source_url = benchmark_real_h5ad_url,
      source_filename = basename(source_file),
      source_bytes = descriptor$source_bytes,
      source_md5 = descriptor$source_md5
    )
  ),
  workload = list(
    input = "native CellxGene AnnData h5ad import in Analysis Mode",
    cell_count = descriptor$cell_count,
    feature_count = descriptor$feature_count,
    assay = assay,
    selected_reduction = selected_reduction,
    selected_gene = selected_gene,
    storage = "BPCells-backed Seurat assay layers with Arrow IPC browser transfers"
  ),
  environment = benchmark_environment(),
  artifact = descriptor,
  processing = list(
    method = "Fresh Pixi-managed R process; Linux VmHWM records the full h5ad import, validation, BPCells preparation, and production transfer peak.",
    baseline_rss_kb = baseline$rss_kb,
    import_and_validation = list(
      elapsed_ms = load_measurement$elapsed_ms,
      rss_before_kb = load_measurement$rss_before_kb,
      rss_after_kb = load_measurement$rss_after_kb,
      hwm_after_kb = load_measurement$hwm_after_kb
    ),
    metadata_query_to_ipc = metadata_transfer,
    reduction_query_to_ipc = reduction_transfer,
    selected_gene_expression_query_to_ipc = expression_transfer,
    final_process_rss_kb = final_status$rss_kb,
    final_process_hwm_kb = final_status$hwm_kb,
    rss_gate = processing_gate
  ),
  browser = NULL,
  acceptance = list(
    rss_limit_bytes = rss_limit_bytes,
    processing_rss_under_limit = processing_gate$passed,
    browser_visualization_rss_under_limit = NULL,
    issue_27_evidence_status = "pending_browser_visualization"
  )
)
benchmark_write_real_h5ad_result(payload, paths)

if (!isTRUE(processing_gate$passed)) {
  stop(
    "Real h5ad processing exceeded the ",
    rss_limit_bytes,
    " byte RSS limit; raw results were written to ",
    paths$results_file,
    call. = FALSE
  )
}

cat("Wrote real h5ad processing metrics to ", paths$results_file, "\n", sep = "")
