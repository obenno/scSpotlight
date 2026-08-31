test_that("synthetic Explore benchmark fixture uses production transfer paths", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("zip")

  helper_path <- scspotlight_test_source_path(
    "benchmarks",
    "explore_1m_helpers.R"
  )
  skip_if_not(
    file.exists(helper_path),
    "Benchmark harnesses are intentionally excluded from built source archives."
  )
  helper_environment <- new.env(parent = asNamespace("scSpotlight"))
  previous_source_root <- Sys.getenv(
    "SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT",
    unset = NA_character_
  )
  Sys.setenv(
    SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT = scspotlight_test_source_path()
  )
  on.exit(
    if (is.na(previous_source_root)) {
      Sys.unsetenv("SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT")
    } else {
      Sys.setenv(SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT = previous_source_root)
    },
    add = TRUE
  )
  sys.source(helper_path, envir = helper_environment)

  bundle_root <- tempfile("scspotlight_benchmark_fixture_")
  on.exit(unlink(bundle_root, recursive = TRUE, force = TRUE), add = TRUE)
  paths <- helper_environment$benchmark_write_structural_explore_bundle(
    root = bundle_root,
    cell_count = 10L
  )

  expect_true(file.exists(paths$archive))
  expect_true(file.exists(paths$manifest))
  expect_match(
    jsonlite::read_json(paths$manifest, simplifyVector = TRUE)$benchmark_fixture$kind,
    "synthetic_structural_workload",
    fixed = TRUE
  )

  provenance <- helper_environment$benchmark_git_provenance()
  expect_named(
    provenance,
    c(
      "source_revision",
      "source_dirty",
      "source_worktree_snapshot_id",
      "source_status_porcelain"
    )
  )
  expect_type(provenance$source_dirty, "logical")
  expect_type(provenance$source_status_porcelain, "character")
  if (isTRUE(provenance$source_dirty)) {
    expect_match(provenance$source_worktree_snapshot_id, "^[0-9a-f]+$")
  }

  bundle <- getFromNamespace(
    "read_scspotlight_explore_bundle",
    "scSpotlight"
  )(paths$bundle_dir)
  expect_s3_class(bundle, "scspotlight_explore_bundle")
  expect_silent(getFromNamespace(
    "assert_no_dense_scale_data",
    "scSpotlight"
  )(bundle))

  transfer_dir <- file.path(bundle_root, "transfers")
  metadata_transfer <- getFromNamespace(
    "prepare_backend_metadata_transfer",
    "scSpotlight"
  )(
    bundle,
    transfer_dir,
    meta_version = 1L,
    resource_prefix = "benchmark-session"
  )
  getFromNamespace("write_backend_metadata_transfer", "scSpotlight")(metadata_transfer)
  metadata <- arrow::read_ipc_stream(metadata_transfer$filePath)
  expect_equal(nrow(metadata), 10L)
  expect_equal(as.character(metadata$cells[[1]]), "BenchmarkCell_0000001")

  reduction_transfer <- getFromNamespace(
    "prepare_backend_reduction_transfer",
    "scSpotlight"
  )(
    bundle,
    "umap",
    transfer_dir,
    reduction_version = 1L,
    resource_prefix = "benchmark-session",
    transfer_attempt_id = 1L
  )
  getFromNamespace("write_backend_reduction_transfer", "scSpotlight")(reduction_transfer)
  reduction <- arrow::read_ipc_stream(reduction_transfer$filePath)
  expect_identical(names(reduction), c("X", "Y"))
  expect_equal(nrow(reduction), 10L)

  expression_transfer <- getFromNamespace(
    "prepare_backend_expression_transfer",
    "scSpotlight"
  )(
    bundle,
    assay = "RNA",
    feature = "BENCHMARK_GENE",
    dir_path = transfer_dir,
    expr_version = 1L,
    resource_prefix = "benchmark-session"
  )
  getFromNamespace("write_backend_expression_transfer", "scSpotlight")(expression_transfer)
  expression <- arrow::read_ipc_stream(expression_transfer$output_file)
  expect_equal(nrow(expression), 10L)
  expect_gt(as.numeric(expression$expr[[1]]), 0)
})

test_that("recorded structural evidence keeps its nonrepresentative provenance", {
  skip_if_not_installed("jsonlite")

  result_path <- scspotlight_test_source_path(
    "benchmarks",
    "evidence",
    "explore-1m-structural-2026-08-09.json"
  )
  skip_if_not(
    file.exists(result_path),
    "Benchmark evidence is intentionally excluded from built source archives."
  )
  result <- jsonlite::read_json(result_path, simplifyVector = FALSE)

  expect_identical(
    result$provenance$artifact_kind,
    "synthetic_structural_workload"
  )
  expect_identical(
    result$provenance$biological_representativeness,
    "not claimed"
  )
  expect_true(result$provenance$source_dirty)
  expect_match(
    result$provenance$source_worktree_snapshot_id,
    "^[0-9a-f]+$"
  )
  expect_equal(result$workload$cell_count, 1000000)
  expect_false(is.null(result$browser$first_view_latency_ms))
  expect_false(is.null(result$browser$selected_gene_expression_end_to_end_latency_ms))

  helper_path <- scspotlight_test_source_path(
    "benchmarks",
    "explore_1m_helpers.R"
  )
  helper_environment <- new.env(parent = asNamespace("scSpotlight"))
  sys.source(helper_path, envir = helper_environment)
  status <- helper_environment$benchmark_evidence_status(
    result,
    source_root = scspotlight_test_source_path()
  )
  expect_identical(status$current, FALSE)
  expect_true(any(grepl("representative", status$reasons, fixed = TRUE)))
  expect_true(any(grepl("current git SHA", status$reasons, fixed = TRUE)))
})

test_that("benchmark provenance must use the checkout that executes the runner", {
  helper_path <- scspotlight_test_source_path(
    "benchmarks",
    "explore_1m_helpers.R"
  )
  runner_paths <- scspotlight_test_source_path(
    "benchmarks",
    c(
      "run_explore_1m_benchmark.R",
      "run_real_h5ad_processing_benchmark.R",
      "run_real_explore_processing_benchmark.R",
      "run_explore_1m_app.R",
      "run_real_h5ad_app.R",
      "run_real_explore_app.R",
      "run_real_explore_startup_timing_app.R"
    )
  )
  skip_if_not(
    all(file.exists(c(helper_path, runner_paths))),
    "Benchmark harnesses are intentionally excluded from built source archives."
  )

  helper_environment <- new.env(parent = asNamespace("scSpotlight"))
  sys.source(helper_path, envir = helper_environment)
  source_root <- scspotlight_test_source_path()
  previous_source_root <- Sys.getenv(
    "SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT",
    unset = NA_character_
  )
  on.exit(
    if (is.na(previous_source_root)) {
      Sys.unsetenv("SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT")
    } else {
      Sys.setenv(SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT = previous_source_root)
    },
    add = TRUE
  )
  withr::local_dir(source_root)
  Sys.setenv(SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT = tempdir())
  expect_error(
    helper_environment$benchmark_execution_source_root(),
    "must match the current working directory"
  )

  Sys.setenv(SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT = source_root)
  expect_identical(
    helper_environment$benchmark_execution_source_root(),
    source_root
  )
  for (runner_path in runner_paths) {
    runner_source <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
    expect_match(runner_source, "benchmark_execution_source_root", fixed = TRUE)
    expect_match(runner_source, "devtools::load_all(source_root", fixed = TRUE)
  }
  for (runner_path in runner_paths[-c(1L, 4L)]) {
    runner_source <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
    expect_match(
      runner_source,
      'source(file.path("benchmarks", "explore_1m_helpers.R"))',
      fixed = TRUE
    )
    expect_lt(
      regexpr("benchmark_execution_source_root", runner_source, fixed = TRUE),
      regexpr(
        'source(file.path(source_root, "benchmarks", "real_',
        runner_source,
        fixed = TRUE
      )
    )
  }
})

test_that("representative benchmark evidence requires exact HEAD and environment locks", {
  skip_if_not_installed("jsonlite")

  helper_path <- scspotlight_test_source_path(
    "benchmarks",
    "explore_1m_helpers.R"
  )
  skip_if_not(
    file.exists(helper_path),
    "Benchmark harnesses are intentionally excluded from built source archives."
  )
  helper_environment <- new.env(parent = asNamespace("scSpotlight"))
  sys.source(helper_path, envir = helper_environment)

  source_root <- scspotlight_test_source_path()
  revision <- helper_environment$benchmark_git_revision(source_root)
  environment <- helper_environment$benchmark_environment(source_root)
  current_provenance <- list(
    source_revision = revision,
    source_dirty = FALSE,
    source_worktree_snapshot_id = revision,
    source_status_porcelain = character()
  )
  result <- list(
    schema_version = 2L,
    provenance = list(
      source_revision = revision,
      source_dirty = FALSE,
      source_worktree_snapshot_id = revision,
      source_status_porcelain = character(),
      artifact_kind = "cellxgene_real_h5ad",
      biological_representativeness = "representative processed artifact",
      source_md5 = "7933979b0faf179ce2674be6e4baed81"
    ),
    workload = list(cell_count = 1102250L),
    environment = environment,
    processing = list(
      rss_gate = list(peak_bytes = 1)
    ),
    browser = list(
      first_view_latency_ms = 1,
      selected_gene_expression_end_to_end_latency_ms = 1,
      server_rss = list(peak_process_hwm_bytes = 1),
      chromium_rss = list(peak_aggregate_hwm_bytes = 1),
      browser_memory = list(runtime_heap_used_bytes = 1),
      environment = list(browser_version = "test-browser")
    ),
    acceptance = list(
      rss_limit_bytes = 6000000000,
      processing_rss_under_limit = TRUE,
      browser_visualization_rss_under_limit = TRUE,
      browser_server_rss_under_limit = TRUE,
      chromium_rss_under_limit = TRUE,
      issue_27_evidence_status = "passed"
    )
  )

  current <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(current$current, TRUE)

  result$processing$rss_gate$peak_bytes <- 6000000001
  forged_processing_gate <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(forged_processing_gate$current, FALSE)
  expect_true(any(grepl(
    "processing RSS measurement",
    forged_processing_gate$reasons,
    fixed = TRUE
  )))
  result$processing$rss_gate$peak_bytes <- 1

  result$browser$server_rss$peak_process_hwm_bytes <- 6000000001
  forged_server_gate <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(forged_server_gate$current, FALSE)
  expect_true(any(grepl(
    "browser server RSS measurement",
    forged_server_gate$reasons,
    fixed = TRUE
  )))
  result$browser$server_rss$peak_process_hwm_bytes <- 1

  result$browser$chromium_rss <- list(peak_aggregate_hwm_bytes = 6000000001)
  forged_chromium_gate <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(forged_chromium_gate$current, FALSE)
  expect_true(any(grepl(
    "Chromium RSS measurement",
    forged_chromium_gate$reasons,
    fixed = TRUE
  )))
  result$browser$chromium_rss$peak_aggregate_hwm_bytes <- 1

  result$acceptance$secondary_evidence_status <- "failed"
  mixed_status <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(mixed_status$current, FALSE)
  expect_true(any(grepl(
    "Every evidence acceptance status must be passed",
    mixed_status$reasons,
    fixed = TRUE
  )))
  result$acceptance$secondary_evidence_status <- NULL

  result_file <- tempfile(fileext = ".json")
  on.exit(unlink(result_file), add = TRUE)
  jsonlite::write_json(
    result,
    result_file,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
  roundtrip_result <- jsonlite::read_json(result_file, simplifyVector = FALSE)
  roundtrip <- helper_environment$benchmark_evidence_status(
    roundtrip_result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(roundtrip$current, TRUE)

  result$provenance$source_revision <- paste(rep("0", 40L), collapse = "")
  stale <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(stale$current, FALSE)
  expect_true(any(grepl("current git SHA", stale$reasons, fixed = TRUE)))

  result$provenance$source_revision <- revision
  result$environment$lockfiles$pixi_lock_md5 <- "stale"
  stale_lock <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(stale_lock$current, FALSE)
  expect_true(any(grepl("pixi.lock", stale_lock$reasons, fixed = TRUE)))

  result$environment$lockfiles$pixi_lock_md5 <- environment$lockfiles$pixi_lock_md5
  result$environment$node_version <- "stale-node"
  stale_runtime <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(stale_runtime$current, FALSE)
  expect_true(any(grepl("node_version", stale_runtime$reasons, fixed = TRUE)))

  result$environment$node_version <- environment$node_version
  result$environment$cpu_model <- paste(environment$cpu_model, "other host")
  result$environment$environment_fingerprint <-
    helper_environment$benchmark_environment_fingerprint(result$environment)
  stale_host <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(stale_host$current, FALSE)
  expect_true(any(grepl("host cpu_model", stale_host$reasons, fixed = TRUE)))

  result$environment$cpu_model <- environment$cpu_model
  result$environment$environment_fingerprint <-
    helper_environment$benchmark_environment_fingerprint(result$environment)
  result$acceptance$chromium_rss_under_limit <- NULL
  missing_rss_gate <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(missing_rss_gate$current, FALSE)
  expect_true(any(grepl("chromium_rss_under_limit", missing_rss_gate$reasons, fixed = TRUE)))

  result$acceptance$chromium_rss_under_limit <- TRUE
  result$processing$rss_gate$peak_bytes <- -1
  result$browser$browser_memory$runtime_heap_used_bytes <- -1
  result$browser$server_rss$peak_process_hwm_bytes <- -1
  result$browser$chromium_rss$peak_aggregate_hwm_bytes <- -1
  negative_rss <- helper_environment$benchmark_evidence_status(
    result,
    source_root = source_root,
    current_provenance = current_provenance,
    current_environment = environment
  )
  expect_identical(negative_rss$current, FALSE)
  expect_true(any(grepl(
    "processing RSS measurement must be non-negative",
    negative_rss$reasons,
    fixed = TRUE
  )))
})

test_that("committed representative evidence is retained as historical evidence", {
  skip_if_not_installed("jsonlite")

  evidence_path <- scspotlight_test_source_path(
    "benchmarks",
    "evidence",
    "real-h5ad-2026-08-10.json"
  )
  helper_path <- scspotlight_test_source_path(
    "benchmarks",
    "explore_1m_helpers.R"
  )
  skip_if_not(
    all(file.exists(c(evidence_path, helper_path))),
    "Benchmark evidence is intentionally excluded from built source archives."
  )

  result <- jsonlite::read_json(evidence_path, simplifyVector = FALSE)
  helper_environment <- new.env(parent = asNamespace("scSpotlight"))
  sys.source(helper_path, envir = helper_environment)
  status <- helper_environment$benchmark_evidence_status(
    result,
    source_root = scspotlight_test_source_path()
  )

  expect_identical(result$provenance$artifact_kind, "cellxgene_real_h5ad")
  expect_equal(result$workload$cell_count, 1102250)
  expect_identical(result$provenance$source_dirty, TRUE)
  expect_identical(status$current, FALSE)
  expect_true(any(grepl("schema version 2", status$reasons, fixed = TRUE)))
  expect_true(any(grepl("current git SHA", status$reasons, fixed = TRUE)))
})

test_that("real h5ad benchmark records source provenance and a strict RSS gate", {
  helper_path <- scspotlight_test_source_path(
    "benchmarks",
    "real_h5ad_helpers.R"
  )
  processing_path <- scspotlight_test_source_path(
    "benchmarks",
    "run_real_h5ad_processing_benchmark.R"
  )
  browser_path <- scspotlight_test_source_path("benchmarks", "real-h5ad.spec.js")
  runner_path <- scspotlight_test_source_path(
    "dev",
    "run_real_h5ad_benchmark.sh"
  )
  skip_if_not(
    all(file.exists(c(helper_path, processing_path, browser_path, runner_path))),
    "Benchmark harnesses are intentionally excluded from built source archives."
  )

  helper_environment <- new.env(parent = asNamespace("scSpotlight"))
  previous_source_root <- Sys.getenv(
    "SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT",
    unset = NA_character_
  )
  Sys.setenv(
    SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT = scspotlight_test_source_path()
  )
  on.exit(
    if (is.na(previous_source_root)) {
      Sys.unsetenv("SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT")
    } else {
      Sys.setenv(SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT = previous_source_root)
    },
    add = TRUE
  )
  sys.source(helper_path, envir = helper_environment)
  expect_identical(
    helper_environment$benchmark_real_h5ad_url,
    "https://datasets.cellxgene.cziscience.com/aa6ebee3-68cc-41b4-80b2-5ef5c3317e14.h5ad"
  )
  expect_identical(
    helper_environment$benchmark_real_h5ad_expected_bytes,
    9663215939
  )
  expect_identical(
    helper_environment$benchmark_real_h5ad_expected_md5,
    "7933979b0faf179ce2674be6e4baed81"
  )
  expect_identical(
    helper_environment$benchmark_max_rss_limit_bytes,
    6000000000
  )
  expect_false(
    helper_environment$benchmark_rss_gate(
      peak_kb = 6000000001 / 1024,
      limit_bytes = 6000000000
    )$passed
  )

  processing_source <- paste(readLines(processing_path, warn = FALSE), collapse = "\n")
  helper_source <- paste(readLines(helper_path, warn = FALSE), collapse = "\n")
  browser_source <- paste(readLines(browser_path, warn = FALSE), collapse = "\n")
  runner_source <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
  expect_match(processing_source, "load_analysis_input_file", fixed = TRUE)
  expect_match(processing_source, "prepare_backend_expression_transfer", fixed = TRUE)
  expect_match(helper_source, "backend = transfer$backend", fixed = TRUE)
  expect_match(processing_source, "issue_27_evidence_status", fixed = TRUE)
  expect_match(browser_source, "SystemInfo.getProcessInfo", fixed = TRUE)
  expect_match(browser_source, "first_view_latency_ms", fixed = TRUE)
  expect_match(browser_source, "selected_gene_expression_end_to_end_latency_ms", fixed = TRUE)
  expect_match(browser_source, "chromium_rss_under_limit", fixed = TRUE)
  expect_match(runner_source, "SCSPOTLIGHT_TEMP_ROOT", fixed = TRUE)
  expect_match(runner_source, "TMPDIR", fixed = TRUE)
  expect_match(runner_source, "XDG_CACHE_HOME", fixed = TRUE)
  expect_match(runner_source, "playwright install chromium", fixed = TRUE)
})

test_that("real Explore benchmark converts the CellxGene source and measures production transfers", {
  helper_path <- scspotlight_test_source_path(
    "benchmarks",
    "real_explore_helpers.R"
  )
  processing_path <- scspotlight_test_source_path(
    "benchmarks",
    "run_real_explore_processing_benchmark.R"
  )
  browser_path <- scspotlight_test_source_path("benchmarks", "real-explore.spec.js")
  runner_path <- scspotlight_test_source_path(
    "dev",
    "run_real_explore_benchmark.sh"
  )
  skip_if_not(
    all(file.exists(c(helper_path, processing_path, browser_path, runner_path))),
    "Benchmark harnesses are intentionally excluded from built source archives."
  )

  helper_source <- paste(readLines(helper_path, warn = FALSE), collapse = "\n")
  processing_source <- paste(readLines(processing_path, warn = FALSE), collapse = "\n")
  browser_source <- paste(readLines(browser_path, warn = FALSE), collapse = "\n")
  runner_source <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
  expect_match(helper_source, "ENSG00000243485", fixed = TRUE)
  expect_match(processing_source, "convert_to_explore_bundle", fixed = TRUE)
  expect_match(processing_source, "decompress_matrix_input", fixed = TRUE)
  expect_match(processing_source, "prepare_backend_expression_transfer", fixed = TRUE)
  expect_match(processing_source, "Production DuckDB query plus chunked Arrow IPC writer", fixed = TRUE)
  expect_match(browser_source, "archive_filename", fixed = TRUE)
  expect_match(browser_source, "selected_gene_expression_end_to_end_latency_ms", fixed = TRUE)
  expect_match(browser_source, "SystemInfo.getProcessInfo", fixed = TRUE)
  expect_match(runner_source, "SCSPOTLIGHT_REAL_EXPLORE_ROOT", fixed = TRUE)
  expect_match(runner_source, "SCSPOTLIGHT_TEMP_ROOT", fixed = TRUE)
  expect_match(runner_source, "playwright install chromium", fixed = TRUE)
})

test_that("real Explore startup timing harness separates upload, readiness, and settled view", {
  helper_path <- scspotlight_test_source_path(
    "benchmarks",
    "real_explore_helpers.R"
  )
  app_path <- scspotlight_test_source_path(
    "benchmarks",
    "run_real_explore_startup_timing_app.R"
  )
  browser_path <- scspotlight_test_source_path(
    "benchmarks",
    "real-explore-startup-timing.spec.js"
  )
  runner_path <- scspotlight_test_source_path(
    "dev",
    "run_real_explore_startup_timing.sh"
  )
  skip_if_not(
    all(file.exists(c(helper_path, app_path, browser_path, runner_path))),
    "Benchmark harnesses are intentionally excluded from built source archives."
  )

  helper_source <- paste(readLines(helper_path, warn = FALSE), collapse = "\n")
  app_source <- paste(readLines(app_path, warn = FALSE), collapse = "\n")
  browser_source <- paste(readLines(browser_path, warn = FALSE), collapse = "\n")
  runner_source <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
  expect_match(helper_source, "benchmark_real_explore_startup_timing_paths", fixed = TRUE)
  expect_match(app_source, "getFromNamespace", fixed = TRUE)
  expect_match(browser_source, "browser_upload_to_server_dataset_load_start", fixed = TRUE)
  expect_match(browser_source, "initial_plot_ready_after_archive_selection_ms", fixed = TRUE)
  expect_match(browser_source, "first_view_settled_after_archive_selection_ms", fixed = TRUE)
  expect_match(browser_source, "event.source === \"browser\"", fixed = TRUE)
  expect_match(runner_source, "SCSPOTLIGHT_BENCHMARK_STARTUP_TIMING_EVENT_FILE", fixed = TRUE)
  expect_match(runner_source, "SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_EVENT_FILE", fixed = TRUE)
})
