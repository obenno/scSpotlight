test_that("create_bundle_archive builds a zip bundle archive", {
  skip_if_not_installed("zip")

  create_bundle_archive <- getFromNamespace(
    "create_bundle_archive",
    "scSpotlight"
  )

  root_dir <- tempfile("bundle_archive_")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  bundle_dir <- file.path(root_dir, "bundle")
  dir.create(bundle_dir)
  writeLines("hello", file.path(bundle_dir, "README.txt"))

  archive_file <- file.path(root_dir, "bundle.zip")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(root_dir)

  expect_invisible(create_bundle_archive(archive_file, "bundle"))
  expect_true(file.exists(archive_file))

  extract_dir <- tempfile("bundle_extract_")
  dir.create(extract_dir)
  on.exit(unlink(extract_dir, recursive = TRUE, force = TRUE), add = TRUE)

  zip::unzip(archive_file, exdir = extract_dir)
  expect_true(file.exists(file.path(extract_dir, "bundle", "README.txt")))
})

test_that("is_absolute_bundle_path recognizes Windows and UNC paths", {
  is_absolute_bundle_path <- getFromNamespace(
    "is_absolute_bundle_path",
    "scSpotlight"
  )

  expect_true(is_absolute_bundle_path("C:/tmp/bundle.zip"))
  expect_true(is_absolute_bundle_path("C:\\tmp\\bundle.zip"))
  expect_true(is_absolute_bundle_path("\\\\server\\share\\bundle.zip"))
  expect_true(is_absolute_bundle_path("/tmp/bundle.zip"))
  expect_false(is_absolute_bundle_path("bundle.zip"))
})

test_that("create_bundle_archive preserves bundle paths across directories", {
  skip_if_not_installed("zip")

  create_bundle_archive <- getFromNamespace(
    "create_bundle_archive",
    "scSpotlight"
  )

  root_dir <- tempfile("bundle_archive_root_")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  work_root <- file.path(root_dir, "work")
  output_root <- file.path(root_dir, "output")
  dir.create(work_root)
  dir.create(output_root)

  bundle_dir <- file.path(work_root, "bundle")
  dir.create(bundle_dir)
  writeLines("hello", file.path(bundle_dir, "README.txt"))

  archive_file <- file.path(output_root, "bundle.zip")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(work_root)

  expect_invisible(create_bundle_archive(archive_file, "bundle"))
  expect_true(file.exists(archive_file))

  extract_dir <- tempfile("bundle_extract_crossdir_")
  dir.create(extract_dir)
  on.exit(unlink(extract_dir, recursive = TRUE, force = TRUE), add = TRUE)

  zip::unzip(archive_file, exdir = extract_dir)
  expect_true(file.exists(file.path(extract_dir, "bundle", "README.txt")))
})

test_that("convert_to_bpcells_bundle writes relative output beside caller cwd", {
  skip_if_not_installed("zip")
  skip_if_not_installed("BPCells")
  skip_if_not_installed("Seurat")

  convert_to_bpcells_bundle <- getFromNamespace(
    "convert_to_bpcells_bundle",
    "scSpotlight"
  )
  ensure_assay5 <- getFromNamespace("ensure_assay5", "scSpotlight")

  root_dir <- tempfile("bundle_convert_root_")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  input_dir <- file.path(root_dir, "input")
  output_dir <- file.path(root_dir, "output")
  dir.create(input_dir)
  dir.create(output_dir)

  counts <- methods::as(
    Matrix::Matrix(matrix(c(1, 0, 2, 3), nrow = 2), sparse = TRUE),
    "dgCMatrix"
  )
  rownames(counts) <- c("g1", "g2")
  colnames(counts) <- c("c1", "c2")

  object <- Seurat::CreateSeuratObject(counts = counts)
  object <- ensure_assay5(object, assay = "RNA")
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts
  object[["percent.mt"]] <- c(0, 0)
  object[["pca"]] <- SeuratObject::CreateDimReducObject(
    embeddings = matrix(
      c(1, 2, 3, 4),
      ncol = 2,
      dimnames = list(colnames(counts), c("PC_1", "PC_2"))
    ),
    assay = "RNA",
    key = "PC_"
  )

  input_file <- file.path(input_dir, "object.Rds")
  saveRDS(object, input_file)

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(output_dir)

  output_file <- convert_to_bpcells_bundle(
    input_file,
    output_file = "converted.zip"
  )

  expect_equal(
    output_file,
    file.path(
      normalizePath(output_dir, winslash = "/", mustWork = TRUE),
      "converted.zip"
    )
  )
  expect_true(file.exists(output_file))
})
