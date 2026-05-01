test_that("write_h5ad_scanpy writes AnnData-compatible structure", {
  skip_if_not_installed("BPCells")
  skip_if_not_installed("rhdf5")

  write_h5ad_scanpy <- getFromNamespace("write_h5ad_scanpy", "scSpotlight")

  counts <- Matrix::rsparsematrix(6, 4, density = 0.4)
  counts <- abs(counts)
  rownames(counts) <- paste0("gene", seq_len(nrow(counts)))
  colnames(counts) <- paste0("cell", seq_len(ncol(counts)))

  obj <- Seurat::CreateSeuratObject(counts = counts)
  obj <- Seurat::NormalizeData(obj, verbose = FALSE)

  pca_embeddings <- matrix(runif(ncol(obj) * 3), nrow = ncol(obj), ncol = 3)
  rownames(pca_embeddings) <- colnames(obj)
  colnames(pca_embeddings) <- paste0("PC_", seq_len(ncol(pca_embeddings)))
  pca_loadings <- matrix(runif(nrow(obj) * 3), nrow = nrow(obj), ncol = 3)
  rownames(pca_loadings) <- rownames(obj)
  colnames(pca_loadings) <- colnames(pca_embeddings)
  obj[["pca"]] <- Seurat::CreateDimReducObject(
    embeddings = pca_embeddings,
    loadings = pca_loadings,
    stdev = c(2, 1, 0.5),
    assay = SeuratObject::DefaultAssay(obj),
    key = "PC_"
  )

  out <- tempfile(fileext = ".h5ad")
  write_h5ad_scanpy(obj, out)

  expect_true(file.exists(out))
  expect_identical(as.vector(rhdf5::h5readAttributes(out, "/")[["encoding-type"]]), "anndata")
  expect_identical(as.vector(rhdf5::h5readAttributes(out, "/")[["encoding-version"]]), "0.1.0")

  listing <- rhdf5::h5ls(out, recursive = TRUE)
  full_paths <- ifelse(listing$group == "/", paste0("/", listing$name), paste0(listing$group, "/", listing$name))

  expect_true("/obs" %in% full_paths)
  expect_true("/var" %in% full_paths)
  expect_true("/X" %in% full_paths)
  expect_true("/layers" %in% full_paths)
  expect_true("/raw" %in% full_paths)
  expect_true("/obsm/X_pca" %in% full_paths)
  expect_true("/varm/PCs" %in% full_paths)
  expect_true("/uns/pca/variance" %in% full_paths)

  expect_identical(as.vector(rhdf5::h5readAttributes(out, "obs")[["encoding-type"]]), "dataframe")
  expect_identical(as.vector(rhdf5::h5readAttributes(out, "var")[["encoding-type"]]), "dataframe")
  expect_identical(as.vector(rhdf5::h5readAttributes(out, "raw")[["encoding-type"]]), "raw")
  expect_identical(as.vector(rhdf5::h5readAttributes(out, "obsm")[["encoding-type"]]), "dict")
  expect_identical(as.vector(rhdf5::h5readAttributes(out, "varm")[["encoding-type"]]), "dict")
  expect_identical(as.vector(rhdf5::h5readAttributes(out, "uns")[["encoding-type"]]), "dict")
})

test_that("write_h5ad_scanpy excludes counts from layers when written to raw", {
  skip_if_not_installed("BPCells")
  skip_if_not_installed("rhdf5")

  write_h5ad_scanpy <- getFromNamespace("write_h5ad_scanpy", "scSpotlight")

  counts <- Matrix::rsparsematrix(6, 4, density = 0.4)
  counts <- abs(counts)
  rownames(counts) <- paste0("gene", seq_len(nrow(counts)))
  colnames(counts) <- paste0("cell", seq_len(ncol(counts)))

  obj <- Seurat::CreateSeuratObject(counts = counts)
  obj <- Seurat::NormalizeData(obj, verbose = FALSE)

  out <- tempfile(fileext = ".h5ad")
  write_h5ad_scanpy(obj, out, x_layer = "data")

  # When x_layer = "data", counts should be in raw/X but NOT in layers/counts
  listing <- rhdf5::h5ls(out, recursive = TRUE)
  full_paths <- ifelse(listing$group == "/", paste0("/", listing$name), paste0(listing$group, "/", listing$name))

  expect_true("/raw/X" %in% full_paths)
  expect_false("/layers/counts" %in% full_paths)
})

test_that("write_h5ad_scanpy includes raw/obs when raw is written", {
  skip_if_not_installed("BPCells")
  skip_if_not_installed("rhdf5")

  write_h5ad_scanpy <- getFromNamespace("write_h5ad_scanpy", "scSpotlight")

  counts <- Matrix::rsparsematrix(6, 4, density = 0.4)
  counts <- abs(counts)
  rownames(counts) <- paste0("gene", seq_len(nrow(counts)))
  colnames(counts) <- paste0("cell", seq_len(ncol(counts)))

  obj <- Seurat::CreateSeuratObject(counts = counts)
  obj <- Seurat::NormalizeData(obj, verbose = FALSE)

  out <- tempfile(fileext = ".h5ad")
  write_h5ad_scanpy(obj, out, x_layer = "data")

  # raw/obs should exist when raw is written
  listing <- rhdf5::h5ls(out, recursive = TRUE)
  full_paths <- ifelse(listing$group == "/", paste0("/", listing$name), paste0(listing$group, "/", listing$name))

  expect_true("/raw/obs" %in% full_paths)
})

test_that("import_h5ad_as_seurat_bpcells validates AnnData encoding", {
  skip_if_not_installed("BPCells")
  skip_if_not_installed("rhdf5")

  import_h5ad_as_seurat_bpcells <- getFromNamespace("import_h5ad_as_seurat_bpcells", "scSpotlight")

  # Create a non-AnnData HDF5 file with wrong encoding-type
  tmp <- tempfile(fileext = ".h5ad")
  rhdf5::h5createFile(tmp)
  rhdf5::h5write(1:10, tmp, "data")
  # Write a non-anndata encoding-type attribute and close handle
  fid <- rhdf5::H5Fopen(tmp)
  rhdf5::h5writeAttribute("not_anndata", fid, name = "encoding-type")
  rhdf5::H5Fclose(fid)

  expect_error(
    import_h5ad_as_seurat_bpcells(tmp, backend_root = tempdir()),
    "does not appear to be a valid AnnData file"
  )
})

test_that("convert_to_scanpy_h5ad rejects in-place h5ad conversion", {
  skip_if_not_installed("BPCells")
  skip_if_not_installed("rhdf5")

  convert_to_scanpy_h5ad <- getFromNamespace("convert_to_scanpy_h5ad", "scSpotlight")

  tmp <- tempfile(fileext = ".h5ad")
  rhdf5::h5createFile(tmp)

  expect_error(
    convert_to_scanpy_h5ad(tmp, output_file = tmp),
    "output_file must not overwrite input_file"
  )
})
