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
  reduction = c("reductionName", "activeReduction"),
  reductions = c("reductionName", "activeReduction"),
  pca = character(0),
  expression = c("geneName", "assay")
)

sanitize_transfer_error_value <- function(value) {
  value <- as.character(value)
  value <- vapply(value, function(item) {
    if (is.na(item) || !nzchar(item)) {
      return(NA_character_)
    }

    if (grepl("[/\\\\]", item)) {
      item <- basename(item)
    }

    item
  }, character(1), USE.NAMES = FALSE)

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
    payload$resourcePrefix <- basename(as.character(resource_prefix)[[1]])
  }

  fields <- transfer_error_context_fields[[payload_type]]
  for (field in fields) {
    value <- context[[field]]
    if (is.null(value)) {
      next
    }

    value <- sanitize_transfer_error_value(value)
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
  if (isTruthy(cols)) {
    patch_key <- paste(sort(cols), collapse = "|")
    file_name <- hash_md5(paste0(
      "meta_patch_",
      patch_key,
      "_",
      meta_version
    ))
    payload <- list(
      metaFile = file_name,
      cols = cols,
      metaVersion = meta_version
    )
  } else {
    file_name <- hash_md5(paste0("meta_", meta_version))
    payload <- list(metaFile = file_name, metaVersion = meta_version)
  }

  if (isTruthy(resource_prefix)) {
    payload$resourcePrefix <- basename(as.character(resource_prefix)[[1]])
  }

  if (is_scspotlight_explore_bundle(object)) {
    query_plan <- explore_bundle_metadata_query_plan(object, cols = cols)
    return(list(
      backend = "explore_bundle",
      metadata_path = query_plan$metadata_path,
      cols = query_plan$cols,
      filePath = file.path(dir_path, file_name),
      payload = payload
    ))
  }

  list(
    backend = "data_frame",
    data = clean_meta_frame(get_backend_metadata(object, cols = cols)),
    cols = cols,
    filePath = file.path(dir_path, file_name),
    payload = payload
  )
}

write_backend_metadata_transfer <- function(transfer) {
  if (identical(transfer$backend, "explore_bundle")) {
    extract_explore_metadata_to_ipc(
      metadata_path = transfer$metadata_path,
      output_file = transfer$filePath,
      cols = transfer$cols
    )
    return(transfer$payload)
  }

  write_ipc_stream(as_arrow_table(transfer$data), transfer$filePath)
  transfer$payload
}

write_backend_pca_stdev_transfer <- function(
  object,
  dir_path,
  reduction_version,
  resource_prefix = NULL
) {
  file_name <- hash_md5(paste0("pca_stdev_", reduction_version))
  file_path <- file.path(dir_path, file_name)
  pca_stdev <- get_backend_pca_stdev(object)

  if (length(pca_stdev)) {
    write_ipc_stream(
      arrow_table(stdev = Array$create(pca_stdev, type = float32())),
      file_path
    )
    payload <- list(stdevFile = file_name, reductionVersion = reduction_version)
    if (isTruthy(resource_prefix)) {
      payload$resourcePrefix <- basename(as.character(resource_prefix)[[1]])
    }
    return(payload)
  }

  if (file.exists(file_path)) {
    file.remove(file_path)
  }
  payload <- list(stdevFile = NULL, reductionVersion = reduction_version)
  if (isTruthy(resource_prefix)) {
    payload$resourcePrefix <- basename(as.character(resource_prefix)[[1]])
  }
  payload
}

prepare_backend_reduction_transfer <- function(
  object,
  reduction_name,
  dir_path,
  reduction_version,
  resource_prefix = NULL
) {
  file_name <- hash_md5(paste0(
    "reduction_",
    reduction_name,
    "_",
    reduction_version
  ))
  payload <- list(
    reductionFile = file_name,
    reductionName = reduction_name,
    reductionVersion = reduction_version
  )

  if (isTruthy(resource_prefix)) {
    payload$resourcePrefix <- basename(as.character(resource_prefix)[[1]])
  }

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
      output_file = transfer$filePath
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
  add_resource_prefix <- function(payload) {
    if (isTruthy(resource_prefix)) {
      payload$resourcePrefix <- basename(as.character(resource_prefix)[[1]])
    }
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

  list(
    backend = "bpcells",
    matrix_dir = layer_ref$matrix_dir,
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

  stop("Unsupported expression transfer backend: ", transfer$backend)
}
