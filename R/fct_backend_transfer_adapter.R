#' Backend transfer adapter helpers
#'
#' @noRd

transfer_error_payload_types <- c(
  "metadata",
  "metadata_patch",
  "reduction",
  "reductions",
  "pca",
  "expression"
)

transfer_error_context_fields <- list(
  metadata = character(0),
  metadata_patch = "cols",
  reduction = c("reductionName", "activeReduction", "transferAttemptId"),
  reductions = c("reductionName", "activeReduction", "transferAttemptId"),
  pca = character(0),
  expression = c("geneName", "assay")
)

normalize_transfer_resource_prefix <- function(resource_prefix) {
  resource_prefix <- as.character(resource_prefix %||% character())
  resource_prefix <- resource_prefix[!is.na(resource_prefix) & nzchar(resource_prefix)]
  if (length(resource_prefix) != 1L || !grepl(
    "^[A-Za-z0-9][A-Za-z0-9_-]*$",
    resource_prefix[[1]],
    perl = TRUE
  ) || identical(resource_prefix[[1]], "data")) {
    stop(
      "File-backed browser transfers require a valid session resource prefix.",
      call. = FALSE
    )
  }

  resource_prefix[[1]]
}

validate_backend_metadata_patch_cols <- function(object, cols) {
  cols <- normalize_transfer_cols(cols)
  if (!length(cols)) {
    return(character())
  }

  reserved_cols <- c("cells", ".scspotlight_cell_idx", ".scspotlight_cell_id")
  invalid_reserved <- intersect(cols, reserved_cols)
  if (length(invalid_reserved)) {
    stop(
      "Metadata patch columns cannot include reserved Cell ID fields: ",
      paste(invalid_reserved, collapse = ", "),
      call. = FALSE
    )
  }

  available_cols <- get_backend_metadata_columns(object)
  invalid_cols <- setdiff(cols, available_cols)
  if (length(invalid_cols)) {
    stop(
      "Metadata patch columns are not available: ",
      paste(invalid_cols, collapse = ", "),
      call. = FALSE
    )
  }

  cols
}

normalize_transfer_cols <- function(cols) {
  cols <- unique(as.character(cols %||% character()))
  cols[!is.na(cols) & nzchar(cols) & cols != "None"]
}

make_clear_expr_payload <- function(invalidate_version = NULL) {
  if (is.null(invalidate_version)) {
    # Shiny serializes a named empty list as the contract's empty JSON object.
    return(structure(list(), names = character()))
  }

  if (
    !is.numeric(invalidate_version) ||
      length(invalidate_version) != 1L ||
      is.na(invalidate_version) ||
      !is.finite(invalidate_version) ||
      invalidate_version < 0
  ) {
    stop("`invalidate_version` must be a finite non-negative number.")
  }

  list(invalidateVersion = unname(as.numeric(invalidate_version)))
}

sanitize_transfer_error_value <- function(value, field) {
  value <- as.character(value)
  value <- vapply(
    value,
    function(item) {
      if (is.na(item) || !nzchar(item)) {
        return(NA_character_)
      }

      pattern <- if (identical(field, "geneName")) {
        "^[A-Za-z0-9][A-Za-z0-9_.+-]*(?:/[A-Za-z0-9][A-Za-z0-9_.+-]*)*$"
      } else {
        "^[A-Za-z0-9][A-Za-z0-9_.+-]*$"
      }
      if (!grepl(pattern, item, perl = TRUE)) {
        return(NA_character_)
      }

      item
    },
    character(1),
    USE.NAMES = FALSE
  )

  value[!is.na(value) & nzchar(value)]
}

make_transfer_error_payload <- function(
  payload_type,
  reason_code,
  version,
  context = list(),
  resource_prefix = NULL
) {
  payload_type <- as.character(payload_type)[[1]]
  if (!payload_type %in% transfer_error_payload_types) {
    stop("Unsupported transfer error payload type: ", payload_type)
  }

  payload <- list(
    payloadType = payload_type,
    reasonCode = as.character(reason_code)[[1]],
    version = version
  )

  if (isTruthy(resource_prefix)) {
    payload$resourcePrefix <- normalize_transfer_resource_prefix(resource_prefix)
  }

  fields <- transfer_error_context_fields[[payload_type]]
  for (field in fields) {
    value <- context[[field]]
    if (is.null(value)) {
      next
    }

    if (identical(field, "transferAttemptId")) {
      value <- suppressWarnings(as.numeric(value[[1]]))
      if (!is.finite(value) || value < 1) {
        next
      }
      payload[[field]] <- value
      next
    }

    value <- sanitize_transfer_error_value(value, field = field)
    if (!length(value)) {
      next
    }

    payload[[field]] <- if (identical(field, "cols")) value else value[[1]]
  }

  payload
}

prepare_backend_metadata_transfer <- function(
  object,
  dir_path,
  meta_version,
  cols = NULL,
  resource_prefix = NULL
) {
  resource_prefix <- normalize_transfer_resource_prefix(resource_prefix)
  cols <- normalize_transfer_cols(cols)
  is_patch <- length(cols) > 0L
  if (is_patch) {
    cols <- validate_backend_metadata_patch_cols(object, cols)
  }
  if (is_patch) {
    patch_key <- paste(sort(cols), collapse = "|")
    file_name <- hash_md5(paste0(
      "meta_patch_",
      patch_key,
      "_",
      meta_version
    ))
    payload <- list(
      metaFile = file_name,
      cols = unname(as.list(cols)),
      metaVersion = meta_version
    )
  } else {
    file_name <- hash_md5(paste0("meta_", meta_version))
    payload <- list(metaFile = file_name, metaVersion = meta_version)
  }

  payload$resourcePrefix <- resource_prefix

  if (is_scspotlight_explore_bundle(object)) {
    query_plan <- explore_bundle_metadata_query_plan(object, cols = cols)
    payload$cellIdentity <- query_plan$cell_identity
    return(list(
      backend = "explore_bundle",
      metadata_path = query_plan$metadata_path,
      cols = query_plan$cols,
      cell_count = query_plan$cell_count,
      include_cells = !is_patch,
      filePath = file.path(dir_path, file_name),
      payload = payload
    ))
  }

  metadata <- get_backend_metadata(object, cols = cols)
  cell_ids <- rownames(metadata)
  if (
    is.null(cell_ids) ||
      length(cell_ids) != nrow(metadata) ||
      any(is.na(cell_ids) | !nzchar(cell_ids))
  ) {
    stop(
      "Metadata transfer requires canonical Cell IDs in row names.",
      call. = FALSE
    )
  }
  payload$cellIdentity <- rlang::hash(as.character(cell_ids))
  list(
    backend = "data_frame",
    data = clean_meta_frame(metadata),
    cols = cols,
    include_cells = !is_patch,
    filePath = file.path(dir_path, file_name),
    payload = payload
  )
}

write_backend_metadata_transfer <- function(transfer) {
  if (identical(transfer$backend, "explore_bundle")) {
    extract_explore_metadata_to_ipc(
      metadata_path = transfer$metadata_path,
      output_file = transfer$filePath,
      cols = transfer$cols,
      expected_cell_count = transfer$cell_count,
      include_cells = transfer$include_cells
    )
    return(transfer$payload)
  }

  data <- transfer$data
  if (!transfer$include_cells) {
    data$cells <- NULL
  }
  write_ipc_stream(as_arrow_table(data), transfer$filePath)
  transfer$payload
}

write_backend_pca_stdev_transfer <- function(
  object,
  dir_path,
  reduction_version,
  resource_prefix = NULL
) {
  resource_prefix <- normalize_transfer_resource_prefix(resource_prefix)
  file_name <- hash_md5(paste0("pca_stdev_", reduction_version))
  file_path <- file.path(dir_path, file_name)
  pca_stdev <- get_backend_pca_stdev(object)

  if (length(pca_stdev)) {
    write_ipc_stream(
      arrow_table(stdev = Array$create(pca_stdev, type = float32())),
      file_path
    )
    payload <- list(stdevFile = file_name, reductionVersion = reduction_version)
    payload$resourcePrefix <- resource_prefix
    return(payload)
  }

  if (file.exists(file_path)) {
    file.remove(file_path)
  }
  payload <- list(stdevFile = NULL, reductionVersion = reduction_version)
  payload$resourcePrefix <- resource_prefix
  payload
}

prepare_backend_reduction_transfer <- function(
  object,
  reduction_name,
  dir_path,
  reduction_version,
  resource_prefix = NULL,
  transfer_attempt_id
) {
  resource_prefix <- normalize_transfer_resource_prefix(resource_prefix)
  transfer_attempt_id <- suppressWarnings(as.numeric(transfer_attempt_id[[1]]))
  if (!is.finite(transfer_attempt_id) || transfer_attempt_id < 1) {
    stop("transfer_attempt_id must be a positive finite number.", call. = FALSE)
  }
  file_name <- hash_md5(paste0(
    "reduction_",
    reduction_name,
    "_",
    reduction_version,
    "_",
    transfer_attempt_id
  ))
  payload <- list(
    reductionFile = file_name,
    reductionName = reduction_name,
    reductionVersion = reduction_version
  )
  payload$resourcePrefix <- resource_prefix
  payload$transferAttemptId <- transfer_attempt_id

  if (is_scspotlight_explore_bundle(object)) {
    query_plan <- explore_bundle_reduction_query_plan(
      object,
      reduction = reduction_name
    )
    return(list(
      backend = "explore_bundle",
      reduction_path = query_plan$reduction_path,
      x_col = query_plan$x_col,
      y_col = query_plan$y_col,
      cell_count = query_plan$cell_count,
      filePath = file.path(dir_path, file_name),
      payload = payload
    ))
  }

  list(
    backend = "data_frame",
    data = get_backend_reduction(object, reduction = reduction_name),
    filePath = file.path(dir_path, file_name),
    payload = payload
  )
}

write_backend_reduction_transfer <- function(transfer) {
  if (identical(transfer$backend, "explore_bundle")) {
    extract_explore_reduction_to_ipc(
      reduction_path = transfer$reduction_path,
      x_col = transfer$x_col,
      y_col = transfer$y_col,
      output_file = transfer$filePath,
      expected_cell_count = transfer$cell_count
    )
    return(transfer$payload)
  }

  reduction_data <- transfer$data
  write_ipc_stream(
    arrow_table(
      X = Array$create(reduction_data$X, type = float32()),
      Y = Array$create(reduction_data$Y, type = float32())
    ),
    transfer$filePath
  )
  transfer$payload
}

prepare_backend_expression_transfer <- function(
  object,
  assay,
  feature,
  dir_path,
  expr_version,
  backend_root = NULL,
  resource_prefix = NULL
) {
  resource_prefix <- normalize_transfer_resource_prefix(resource_prefix)
  add_resource_prefix <- function(payload) {
    payload$resourcePrefix <- resource_prefix
    payload
  }

  if (is_scspotlight_explore_bundle(object)) {
    assay <- assay %||% get_backend_default_assay(object)
    file_name <- hash_md5(paste0(
      "expr_explore_",
      assay,
      "_",
      feature,
      "_",
      expr_version
    ))
    query_plan <- explore_bundle_expression_query_plan(
      object,
      feature = feature,
      assay = assay
    )
    return(list(
      backend = "explore_bundle",
      feature = feature,
      assay = assay,
      block_path = query_plan$block_path,
      feature_idx = query_plan$feature_idx,
      cell_count = query_plan$cell_count,
      output_file = file.path(dir_path, file_name),
      payload = add_resource_prefix(list(
        geneName = feature,
        assay = assay,
        exprVersion = expr_version,
        exprFile = file_name
      ))
    ))
  }

  layer_ref <- get_bpcells_layer_ref(
    object,
    assay = assay,
    backend_root = backend_root
  )
  file_name <- hash_md5(paste0(
    "expr_",
    layer_ref$assay,
    "_",
    layer_ref$layer,
    "_",
    feature,
    "_",
    expr_version
  ))

  transfer <- list(
    backend = if (!is.null(layer_ref$matrix_dir)) {
      "bpcells"
    } else {
      "bpcells_anndata_hdf5"
    },
    feature = feature,
    assay = layer_ref$assay,
    layer = layer_ref$layer,
    output_file = file.path(dir_path, file_name),
    payload = add_resource_prefix(list(
      geneName = feature,
      assay = layer_ref$assay,
      exprVersion = expr_version,
      exprFile = file_name
    ))
  )

  if (!is.null(layer_ref$matrix_dir)) {
    transfer$matrix_dir <- layer_ref$matrix_dir
  } else {
    transfer$h5ad_path <- layer_ref$h5ad_path
    transfer$h5ad_group <- layer_ref$h5ad_group
  }

  transfer
}

write_backend_expression_transfer <- function(transfer) {
  if (identical(transfer$backend, "explore_bundle")) {
    extract_explore_query_expr_to_ipc(
      block_path = transfer$block_path,
      feature_idx = transfer$feature_idx,
      cell_count = transfer$cell_count,
      output_file = transfer$output_file
    )
    return(transfer$payload)
  }

  if (identical(transfer$backend, "bpcells")) {
    extract_bpcells_expr_to_ipc(
      matrix_dir = transfer$matrix_dir,
      feature = transfer$feature,
      output_file = transfer$output_file
    )
    return(transfer$payload)
  }

  if (identical(transfer$backend, "bpcells_anndata_hdf5")) {
    extract_bpcells_expr_to_ipc(
      feature = transfer$feature,
      output_file = transfer$output_file,
      h5ad_path = transfer$h5ad_path,
      h5ad_group = transfer$h5ad_group
    )
    return(transfer$payload)
  }

  stop("Unsupported expression transfer backend: ", transfer$backend)
}
