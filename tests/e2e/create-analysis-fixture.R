create_analysis_fixture <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  cells <- paste0("Cell", seq_len(6L))
  counts <- Matrix::Matrix(
    c(
      4, 0, 1, 2, 3, 1,
      0, 5, 2, 1, 1, 3,
      2, 1, 4, 3, 2, 2,
      1, 2, 1, 5, 4, 1,
      3, 1, 2, 1, 3, 4
    ),
    nrow = 5L,
    dimnames = list(
      c("MT-CO1", "GeneA", "GeneB", "GeneC", "GeneD"),
      cells
    ),
    sparse = TRUE
  )

  object <- Seurat::CreateSeuratObject(counts = counts)
  object <- Seurat::NormalizeData(object, verbose = FALSE)
  object$nFeature_RNA <- c(100, 200, 300, 400, 500, 600)
  object$percent.mt <- c(5, 10, 20, 30, 40, 60)
  object$cluster <- factor(c("A", "A", "B", "B", "C", "C"))
  object$batch <- factor(c("batch1", "batch1", "batch1", "batch2", "batch2", "batch2"))
  Seurat::VariableFeatures(object) <- rownames(counts)[2:5]

  umap_embeddings <- matrix(
    c(
      -2, -1,
      -1, 0,
      0, 1,
      1, 1,
      2, 0,
      3, -1
    ),
    ncol = 2L,
    byrow = TRUE,
    dimnames = list(cells, c("UMAP_1", "UMAP_2"))
  )
  pca_embeddings <- matrix(
    c(
      -3, 0,
      -2, 1,
      -1, 1,
      1, 0,
      2, -1,
      3, -1
    ),
    ncol = 2L,
    byrow = TRUE,
    dimnames = list(cells, c("PC_1", "PC_2"))
  )
  object[["umap"]] <- Seurat::CreateDimReducObject(
    embeddings = umap_embeddings,
    key = "UMAP_",
    assay = "RNA"
  )
  object[["pca"]] <- Seurat::CreateDimReducObject(
    embeddings = pca_embeddings,
    stdev = c(2, 1),
    key = "PC_",
    assay = "RNA"
  )

  saveRDS(object, path)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}
