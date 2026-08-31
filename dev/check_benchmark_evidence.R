#!/usr/bin/env Rscript

source("benchmarks/explore_1m_helpers.R")

args <- commandArgs(trailingOnly = TRUE)
evidence_file <- if (length(args)) {
  args[[1]]
} else {
  Sys.getenv(
    "SCSPOTLIGHT_BENCHMARK_EVIDENCE_FILE",
    file.path(
      "benchmarks",
      "evidence",
      "real-h5ad-2026-08-10.json"
    )
  )
}
if (!file.exists(evidence_file)) {
  stop("Benchmark evidence file does not exist: ", evidence_file, call. = FALSE)
}

result <- jsonlite::read_json(evidence_file, simplifyVector = FALSE)
status <- benchmark_evidence_status(result, source_root = getwd())
if (!isTRUE(status$current)) {
  message("Benchmark evidence is historical, incomplete, or stale: ", evidence_file)
  for (reason in status$reasons) {
    message("- ", reason)
  }
  quit(save = "no", status = 1L)
}

message(
  "Benchmark evidence is current for ",
  status$current_revision,
  ": ",
  evidence_file
)
