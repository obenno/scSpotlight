explore_load_public_messages <- list(
  unsupported_file = paste(
    "Explore Mode only supports files ending in .explore-parquet.zip.",
    "Choose a scSpotlight Explore Parquet archive."
  ),
  unsupported_archive = paste(
    "This Explore archive uses an unsupported bundle type.",
    "Create it with a supported version of scSpotlight and try again."
  ),
  invalid = paste(
    "The Explore archive could not be opened. It may be incomplete or damaged.",
    "Create a new scSpotlight Explore Parquet bundle and try again."
  ),
  warning = paste(
    "The Explore archive loaded with warnings.",
    "If data appears incomplete, create a new bundle or contact the server administrator."
  )
)

explore_extraction_roots <- function(temp_root) {
  if (!dir.exists(temp_root)) {
    return(character())
  }

  list.files(
    temp_root,
    pattern = "^matrixDir",
    full.names = TRUE,
    all.files = TRUE
  )
}

write_explore_load_error_fixture <- function(scenario) {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("zip")

  fixture_root <- tempfile("explore_load_server_private_")
  bundle_parent <- file.path(fixture_root, "server-private", "session-31")
  bundle_dir <- file.path(bundle_parent, "uploaded-bundle")
  archive_dir <- file.path(fixture_root, "browser-uploads")
  dir.create(file.path(bundle_dir, "reductions"), recursive = TRUE)
  dir.create(file.path(bundle_dir, "expression"), recursive = TRUE)
  dir.create(archive_dir, recursive = TRUE)

  if (identical(scenario, "missing_manifest")) {
    writeLines("not an Explore bundle", file.path(bundle_dir, "README.txt"))
  } else {
    manifest <- list(
      bundle_type = if (
        scenario %in%
          c(
            "unsupported_bundle_type",
            "multiple_manifests",
            "mixed_matrix_unsupported_manifest"
          )
      ) {
        "future_scspotlight_bundle"
      } else if (identical(scenario, "malformed_bundle_type")) {
        c("scspotlight_explore_parquet_bundle", "future_bundle")
      } else if (identical(scenario, "blank_bundle_type")) {
        "   "
      } else {
        getFromNamespace(
          "scspotlight_explore_bundle_type",
          "scSpotlight"
        )
      },
      schema_version = 1L,
      created_at = "2026-08-13 00:00:00 UTC",
      scspotlight_version = "0.0.5.9000",
      cell_count = 2L,
      feature_count = 1L,
      assay = "RNA",
      layer = "data",
      default_assay = "RNA",
      assays = if (identical(scenario, "invalid_assays")) {
        list(list(name = "RNA", layers = list("data")), "invalid")
      } else {
        list(list(name = "RNA", layers = list("data")))
      },
      block_size = 1024L,
      expression_compression = "zstd",
      reductions = "umap"
    )
    if (identical(scenario, "missing_bundle_type")) {
      manifest$bundle_type <- NULL
    }
    jsonlite::write_json(
      manifest,
      file.path(bundle_dir, "manifest.json"),
      auto_unbox = TRUE
    )
    if (
      scenario %in%
        c(
          "multiple_manifests",
          "multiple_supported_manifests",
          "valid_with_extra_manifest",
          "valid_with_malformed_manifest"
        )
    ) {
      nested_dir <- file.path(bundle_dir, "nested-bundle")
      dir.create(nested_dir)
      nested_manifest_path <- file.path(nested_dir, "manifest.json")
      if (identical(scenario, "valid_with_malformed_manifest")) {
        writeLines("{ malformed private manifest", nested_manifest_path)
      } else {
        nested_manifest <- manifest
        if (!identical(scenario, "multiple_supported_manifests")) {
          nested_manifest$bundle_type <- "future_scspotlight_bundle"
        }
        jsonlite::write_json(
          nested_manifest,
          nested_manifest_path,
          auto_unbox = TRUE
        )
      }
    }
    if (identical(scenario, "mixed_matrix_unsupported_manifest")) {
      writeLines(
        "%%MatrixMarket matrix coordinate integer general",
        file.path(
          bundle_dir,
          "matrix.mtx"
        )
      )
    }
    arrow::write_parquet(
      data.frame(cell_idx = 0:1, cell_id = c("cell-1", "cell-2")),
      file.path(bundle_dir, "cells.parquet")
    )
    arrow::write_parquet(
      data.frame(
        cluster = c("a", "b"),
        .scspotlight_cell_idx = 0:1,
        check.names = FALSE
      ),
      file.path(bundle_dir, "metadata.parquet")
    )
    arrow::write_parquet(
      data.frame(
        feature_idx = 0L,
        feature = "g1",
        assay = "RNA",
        layer = "data",
        block = 0L
      ),
      file.path(bundle_dir, "features.parquet")
    )
    arrow::write_parquet(
      data.frame(
        cell_idx = 0:1,
        UMAP_1 = c(1, 2),
        UMAP_2 = c(3, 4)
      ),
      file.path(bundle_dir, "reductions", "umap.parquet")
    )
    arrow::write_parquet(
      data.frame(
        feature_idx = integer(),
        cell_idx = integer(),
        value = numeric()
      ),
      file.path(bundle_dir, "expression", "block_00000.parquet")
    )

    if (
      !scenario %in%
        c(
          "valid",
          "unsupported_bundle_type",
          "missing_bundle_type",
          "malformed_bundle_type",
          "blank_bundle_type",
          "multiple_manifests",
          "multiple_supported_manifests",
          "valid_with_extra_manifest",
          "valid_with_malformed_manifest",
          "mixed_matrix_unsupported_manifest",
          "invalid_assays"
        )
    ) {
      switch(
        scenario,
        missing_required_file = unlink(file.path(
          bundle_dir,
          "metadata.parquet"
        )),
        invalid_schema = arrow::write_parquet(
          data.frame(cluster = c("a", "b")),
          file.path(bundle_dir, "metadata.parquet")
        ),
        invalid_index = arrow::write_parquet(
          data.frame(cell_idx = c(0L, 0L), cell_id = c("cell-1", "cell-2")),
          file.path(bundle_dir, "cells.parquet")
        ),
        missing_reduction = unlink(
          file.path(bundle_dir, "reductions", "umap.parquet")
        ),
        missing_expression_block = unlink(
          file.path(bundle_dir, "expression", "block_00000.parquet")
        ),
        corrupt_parquet = writeLines(
          "private raw Parquet failure data",
          file.path(bundle_dir, "metadata.parquet")
        ),
        stop("Unknown Explore load error fixture scenario: ", scenario)
      )
    }
  }

  archive <- file.path(
    archive_dir,
    paste0(scenario, ".explore-parquet.zip")
  )
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(bundle_parent)
  zip::zipr(
    zipfile = archive,
    files = basename(bundle_dir),
    recurse = TRUE,
    include_directories = TRUE
  )

  list(
    root = fixture_root,
    archive = archive
  )
}

expect_path_free_explore_load_failure <- function(
  scenario,
  diagnostic_pattern,
  expected_public_message = explore_load_public_messages$invalid
) {
  load_explore_input_file <- getFromNamespace(
    "load_explore_input_file",
    "scSpotlight"
  )
  fixture <- write_explore_load_error_fixture(scenario)
  on.exit(unlink(fixture$root, recursive = TRUE, force = TRUE), add = TRUE)

  notifications <- character()
  statuses <- character()
  diagnostics <- character()
  temp_root <- file.path(fixture$root, "server-private", "extract")
  loaded <- load_explore_input_file(
    input_file = fixture$archive,
    input_name = basename(fixture$archive),
    temp_root = temp_root,
    status = function(message) statuses <<- c(statuses, as.character(message)),
    notify = function(ui, ...) {
      notifications <<- c(notifications, as.character(ui))
    },
    diagnostic = function(message) {
      diagnostics <<- c(diagnostics, as.character(message))
    }
  )

  expect_null(loaded)
  expect_identical(tail(statuses, 1L), expected_public_message)
  expect_identical(
    tail(notifications, 1L),
    expected_public_message
  )

  public_messages <- c(statuses, notifications)
  expect_false(any(grepl(fixture$root, public_messages, fixed = TRUE)))
  expect_false(any(grepl(
    "/tmp|server-private|session-31|matrixDir|manifest\\.json|metadata\\.parquet|DuckDB|Arrow|Traceback|Calls:",
    public_messages,
    ignore.case = TRUE
  )))
  expect_length(diagnostics, 1L)
  expect_match(
    diagnostics,
    normalizePath(fixture$archive, winslash = "/", mustWork = TRUE),
    fixed = TRUE
  )
  expect_match(diagnostics, diagnostic_pattern)
  expect_identical(explore_extraction_roots(temp_root), character())
}

test_that("Explore input boundary distinguishes unsupported files", {
  load_explore_input_file <- getFromNamespace(
    "load_explore_input_file",
    "scSpotlight"
  )
  notifications <- character()
  statuses <- character()

  loaded <- load_explore_input_file(
    input_file = "/tmp/server-private/session-31/object.Rds",
    input_name = "object.Rds",
    temp_root = tempdir(),
    status = function(message) statuses <<- c(statuses, as.character(message)),
    notify = function(ui, ...) {
      notifications <<- c(notifications, as.character(ui))
    }
  )

  expect_null(loaded)
  expect_identical(statuses, explore_load_public_messages$unsupported_file)
  expect_identical(
    notifications,
    explore_load_public_messages$unsupported_file
  )
  expect_false(any(grepl(
    "/tmp|server-private|session-31|object.Rds",
    c(
      statuses,
      notifications
    )
  )))
})

test_that("Explore input boundary preserves valid bundle loading", {
  load_explore_input_file <- getFromNamespace(
    "load_explore_input_file",
    "scSpotlight"
  )
  fixture <- write_explore_load_error_fixture("valid")
  on.exit(unlink(fixture$root, recursive = TRUE, force = TRUE), add = TRUE)

  notifications <- character()
  diagnostics <- character()
  temp_root <- file.path(fixture$root, "server-private", "extract")
  loaded <- load_explore_input_file(
    input_file = fixture$archive,
    input_name = basename(fixture$archive),
    temp_root = temp_root,
    notify = function(ui, ...) {
      notifications <<- c(notifications, as.character(ui))
    },
    diagnostic = function(message) {
      diagnostics <<- c(diagnostics, as.character(message))
    }
  )

  expect_named(loaded, c("object", "assays", "default_assay"))
  expect_s3_class(loaded$object, "scspotlight_explore_bundle")
  expect_equal(loaded$object$manifest$cell_count, 2L)
  expect_equal(loaded$object$manifest$reductions, "umap")
  expect_equal(loaded$assays, "RNA")
  expect_equal(loaded$default_assay, "RNA")
  expect_length(notifications, 0L)
  expect_length(diagnostics, 0L)
  extraction_roots <- explore_extraction_roots(temp_root)
  expect_length(extraction_roots, 1L)
  expect_true(file.exists(file.path(loaded$object$root, "metadata.parquet")))
  expect_true(startsWith(
    normalizePath(loaded$object$root, winslash = "/", mustWork = TRUE),
    paste0(
      normalizePath(extraction_roots[[1]], winslash = "/", mustWork = TRUE),
      "/"
    )
  ))
})

test_that("Explore input boundary preserves supported-root selection", {
  load_explore_input_file <- getFromNamespace(
    "load_explore_input_file",
    "scSpotlight"
  )
  expect_supported_root_load <- function(scenario) {
    fixture <- write_explore_load_error_fixture(scenario)
    on.exit(unlink(fixture$root, recursive = TRUE, force = TRUE), add = TRUE)

    notifications <- character()
    diagnostics <- character()
    loaded <- load_explore_input_file(
      input_file = fixture$archive,
      input_name = basename(fixture$archive),
      temp_root = file.path(fixture$root, "server-private", "extract"),
      notify = function(ui, ...) {
        notifications <<- c(notifications, as.character(ui))
      },
      diagnostic = function(message) {
        diagnostics <<- c(diagnostics, as.character(message))
      }
    )

    expect_named(loaded, c("object", "assays", "default_assay"))
    expect_s3_class(loaded$object, "scspotlight_explore_bundle")
    expect_equal(
      loaded$object$manifest$bundle_type,
      getFromNamespace(
        "scspotlight_explore_bundle_type",
        "scSpotlight"
      )
    )
    expect_length(notifications, 0L)
    expect_length(diagnostics, 0L)
  }

  for (scenario in c(
    "valid_with_extra_manifest",
    "multiple_supported_manifests"
  )) {
    expect_supported_root_load(scenario)
  }
})

test_that("Explore input boundary sanitizes malformed archive failures", {
  scenarios <- c(
    missing_manifest = "manifest",
    missing_required_file = "metadata\\.parquet",
    invalid_schema = "required column",
    invalid_index = "dense, unique cell_idx",
    invalid_assays = "operator is invalid for atomic vectors",
    valid_with_malformed_manifest = "parse error|lexical error|JSON",
    mixed_matrix_unsupported_manifest = "manifest not found",
    missing_reduction = "umap",
    missing_expression_block = "block_00000\\.parquet",
    corrupt_parquet = "Invalid Input Error|magic bytes|Parquet|DuckDB"
  )

  for (scenario in names(scenarios)) {
    expect_path_free_explore_load_failure(
      scenario,
      scenarios[[scenario]]
    )
  }
})

test_that("Explore input boundary identifies unsupported bundle types", {
  expect_path_free_explore_load_failure(
    "unsupported_bundle_type",
    "future_scspotlight_bundle",
    expected_public_message = explore_load_public_messages$unsupported_archive
  )
})

test_that("Explore input boundary treats malformed manifest types as invalid", {
  scenarios <- c(
    missing_bundle_type = "missing or malformed bundle_type",
    malformed_bundle_type = "missing or malformed bundle_type",
    blank_bundle_type = "missing or malformed bundle_type",
    multiple_manifests = "multiple manifest\\.json"
  )

  for (scenario in names(scenarios)) {
    expect_path_free_explore_load_failure(
      scenario,
      scenarios[[scenario]]
    )
  }
})

test_that("Explore input boundary sanitizes decompression failures", {
  skip_if_not_installed("zip")

  load_explore_input_file <- getFromNamespace(
    "load_explore_input_file",
    "scSpotlight"
  )
  fixture_root <- tempfile("explore_corrupt_archive_private_")
  dir.create(fixture_root)
  on.exit(unlink(fixture_root, recursive = TRUE, force = TRUE), add = TRUE)
  archive <- file.path(fixture_root, "corrupt.explore-parquet.zip")
  writeLines("not a zip archive", archive)
  temp_root <- file.path(fixture_root, "server-private", "extract")

  notifications <- character()
  diagnostics <- character()
  loaded <- load_explore_input_file(
    input_file = archive,
    input_name = basename(archive),
    temp_root = temp_root,
    notify = function(ui, ...) {
      notifications <<- c(notifications, as.character(ui))
    },
    diagnostic = function(message) {
      diagnostics <<- c(diagnostics, as.character(message))
    }
  )

  expect_null(loaded)
  expect_identical(notifications, explore_load_public_messages$invalid)
  expect_false(any(grepl(
    "/tmp|server-private|corrupt\\.explore|zip archive|zip error",
    notifications,
    ignore.case = TRUE
  )))
  expect_length(diagnostics, 1L)
  expect_match(
    diagnostics,
    normalizePath(archive, winslash = "/"),
    fixed = TRUE
  )
  expect_identical(explore_extraction_roots(temp_root), character())
})

test_that("decompression removes partial extraction roots after failures", {
  decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  fixture_root <- tempfile("explore_partial_extract_private_")
  dir.create(fixture_root)
  on.exit(unlink(fixture_root, recursive = TRUE, force = TRUE), add = TRUE)
  payload <- file.path(fixture_root, "payload.txt")
  archive <- file.path(fixture_root, "payload.tar.gz")
  writeLines("archive payload", payload)
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(fixture_root)
  utils::tar(archive, files = basename(payload), compression = "gzip")

  testthat::local_mocked_bindings(
    untar = function(tarfile, exdir, ...) {
      writeLines("partial private data", file.path(exdir, "partial.txt"))
      stop("private extraction failure", call. = FALSE)
    },
    .package = "scSpotlight"
  )

  temp_root <- file.path(fixture_root, "server-private", "extract")
  extraction_error <- tryCatch(
    decompress_matrix_input(
      basename(archive),
      archive,
      temp_root = temp_root,
      return_extraction_details = TRUE
    ),
    error = identity
  )

  expect_s3_class(extraction_error, "error")
  expect_match(
    conditionMessage(extraction_error),
    "private extraction failure",
    fixed = TRUE
  )
  expect_identical(explore_extraction_roots(temp_root), character())
})

test_that("Explore input boundary logs raw warnings but only shows generic warnings", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("zip")

  load_explore_input_file <- getFromNamespace(
    "load_explore_input_file",
    "scSpotlight"
  )
  original_decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  fixture <- write_explore_load_error_fixture("valid")
  on.exit(unlink(fixture$root, recursive = TRUE, force = TRUE), add = TRUE)
  raw_warning <- paste(
    "Arrow warning for",
    file.path(fixture$root, "server-private", "metadata.parquet")
  )
  testthat::local_mocked_bindings(
    decompress_matrix_input = function(...) {
      warning(raw_warning, call. = FALSE)
      original_decompress_matrix_input(...)
    },
    .package = "scSpotlight"
  )

  notifications <- character()
  diagnostics <- character()
  loaded <- load_explore_input_file(
    input_file = fixture$archive,
    input_name = basename(fixture$archive),
    temp_root = file.path(fixture$root, "server-private", "extract"),
    notify = function(ui, type = "default", ...) {
      notifications <<- c(notifications, paste(type, as.character(ui)))
    },
    diagnostic = function(message) {
      diagnostics <<- c(diagnostics, as.character(message))
    }
  )

  expect_named(loaded, c("object", "assays", "default_assay"))
  expect_identical(
    notifications,
    paste("warning", explore_load_public_messages$warning)
  )
  expect_false(any(grepl(fixture$root, notifications, fixed = TRUE)))
  expect_false(any(grepl("Arrow|metadata\\.parquet", notifications)))
  expect_length(diagnostics, 1L)
  expect_match(diagnostics, raw_warning, fixed = TRUE)
})

test_that("Explore input boundary retains warnings when loading later fails", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("zip")

  load_explore_input_file <- getFromNamespace(
    "load_explore_input_file",
    "scSpotlight"
  )
  original_decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  fixture <- write_explore_load_error_fixture("missing_required_file")
  on.exit(unlink(fixture$root, recursive = TRUE, force = TRUE), add = TRUE)
  raw_warning <- paste(
    "Arrow warning before failure for",
    file.path(fixture$root, "server-private", "metadata.parquet")
  )
  testthat::local_mocked_bindings(
    decompress_matrix_input = function(...) {
      warning(raw_warning, call. = FALSE)
      original_decompress_matrix_input(...)
    },
    .package = "scSpotlight"
  )

  notifications <- character()
  diagnostics <- character()
  loaded <- load_explore_input_file(
    input_file = fixture$archive,
    input_name = basename(fixture$archive),
    temp_root = file.path(fixture$root, "server-private", "extract"),
    notify = function(ui, type = "default", ...) {
      notifications <<- c(notifications, paste(type, as.character(ui)))
    },
    diagnostic = function(message) {
      diagnostics <<- c(diagnostics, as.character(message))
    }
  )

  expect_null(loaded)
  expect_identical(
    notifications,
    paste("error", explore_load_public_messages$invalid)
  )
  expect_false(any(grepl(fixture$root, notifications, fixed = TRUE)))
  expect_length(diagnostics, 2L)
  expect_match(diagnostics[[1]], raw_warning, fixed = TRUE)
  expect_match(diagnostics[[2]], "metadata\\.parquet")
})

test_that("Explore module rejects invalid artifacts without replacing Session state", {
  skip_if_not_installed("shiny")

  session <- shiny::MockShinySession$new()
  session$options$golem_options <- list(
    runningMode = "explore",
    dataDir = NULL,
    nCores = 1L
  )
  session$userData$tempDir <- tempfile("explore_module_temp_")
  session$userData$backendDir <- tempfile("explore_module_backend_")
  dir.create(session$userData$tempDir, recursive = TRUE)
  dir.create(session$userData$backendDir, recursive = TRUE)
  on.exit(
    unlink(
      c(session$userData$tempDir, session$userData$backendDir),
      recursive = TRUE,
      force = TRUE
    ),
    add = TRUE
  )

  current_artifact <- structure(list(id = "active"), class = "dataset_artifact")
  artifact_value <- shiny::reactiveVal(current_artifact)
  gene_indicator <- shiny::reactiveVal(4L)
  metadata_indicator <- shiny::reactiveVal(5L)
  reduction_indicator <- shiny::reactiveVal(6L)
  notifications <- character()
  waiter_hidden <- 0L
  reset_calls <- 0L

  testthat::local_mocked_bindings(
    waiter_show = function(...) invisible(NULL),
    waiter_update = function(...) invisible(NULL),
    waiting_screen = function(message = NULL) message %||% "loading",
    showNotification = function(ui, ..., session = NULL) {
      notifications <<- c(notifications, as.character(ui))
      invisible(NULL)
    },
    load_explore_input_file = function(
      input_file,
      input_name,
      status,
      notify,
      ...
    ) {
      expect_match(input_file, "server-private", fixed = TRUE)
      expect_identical(input_name, "bad.explore-parquet.zip")
      status(explore_load_public_messages$invalid)
      notify(explore_load_public_messages$invalid, type = "error", duration = 8)
      NULL
    },
    .package = "scSpotlight"
  )
  testthat::local_mocked_bindings(
    waiter_hide = function(...) {
      waiter_hidden <<- waiter_hidden + 1L
      invisible(NULL)
    },
    .package = "waiter"
  )

  testServer(
    getFromNamespace("mod_dataInput_server", "scSpotlight"),
    session = session,
    args = list(
      obj = artifact_value,
      hvgSelectMethod = shiny::reactive("vst"),
      clusterDims = shiny::reactive(30L),
      clusterResolution = shiny::reactive(0.5),
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = metadata_indicator,
      reductionUpdateIndicator = reduction_indicator,
      analysisTransition = list(reset = function(...) {
        reset_calls <<- reset_calls + 1L
        TRUE
      })
    ),
    {
      session$setInputs(
        dataInput = list(
          name = "bad.explore-parquet.zip",
          datapath = "/tmp/server-private/session-31/bad.explore-parquet.zip"
        )
      )
      session$flushReact()
    }
  )

  expect_identical(shiny::isolate(artifact_value()), current_artifact)
  expect_identical(shiny::isolate(gene_indicator()), 4L)
  expect_identical(shiny::isolate(metadata_indicator()), 5L)
  expect_identical(shiny::isolate(reduction_indicator()), 6L)
  expect_identical(reset_calls, 0L)
  expect_identical(waiter_hidden, 1L)
  expect_identical(notifications, explore_load_public_messages$invalid)
  expect_false(any(grepl(
    "/tmp|server-private|session-31|bad.explore",
    notifications
  )))
})

test_that("Explore module applies a validated load result", {
  skip_if_not_installed("shiny")

  session <- shiny::MockShinySession$new()
  session$options$golem_options <- list(
    runningMode = "explore",
    dataDir = NULL,
    nCores = 1L
  )
  session$userData$tempDir <- tempfile("explore_success_temp_")
  session$userData$backendDir <- tempfile("explore_success_backend_")
  dir.create(session$userData$tempDir, recursive = TRUE)
  dir.create(session$userData$backendDir, recursive = TRUE)
  on.exit(
    unlink(
      c(session$userData$tempDir, session$userData$backendDir),
      recursive = TRUE,
      force = TRUE
    ),
    add = TRUE
  )

  loaded_bundle <- structure(
    list(manifest = list(default_assay = "RNA")),
    class = "scspotlight_explore_bundle"
  )
  artifact_value <- shiny::reactiveVal(NULL)
  gene_indicator <- shiny::reactiveVal(0L)
  metadata_indicator <- shiny::reactiveVal(0L)
  reduction_indicator <- shiny::reactiveVal(0L)
  assay_updates <- list()

  testthat::local_mocked_bindings(
    waiter_show = function(...) invisible(NULL),
    waiter_update = function(...) invisible(NULL),
    updateSelectizeInput = function(
      session,
      inputId,
      choices = NULL,
      selected = NULL,
      ...
    ) {
      if (identical(inputId, "selectAssay")) {
        assay_updates <<- list(choices = choices, selected = selected)
      }
      invisible(NULL)
    },
    load_explore_input_file = function(...) {
      list(
        object = loaded_bundle,
        assays = "RNA",
        default_assay = "RNA"
      )
    },
    show_captured_warnings = function(...) {
      stop("Explore loads must not show raw captured warnings")
    },
    .package = "scSpotlight"
  )

  testServer(
    getFromNamespace("mod_dataInput_server", "scSpotlight"),
    session = session,
    args = list(
      obj = artifact_value,
      hvgSelectMethod = shiny::reactive("vst"),
      clusterDims = shiny::reactive(30L),
      clusterResolution = shiny::reactive(0.5),
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = metadata_indicator,
      reductionUpdateIndicator = reduction_indicator
    ),
    {
      session$setInputs(
        dataInput = list(
          name = "valid.explore-parquet.zip",
          datapath = "/tmp/server-private/session-31/valid.explore-parquet.zip"
        )
      )
      session$flushReact()
    }
  )

  expect_identical(shiny::isolate(artifact_value()), loaded_bundle)
  expect_identical(shiny::isolate(gene_indicator()), 1)
  expect_identical(shiny::isolate(metadata_indicator()), 1)
  expect_identical(shiny::isolate(reduction_indicator()), 1)
  expect_identical(assay_updates, list(choices = "RNA", selected = "RNA"))
})

test_that("Analysis module preserves successful load publication behavior", {
  skip_if_not_installed("shiny")

  session <- shiny::MockShinySession$new()
  session$options$golem_options <- list(
    runningMode = "analysis",
    dataDir = NULL,
    nCores = 1L
  )
  session$userData$tempDir <- tempfile("analysis_success_temp_")
  session$userData$backendDir <- tempfile("analysis_success_backend_")
  dir.create(session$userData$tempDir, recursive = TRUE)
  dir.create(session$userData$backendDir, recursive = TRUE)
  on.exit(
    unlink(
      c(session$userData$tempDir, session$userData$backendDir),
      recursive = TRUE,
      force = TRUE
    ),
    add = TRUE
  )

  loaded_analysis <- structure(
    list(id = "analysis"),
    class = "analysis_fixture"
  )
  artifact_value <- shiny::reactiveVal(NULL)
  gene_indicator <- shiny::reactiveVal(0L)
  metadata_indicator <- shiny::reactiveVal(0L)
  reduction_indicator <- shiny::reactiveVal(0L)
  assay_updates <- list()
  warning_details <- list()
  assays_saw_published <- FALSE
  default_saw_published <- FALSE
  warnings_saw_published <- FALSE

  testthat::local_mocked_bindings(
    assert_bpcells_available = function(...) invisible(TRUE),
    assert_no_dense_scale_data = function(...) invisible(TRUE),
    waiter_show = function(...) invisible(NULL),
    waiter_update = function(...) invisible(NULL),
    updateSelectizeInput = function(
      session,
      inputId,
      choices = NULL,
      selected = NULL,
      ...
    ) {
      if (identical(inputId, "selectAssay")) {
        assay_updates <<- list(choices = choices, selected = selected)
      }
      invisible(NULL)
    },
    load_analysis_input_file = function(...) {
      warning("analysis fixture warning", call. = FALSE)
      loaded_analysis
    },
    load_explore_input_file = function(...) {
      stop("Analysis Mode must not use the Explore loader")
    },
    get_backend_assays = function(object) {
      assays_saw_published <<- identical(
        shiny::isolate(artifact_value()),
        loaded_analysis
      )
      "RNA"
    },
    get_backend_default_assay = function(object) {
      default_saw_published <<- identical(
        shiny::isolate(artifact_value()),
        loaded_analysis
      )
      "RNA"
    },
    show_captured_warnings = function(warnings, title, ...) {
      warnings_saw_published <<- identical(
        shiny::isolate(artifact_value()),
        loaded_analysis
      )
      warning_details <<- list(warnings = warnings, title = title)
      invisible(NULL)
    },
    .package = "scSpotlight"
  )

  testServer(
    getFromNamespace("mod_dataInput_server", "scSpotlight"),
    session = session,
    args = list(
      obj = artifact_value,
      hvgSelectMethod = shiny::reactive("vst"),
      clusterDims = shiny::reactive(30L),
      clusterResolution = shiny::reactive(0.5),
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = metadata_indicator,
      reductionUpdateIndicator = reduction_indicator
    ),
    {
      session$setInputs(
        dataInput = list(
          name = "valid-analysis.Rds",
          datapath = "/tmp/server-private/session-31/valid-analysis.Rds"
        )
      )
      session$flushReact()
    }
  )

  expect_identical(shiny::isolate(artifact_value()), loaded_analysis)
  expect_true(assays_saw_published)
  expect_true(default_saw_published)
  expect_true(warnings_saw_published)
  expect_identical(assay_updates, list(choices = "RNA", selected = "RNA"))
  expect_identical(
    warning_details,
    list(
      warnings = "analysis fixture warning",
      title = "Input loaded with warnings: valid-analysis.Rds"
    )
  )
  expect_identical(shiny::isolate(gene_indicator()), 1)
  expect_identical(shiny::isolate(metadata_indicator()), 1)
  expect_identical(shiny::isolate(reduction_indicator()), 1)
})
