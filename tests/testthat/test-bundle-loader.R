test_that("load_scspotlight_bundle validates input path", {
  load_scspotlight_bundle <- getFromNamespace("load_scspotlight_bundle", "scSpotlight")

  expect_error(load_scspotlight_bundle(character(0)), "Expected a single RDS file path")
  expect_error(load_scspotlight_bundle(""), "Expected a single RDS file path")
  expect_error(
    load_scspotlight_bundle(file.path(tempdir(), "missing_bundle_file.Rds")),
    "Bundle file does not exist"
  )
})

test_that("load_scspotlight_bundle reports loader failures clearly", {
  load_scspotlight_bundle <- getFromNamespace("load_scspotlight_bundle", "scSpotlight")

  bundle_dir <- tempfile("bundle_loader_")
  dir.create(bundle_dir)
  bundle_file <- file.path(bundle_dir, "object.Rds")
  saveRDS(list(not = "a seurat object"), bundle_file)

  expect_error(
    load_scspotlight_bundle(bundle_file),
    "Failed to load Seurat RDS bundle 'object\\.Rds'"
  )
})
