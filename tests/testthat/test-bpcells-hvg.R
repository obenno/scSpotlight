test_that("BPCells-native HVG methods match Seurat exactly", {
  skip_if_not_installed("BPCells")

  ensure_bpcells_backing <- getFromNamespace("ensure_bpcells_backing", "scSpotlight")
  materialize_bpcells_layers <- getFromNamespace("materialize_bpcells_layers", "scSpotlight")
  preferred_expr_layer <- getFromNamespace("preferred_expr_layer", "scSpotlight")
  set_variable_features_backend <- getFromNamespace("set_variable_features_backend", "scSpotlight")

  set.seed(42)
  counts <- Matrix::rsparsematrix(1500, 300, density = 0.04)
  counts <- abs(counts)
  rownames(counts) <- paste0("gene", seq_len(nrow(counts)))
  colnames(counts) <- paste0("cell", seq_len(ncol(counts)))

  obj <- Seurat::CreateSeuratObject(counts = counts)
  obj <- Seurat::NormalizeData(obj, verbose = FALSE)

  bp_obj <- ensure_bpcells_backing(obj, root_dir = tempfile("bp_hvg_"))
  dense_obj <- materialize_bpcells_layers(bp_obj)

  compare_method <- function(method, nfeatures = 200L) {
    layer <- if (identical(method, "vst")) "counts" else preferred_expr_layer(bp_obj)
    expected <- Seurat::FindVariableFeatures(
      dense_obj,
      selection.method = method,
      layer = layer,
      nfeatures = nfeatures,
      verbose = FALSE
    )
    actual <- set_variable_features_backend(
      bp_obj,
      selection.method = method,
      nfeatures = nfeatures,
      verbose = FALSE
    )

    expect_identical(Seurat::VariableFeatures(actual), Seurat::VariableFeatures(expected))
  }

  compare_method("mean.var.plot")
  compare_method("dispersion")
})
