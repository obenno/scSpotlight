test_that("an older metadata patch completion cannot clear a newer request", {
  skip_if_not_installed("later")
  skip_if_not_installed("promises")
  skip_if_not_installed("shiny")

  seurat_value <- shiny::reactiveVal(NULL)
  meta_update_indicator <- shiny::reactiveVal(NULL)
  patch_request <- shiny::reactiveVal(NULL)
  meta_processed <- shiny::reactiveVal(FALSE)
  pending_promises <- list()

  testthat::local_mocked_bindings(
    future_promise = function(expr, ...) {
      promises::promise(function(resolve, reject) {
        pending_promises[[length(pending_promises) + 1L]] <<- list(
          resolve = resolve,
          reject = reject
        )
      })
    },
    prepare_backend_metadata_transfer = function(...) {
      list(filePath = tempfile("metadata-patch-"))
    },
    showNotification = function(...) invisible(NULL),
    removeNotification = function(...) invisible(NULL),
    show_captured_warnings = function(...) invisible(NULL),
    .package = "scSpotlight"
  )

  testServer(
    mod_UpdateMetaData_server,
    args = list(
      seuratObj = seurat_value,
      metaUpdateIndicator = meta_update_indicator,
      metaPatchRequest = patch_request,
      metaProcessed = meta_processed
    ),
    {
      session$userData$tempDir <- tempdir()
      session$userData$dataResourcePrefix <- "data-test-session"
      seurat_value(list(loaded = TRUE))

      older_request <- list(cols = "older", version = 1L)
      newer_request <- list(cols = "newer", version = 2L)

      patch_request(older_request)
      session$flushReact()
      expect_length(pending_promises, 1L)

      patch_request(newer_request)
      pending_promises[[1L]]$resolve(list(
        value = list(
          metaFile = "older.arrow",
          metaVersion = older_request$version,
          cols = older_request$cols,
          resourcePrefix = "data-test-session"
        ),
        warnings = character()
      ))
      for (i in seq_len(10L)) {
        later::run_now(0.05)
      }
      session$flushReact()

      expect_identical(shiny::isolate(patch_request()), newer_request)
      expect_length(pending_promises, 2L)

      pending_promises[[2L]]$resolve(list(
        value = list(
          metaFile = "newer.arrow",
          metaVersion = newer_request$version,
          cols = newer_request$cols,
          resourcePrefix = "data-test-session"
        ),
        warnings = character()
      ))
      for (i in seq_len(10L)) {
        later::run_now(0.05)
      }
      session$flushReact()

      expect_null(shiny::isolate(patch_request()))
    }
  )
})
