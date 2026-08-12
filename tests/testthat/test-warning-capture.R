test_that("capture_operation_warnings returns warnings without re-emitting them", {
  capture_operation_warnings <- getFromNamespace(
    "capture_operation_warnings",
    "scSpotlight"
  )

  result <- expect_silent(capture_operation_warnings({
    warning("first warning", call. = FALSE)
    warning("second warning", call. = FALSE)
    42
  }))

  expect_equal(result$value, 42)
  expect_equal(result$warnings, c("first warning", "second warning"))
})

test_that("capture_operation_warnings returns empty warnings when none occur", {
  capture_operation_warnings <- getFromNamespace(
    "capture_operation_warnings",
    "scSpotlight"
  )

  result <- capture_operation_warnings("ok")

  expect_equal(result$value, "ok")
  expect_length(result$warnings, 0)
})

test_that("async transfer workers use the package warning envelope", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("future")
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  future::plan(future::sequential)

  capture_operation_warnings <- getFromNamespace(
    "capture_operation_warnings",
    "scSpotlight"
  )
  completed <- FALSE
  result <- NULL
  error <- NULL

  testthat::capture_warnings({
    promises::future_promise({
      capture_operation_warnings(list(answer = 42L))
    }) %...>%
      (function(value) {
        result <<- value
        completed <<- TRUE
      }) %...!%
      (function(condition) {
        error <<- condition
        completed <<- TRUE
      })

    while (!completed) {
      later::run_now(0.1)
    }
  })

  expect_null(error)
  expect_identical(result, list(
    value = list(answer = 42L),
    warnings = character(0)
  ))
})
