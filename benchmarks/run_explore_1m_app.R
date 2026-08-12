source(file.path("benchmarks", "explore_1m_helpers.R"))

devtools::load_all(".", quiet = TRUE, export_all = FALSE)

port <- suppressWarnings(as.integer(Sys.getenv("SCSPOTLIGHT_BENCHMARK_PORT", "8900")))
if (is.na(port) || port < 1L || port > 65535L) {
  stop("SCSPOTLIGHT_BENCHMARK_PORT must be a valid port number.")
}

paths <- benchmark_write_structural_explore_bundle(cell_count = benchmark_cell_count())
pid_file <- Sys.getenv(
  "SCSPOTLIGHT_BENCHMARK_PID_FILE",
  file.path(paths$root, "shiny-server.pid")
)
dir.create(dirname(pid_file), recursive = TRUE, showWarnings = FALSE)
writeLines(as.character(Sys.getpid()), pid_file)
on.exit(unlink(pid_file), add = TRUE)

run_app(
  runningMode = "explore",
  dataDir = paths$root,
  nCores = 1L,
  options = list(
    port = port,
    host = "127.0.0.1",
    launch.browser = FALSE
  )
)
