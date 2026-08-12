test_that("synthetic Explore benchmark fixture uses production transfer paths", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("zip")

  helper_path <- scspotlight_test_source_path(
    "benchmarks",
    "explore_1m_helpers.R"
  )
  expect_true(file.exists(helper_path))
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
  )(bundle, transfer_dir, meta_version = 1L)
  getFromNamespace("write_backend_metadata_transfer", "scSpotlight")(metadata_transfer)
  metadata <- arrow::read_ipc_stream(metadata_transfer$filePath)
  expect_equal(nrow(metadata), 10L)
  expect_equal(as.character(metadata$cells[[1]]), "BenchmarkCell_0000001")

  reduction_transfer <- getFromNamespace(
    "prepare_backend_reduction_transfer",
    "scSpotlight"
  )(bundle, "umap", transfer_dir, reduction_version = 1L)
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
    expr_version = 1L
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
  expect_true(file.exists(result_path))
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
  expect_true(file.exists(helper_path))
  expect_true(file.exists(processing_path))
  expect_true(file.exists(browser_path))
  expect_true(file.exists(runner_path))

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
  expect_true(file.exists(helper_path))
  expect_true(file.exists(processing_path))
  expect_true(file.exists(browser_path))
  expect_true(file.exists(runner_path))

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
  expect_true(file.exists(helper_path))
  expect_true(file.exists(app_path))
  expect_true(file.exists(browser_path))
  expect_true(file.exists(runner_path))

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
