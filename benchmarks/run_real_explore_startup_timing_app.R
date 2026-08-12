source(file.path("benchmarks", "real_explore_helpers.R"))

devtools::load_all(".", quiet = TRUE, export_all = FALSE)
benchmark_timing_enabled <- getFromNamespace(
  "scspotlight_benchmark_timing_enabled",
  "scSpotlight"
)

paths <- benchmark_real_explore_startup_timing_paths()
if (!file.exists(paths$archive_file) || !file.exists(paths$descriptor_file)) {
  stop(
    "The retained real Explore archive or descriptor is missing. Set SCSPOTLIGHT_REAL_EXPLORE_SOURCE_RUN_ID or explicit timing paths.",
    call. = FALSE
  )
}

port <- suppressWarnings(as.integer(Sys.getenv("SCSPOTLIGHT_BENCHMARK_PORT", "8903")))
if (is.na(port) || port < 1L || port > 65535L) {
  stop("SCSPOTLIGHT_BENCHMARK_PORT must be a valid port number.", call. = FALSE)
}

dir.create(paths$run_root, recursive = TRUE, showWarnings = FALSE)
unlink(paths$event_file, force = TRUE)
unlink(paths$results_file, force = TRUE)
writeLines(as.character(Sys.getpid()), paths$pid_file)
on.exit(unlink(paths$pid_file), add = TRUE)

mode <- tolower(trimws(Sys.getenv(
  "SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_INPUT_MODE",
  "server_data_dir"
)))
if (!mode %in% c("server_data_dir", "browser_upload")) {
  stop(
    "SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_INPUT_MODE must be server_data_dir or browser_upload.",
    call. = FALSE
  )
}

if (!benchmark_timing_enabled()) {
  stop(
    "SCSPOTLIGHT_BENCHMARK_STARTUP_TIMING must be enabled for this runner.",
    call. = FALSE
  )
}

run_app(
  runningMode = "explore",
  dataDir = if (identical(mode, "server_data_dir")) dirname(paths$archive_file) else NULL,
  nCores = 1L,
  options = list(
    port = port,
    host = "127.0.0.1",
    launch.browser = FALSE
  )
)
