test_that("capture_warnings returns warnings without re-emitting them", {
  capture_warnings <- getFromNamespace("capture_warnings", "scSpotlight")

  result <- expect_silent(capture_warnings({
    warning("first warning", call. = FALSE)
    warning("second warning", call. = FALSE)
    42
  }))

  expect_equal(result$value, 42)
  expect_equal(result$warnings, c("first warning", "second warning"))
})

test_that("capture_warnings returns empty warnings when none occur", {
  capture_warnings <- getFromNamespace("capture_warnings", "scSpotlight")

  result <- capture_warnings("ok")

  expect_equal(result$value, "ok")
  expect_length(result$warnings, 0)
})
