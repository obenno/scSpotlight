test_that("clean_meta_frame preserves missing numeric values", {
  clean_meta_frame <- getFromNamespace("clean_meta_frame", "scSpotlight")

  meta <- data.frame(
    score = c(1, NA_real_, NaN, Inf),
    group = c("a", "b", "c", "d"),
    keep = c(TRUE, FALSE, NA, TRUE),
    row.names = c("cell-a", "cell-b", "cell-c", "cell-d"),
    stringsAsFactors = FALSE
  )

  cleaned <- clean_meta_frame(meta)

  expect_equal(
    as.character(cleaned$cells),
    c("cell-a", "cell-b", "cell-c", "cell-d")
  )
  expect_false(is.factor(cleaned$cells))
  expect_true(is.na(cleaned$score[[2]]))
  expect_true(is.na(cleaned$score[[3]]))
  expect_true(is.na(cleaned$score[[4]]))
  expect_s3_class(cleaned$group, "factor")
  expect_s3_class(cleaned$keep, "factor")
})

test_that("clean_meta_frame does not replace numeric NA with zero", {
  clean_meta_frame <- getFromNamespace("clean_meta_frame", "scSpotlight")

  meta <- data.frame(
    value = c(NA_real_, 2),
    row.names = c("cell-a", "cell-b"),
    stringsAsFactors = FALSE
  )
  cleaned <- clean_meta_frame(meta)

  expect_true(is.na(cleaned$value[[1]]))
  expect_identical(cleaned$value[[2]], 2)
})

test_that("clean_meta_frame refuses metadata without canonical Cell IDs", {
  clean_meta_frame <- getFromNamespace("clean_meta_frame", "scSpotlight")

  meta <- data.frame(value = c(1, 2), stringsAsFactors = FALSE)

  expect_error(
    clean_meta_frame(meta),
    "canonical Cell IDs",
    fixed = TRUE
  )
})
