test_that("configured test source roots fail closed", {
  skip_if_not_installed("withr")

  missing_root <- tempfile("scspotlight_missing_source_root_")
  withr::local_envvar(SCSPOTLIGHT_TEST_SOURCE_ROOT = missing_root)

  expect_error(
    scspotlight_test_source_root(),
    "SCSPOTLIGHT_TEST_SOURCE_ROOT does not contain package source",
    fixed = TRUE
  )
})

test_that("source checkouts resolve their own root without configuration", {
  skip_if_not_installed("withr")

  withr::local_envvar(c(
    SCSPOTLIGHT_TEST_SOURCE_ROOT = "",
    SCSPOTLIGHT_TEST_SOURCE_KIND = "built_source_archive",
    `_R_CHECK_PACKAGE_NAME_` = "scSpotlight"
  ))

  root <- scspotlight_test_source_root()

  expect_true(file.exists(file.path(root, "DESCRIPTION")))
  expect_true(file.exists(file.path(root, "tests", "testthat")))
  expect_identical(
    scspotlight_test_source_path("DESCRIPTION"),
    file.path(root, "DESCRIPTION")
  )
})

test_that("package checks run the built source archive in isolation", {
  check_script <- scspotlight_test_source_path("dev", "check_package.R")
  skip_if_not(
    file.exists(check_script),
    "Package-check tooling is intentionally excluded from built source archives."
  )

  source_text <- paste(readLines(check_script, warn = FALSE), collapse = "\n")

  expect_match(source_text, "devtools::build", fixed = TRUE)
  expect_match(source_text, "utils::untar", fixed = TRUE)
  expect_match(source_text, "devtools::check_built", fixed = TRUE)
  expect_match(source_text, "SCSPOTLIGHT_TEST_SOURCE_ROOT", fixed = TRUE)
  expect_no_match(source_text, "devtools::check(\n", fixed = TRUE)
})

test_that("package checks exclude project-local scratch staging from their copy", {
  check_script <- scspotlight_test_source_path("dev", "check_package.R")
  skip_if_not(
    file.exists(check_script),
    "Package-check tooling is intentionally excluded from built source archives."
  )

  source_text <- paste(readLines(check_script, warn = FALSE), collapse = "\n")

  expect_match(source_text, "scratch_relative_path", fixed = TRUE)
  expect_match(source_text, "stage_relative_path", fixed = TRUE)
  expect_match(source_text, "inside_staging_root", fixed = TRUE)
  expect_match(source_text, "\\.tmp", fixed = TRUE)
  expect_match(source_text, "\\.review-tmp", fixed = TRUE)
})
