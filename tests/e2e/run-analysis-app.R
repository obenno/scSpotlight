source("tests/e2e/create-analysis-fixture.R")

port <- suppressWarnings(as.integer(Sys.getenv("SCSPOTLIGHT_E2E_PORT", "8899")))
if (is.na(port) || port < 1L || port > 65535L) {
  stop("SCSPOTLIGHT_E2E_PORT must be a valid port number.", call. = FALSE)
}

fixture_path <- file.path(
  getwd(),
  "tests",
  "e2e",
  ".tmp",
  "view-filter-e2e.rds"
)
create_analysis_fixture(fixture_path)

devtools::load_all(".", quiet = TRUE, export_all = FALSE)
run_app(
  runningMode = "analysis",
  nCores = 1L,
  options = list(
    port = port,
    host = "127.0.0.1",
    launch.browser = FALSE
  )
)
