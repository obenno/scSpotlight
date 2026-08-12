test_that("runtime temporary roots honor SCSPOTLIGHT_TEMP_ROOT", {
  skip_if_not_installed("withr")

  scspotlight_temp_root <- getFromNamespace(
    "scspotlight_temp_root",
    "scSpotlight"
  )
  scspotlight_temp_path <- getFromNamespace(
    "scspotlight_temp_path",
    "scSpotlight"
  )
  root <- tempfile("scspotlight_runtime_temp_")
  withr::local_envvar(SCSPOTLIGHT_TEMP_ROOT = root)

  resolved_root <- scspotlight_temp_root()
  generated_path <- scspotlight_temp_path("ipc_")

  expect_identical(resolved_root, normalizePath(root, winslash = "/"))
  expect_identical(dirname(generated_path), resolved_root)
})

test_that("application and archive paths use the shared runtime temporary root", {
  app_source <- paste(
    readLines(scspotlight_test_source_path("R", "app_server.R"), warn = FALSE),
    collapse = "\n"
  )
  input_source <- paste(
    readLines(scspotlight_test_source_path("R", "mod_dataInput.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(app_source, "scspotlight_temp_root", fixed = TRUE)
  expect_match(input_source, "scspotlight_temp_path", fixed = TRUE)
  expect_match(input_source, "temp_root = scspotlight_temp_root", fixed = TRUE)
  expect_match(input_source, "tmpdir = temp_root", fixed = TRUE)
})
