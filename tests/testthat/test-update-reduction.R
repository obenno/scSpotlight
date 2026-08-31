test_that("overlapping reduction transfers remove only their own notifications", {
  skip_if_not_installed("later")
  skip_if_not_installed("promises")
  skip_if_not_installed("shiny")

  seurat_value <- shiny::reactiveVal(NULL)
  reduction_update_indicator <- shiny::reactiveVal(0L)
  reduction_processed <- shiny::reactiveVal(FALSE)
  pending_promises <- list()
  shown_notification_ids <- character()
  removed_notification_ids <- character()

  testthat::local_mocked_bindings(
    future_promise = function(expr, ...) {
      promises::promise(function(resolve, reject) {
        pending_promises[[length(pending_promises) + 1L]] <<- list(
          resolve = resolve,
          reject = reject
        )
      })
    },
    get_backend_reduction_names = function(...) c("umap", "pca"),
    get_backend_cell_count = function(...) 250000L,
    write_backend_pca_stdev_transfer = function(...) list(stdevFile = NULL),
    prepare_backend_reduction_transfer = function(...) list(filePath = tempfile()),
    capture_operation_warnings = function(expr) {
      list(value = expr, warnings = character())
    },
    show_captured_warnings = function(...) invisible(NULL),
    scspotlight_benchmark_timing_event = function(...) invisible(NULL),
    updateSelectizeInput = function(...) invisible(NULL),
    showNotification = function(
      ui,
      action = NULL,
      duration = NULL,
      closeButton = TRUE,
      type = "default",
      id = NULL,
      session = NULL
    ) {
      shown_notification_ids <<- c(shown_notification_ids, id)
      invisible(id)
    },
    removeNotification = function(id, session = NULL) {
      removed_notification_ids <<- c(removed_notification_ids, id)
      invisible(NULL)
    },
    .package = "scSpotlight"
  )

  testServer(
    mod_UpdateReduction_server,
    args = list(
      seuratObj = seurat_value,
      reductionUpdateIndicator = reduction_update_indicator,
      reductionProcessed = reduction_processed
    ),
    {
      session$userData$tempDir <- tempdir()
      session$userData$dataResourcePrefix <- "data-test-session"
      seurat_value(list(loaded = TRUE))

      reduction_update_indicator(1L)
      session$flushReact()
      expect_length(pending_promises, 1L)

      session$setInputs(reduction = "pca")
      session$flushReact()
      expect_length(pending_promises, 2L)
    }
  )

  expect_identical(
    shown_notification_ids,
    c(
      "update_reduction_notification_1",
      "update_reduction_notification_2"
    )
  )

  pending_promises[[2L]]$resolve(list(
    value = list(reductionFile = "pca.arrow", reductionName = "pca"),
    warnings = character()
  ))
  for (i in seq_len(10L)) {
    later::run_now(0.05)
  }

  expect_identical(
    removed_notification_ids,
    "update_reduction_notification_2"
  )

  pending_promises[[1L]]$resolve(list(
    value = list(list(reductionFile = "umap.arrow", reductionName = "umap")),
    warnings = character()
  ))
  for (i in seq_len(10L)) {
    later::run_now(0.05)
  }

  expect_identical(
    removed_notification_ids,
    c(
      "update_reduction_notification_2",
      "update_reduction_notification_1"
    )
  )
})
