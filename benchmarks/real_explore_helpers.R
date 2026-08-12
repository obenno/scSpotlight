benchmark_source_root <- Sys.getenv("SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT", getwd())
benchmark_real_h5ad_helpers_file <- file.path(
  benchmark_source_root,
  "benchmarks",
  "real_h5ad_helpers.R"
)
if (!file.exists(benchmark_real_h5ad_helpers_file)) {
  stop(
    "Unable to locate benchmarks/real_h5ad_helpers.R. Set SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT.",
    call. = FALSE
  )
}
source(benchmark_real_h5ad_helpers_file)

benchmark_real_explore_selected_gene <- "ENSG00000243485"
benchmark_real_explore_archive_filename <- paste0(
  sub("\\.[Hh]5[Aa][Dd]$", "", benchmark_real_h5ad_filename),
  ".explore-parquet.zip"
)

benchmark_real_explore_root <- function() {
  root <- Sys.getenv(
    "SCSPOTLIGHT_REAL_EXPLORE_ROOT",
    file.path(benchmark_temp_root(), "cellxgene-explore")
  )
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

benchmark_real_explore_paths <- function() {
  root <- benchmark_real_explore_root()
  run_id <- trimws(Sys.getenv("SCSPOTLIGHT_REAL_EXPLORE_RUN_ID", "latest"))
  if (!grepl("^[A-Za-z0-9_.-]+$", run_id)) {
    stop(
      "SCSPOTLIGHT_REAL_EXPLORE_RUN_ID must contain only letters, digits, _, ., or -.",
      call. = FALSE
    )
  }

  source_file <- Sys.getenv(
    "SCSPOTLIGHT_REAL_H5AD_FILE",
    file.path(
      benchmark_real_h5ad_root(),
      "source",
      benchmark_real_h5ad_filename
    )
  )
  run_root <- file.path(root, "runs", run_id)
  list(
    root = root,
    source_file = normalizePath(source_file, winslash = "/", mustWork = FALSE),
    run_root = normalizePath(run_root, winslash = "/", mustWork = FALSE),
    archive_file = file.path(run_root, benchmark_real_explore_archive_filename),
    processing_root = file.path(run_root, "processing"),
    browser_root = file.path(run_root, "browser"),
    descriptor_file = file.path(run_root, "artifact.json"),
    results_file = file.path(run_root, "results.json"),
    pid_file = file.path(run_root, "shiny-server.pid")
  )
}

benchmark_real_explore_startup_timing_paths <- function() {
  root <- benchmark_real_explore_root()
  source_run_id <- trimws(Sys.getenv(
    "SCSPOTLIGHT_REAL_EXPLORE_SOURCE_RUN_ID",
    "20260811-real-explore-streaming-fix"
  ))
  run_id <- trimws(Sys.getenv(
    "SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_RUN_ID",
    "latest"
  ))
  for (value in c(source_run_id, run_id)) {
    if (!grepl("^[A-Za-z0-9_.-]+$", value)) {
      stop(
        "Explore startup timing run IDs must contain only letters, digits, _, ., or -.",
        call. = FALSE
      )
    }
  }

  source_root <- file.path(root, "runs", source_run_id)
  timing_root <- Sys.getenv(
    "SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_ROOT",
    file.path(root, "startup-timings")
  )
  timing_root <- normalizePath(timing_root, winslash = "/", mustWork = FALSE)
  run_root <- file.path(timing_root, run_id)
  archive_file <- Sys.getenv(
    "SCSPOTLIGHT_REAL_EXPLORE_TIMING_ARCHIVE_FILE",
    file.path(source_root, benchmark_real_explore_archive_filename)
  )
  descriptor_file <- Sys.getenv(
    "SCSPOTLIGHT_REAL_EXPLORE_TIMING_DESCRIPTOR_FILE",
    file.path(source_root, "artifact.json")
  )

  list(
    source_root = normalizePath(source_root, winslash = "/", mustWork = FALSE),
    archive_file = normalizePath(archive_file, winslash = "/", mustWork = FALSE),
    descriptor_file = normalizePath(
      descriptor_file,
      winslash = "/",
      mustWork = FALSE
    ),
    run_root = normalizePath(run_root, winslash = "/", mustWork = FALSE),
    event_file = file.path(run_root, "server-events.jsonl"),
    results_file = file.path(run_root, "startup-timing.json"),
    pid_file = file.path(run_root, "shiny-server.pid"),
    browser_root = file.path(run_root, "browser")
  )
}
