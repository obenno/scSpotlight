source(file.path("benchmarks", "real_h5ad_helpers.R"))

devtools::load_all(".", quiet = TRUE, export_all = FALSE)

paths <- benchmark_real_h5ad_paths()
benchmark_assert_real_h5ad_file(paths$source_file)
if (!file.exists(paths$descriptor_file) || !file.exists(paths$results_file)) {
  stop(
    "Run benchmarks/run_real_h5ad_processing_benchmark.R before browser measurement.",
    call. = FALSE
  )
}

port <- suppressWarnings(as.integer(Sys.getenv("SCSPOTLIGHT_BENCHMARK_PORT", "8901")))
if (is.na(port) || port < 1L || port > 65535L) {
  stop("SCSPOTLIGHT_BENCHMARK_PORT must be a valid port number.", call. = FALSE)
}

dir.create(dirname(paths$pid_file), recursive = TRUE, showWarnings = FALSE)
writeLines(as.character(Sys.getpid()), paths$pid_file)
on.exit(unlink(paths$pid_file), add = TRUE)

run_app(
  runningMode = "analysis",
  dataDir = dirname(paths$source_file),
  nCores = 1L,
  options = list(
    port = port,
    host = "127.0.0.1",
    launch.browser = FALSE
  )
)
