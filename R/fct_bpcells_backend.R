#' BPCells backend helpers
#'
#' @noRd

bpcells_minimum_version <- base::package_version("0.3.1")

#' @noRd
bpcells_available <- function(min_version = bpcells_minimum_version) {
  if (!rlang::is_installed("BPCells")) {
    return(FALSE)
  }

  utils::packageVersion("BPCells") >= min_version
}

#' @noRd
assert_bpcells_available <- function(min_version = bpcells_minimum_version) {
  if (bpcells_available(min_version = min_version)) {
    return(invisible(TRUE))
  }

  if (!rlang::is_installed("BPCells")) {
    stop("BPCells >= ", as.character(min_version), " must be installed for scSpotlight to load data")
  }

  stop(
    "BPCells >= ",
    as.character(min_version),
    " is required; found ",
    as.character(utils::packageVersion("BPCells")),
    "."
  )
}

is_bpcells_matrix <- function(x) {
  inherits(x, "IterableMatrix") || inherits(x, "MatrixDir") || inherits(x, "MatrixMem")
}

#' @noRd
optimize_bpcells_matrix_type <- function(mat, layer = NULL) {
  if (!bpcells_available() || is_bpcells_matrix(mat)) {
    return(mat)
  }

  target_type <- if (!is.null(layer) && grepl("^counts", layer)) "uint32_t" else "float"
  BPCells::convert_matrix_type(mat, type = target_type)
}

#' @noRd
is_seurat_bpcells <- function(object, assay = NULL) {
  if (!isTruthy(object)) {
    return(FALSE)
  }

  assay <- assay %||% DefaultAssay(object)
  layers <- tryCatch(SeuratObject::Layers(object[[assay]]), error = function(...) character(0))
  any(vapply(layers, function(layer) {
    is_bpcells_matrix(SeuratObject::LayerData(object, assay = assay, layer = layer))
  }, logical(1)))
}

#' @noRd
materialize_bpcells_layers <- function(object, assays = NULL) {
  assays <- assays %||% Assays(object)

  for (assay in assays) {
    layers <- tryCatch(SeuratObject::Layers(object[[assay]]), error = function(...) character(0))
    if (!length(layers)) {
      next
    }

    for (layer in layers) {
      layer_data <- SeuratObject::LayerData(object, assay = assay, layer = layer)
      if (!is_bpcells_matrix(layer_data)) {
        next
      }

      SeuratObject::LayerData(object, assay = assay, layer = layer) <- methods::as(layer_data, Class = "dgCMatrix")
    }
  }

  object
}

#' @noRd
materialize_layer_matrix <- function(object, assay = NULL, layer = NULL) {
  assay <- assay %||% DefaultAssay(object)
  layer <- layer %||% preferred_expr_layer(object, assay)
  mat <- SeuratObject::LayerData(object, assay = assay, layer = layer)

  if (inherits(mat, "dgCMatrix")) {
    return(mat)
  }

  methods::as(mat, Class = "dgCMatrix")
}

#' @noRd
bp_expm1_row_stats <- function(mat) {
  BPCells::matrix_stats(expm1(mat), row_stats = "variance")$row_stats
}

#' @noRd
bp_calc_dispersion <- function(mat, feature_names, num.bin = 20L,
                               binning.method = "equal_width") {
  stats <- bp_expm1_row_stats(mat)
  exp_mean <- as.numeric(stats["mean", ])
  exp_var <- as.numeric(stats["variance", ])
  feature.mean <- log1p(exp_mean)
  feature.dispersion <- log(exp_var / exp_mean)
  feature.dispersion[is.na(feature.dispersion)] <- 0
  feature.mean[is.na(feature.mean)] <- 0

  data.x.breaks <- switch(
    EXPR = binning.method,
    equal_width = num.bin,
    equal_frequency = c(stats::quantile(
      x = feature.mean[feature.mean > 0],
      probs = seq.int(from = 0, to = 1, length.out = num.bin)
    )),
    stop("Unknown binning method: ", binning.method)
  )
  data.x.bin <- cut(x = feature.mean, breaks = data.x.breaks, include.lowest = TRUE)
  mean.y <- tapply(X = feature.dispersion, INDEX = data.x.bin, FUN = mean)
  sd.y <- tapply(X = feature.dispersion, INDEX = data.x.bin, FUN = stats::sd)
  feature.dispersion.scaled <- (feature.dispersion - mean.y[as.numeric(x = data.x.bin)]) /
    sd.y[as.numeric(x = data.x.bin)]

  hvf.info <- data.frame(
    mvp.mean = feature.mean,
    mvp.dispersion = feature.dispersion,
    mvp.dispersion.scaled = feature.dispersion.scaled,
    row.names = feature_names
  )
  hvf.info
}

#' @noRd
bp_dispersion_hvf <- function(mat, feature_names, nselect = 2000L, ...) {
  hvf.info <- bp_calc_dispersion(mat, feature_names = feature_names, ...)
  hvf.info$variable <- FALSE
  hvf.info$rank <- NA_integer_
  vf <- head(order(hvf.info$mvp.dispersion, decreasing = TRUE), n = nselect)
  hvf.info$variable[vf] <- TRUE
  hvf.info$rank[vf] <- seq_along(vf)
  hvf.info
}

#' @noRd
bp_mvp_hvf <- function(mat, nselect = 2000L, mean.cutoff = c(0.1, 8),
                       dispersion.cutoff = c(1, Inf), feature_names, ...) {
  hvf.info <- bp_dispersion_hvf(mat, feature_names = feature_names, nselect = nselect, ...)
  hvf.info$variable <- FALSE
  hvf.info$rank <- NA_integer_
  hvf.info <- hvf.info[order(hvf.info$mvp.dispersion, decreasing = TRUE), , drop = FALSE]
  means.use <- (hvf.info[, 1] > mean.cutoff[1]) & (hvf.info[, 1] < mean.cutoff[2])
  dispersions.use <- (hvf.info[, 3] > dispersion.cutoff[1]) & (hvf.info[, 3] < dispersion.cutoff[2])
  selected.indices <- which(means.use & dispersions.use)
  hvf.info$variable[selected.indices] <- TRUE
  hvf.info$rank[selected.indices] <- seq_along(selected.indices)
  hvf.info[match(feature_names, rownames(hvf.info)), , drop = FALSE]
}

#' @noRd
set_variable_features_backend <- function(object, assay = NULL, selection.method = "vst",
                                         nfeatures = 2000L, verbose = TRUE, ...) {
  assay <- assay %||% DefaultAssay(object)
  layer <- if (identical(selection.method, "vst")) "counts" else preferred_expr_layer(object, assay)

  if (!is_seurat_bpcells(object, assay) || identical(selection.method, "vst")) {
    return(Seurat::FindVariableFeatures(
      object,
      selection.method = selection.method,
      layer = layer,
      nfeatures = nfeatures,
      verbose = verbose,
      ...
    ))
  }

  if (isTRUE(verbose)) {
    message("Finding variable features for BPCells layer ", layer)
  }

  mat <- SeuratObject::LayerData(object, assay = assay, layer = layer, fast = TRUE)
  feature_names <- SeuratObject::Features(object[[assay]], layer = layer)

  hvf.info <- switch(
    selection.method,
    "mean.var.plot" = bp_mvp_hvf(mat, feature_names = feature_names, nselect = nfeatures, ...),
    "mvp" = bp_mvp_hvf(mat, feature_names = feature_names, nselect = nfeatures, ...),
    "dispersion" = bp_dispersion_hvf(mat, feature_names = feature_names, nselect = nfeatures, ...),
    "disp" = bp_dispersion_hvf(mat, feature_names = feature_names, nselect = nfeatures, ...),
    NULL
  )

  if (!is.null(hvf.info)) {
    ranked_features <- rownames(hvf.info)[order(hvf.info[["rank"]], na.last = NA)]
    ranked_features <- head(ranked_features, nfeatures)
    VariableFeatures(object) <- ranked_features
    return(object)
  }

  if (isTRUE(verbose)) {
    message(
      "Materializing BPCells layer '",
      layer,
      "' as sparse matrix for unsupported FindVariableFeatures method '",
      selection.method,
      "'."
    )
  }

  mat <- materialize_layer_matrix(object, assay = assay, layer = layer)
  temp <- Seurat::CreateSeuratObject(counts = mat, assay = assay)
  if (!identical(layer, "counts")) {
    SeuratObject::LayerData(temp, assay = assay, layer = layer) <- mat
  }

  temp <- Seurat::FindVariableFeatures(
    temp,
    selection.method = selection.method,
    layer = layer,
    nfeatures = nfeatures,
    verbose = verbose,
    ...
  )

  VariableFeatures(object) <- stats::na.omit(VariableFeatures(temp))
  object
}

#' @noRd
ensure_assay5 <- function(object, assay = NULL) {
  assay <- assay %||% DefaultAssay(object)
  if (inherits(object[[assay]], "Assay")) {
    object[[assay]] <- methods::as(object[[assay]], Class = "Assay5")
  }
  object
}

#' @noRd
preferred_expr_layer <- function(object, assay = NULL) {
  assay <- assay %||% DefaultAssay(object)
  layers <- SeuratObject::Layers(object[[assay]])
  if ("data" %in% layers) {
    data_layer <- SeuratObject::LayerData(object, assay = assay, layer = "data")
    dims <- tryCatch(dim(data_layer), error = function(...) c(0L, 0L))
    if (all(dims > 0)) {
      return("data")
    }
  }
  if ("counts" %in% layers) {
    return("counts")
  }
  layers[[1]]
}

#' @noRd
ensure_bpcells_backing <- function(object, root_dir, assays = NULL, layers = c("counts", "data")) {
  assert_bpcells_available()

  assays <- assays %||% Assays(object)
  dir.create(root_dir, recursive = TRUE, showWarnings = FALSE)

  for (assay in assays) {
    object <- ensure_assay5(object, assay)
    assay_layers <- intersect(layers, SeuratObject::Layers(object[[assay]]))
    if (!length(assay_layers)) {
      next
    }

    assay_dir <- file.path(root_dir, assay)
    dir.create(assay_dir, recursive = TRUE, showWarnings = FALSE)

    for (layer in assay_layers) {
      mat <- SeuratObject::LayerData(object, assay = assay, layer = layer)
      if (is_bpcells_matrix(mat)) {
        next
      }

      layer_dir <- file.path(assay_dir, layer)
      mat <- optimize_bpcells_matrix_type(mat, layer = layer)
      BPCells::write_matrix_dir(mat = mat, dir = layer_dir, overwrite = TRUE)
      SeuratObject::LayerData(object, assay = assay, layer = layer) <- BPCells::open_matrix_dir(layer_dir)
    }
  }

  object
}

#' @noRd
h5ad_h5ls <- function(path) {
  if (!requireNamespace("rhdf5", quietly = TRUE)) {
    stop("rhdf5 must be installed for native .h5ad import")
  }
  rhdf5::h5ls(path, recursive = TRUE)
}

#' @noRd
h5ad_normalize_path <- function(path) {
  if (!nzchar(path)) {
    return("/")
  }
  if (!startsWith(path, "/")) {
    path <- paste0("/", path)
  }
  path
}

#' @noRd
h5ad_path_exists <- function(index, path) {
  path <- h5ad_normalize_path(path)
  full_path <- ifelse(index$group == "/", paste0("/", index$name), paste0(index$group, "/", index$name))
  any(full_path == path)
}

#' @noRd
h5ad_group_children <- function(index, group) {
  group <- h5ad_normalize_path(group)
  index$name[index$group == group]
}

#' @noRd
h5ad_read_attrs <- function(path, name) {
  if (!requireNamespace("rhdf5", quietly = TRUE)) {
    stop("rhdf5 must be installed for native .h5ad import")
  }
  tryCatch(rhdf5::h5readAttributes(path, name), error = function(...) list())
}

#' @noRd
h5ad_simplify_value <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (is.matrix(x) && 1L %in% dim(x)) {
    x <- as.vector(x)
  } else if (is.array(x) && length(dim(x)) == 1L) {
    x <- as.vector(x)
  }
  if (is.list(x) && length(x) == 1L) {
    x <- x[[1]]
  }
  x
}

#' @noRd
h5ad_read_dataset <- function(path, name) {
  if (!requireNamespace("rhdf5", quietly = TRUE)) {
    stop("rhdf5 must be installed for native .h5ad import")
  }
  h5ad_simplify_value(rhdf5::h5read(path, name, compoundAsDataFrame = TRUE))
}

#' @noRd
h5ad_decode_categorical <- function(codes, categories) {
  codes <- as.integer(h5ad_simplify_value(codes))
  categories <- h5ad_simplify_value(categories)
  categories_chr <- as.character(categories)
  values <- rep(NA_character_, length(codes))
  valid <- !is.na(codes) & codes >= 0L
  values[valid] <- categories_chr[codes[valid] + 1L]
  factor(values, levels = categories_chr)
}

#' @noRd
h5ad_decode_nullable <- function(values, mask, type = c("character", "integer", "logical")) {
  type <- match.arg(type)
  values <- h5ad_simplify_value(values)
  mask <- as.logical(h5ad_simplify_value(mask))

  out <- switch(
    type,
    character = as.character(values),
    integer = as.integer(values),
    logical = as.logical(values)
  )

  if (length(mask) == length(out)) {
    out[mask] <- NA
  }

  out
}

#' @noRd
h5ad_read_dataframe_column <- function(path, index, group, column) {
  column_path <- file.path(group, column)
  attrs <- h5ad_read_attrs(path, column_path)
  encoding_type <- as.character(attrs[["encoding-type"]] %||% "")

  if (identical(encoding_type, "categorical")) {
    return(h5ad_decode_categorical(
      h5ad_read_dataset(path, file.path(column_path, "codes")),
      h5ad_read_dataset(path, file.path(column_path, "categories"))
    ))
  }

  if (identical(encoding_type, "nullable-integer")) {
    return(h5ad_decode_nullable(
      h5ad_read_dataset(path, file.path(column_path, "values")),
      h5ad_read_dataset(path, file.path(column_path, "mask")),
      type = "integer"
    ))
  }

  if (identical(encoding_type, "nullable-boolean")) {
    return(h5ad_decode_nullable(
      h5ad_read_dataset(path, file.path(column_path, "values")),
      h5ad_read_dataset(path, file.path(column_path, "mask")),
      type = "logical"
    ))
  }

  if (identical(encoding_type, "nullable-string-array")) {
    return(h5ad_decode_nullable(
      h5ad_read_dataset(path, file.path(column_path, "values")),
      h5ad_read_dataset(path, file.path(column_path, "mask")),
      type = "character"
    ))
  }

  legacy_category_path <- file.path(group, "__categories", column)
  if (h5ad_path_exists(index, legacy_category_path)) {
    return(h5ad_decode_categorical(
      h5ad_read_dataset(path, column_path),
      h5ad_read_dataset(path, legacy_category_path)
    ))
  }

  values <- h5ad_read_dataset(path, column_path)
  if (is.factor(values)) {
    return(values)
  }
  if (is.matrix(values) && ncol(values) == 1L) {
    return(values[, 1])
  }
  if (is.array(values) && length(dim(values)) == 1L) {
    return(as.vector(values))
  }
  values
}

#' @noRd
h5ad_read_dataframe <- function(path, index, group) {
  if (!h5ad_path_exists(index, group)) {
    return(NULL)
  }

  attrs <- h5ad_read_attrs(path, group)
  index_key <- as.character(h5ad_simplify_value(attrs[["_index"]] %||% "_index"))
  if (!h5ad_path_exists(index, file.path(group, index_key)) && h5ad_path_exists(index, file.path(group, "bpcells_name"))) {
    index_key <- "bpcells_name"
  }
  col_order <- h5ad_simplify_value(attrs[["column-order"]])
  if (is.null(col_order)) {
    col_order <- setdiff(h5ad_group_children(index, group), c(index_key, "__categories"))
  }
  col_order <- as.character(col_order)

  row_names <- h5ad_read_dataset(path, file.path(group, index_key))
  row_names <- as.character(h5ad_simplify_value(row_names))
  data <- lapply(col_order, function(column) {
    h5ad_read_dataframe_column(path, index, group, column)
  })
  names(data) <- col_order
  out <- as.data.frame(data, stringsAsFactors = FALSE, optional = TRUE)
  rownames(out) <- row_names
  out
}

#' @noRd
h5ad_read_index_names <- function(path, index, group) {
  attrs <- h5ad_read_attrs(path, group)
  index_key <- as.character(h5ad_simplify_value(attrs[["_index"]] %||% "_index"))
  if (!h5ad_path_exists(index, file.path(group, index_key)) && h5ad_path_exists(index, file.path(group, "bpcells_name"))) {
    index_key <- "bpcells_name"
  }
  as.character(h5ad_simplify_value(h5ad_read_dataset(path, file.path(group, index_key))))
}

#' @noRd
h5ad_matrix_feature_group <- function(index, group) {
  if (startsWith(group, "raw/") && h5ad_path_exists(index, "raw/var")) {
    return("raw/var")
  }

  "var"
}

#' @noRd
h5ad_read_sparse_matrix <- function(path, group, feature_names = NULL, cell_names = NULL) {
  attrs <- h5ad_read_attrs(path, group)
  encoding_type <- as.character(attrs[["encoding-type"]] %||% "")
  if (!encoding_type %in% c("csr_matrix", "csc_matrix")) {
    stop("Only csr_matrix and csc_matrix encodings are supported for fallback h5ad import")
  }

  shape <- as.integer(attrs[["shape"]])
  cell_count <- shape[[1]]
  feature_count <- shape[[2]]
  data <- as.numeric(h5ad_read_dataset(path, file.path(group, "data")))
  indices <- as.integer(h5ad_read_dataset(path, file.path(group, "indices"))) + 1L
  indptr <- as.integer(h5ad_read_dataset(path, file.path(group, "indptr")))

  mat <- if (identical(encoding_type, "csr_matrix")) {
    row_ids <- rep.int(seq_len(cell_count), diff(indptr))
    Matrix::sparseMatrix(
      i = row_ids,
      j = indices,
      x = data,
      dims = c(cell_count, feature_count)
    )
  } else {
    col_ids <- rep.int(seq_len(feature_count), diff(indptr))
    Matrix::sparseMatrix(
      i = indices,
      j = col_ids,
      x = data,
      dims = c(cell_count, feature_count)
    )
  }
  mat <- Matrix::t(mat)

  if (!is.null(feature_names) && length(feature_names) == nrow(mat)) {
    rownames(mat) <- feature_names
  }
  if (!is.null(cell_names) && length(cell_names) == ncol(mat)) {
    colnames(mat) <- cell_names
  }

  mat
}

#' @noRd
h5ad_reduction_name <- function(name) {
  name <- sub("^X_", "", name)
  tolower(name)
}

#' @noRd
h5ad_reduction_key <- function(name) {
  name <- h5ad_reduction_name(name)
  switch(
    name,
    pca = "PC_",
    umap = "UMAP_",
    tsne = "tSNE_",
    paste0(toupper(name), "_")
  )
}

#' @noRd
h5ad_add_reductions <- function(object, path, index, assay = NULL) {
  assay <- assay %||% DefaultAssay(object)
  if (!h5ad_path_exists(index, "obsm")) {
    return(object)
  }

  for (name in h5ad_group_children(index, "obsm")) {
    reduction_path <- file.path("obsm", name)
    embeddings <- h5ad_read_dataset(path, reduction_path)
    if (is.null(embeddings)) {
      next
    }
    embeddings <- as.matrix(embeddings)
    if (!nrow(embeddings) || !ncol(embeddings)) {
      next
    }

    if (nrow(embeddings) != ncol(object) && ncol(embeddings) == ncol(object)) {
      embeddings <- t(embeddings)
    }
    if (nrow(embeddings) != ncol(object)) {
      next
    }

    rownames(embeddings) <- colnames(object)
    colnames(embeddings) <- paste0(h5ad_reduction_key(name), seq_len(ncol(embeddings)))
    object[[h5ad_reduction_name(name)]] <- Seurat::CreateDimReducObject(
      embeddings = embeddings,
      assay = assay,
      key = h5ad_reduction_key(name)
    )
  }

  object
}

#' @noRd
h5ad_open_matrix_if_available <- function(path, index, group) {
  if (!h5ad_path_exists(index, group)) {
    return(NULL)
  }

  tryCatch(
    BPCells::open_matrix_anndata_hdf5(path, group = group),
    error = function(...) NULL
  )
}

#' @noRd
h5ad_open_counts_matrix <- function(path, index) {
  for (candidate in c("layers/counts", "raw/X", "X")) {
    mat <- h5ad_open_matrix_if_available(path, index, candidate)
    if (!is.null(mat)) {
      return(list(group = candidate, matrix = mat))
    }
  }
  stop("No BPCells-readable expression matrix found in .h5ad file")
}

#' @noRd
h5ad_open_data_matrix <- function(path, index, counts_group) {
  candidates <- character(0)
  if (!identical(counts_group, "X")) {
    candidates <- c(candidates, "X")
  }
  candidates <- c(candidates, "layers/data")

  for (candidate in candidates) {
    mat <- h5ad_open_matrix_if_available(path, index, candidate)
    if (!is.null(mat)) {
      return(list(group = candidate, matrix = mat))
    }
  }

  NULL
}

#' @noRd
h5ad_fallback_sparse_layers <- function(path, index, counts_group) {
  feature_group <- h5ad_matrix_feature_group(index, counts_group)
  feature_names <- if (h5ad_path_exists(index, feature_group)) h5ad_read_index_names(path, index, feature_group) else NULL
  cell_names <- if (h5ad_path_exists(index, "obs")) h5ad_read_index_names(path, index, "obs") else NULL

  counts <- h5ad_read_sparse_matrix(
    path,
    counts_group,
    feature_names = feature_names,
    cell_names = cell_names
  )

  data <- NULL
  if (h5ad_path_exists(index, "layers/data")) {
    data <- h5ad_read_sparse_matrix(
      path,
      "layers/data",
      feature_names = if (h5ad_path_exists(index, "var")) h5ad_read_index_names(path, index, "var") else feature_names,
      cell_names = cell_names
    )
  }

  list(counts = counts, data = data)
}

#' @noRd
import_h5ad_as_seurat_bpcells <- function(input_file, backend_root, assay = "RNA") {
  assert_bpcells_available()
  if (!requireNamespace("rhdf5", quietly = TRUE)) {
    stop("rhdf5 must be installed for native .h5ad import")
  }

  index <- h5ad_h5ls(input_file)
  counts_info <- tryCatch(h5ad_open_counts_matrix(input_file, index), error = function(...) NULL)
  counts_group <- counts_info$group %||% if (h5ad_path_exists(index, "layers/counts")) "layers/counts" else if (h5ad_path_exists(index, "raw/X")) "raw/X" else "X"
  counts <- counts_info$matrix %||% NULL
  data_info <- if (!is.null(counts_info)) h5ad_open_data_matrix(input_file, index, counts_group) else NULL
  meta <- h5ad_read_dataframe(input_file, index, "obs")

  if (is.null(counts)) {
    fallback_layers <- h5ad_fallback_sparse_layers(input_file, index, counts_group)
    counts <- fallback_layers$counts
    if (!is.null(fallback_layers$data)) {
      data_info <- list(group = "layers/data", matrix = fallback_layers$data)
    }
  }

  object <- Seurat::CreateSeuratObject(
    counts = counts,
    assay = assay,
    meta.data = meta %||% NULL
  )
  object <- ensure_assay5(object, assay = assay)

  if (!is.null(data_info)) {
    same_shape <- identical(dim(data_info$matrix), dim(SeuratObject::LayerData(object, assay = assay, layer = "counts")))
    if (isTRUE(same_shape)) {
      SeuratObject::LayerData(object, assay = assay, layer = "data") <-
        data_info$matrix
    }
  }

  object <- h5ad_add_reductions(object, input_file, index, assay = assay)
  ensure_bpcells_backing(object, root_dir = backend_root, assays = assay)
}

#' @noRd
extract_expr_vector <- function(mat, feature_name) {
  feature_idx <- match(feature_name, rownames(mat))
  if (is.na(feature_idx)) {
    stop(sprintf("Feature '%s' not found", feature_name))
  }

  feature_values <- tryCatch(
    mat[feature_idx, , drop = TRUE],
    error = function(...) mat[feature_idx, , drop = FALSE]
  )

  if (isS4(feature_values) || is.matrix(feature_values) || inherits(feature_values, "Matrix")) {
    # Some Assay5/BPCells-backed slices come back as 1 x N S4 matrices.
    # Materialize that single feature row before coercing to numeric.
    feature_values <- as.matrix(feature_values)
    if (nrow(feature_values) == 1L || ncol(feature_values) == 1L) {
      feature_values <- drop(feature_values)
    }
  }

  as.numeric(feature_values)
}

#' @noRd
get_backend_features <- function(object, assay = NULL, layer = NULL) {
  assay <- assay %||% DefaultAssay(object)
  layer <- layer %||% preferred_expr_layer(object, assay)
  mat <- SeuratObject::LayerData(object, assay = assay, layer = layer)
  rownames(mat)
}

#' @noRd
get_backend_metadata <- function(object, cols = NULL) {
  meta <- object[[]]
  if (isTruthy(cols)) {
    cols <- intersect(cols, colnames(meta))
    meta <- meta[, cols, drop = FALSE]
  }
  meta
}

#' @noRd
get_backend_reduction_names <- function(object) {
  SeuratObject::Reductions(object)
}

#' @noRd
get_backend_reduction <- function(object, reduction, n_components = 2L) {
  emb <- Seurat::Embeddings(object[[reduction]])
  keep <- seq_len(min(ncol(emb), n_components))
  out <- as.data.frame(emb[, keep, drop = FALSE])
  if (ncol(out) == 1L) {
    out$V2 <- 0
  }
  colnames(out)[1:2] <- c("X", "Y")
  out[, c("X", "Y"), drop = FALSE]
}

#' @noRd
get_backend_expr <- function(object, assay = NULL, features, layer = NULL) {
  assay <- assay %||% DefaultAssay(object)
  layer <- layer %||% preferred_expr_layer(object, assay)
  mat <- SeuratObject::LayerData(object, assay = assay, layer = layer)

  out <- lapply(features, function(feature_name) {
    extract_expr_vector(mat, feature_name)
  })
  names(out) <- features
  out
}

#' @noRd
bp_write_cached_matrix <- function(mat) {
  if (!bpcells_available()) {
    return(mat)
  }
  if (!is.function(BPCells::write_matrix_memory)) {
    return(mat)
  }
  BPCells::write_matrix_memory(mat, compress = FALSE)
}

#' @noRd
run_bpcells_pca <- function(object, assay = NULL, layer = NULL, npcs = 50L) {
  assert_bpcells_available()

  assay <- assay %||% DefaultAssay(object)
  layer <- layer %||% preferred_expr_layer(object, assay)
  features <- VariableFeatures(object)
  if (!length(features)) {
    stop("Variable features are required before running BPCells PCA")
  }

  mat <- SeuratObject::LayerData(object, assay = assay, layer = layer)
  mat <- mat[features, , drop = FALSE]
  mat <- bp_write_cached_matrix(mat)

  stats <- BPCells::matrix_stats(mat, row_stats = "variance")$row_stats
  row_means <- as.numeric(stats["mean", ])
  row_vars <- as.numeric(stats["variance", ])
  row_sds <- sqrt(pmax(row_vars, 1e-8))

  scaled_mat <- (mat - row_means) / row_sds
  scaled_mat <- bp_write_cached_matrix(scaled_mat)

  n_pcs <- min(as.integer(npcs), nrow(scaled_mat) - 1L, ncol(scaled_mat) - 1L)
  if (n_pcs < 2L) {
    stop("Not enough cells/features to compute PCA")
  }

  svd <- BPCells::svds(scaled_mat, k = n_pcs)
  embeddings <- as.matrix(BPCells::multiply_cols(svd$v, svd$d))
  loadings <- as.matrix(svd$u)

  rownames(embeddings) <- colnames(mat)
  colnames(embeddings) <- paste0("PC_", seq_len(ncol(embeddings)))
  rownames(loadings) <- rownames(mat)
  colnames(loadings) <- colnames(embeddings)

  stdev <- as.numeric(svd$d) / sqrt(max(ncol(mat) - 1L, 1L))

  object[["pca"]] <- Seurat::CreateDimReducObject(
    embeddings = embeddings,
    loadings = loadings,
    stdev = stdev,
    assay = assay,
    key = "PC_"
  )

  object
}

#' @noRd
run_memory_conserving_pca <- function(object, assay = NULL, layer = NULL, npcs = 50L) {
  assay <- assay %||% DefaultAssay(object)
  layer <- layer %||% preferred_expr_layer(object, assay)

  if (is_seurat_bpcells(object, assay) && bpcells_available()) {
    return(run_bpcells_pca(object, assay = assay, layer = layer, npcs = npcs))
  }

  object <- Seurat::ScaleData(object, features = VariableFeatures(object))
  Seurat::RunPCA(object, npcs = npcs)
}

#' @noRd
run_memory_conserving_processing <- function(seuratObj, normalization = TRUE,
                                             hvg_method = "vst", ndims = 30, res = 0.5,
                                             npcs = NULL) {
  npcs <- npcs %||% max(ndims, 30L)

  if (normalization) {
    seuratObj <- Seurat::NormalizeData(seuratObj)
  }

  seuratObj <- set_variable_features_backend(
    seuratObj,
    selection.method = hvg_method,
    nfeatures = 2000L
  )

  pca_layer <- preferred_expr_layer(seuratObj)
  seuratObj <- run_memory_conserving_pca(seuratObj, layer = pca_layer, npcs = npcs)
  seuratObj <- Seurat::FindNeighbors(seuratObj, dims = seq_len(ndims), reduction = "pca")
  seuratObj <- Seurat::FindClusters(seuratObj, resolution = res)
  seuratObj <- Seurat::RunUMAP(seuratObj, dims = seq_len(ndims), reduction = "pca")
  seuratObj
}

#' @noRd
assert_h5ad_write_dependencies <- function() {
  assert_bpcells_available()

  if (!requireNamespace("rhdf5", quietly = TRUE)) {
    stop("rhdf5 must be installed for Scanpy-compatible .h5ad export")
  }

  invisible(TRUE)
}

#' @noRd
h5ad_write_attribute <- function(value, file, name, attr_name) {
  fid <- rhdf5::H5Fopen(file)
  on.exit(rhdf5::H5Fclose(fid), add = TRUE)

  h5obj <- if (identical(name, "/")) {
    fid
  } else {
    rhdf5::H5Oopen(fid, name)
  }

  if (!identical(name, "/")) {
    on.exit(rhdf5::H5Oclose(h5obj), add = TRUE)
  }

  rhdf5::h5writeAttribute(value, h5obj, name = attr_name)
}

#' @noRd
h5ad_write_encoding <- function(file, name, encoding_type, encoding_version) {
  h5ad_write_attribute(encoding_type, file = file, name = name, attr_name = "encoding-type")
  h5ad_write_attribute(encoding_version, file = file, name = name, attr_name = "encoding-version")
}

#' @noRd
h5ad_create_group <- function(file, name, encoding_type = NULL, encoding_version = NULL) {
  fid <- rhdf5::H5Fopen(file)
  group_exists <- rhdf5::H5Lexists(fid, name)
  rhdf5::H5Fclose(fid)
  if (!group_exists) {
    rhdf5::h5createGroup(file, name)
  }
  if (!is.null(encoding_type) && !is.null(encoding_version)) {
    h5ad_write_encoding(file, name, encoding_type = encoding_type, encoding_version = encoding_version)
  }
}

#' @noRd
h5ad_write_string_dataset <- function(value, file, name) {
  rhdf5::h5write(
    as.character(value),
    file = file,
    name = name,
    variableLengthString = TRUE,
    encoding = "UTF-8"
  )
  h5ad_write_encoding(file, name, encoding_type = "string-array", encoding_version = "0.2.0")
}

#' @noRd
h5ad_write_array_dataset <- function(value, file, name, chunk = NULL, level = 0L) {
  if (is.character(value)) {
    h5ad_write_string_dataset(value, file = file, name = name)
    return(invisible(NULL))
  }

  if (is.matrix(value) && !is.null(chunk)) {
    rhdf5::h5createDataset(
      file = file,
      dataset = name,
      dims = dim(value),
      storage.mode = storage.mode(value),
      chunk = chunk,
      level = level
    )
    rhdf5::h5write(value, file = file, name = name)
  } else {
    rhdf5::h5write(value, file = file, name = name)
  }

  h5ad_write_encoding(file, name, encoding_type = "array", encoding_version = "0.2.0")
}

#' @noRd
h5ad_write_scalar <- function(value, file, name) {
  if (is.character(value)) {
    rhdf5::h5write(
      as.character(value),
      file = file,
      name = name,
      variableLengthString = TRUE,
      encoding = "UTF-8"
    )
  } else {
    rhdf5::h5write(value, file = file, name = name)
  }
  if (is.character(value)) {
    h5ad_write_encoding(file, name, encoding_type = "string", encoding_version = "0.2.0")
  } else {
    h5ad_write_encoding(file, name, encoding_type = "numeric-scalar", encoding_version = "0.2.0")
  }
}

#' @noRd
h5ad_write_categorical <- function(value, file, name) {
  h5ad_create_group(file, name, encoding_type = "categorical", encoding_version = "0.2.0")
  codes <- as.integer(value) - 1L
  codes[is.na(codes)] <- -1L
  h5ad_write_array_dataset(codes, file = file, name = file.path(name, "codes"))
  h5ad_write_string_dataset(levels(value), file = file, name = file.path(name, "categories"))
  h5ad_write_attribute(isTRUE(is.ordered(value)), file = file, name = name, attr_name = "ordered")
}

#' @noRd
h5ad_write_nullable <- function(value, file, name, type) {
  encoding_type <- switch(
    type,
    integer = "nullable-integer",
    logical = "nullable-boolean",
    character = "nullable-string-array",
    stop("Unsupported nullable type: ", type)
  )

  h5ad_create_group(file, name, encoding_type = encoding_type, encoding_version = "0.1.0")
  mask <- is.na(value)
  values <- switch(
    type,
    integer = {
      out <- as.integer(value)
      out[mask] <- 0L
      out
    },
    logical = {
      out <- as.logical(value)
      out[mask] <- FALSE
      out
    },
    character = {
      out <- as.character(value)
      out[mask] <- ""
      out
    }
  )

  if (identical(type, "character")) {
    h5ad_write_attribute("NA", file = file, name = name, attr_name = "na-value")
    h5ad_write_string_dataset(values, file = file, name = file.path(name, "values"))
  } else {
    h5ad_write_array_dataset(values, file = file, name = file.path(name, "values"))
  }
  h5ad_write_array_dataset(mask, file = file, name = file.path(name, "mask"))
}

#' @noRd
h5ad_write_dataframe_column <- function(value, file, name) {
  if (is.factor(value)) {
    h5ad_write_categorical(value, file = file, name = name)
    return(invisible(NULL))
  }

  if (is.integer(value) && anyNA(value)) {
    h5ad_write_nullable(value, file = file, name = name, type = "integer")
    return(invisible(NULL))
  }

  if (is.logical(value) && anyNA(value)) {
    h5ad_write_nullable(value, file = file, name = name, type = "logical")
    return(invisible(NULL))
  }

  if (is.character(value) && anyNA(value)) {
    h5ad_write_nullable(value, file = file, name = name, type = "character")
    return(invisible(NULL))
  }

  if (is.character(value)) {
    h5ad_write_string_dataset(value, file = file, name = name)
    return(invisible(NULL))
  }

  if (is.logical(value) || is.integer(value) || is.numeric(value)) {
    h5ad_write_array_dataset(value, file = file, name = name)
    return(invisible(NULL))
  }

  stop("Unsupported dataframe column type for AnnData export: ", paste(class(value), collapse = "/"))
}

#' @noRd
h5ad_write_dataframe <- function(data, file, name) {
  if (!is.data.frame(data)) {
    stop("Expected a data.frame for AnnData dataframe export")
  }

  if ("_index" %in% colnames(data)) {
    stop("'_index' is a reserved dataframe column name for AnnData export")
  }

  h5ad_create_group(file, name, encoding_type = "dataframe", encoding_version = "0.2.0")
  h5ad_write_attribute(colnames(data), file = file, name = name, attr_name = "column-order")
  h5ad_write_attribute("_index", file = file, name = name, attr_name = "_index")
  h5ad_write_string_dataset(rownames(data), file = file, name = file.path(name, "_index"))

  for (column in colnames(data)) {
    h5ad_write_dataframe_column(data[[column]], file = file, name = file.path(name, column))
  }
}

#' @noRd
h5ad_write_matrix_group <- function(mat, file, group, buffer_size, chunk_size, gzip_level) {
  BPCells::write_matrix_anndata_hdf5(
    mat = mat,
    path = file,
    group = group,
    buffer_size = buffer_size,
    chunk_size = chunk_size,
    gzip_level = gzip_level
  )
  rhdf5::h5closeAll()
}

#' @noRd
h5ad_write_dense_matrix <- function(mat, file, name, chunk_rows = 4096L, gzip_level = 0L) {
  mat <- as.matrix(mat)
  chunk <- if (length(dim(mat)) == 2L) c(min(nrow(mat), chunk_rows), ncol(mat)) else NULL
  h5ad_write_array_dataset(mat, file = file, name = name, chunk = chunk, level = gzip_level)
}

#' @noRd
h5ad_assay_meta <- function(object, assay, features) {
  meta <- tryCatch(object[[assay]][[]], error = function(...) NULL)

  if (is.null(meta)) {
    meta <- data.frame(row.names = features)
  } else if (!length(features)) {
    meta <- meta[0, , drop = FALSE]
  } else if (!all(features %in% rownames(meta))) {
    meta <- data.frame(row.names = features)
  } else {
    meta <- meta[features, , drop = FALSE]
  }

  hvgs <- tryCatch(VariableFeatures(object), error = function(...) character(0))
  meta$highly_variable <- rownames(meta) %in% hvgs

  meta
}

#' @noRd
h5ad_layer_features <- function(object, assay, layer) {
  SeuratObject::Features(object[[assay]], layer = layer)
}

#' @noRd
h5ad_layer_matches_x <- function(object, assay, layer, x_features, x_cells) {
  mat <- SeuratObject::LayerData(object, assay = assay, layer = layer)
  features <- h5ad_layer_features(object, assay = assay, layer = layer)
  identical(dim(mat), c(length(features), length(x_cells))) &&
    identical(features, x_features) &&
    identical(colnames(mat), x_cells)
}

#' @noRd
h5ad_reduction_export_name <- function(name) {
  if (startsWith(name, "X_")) {
    return(name)
  }

  paste0("X_", name)
}

#' @noRd
h5ad_uns_payload <- function(object, assay, x_layer) {
  payload <- list(
    scspotlight = list(
      default_assay = assay,
      x_layer = x_layer
    )
  )

  if ("pca" %in% SeuratObject::Reductions(object)) {
    stdev <- tryCatch(Seurat::Stdev(object[["pca"]]), error = function(...) numeric(0))
    if (length(stdev)) {
      variance <- stdev^2
      variance_ratio <- variance / sum(variance)
      payload$pca <- list(
        variance = variance,
        variance_ratio = variance_ratio
      )
    }
  }

  payload
}

#' @noRd
h5ad_write_mapping <- function(values, file, name) {
  h5ad_create_group(file, name, encoding_type = "dict", encoding_version = "0.1.0")

  for (key in names(values)) {
    value <- values[[key]]
    target <- file.path(name, key)

    if (is.list(value) && !is.data.frame(value)) {
      h5ad_write_mapping(value, file = file, name = target)
    } else if ((is.atomic(value) || is.matrix(value)) && length(value) == 1L && is.null(dim(value))) {
      h5ad_write_scalar(value, file = file, name = target)
    } else if (is.character(value)) {
      h5ad_write_string_dataset(value, file = file, name = target)
    } else if (is.atomic(value) || is.matrix(value)) {
      h5ad_write_array_dataset(value, file = file, name = target)
    } else {
      stop("Unsupported uns value for AnnData export at key '", key, "'")
    }
  }
}

#' Write a Scanpy-compatible h5ad file
#'
#' Writes the active Seurat assay to a Scanpy-compatible `.h5ad` file using the
#' AnnData on-disk structure. Matrix payloads are streamed with BPCells and the
#' surrounding AnnData metadata structure is written with `rhdf5`.
#'
#' @param object A Seurat object.
#' @param output_file Path to the output `.h5ad` file.
#' @param assay Assay name to export. Defaults to the active assay.
#' @param x_layer Layer to write as `X`. Defaults to the preferred expression
#'   layer (`data` when present, otherwise `counts`).
#' @param include_raw Whether to write the `raw` group when a counts layer is
#'   available and differs from `X`.
#' @param matrix_buffer_size BPCells write buffer size for sparse matrix export.
#' @param matrix_chunk_size BPCells write chunk size for sparse matrix export.
#' @param gzip_level Gzip compression level used for matrix and dense array output.
#' @param obsm_chunk_rows Chunk row count for dense `obsm`/`varm` arrays.
#'
#' @return The normalized output `.h5ad` path.
#'
#' @examples
#' \dontrun{
#' write_h5ad_scanpy(pbmc, "pbmc.h5ad")
#' }
#' @export
write_h5ad_scanpy <- function(object,
                              output_file,
                              assay = NULL,
                              x_layer = NULL,
                              include_raw = TRUE,
                              matrix_buffer_size = 16384L,
                              matrix_chunk_size = 1024L,
                              gzip_level = 0L,
                              obsm_chunk_rows = 4096L) {
  assert_h5ad_write_dependencies()

  if (!inherits(object, "Seurat")) {
    stop("object must be a Seurat object")
  }

  assay <- assay %||% DefaultAssay(object)
  if (!assay %in% Assays(object)) {
    stop("Assay not found in object: ", assay)
  }

  object <- ensure_assay5(object, assay = assay)
  x_layer <- x_layer %||% preferred_expr_layer(object, assay)
  layers <- SeuratObject::Layers(object[[assay]])
  if (!x_layer %in% layers) {
    stop("Layer not found in assay '", assay, "': ", x_layer)
  }

  if (!is_seurat_bpcells(object, assay = assay)) {
    export_backend_root <- tempfile("scspotlight_h5ad_layers_")
    dir.create(export_backend_root, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(export_backend_root, recursive = TRUE, force = TRUE), add = TRUE)
    object <- ensure_bpcells_backing(
      object,
      root_dir = export_backend_root,
      assays = assay,
      layers = setdiff(layers, "scale.data")
    )
  }

  x_mat <- SeuratObject::LayerData(object, assay = assay, layer = x_layer)
  x_mat_write <- SeuratObject::LayerData(object, assay = assay, layer = x_layer, fast = TRUE)
  x_features <- h5ad_layer_features(object, assay = assay, layer = x_layer)
  x_cells <- colnames(x_mat)
  obs <- object[[]][x_cells, , drop = FALSE]
  var <- h5ad_assay_meta(object, assay = assay, features = x_features)

  counts_exists <- "counts" %in% layers
  counts_mat <- if (counts_exists) SeuratObject::LayerData(object, assay = assay, layer = "counts") else NULL
  counts_mat_write <- if (counts_exists) SeuratObject::LayerData(object, assay = assay, layer = "counts", fast = TRUE) else NULL
  counts_features <- if (counts_exists) h5ad_layer_features(object, assay = assay, layer = "counts") else character(0)
  counts_same_as_x <- counts_exists &&
    identical(counts_features, x_features) &&
    identical(colnames(counts_mat), x_cells)

  if (file.exists(output_file)) {
    unlink(output_file)
  }
  rhdf5::h5createFile(output_file)
  h5ad_write_encoding(output_file, "/", encoding_type = "anndata", encoding_version = "0.1.0")

  h5ad_write_matrix_group(
    x_mat_write,
    file = output_file,
    group = "X",
    buffer_size = as.integer(matrix_buffer_size),
    chunk_size = as.integer(matrix_chunk_size),
    gzip_level = as.integer(gzip_level)
  )

  h5ad_create_group(output_file, "layers", encoding_type = "dict", encoding_version = "0.1.0")
  same_space_layers <- setdiff(layers, c(x_layer, "scale.data"))
  same_space_layers <- same_space_layers[vapply(same_space_layers, function(layer) {
    h5ad_layer_matches_x(object, assay = assay, layer = layer, x_features = x_features, x_cells = x_cells)
  }, logical(1))]
  for (layer in same_space_layers) {
    h5ad_write_matrix_group(
      SeuratObject::LayerData(object, assay = assay, layer = layer, fast = TRUE),
      file = output_file,
      group = file.path("layers", layer),
      buffer_size = as.integer(matrix_buffer_size),
      chunk_size = as.integer(matrix_chunk_size),
      gzip_level = as.integer(gzip_level)
    )
  }

  write_raw <- isTRUE(include_raw) && counts_exists && (!identical(x_layer, "counts") || !counts_same_as_x)
  if (write_raw) {
    h5ad_create_group(output_file, "raw", encoding_type = "raw", encoding_version = "0.1.0")
    h5ad_write_matrix_group(
      counts_mat_write,
      file = output_file,
      group = "raw/X",
      buffer_size = as.integer(matrix_buffer_size),
      chunk_size = as.integer(matrix_chunk_size),
      gzip_level = as.integer(gzip_level)
    )
  }

  h5ad_write_dataframe(obs, file = output_file, name = "obs")
  h5ad_write_dataframe(var, file = output_file, name = "var")
  if (write_raw) {
    h5ad_write_dataframe(h5ad_assay_meta(object, assay = assay, features = counts_features), file = output_file, name = "raw/var")
    h5ad_create_group(output_file, "raw/varm", encoding_type = "dict", encoding_version = "0.1.0")
  }

  h5ad_create_group(output_file, "obsm", encoding_type = "dict", encoding_version = "0.1.0")
  reductions <- SeuratObject::Reductions(object)
  for (reduction in reductions) {
    embeddings <- Seurat::Embeddings(object[[reduction]])
    embeddings <- embeddings[x_cells, , drop = FALSE]
    h5ad_write_dense_matrix(
      embeddings,
      file = output_file,
      name = file.path("obsm", h5ad_reduction_export_name(reduction)),
      chunk_rows = as.integer(obsm_chunk_rows),
      gzip_level = as.integer(gzip_level)
    )
  }

  h5ad_create_group(output_file, "varm", encoding_type = "dict", encoding_version = "0.1.0")
  if ("pca" %in% reductions) {
    loadings <- tryCatch(Seurat::Loadings(object[["pca"]]), error = function(...) NULL)
    if (!is.null(loadings) && nrow(loadings) && all(x_features %in% rownames(loadings))) {
      loadings <- loadings[x_features, , drop = FALSE]
      h5ad_write_dense_matrix(
        loadings,
        file = output_file,
        name = "varm/PCs",
        chunk_rows = as.integer(obsm_chunk_rows),
        gzip_level = as.integer(gzip_level)
      )
    }
  }

  h5ad_write_mapping(h5ad_uns_payload(object, assay = assay, x_layer = x_layer), file = output_file, name = "uns")

  normalizePath(output_file, winslash = "/", mustWork = FALSE)
}

#' Convert a file to a Scanpy-compatible h5ad file
#'
#' Reads a Seurat `.Rds` or `.h5ad` file and writes a Scanpy-compatible `.h5ad`
#' file using the current Seurat / BPCells backend.
#'
#' @param input_file Path to an input Seurat `.Rds` or `.h5ad` file.
#' @param output_file Path to the output `.h5ad` file. If `NULL`, it is created
#'   next to `input_file` with the same base name and a `.h5ad` suffix.
#' @param assay Assay name to export. Defaults to the active assay.
#' @param x_layer Layer to write as `X`.
#' @param include_raw Whether to write Scanpy `raw` from the counts layer.
#' @param matrix_buffer_size BPCells write buffer size for sparse matrix export.
#' @param matrix_chunk_size BPCells write chunk size for sparse matrix export.
#' @param gzip_level Gzip compression level used for matrix and dense array output.
#' @param obsm_chunk_rows Chunk row count for dense `obsm`/`varm` arrays.
#'
#' @return The normalized output `.h5ad` path.
#'
#' @examples
#' \dontrun{
#' convert_to_scanpy_h5ad("pbmc3k.Rds")
#' }
#' @export
convert_to_scanpy_h5ad <- function(input_file,
                                   output_file = NULL,
                                   assay = NULL,
                                   x_layer = NULL,
                                   include_raw = TRUE,
                                   matrix_buffer_size = 16384L,
                                   matrix_chunk_size = 1024L,
                                   gzip_level = 0L,
                                   obsm_chunk_rows = 4096L) {
  assert_h5ad_write_dependencies()

  if (!file.exists(input_file)) {
    stop("Input file does not exist: ", input_file)
  }

  input_type <- if (grepl("\\.[Rr][Dd][Ss]$", input_file)) {
    "rds"
  } else if (grepl("\\.[Hh]5[Aa][Dd]$", input_file)) {
    "h5ad"
  } else {
    stop("input_file must point to a .Rds or .h5ad file")
  }

  if (is.null(output_file)) {
    output_file <- sub("\\.[^.]+$", ".h5ad", input_file)
  }
  if (!grepl("\\.[Hh]5[Aa][Dd]$", output_file)) {
    stop("output_file must end with .h5ad")
  }

  work_root <- tempfile("scspotlight_h5ad_export_")
  dir.create(work_root, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(work_root, recursive = TRUE, force = TRUE), add = TRUE)

  object <- switch(
    input_type,
    rds = readRDS(input_file),
    h5ad = import_h5ad_as_seurat_bpcells(input_file, backend_root = file.path(work_root, "backend_layers"))
  )

  if (!inherits(object, "Seurat")) {
    stop("input_file did not produce a Seurat object")
  }

  write_h5ad_scanpy(
    object = object,
    output_file = output_file,
    assay = assay,
    x_layer = x_layer,
    include_raw = include_raw,
    matrix_buffer_size = matrix_buffer_size,
    matrix_chunk_size = matrix_chunk_size,
    gzip_level = gzip_level,
    obsm_chunk_rows = obsm_chunk_rows
  )
}

#' @noRd
create_scspotlight_manifest <- function(object) {
  list(
    bundle_type = "scspotlight_bpcells_seurat_bundle",
    schema_version = 1L,
    created_at = as.character(Sys.time()),
    seurat_version = as.character(utils::packageVersion("Seurat")),
    seuratobject_version = as.character(utils::packageVersion("SeuratObject")),
    bpcells_version = if (bpcells_available()) as.character(utils::packageVersion("BPCells")) else NA_character_,
    assays = stats::setNames(lapply(Assays(object), function(assay) {
      list(layers = SeuratObject::Layers(object[[assay]]))
    }), Assays(object)),
    reductions = SeuratObject::Reductions(object),
    default_assay = DefaultAssay(object)
  )
}

#' @noRd
read_scspotlight_manifest <- function(bundle_dir) {
  manifest_path <- file.path(bundle_dir, "manifest.json")
  if (!file.exists(manifest_path)) {
    return(NULL)
  }
  jsonlite::read_json(manifest_path, simplifyVector = TRUE)
}

#' @noRd
is_scspotlight_bundle_dir <- function(bundle_dir) {
  manifest <- read_scspotlight_manifest(bundle_dir)
  is.list(manifest) && identical(manifest$bundle_type, "scspotlight_bpcells_seurat_bundle")
}

#' @noRd
find_scspotlight_bundle_rds <- function(bundle_dir) {
  manifest <- read_scspotlight_manifest(bundle_dir)
  rds_files <- list.files(bundle_dir, pattern = "\\.[Rr][Dd][Ss]$", full.names = TRUE)
  if (!length(rds_files)) {
    stop("No RDS file found in bundle directory")
  }
  if (length(rds_files) == 1L) {
    return(rds_files[[1]])
  }
  if (!is.null(manifest) && !is.null(manifest$rds_file)) {
    candidate <- file.path(bundle_dir, manifest$rds_file)
    if (file.exists(candidate)) {
      return(candidate)
    }
  }
  stop("Multiple RDS files found in bundle directory; cannot determine bundle entrypoint")
}

#' @noRd
prepare_bundle_object <- function(object, bundle_dir) {
  object_copy <- object
  support_dir <- file.path(bundle_dir, "supporting")
  dir.create(support_dir, recursive = TRUE, showWarnings = FALSE)

  copy_dir_recursive <- function(from, to) {
    dir.create(to, recursive = TRUE, showWarnings = FALSE)
    entries <- list.files(from, all.files = TRUE, no.. = TRUE, full.names = TRUE)
    for (entry in entries) {
      target <- file.path(to, basename(entry))
      if (dir.exists(entry)) {
        copy_dir_recursive(entry, target)
      } else {
        ok <- file.copy(from = entry, to = target, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE)
        if (!isTRUE(ok)) {
          stop(sprintf("Failed to copy file '%s' into bundle", entry))
        }
      }
    }
  }

  for (assay in Assays(object_copy)) {
    layers <- SeuratObject::Layers(object_copy[[assay]])
    if (!length(layers)) {
      next
    }

    if ("scale.data" %in% layers) {
      SeuratObject::LayerData(object_copy, assay = assay, layer = "scale.data") <- NULL
      layers <- setdiff(layers, "scale.data")
    }

    for (layer in layers) {
      layer_data <- SeuratObject::LayerData(object_copy, assay = assay, layer = layer)
      if (!is_bpcells_matrix(layer_data)) {
        next
      }

      src_path <- SeuratObject:::.FilePath(layer_data)
      src_path <- Filter(nzchar, src_path)
      if (!length(src_path)) {
        next
      }
      src_path <- src_path[[1]]

      dest_path <- file.path(support_dir, assay, layer)
      dir.create(dirname(dest_path), recursive = TRUE, showWarnings = FALSE)

      if (dir.exists(dest_path)) {
        unlink(dest_path, recursive = TRUE, force = TRUE)
      }
      copy_dir_recursive(src_path, dest_path)

      SeuratObject::LayerData(object_copy, assay = assay, layer = layer) <- BPCells::open_matrix_dir(dest_path)
    }
  }

  object_copy
}

#' @noRd
write_scspotlight_bundle <- function(object, bundle_dir, file_name = "object.Rds", progress = NULL) {
  progress <- progress %||% (function(...) NULL)

  progress(message = "Preparing bundle files")
  dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
  object <- prepare_bundle_object(object, bundle_dir)
  out_rds <- file.path(bundle_dir, file_name)

  progress(message = "Saving Seurat object")
  SeuratObject::SaveSeuratRds(object, out_rds, move = FALSE, relative = TRUE)

  progress(message = "Finalizing saved object")
  saved_object <- readRDS(out_rds)
  tool_names <- names(saved_object@tools)
  if ("SeuratObject::SaveSeuratRds" %in% tool_names && !"SaveSeuratRds" %in% tool_names) {
    saved_object@tools[["SaveSeuratRds"]] <- saved_object@tools[["SeuratObject::SaveSeuratRds"]]
    saved_object@tools[["SeuratObject::SaveSeuratRds"]] <- NULL
    saveRDS(saved_object, out_rds)
  }

  progress(message = "Writing bundle metadata")
  manifest <- create_scspotlight_manifest(object)
  manifest$rds_file <- basename(out_rds)
  jsonlite::write_json(manifest, file.path(bundle_dir, "manifest.json"), auto_unbox = TRUE, pretty = TRUE)

  progress(message = "Writing bundle helpers")
  writeLines(
    c(
      "# scSpotlight BPCells bundle",
      "# After unpacking this archive, replace <bundle_dir> with the extracted folder path.",
      "# Option 1: set the working directory to the bundle folder, then load:",
      "old <- setwd('<bundle_dir>')",
      "source('load_bundle.R')",
      "obj <- load_bundle()",
      "setwd(old)",
      "# Option 2: from any working directory:",
      "source(file.path('<bundle_dir>', 'load_bundle.R'))",
      "obj <- load_bundle('<bundle_dir>')"
    ),
    con = file.path(bundle_dir, "README.txt")
  )
  writeLines(
    c(
      "load_bundle <- function(bundle_dir = '.', rds_file = NULL) {",
      "  if (!requireNamespace('SeuratObject', quietly = TRUE)) {",
      "    stop('SeuratObject is required to load this bundle')",
      "  }",
      "  if (!requireNamespace('jsonlite', quietly = TRUE)) {",
      "    stop('jsonlite is required to read the bundle manifest')",
      "  }",
      "  manifest_path <- file.path(bundle_dir, 'manifest.json')",
      "  if (!file.exists(manifest_path)) {",
      "    stop('manifest.json not found in bundle directory')",
      "  }",
      "  manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)",
      "  if (is.null(rds_file)) {",
      "    rds_file <- manifest$rds_file",
      "    if (is.null(rds_file) || !nzchar(rds_file)) stop('rds_file missing from manifest')",
      "  }",
      "  old_wd <- getwd()",
      "  on.exit(setwd(old_wd), add = TRUE)",
      "  setwd(bundle_dir)",
      "  SeuratObject::LoadSeuratRds(rds_file)",
      "}"
    ),
    con = file.path(bundle_dir, "load_bundle.R")
  )

  progress(message = "Bundle ready")
  out_rds
}

#' Convert a file to a BPCells bundle archive
#'
#' Reads a standard Seurat `.Rds` or `.h5ad` file, converts assay layers to
#' BPCells-backed storage, writes a portable scSpotlight bundle, and packages it
#' as a `.tar.gz` archive.
#'
#' The resulting archive contains:
#' - a Seurat `.Rds` entrypoint saved with relative bundle paths,
#' - BPCells layer directories under `supporting/`,
#' - a `manifest.json` file describing the bundle layout,
#' - helper files (`README.txt`, `load_bundle.R`) for loading the bundle in a
#'   plain R session.
#'
#' This is intended for converting exchange formats into a portable BPCells
#' bundle that can be loaded by scSpotlight or by `SeuratObject::LoadSeuratRds()`
#' from the extracted bundle directory context.
#'
#' `.h5ad` inputs are imported through `BPCells::open_matrix_anndata_hdf5()` for
#' memory-conserving matrix access. The converter reads `obs` and `obsm` through
#' `rhdf5` without materializing the full matrix in memory.
#'
#' Existing BPCells-backed layers are preserved. Non-BPCells assay layers are
#' rewritten into BPCells-backed on-disk storage before the bundle is created.
#' The bundle writer also drops `scale.data` layers to avoid packaging dense,
#' derived matrices unnecessarily.
#'
#' @param input_file Path to an input Seurat `.Rds` or `.h5ad` file.
#' @param output_file Path to the output `.tar.gz` bundle file. If `NULL`, the
#'   archive is created next to `input_file` with the same base name and a
#'   `.tar.gz` suffix.
#'
#' @return The normalized output archive path.
#'
#' @examples
#' \dontrun{
#' convert_to_bpcells_bundle("pbmc3k.Rds")
#' convert_to_bpcells_bundle("pbmc3k.h5ad", "pbmc3k-bundle.tar.gz")
#' }
#' @export
convert_to_bpcells_bundle <- function(input_file, output_file = NULL) {
  assert_bpcells_available()

  if (!file.exists(input_file)) {
    stop("Input file does not exist: ", input_file)
  }

  input_type <- if (grepl("\\.[Rr][Dd][Ss]$", input_file)) {
    "rds"
  } else if (grepl("\\.[Hh]5[Aa][Dd]$", input_file)) {
    "h5ad"
  } else {
    stop("input_file must point to a .Rds or .h5ad file")
  }

  work_root <- tempfile("scspotlight_bundle_work_")
  dir.create(work_root, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(work_root, recursive = TRUE, force = TRUE), add = TRUE)

  backend_root <- file.path(work_root, "backend_layers")

  object <- switch(
    input_type,
    rds = readRDS(input_file),
    h5ad = {
      import_h5ad_as_seurat_bpcells(input_file, backend_root = backend_root)
    }
  )

  if (!inherits(object, "Seurat")) {
    stop("input_file did not produce a Seurat object")
  }

  if (is.null(output_file)) {
    output_file <- sub("\\.[^.]+$", ".tar.gz", input_file)
  }
  if (!grepl("\\.(tar\\.gz|tgz)$", output_file)) {
    stop("output_file must end with .tar.gz or .tgz")
  }

  bundle_name <- sub("\\.(tar\\.gz|tgz)$", "", basename(output_file))
  if (!is_seurat_bpcells(object)) {
    object <- ensure_bpcells_backing(object, root_dir = backend_root)
  }

  bundle_dir <- file.path(work_root, bundle_name)
  dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
  bundle_rds_name <- paste0(sub("\\.[^.]+$", "", basename(input_file)), ".Rds")
  write_scspotlight_bundle(object, bundle_dir, file_name = bundle_rds_name)

  output_dir <- dirname(output_file)
  if (!dir.exists(output_dir)) {
    stop("Output directory does not exist: ", output_dir)
  }

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(work_root)
  utils::tar(
    tarfile = output_file,
    files = bundle_name,
    compression = "gzip"
  )

  normalizePath(output_file, winslash = "/", mustWork = FALSE)
}

#' @noRd
load_scspotlight_bundle <- function(file) {
  if (!is.character(file) || length(file) != 1L || !nzchar(file)) {
    stop("Expected a single RDS file path")
  }
  if (!file.exists(file)) {
    stop("Bundle file does not exist: ", file)
  }

  file <- normalizePath(file, winslash = "/", mustWork = TRUE)
  old_wd <- getwd()
  bundle_dir <- dirname(file)
  on.exit(setwd(old_wd), add = TRUE)

  tryCatch(
    setwd(bundle_dir),
    error = function(error) {
      stop("Failed to access bundle directory '", bundle_dir, "': ", conditionMessage(error))
    }
  )

  tryCatch(
    SeuratObject::LoadSeuratRds(basename(file)),
    error = function(error) {
      stop("Failed to load Seurat RDS bundle '", basename(file), "': ", conditionMessage(error))
    }
  )
}
