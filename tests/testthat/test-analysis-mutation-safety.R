make_mutation_counts <- function(n_genes = 40L, n_cells = 12L) {
  set.seed(30302)
  counts <- Matrix::rsparsematrix(n_genes, n_cells, density = 0.18)
  counts@x <- abs(counts@x) + 1
  rownames(counts) <- paste0("gene", seq_len(nrow(counts)))
  colnames(counts) <- paste0("cell", seq_len(ncol(counts)))
  methods::as(counts, "dgCMatrix")
}

make_mutation_object <- function(n_genes = 40L, n_cells = 12L) {
  Seurat::CreateSeuratObject(counts = make_mutation_counts(n_genes, n_cells))
}

make_mutation_normalized_object <- function(n_genes = 40L, n_cells = 12L) {
  object <- make_mutation_object(n_genes, n_cells)
  Seurat::NormalizeData(object, verbose = FALSE)
}

add_mutation_reduction <- function(object, name = "umap", key = "UMAP_", offset = 0) {
  embeddings <- matrix(
    seq_len(ncol(object) * 2L) / 10 + offset,
    nrow = ncol(object),
    ncol = 2L,
    dimnames = list(colnames(object), paste0(key, seq_len(2L)))
  )
  object[[name]] <- Seurat::CreateDimReducObject(
    embeddings = embeddings,
    assay = SeuratObject::DefaultAssay(object),
    key = key
  )
  object
}

add_mutation_scale_layer <- function(object) {
  assay <- SeuratObject::DefaultAssay(object)
  SeuratObject::LayerData(object, assay = assay, layer = "scale.data") <- matrix(
    0,
    nrow = nrow(object),
    ncol = ncol(object),
    dimnames = list(rownames(object), colnames(object))
  )
  object
}

expect_mutation_no_scale_data <- function(object) {
  dense_scale_data_layers <- getFromNamespace(
    "dense_scale_data_layers",
    "scSpotlight"
  )
  expect_equal(nrow(dense_scale_data_layers(object)), 0L)
}

test_that("safe subset helper validates selected cells, preserves object order, and drops scale.data", {
  skip_if_not_installed("Seurat")

  safe_subset_seurat_object <- getFromNamespace(
    "safe_subset_seurat_object",
    "scSpotlight"
  )
  object <- add_mutation_scale_layer(make_mutation_normalized_object())

  subsetted <- safe_subset_seurat_object(
    object,
    cells = c("stale_cell", "cell5", "cell2", "cell5"),
    input_label = "Filter selection"
  )

  expect_identical(colnames(subsetted), c("cell2", "cell5"))
  expect_mutation_no_scale_data(subsetted)
  expect_error(
    safe_subset_seurat_object(
      object,
      cells = c("stale_cell", "missing_cell"),
      input_label = "Filter selection"
    ),
    "Filter selection did not match any cells",
    fixed = TRUE
  )
})

test_that("safe subset helper preserves BPCells backing when available", {
  skip_if_not_installed("Seurat")
  skip_if_not_installed("BPCells")

  ensure_bpcells_backing <- getFromNamespace("ensure_bpcells_backing", "scSpotlight")
  is_seurat_bpcells <- getFromNamespace("is_seurat_bpcells", "scSpotlight")
  safe_subset_seurat_object <- getFromNamespace(
    "safe_subset_seurat_object",
    "scSpotlight"
  )

  object <- make_mutation_normalized_object()
  object <- ensure_bpcells_backing(
    object,
    root_dir = tempfile("safe_subset_source_layers_"),
    layers = NULL
  )

  subsetted <- safe_subset_seurat_object(
    object,
    cells = c("cell4", "cell1"),
    backend_root = tempfile("safe_subset_layers_"),
    input_label = "Filter selection"
  )

  expect_identical(colnames(subsetted), c("cell1", "cell4"))
  expect_true(is_seurat_bpcells(subsetted))
  expect_mutation_no_scale_data(subsetted)
})

test_that("View Filter source validates QC metadata without mutating Analysis state", {
  filter_source <- paste(
    readLines(scspotlight_test_source_path("R", "mod_FilterCell.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(filter_source, "new_view_filter_spec", fixed = TRUE)
  expect_match(filter_source, "setViewFilter(view_filter)", fixed = TRUE)
  expect_match(filter_source, "clear_view_filter", fixed = TRUE)
  expect_match(filter_source, "View filter applied. The active Analysis is unchanged.", fixed = TRUE)
  expect_false(grepl(
    "safe_subset_seurat_object",
    filter_source,
    fixed = TRUE
  ))
  expect_false(grepl("standard_process_seurat", filter_source, fixed = TRUE))
  expect_false(grepl("geneUpdateIndicator", filter_source, fixed = TRUE))
  expect_false(grepl("metaUpdateIndicator", filter_source, fixed = TRUE))
  expect_false(grepl("reductionUpdateIndicator", filter_source, fixed = TRUE))
})

test_that("cluster update helper preserves update-mode indicator semantics and no scale.data", {
  skip_if_not_installed("Seurat")

  apply_cluster_update_mode <- getFromNamespace(
    "apply_cluster_update_mode",
    "scSpotlight"
  )
  object <- make_mutation_normalized_object()
  object <- add_mutation_reduction(object, name = "pca", key = "PC_")
  object <- add_mutation_reduction(object, name = "umap", key = "UMAP_")

  calls <- character()
  process_fun <- function(object, ...) {
    calls <<- c(calls, "process")
    object <- add_mutation_scale_layer(object)
    object[["seurat_clusters"]] <- factor(rep("1", ncol(object)))
    add_mutation_reduction(object, name = "umap", key = "UMAP_", offset = 1)
  }
  run_umap_fun <- function(object, ...) {
    calls <<- c(calls, "umap")
    add_mutation_reduction(object, name = "umap", key = "UMAP_", offset = 2)
  }
  find_neighbors_fun <- function(object, ...) {
    calls <<- c(calls, "neighbors")
    object
  }
  find_clusters_fun <- function(object, ...) {
    calls <<- c(calls, "clusters")
    object <- add_mutation_scale_layer(object)
    object[["seurat_clusters"]] <- factor(rep("2", ncol(object)))
    object
  }

  calls <- character()
  update_all <- apply_cluster_update_mode(
    object,
    update_mode = "Update All",
    hvg_method = "vst",
    ndims = 2L,
    resolution = 0.2,
    process_fun = process_fun,
    run_umap_fun = run_umap_fun,
    find_neighbors_fun = find_neighbors_fun,
    find_clusters_fun = find_clusters_fun
  )
  expect_equal(calls, "process")
  expect_true(update_all$metadata_changed)
  expect_true(update_all$reduction_changed)
  expect_mutation_no_scale_data(update_all$object)

  calls <- character()
  update_ndim <- apply_cluster_update_mode(
    object,
    update_mode = "Update nDim Only",
    hvg_method = "vst",
    ndims = 2L,
    resolution = 0.2,
    process_fun = process_fun,
    run_umap_fun = run_umap_fun,
    find_neighbors_fun = find_neighbors_fun,
    find_clusters_fun = find_clusters_fun
  )
  expect_equal(calls, c("umap", "neighbors", "clusters"))
  expect_true(update_ndim$metadata_changed)
  expect_true(update_ndim$reduction_changed)
  expect_mutation_no_scale_data(update_ndim$object)

  calls <- character()
  update_res_reuse <- apply_cluster_update_mode(
    object,
    update_mode = "Update Res Only",
    hvg_method = "vst",
    ndims = 2L,
    resolution = 0.2,
    process_fun = process_fun,
    run_umap_fun = run_umap_fun,
    find_neighbors_fun = find_neighbors_fun,
    find_clusters_fun = find_clusters_fun,
    graphs_fun = function(...) c("RNA_nn", "RNA_snn")
  )
  expect_equal(calls, "clusters")
  expect_true(update_res_reuse$metadata_changed)
  expect_false(update_res_reuse$reduction_changed)
  expect_mutation_no_scale_data(update_res_reuse$object)

  calls <- character()
  update_res_rebuild_graph <- apply_cluster_update_mode(
    object,
    update_mode = "Update Res Only",
    hvg_method = "vst",
    ndims = 2L,
    resolution = 0.2,
    process_fun = process_fun,
    run_umap_fun = run_umap_fun,
    find_neighbors_fun = find_neighbors_fun,
    find_clusters_fun = find_clusters_fun,
    graphs_fun = function(...) character(0)
  )
  expect_equal(calls, c("neighbors", "clusters"))
  expect_true(update_res_rebuild_graph$metadata_changed)
  expect_false(update_res_rebuild_graph$reduction_changed)
  expect_mutation_no_scale_data(update_res_rebuild_graph$object)
})

test_that("cell-cycle scoring falls back on binning failures and returns scoped metadata columns", {
  skip_if_not_installed("Seurat")

  score_cell_cycle_safely <- getFromNamespace(
    "score_cell_cycle_safely",
    "scSpotlight"
  )
  object <- make_mutation_normalized_object()
  fallback_called <- FALSE

  scored <- score_cell_cycle_safely(
    object,
    s.features = rownames(object)[1:3],
    g2m.features = rownames(object)[4:6],
    primary_scoring = function(...) {
      stop("Insufficient data values to produce 24 bins")
    },
    fallback_scoring = function(object, ...) {
      fallback_called <<- TRUE
      object[["S.Score"]] <- stats::setNames(seq_len(ncol(object)), colnames(object))
      object[["G2M.Score"]] <- stats::setNames(seq_len(ncol(object)) * 2, colnames(object))
      object[["Phase"]] <- stats::setNames(rep("S", ncol(object)), colnames(object))
      object
    }
  )

  expect_true(fallback_called)
  expect_true(all(c("S.Score", "G2M.Score", "Phase") %in% colnames(scored[[]])))
  expect_mutation_no_scale_data(scored)
})

test_that("cell-cycle module requests one exact metadata patch for scoring columns", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("Seurat")

  object <- make_mutation_normalized_object()
  seurat_value <- shiny::reactiveVal(object)
  patch_request <- shiny::reactiveVal(NULL)
  patch_version <- shiny::reactiveVal(0L)
  notifications <- character()

  testthat::local_mocked_bindings(
    score_cell_cycle_safely = function(object, ...) {
      object[["S.Score"]] <- stats::setNames(rep(0.1, ncol(object)), colnames(object))
      object[["G2M.Score"]] <- stats::setNames(rep(0.2, ncol(object)), colnames(object))
      object[["Phase"]] <- stats::setNames(rep("S", ncol(object)), colnames(object))
      object
    },
    showNotification = function(ui, ..., session = NULL) {
      notifications <<- c(notifications, as.character(ui))
      invisible(NULL)
    },
    .package = "scSpotlight"
  )

  testServer(
    mod_CellCycling_server,
    args = list(
      seuratObj = seurat_value,
      assay = shiny::reactive("RNA"),
      metaPatchRequest = patch_request,
      metaPatchVersion = patch_version
    ),
    {
      session$setInputs(addCycling = 1)
      session$flushReact()
    }
  )

  expect_equal(shiny::isolate(patch_version()), 1L)
  expect_equal(shiny::isolate(patch_request())$version, 1L)
  expect_identical(
    shiny::isolate(patch_request())$cols,
    c("S.Score", "G2M.Score", "Phase")
  )
  expect_true(all(
    c("S.Score", "G2M.Score", "Phase") %in%
      colnames(shiny::isolate(seurat_value())[[]])
  ))
  expect_false(any(grepl("CellCycleScoring failed|/tmp|private", notifications)))
})

test_that("metadata patches share one monotonic version with full metadata refreshes", {
  app_source <- paste(
    readLines(scspotlight_test_source_path("R", "app_server.R"), warn = FALSE),
    collapse = "\n"
  )
  cell_cycle_source <- paste(
    readLines(scspotlight_test_source_path("R", "mod_CellCyling.R"), warn = FALSE),
    collapse = "\n"
  )
  mutation_source <- paste(app_source, cell_cycle_source, sep = "\n")

  expect_false(
    grepl("metaPatchVersion\\s*<-\\s*reactiveVal\\s*\\(\\s*0", app_source, perl = TRUE),
    info = "metadata patches must not use a separate counter that can lag full metadata transfers"
  )
  expect_false(
    grepl("metaPatchVersion\\s*\\(\\s*\\)\\s*\\+\\s*1L", mutation_source, perl = TRUE),
    info = "patch versions must be allocated from the same server-owned metadata sequence as full refreshes"
  )
  expect_match(
    app_source,
    "nextMetadataVersion|metadataVersion",
    info = "app_server should own a single monotonic metadata version allocator"
  )
  expect_true(
    grepl(
      "metaUpdateIndicator[\\s\\S]*nextMetadataVersion|nextMetadataVersion[\\s\\S]*metaUpdateIndicator",
      app_source,
      perl = TRUE
    ),
    info = "full metadata refreshes must advance the same metadata sequence used by patches"
  )
})

test_that("cell-cycle module surfaces generic path-free errors", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("Seurat")

  object <- make_mutation_normalized_object()
  seurat_value <- shiny::reactiveVal(object)
  patch_request <- shiny::reactiveVal(NULL)
  patch_version <- shiny::reactiveVal(0L)
  notifications <- character()

  testthat::local_mocked_bindings(
    score_cell_cycle_safely = function(...) {
      stop("raw failure from /tmp/private/path/to/object.rds")
    },
    showNotification = function(ui, ..., session = NULL) {
      notifications <<- c(notifications, as.character(ui))
      invisible(NULL)
    },
    .package = "scSpotlight"
  )

  testServer(
    mod_CellCycling_server,
    args = list(
      seuratObj = seurat_value,
      assay = shiny::reactive("RNA"),
      metaPatchRequest = patch_request,
      metaPatchVersion = patch_version
    ),
    {
      session$setInputs(addCycling = 1)
      session$flushReact()
    }
  )

  expect_null(shiny::isolate(patch_request()))
  expect_equal(shiny::isolate(patch_version()), 0L)
  expect_true(any(grepl("Cell-cycle scoring could not be completed", notifications, fixed = TRUE)))
  expect_false(any(grepl("/tmp|private|object.rds|raw failure", notifications)))
})
