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
    assay = DefaultAssay(obj),
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
