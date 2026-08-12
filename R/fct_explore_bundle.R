#' Explore bundle helpers
#'
#' @noRd

scspotlight_explore_bundle_type <- "scspotlight_explore_parquet_bundle"
scspotlight_explore_schema_version <- 1L
scspotlight_explore_archive_pattern <- "\\.explore-parquet\\.[Zz][Ii][Pp]$"
scspotlight_reduction_transfer_chunk_size <- 100000L
scspotlight_metadata_transfer_chunk_size <- 100000L
scspotlight_expression_transfer_chunk_size <- 100000L
scspotlight_expression_export_cell_chunk_size <- 100000L

duckdb_parquet_sql_path <- function(path) {
  gsub(
    "'",
    "''",
    normalizePath(path, winslash = "/", mustWork = TRUE)
  )
}

duckdb_quote_identifier <- function(x) {
  paste0('"', gsub('"', '""', x), '"')
}

explore_parquet_columns <- function(path) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sql_path <- duckdb_parquet_sql_path(path)
  colnames(DBI::dbGetQuery(
    con,
    sprintf("SELECT * FROM read_parquet('%s') LIMIT 0", sql_path)
  ))
}

validate_scspotlight_explore_cells_file <- function(
  cells_path,
  expected_cell_count = NULL
) {
  if (!file.exists(cells_path)) {
    stop("Explore bundle cells.parquet is missing: ", cells_path)
  }

  required_cols <- c("cell_idx", "cell_id")
  missing_cols <- setdiff(required_cols, explore_parquet_columns(cells_path))
  if (length(missing_cols)) {
    stop(
      "Explore bundle cells.parquet is missing required column(s): ",
      paste(missing_cols, collapse = ", ")
    )
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sql_path <- duckdb_parquet_sql_path(cells_path)
  cell_idx <- duckdb_quote_identifier("cell_idx")
  cell_id <- duckdb_quote_identifier("cell_id")
  summary <- DBI::dbGetQuery(
    con,
    sprintf(
      paste(
        "SELECT",
        "COUNT(*) AS row_count,",
        "COUNT(DISTINCT TRY_CAST(%1$s AS BIGINT)) AS distinct_index_count,",
        "MIN(TRY_CAST(%1$s AS BIGINT)) AS min_index,",
        "MAX(TRY_CAST(%1$s AS BIGINT)) AS max_index,",
        "SUM(CASE WHEN TRY_CAST(%1$s AS DOUBLE) IS NULL",
        "OR TRY_CAST(%1$s AS DOUBLE) <> FLOOR(TRY_CAST(%1$s AS DOUBLE))",
        "THEN 1 ELSE 0 END) AS invalid_index_count,",
        "SUM(CASE WHEN %2$s IS NULL",
        "OR TRIM(CAST(%2$s AS VARCHAR)) = '' THEN 1 ELSE 0 END)",
        "AS invalid_id_count,",
        "COUNT(DISTINCT CAST(%2$s AS VARCHAR)) AS distinct_id_count",
        "FROM read_parquet('%3$s')",
        sep = " "
      ),
      cell_idx,
      cell_id,
      sql_path
    )
  )

  row_count <- as.numeric(summary$row_count[[1]])
  distinct_index_count <- as.numeric(summary$distinct_index_count[[1]])
  min_index <- as.numeric(summary$min_index[[1]])
  max_index <- as.numeric(summary$max_index[[1]])
  invalid_index_count <- as.numeric(summary$invalid_index_count[[1]])
  invalid_id_count <- as.numeric(summary$invalid_id_count[[1]])
  distinct_id_count <- as.numeric(summary$distinct_id_count[[1]])
  expected_cell_count <- if (is.null(expected_cell_count)) {
    row_count
  } else {
    as.numeric(expected_cell_count[[1]])
  }

  if (
    !is.finite(row_count) ||
      !is.finite(expected_cell_count) ||
      row_count != expected_cell_count ||
      row_count < 1 ||
      invalid_index_count != 0 ||
      distinct_index_count != row_count ||
      min_index != 0 ||
      max_index != row_count - 1 ||
      invalid_id_count != 0 ||
      distinct_id_count != row_count
  ) {
    stop(
      paste(
        "Explore bundle cells.parquet must contain a dense, unique cell_idx",
        "and non-empty unique Cell IDs."
      ),
      call. = FALSE
    )
  }

  invisible(row_count)
}

validate_scspotlight_explore_metadata_cell_index <- function(
  metadata_path,
  cells_path,
  expected_cell_count
) {
  metadata_cols <- explore_parquet_columns(metadata_path)
  if (!".scspotlight_cell_idx" %in% metadata_cols) {
    stop(
      "Explore bundle metadata.parquet is missing required column: ",
      ".scspotlight_cell_idx"
    )
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  metadata_sql_path <- duckdb_parquet_sql_path(metadata_path)
  cells_sql_path <- duckdb_parquet_sql_path(cells_path)
  metadata_idx <- duckdb_quote_identifier(".scspotlight_cell_idx")
  cell_idx <- duckdb_quote_identifier("cell_idx")
  summary <- DBI::dbGetQuery(
    con,
    sprintf(
      paste(
        "SELECT",
        "COUNT(*) AS metadata_count,",
        "COUNT(DISTINCT TRY_CAST(meta_src.%1$s AS BIGINT))",
        "AS distinct_index_count,",
        "SUM(CASE WHEN TRY_CAST(meta_src.%1$s AS DOUBLE) IS NULL",
        "OR TRY_CAST(meta_src.%1$s AS DOUBLE) <>",
        "FLOOR(TRY_CAST(meta_src.%1$s AS DOUBLE))",
        "THEN 1 ELSE 0 END) AS invalid_index_count,",
        "SUM(CASE WHEN cell_index.%2$s IS NULL THEN 1 ELSE 0 END)",
        "AS missing_cell_count",
        "FROM read_parquet('%3$s') AS meta_src",
        "LEFT JOIN read_parquet('%4$s') AS cell_index",
        "ON TRY_CAST(meta_src.%1$s AS BIGINT) = cell_index.%2$s",
        sep = " "
      ),
      metadata_idx,
      cell_idx,
      metadata_sql_path,
      cells_sql_path
    )
  )

  metadata_count <- as.numeric(summary$metadata_count[[1]])
  distinct_index_count <- as.numeric(summary$distinct_index_count[[1]])
  invalid_index_count <- as.numeric(summary$invalid_index_count[[1]])
  missing_cell_count <- as.numeric(summary$missing_cell_count[[1]])
  expected_cell_count <- as.numeric(expected_cell_count)
  if (
    !is.finite(metadata_count) ||
      metadata_count != expected_cell_count ||
      distinct_index_count != expected_cell_count ||
      invalid_index_count != 0 ||
      missing_cell_count != 0
  ) {
    stop(
      paste(
        "Explore bundle metadata.parquet must contain exactly one valid cell",
        "index for every canonical Cell ID."
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_scspotlight_explore_reduction_cell_index <- function(
  reduction_path,
  expected_cell_count = NULL
) {
  if (!file.exists(reduction_path)) {
    stop("Explore bundle reduction file is missing: ", reduction_path)
  }

  if (!"cell_idx" %in% explore_parquet_columns(reduction_path)) {
    stop(
      "Explore bundle reduction is missing required column cell_idx: ",
      reduction_path
    )
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sql_path <- duckdb_parquet_sql_path(reduction_path)
  cell_idx <- duckdb_quote_identifier("cell_idx")
  summary <- DBI::dbGetQuery(
    con,
    sprintf(
      paste(
        "SELECT",
        "COUNT(*) AS row_count,",
        "COUNT(DISTINCT TRY_CAST(%1$s AS BIGINT)) AS distinct_index_count,",
        "MIN(TRY_CAST(%1$s AS BIGINT)) AS min_index,",
        "MAX(TRY_CAST(%1$s AS BIGINT)) AS max_index,",
        "SUM(CASE WHEN TRY_CAST(%1$s AS DOUBLE) IS NULL",
        "OR TRY_CAST(%1$s AS DOUBLE) <> FLOOR(TRY_CAST(%1$s AS DOUBLE))",
        "THEN 1 ELSE 0 END) AS invalid_index_count",
        "FROM read_parquet('%2$s')",
        sep = " "
      ),
      cell_idx,
      sql_path
    )
  )

  row_count <- as.numeric(summary$row_count[[1]])
  distinct_index_count <- as.numeric(summary$distinct_index_count[[1]])
  min_index <- as.numeric(summary$min_index[[1]])
  max_index <- as.numeric(summary$max_index[[1]])
  invalid_index_count <- as.numeric(summary$invalid_index_count[[1]])
  expected_cell_count <- if (is.null(expected_cell_count)) {
    row_count
  } else {
    as.numeric(expected_cell_count[[1]])
  }

  if (
    !is.finite(row_count) ||
      !is.finite(expected_cell_count) ||
      row_count != expected_cell_count ||
      row_count < 1 ||
      invalid_index_count != 0 ||
      distinct_index_count != row_count ||
      min_index != 0 ||
      max_index != row_count - 1
  ) {
    stop(
      paste(
        "Explore bundle reduction must contain a dense, unique cell_idx",
        "for every canonical Cell ID."
      ),
      call. = FALSE
    )
  }

  invisible(row_count)
}

is_scspotlight_explore_bundle <- function(object) {
  inherits(object, "scspotlight_explore_bundle")
}

read_scspotlight_explore_manifest <- function(bundle_dir) {
  manifest_path <- file.path(bundle_dir, "manifest.json")
  if (!file.exists(manifest_path)) {
    return(NULL)
  }
  jsonlite::read_json(manifest_path, simplifyVector = TRUE)
}

is_scspotlight_explore_bundle_dir <- function(bundle_dir) {
  if (!dir.exists(bundle_dir)) {
    return(FALSE)
  }

  manifest <- read_scspotlight_explore_manifest(bundle_dir)
  is.list(manifest) &&
    identical(manifest$bundle_type, scspotlight_explore_bundle_type)
}

find_scspotlight_explore_bundle_root <- function(path) {
  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    return(NULL)
  }

  if (is_scspotlight_explore_bundle_dir(path)) {
    return(normalizePath(path, winslash = "/", mustWork = TRUE))
  }

  if (file.exists(path) && basename(path) == "manifest.json") {
    parent <- dirname(path)
    if (is_scspotlight_explore_bundle_dir(parent)) {
      return(normalizePath(parent, winslash = "/", mustWork = TRUE))
    }
  }

  if (!dir.exists(path)) {
    return(NULL)
  }

  manifest_paths <- list.files(
    path,
    pattern = "^manifest\\.json$",
    recursive = TRUE,
    full.names = TRUE
  )
  candidate_roots <- unique(dirname(manifest_paths))
  matched_roots <- candidate_roots[
    vapply(candidate_roots, is_scspotlight_explore_bundle_dir, logical(1))
  ]
  if (!length(matched_roots)) {
    return(NULL)
  }

  normalizePath(matched_roots[[1]], winslash = "/", mustWork = TRUE)
}

read_scspotlight_explore_bundle <- function(bundle_dir) {
  bundle_root <- find_scspotlight_explore_bundle_root(bundle_dir)
  if (is.null(bundle_root)) {
    stop("Explore bundle manifest not found: ", bundle_dir)
  }

  manifest <- read_scspotlight_explore_manifest(bundle_root)
  if (!is.list(manifest)) {
    stop("Explore bundle manifest is missing or invalid: ", bundle_root)
  }
  if (!identical(manifest$bundle_type, scspotlight_explore_bundle_type)) {
    stop(
      "Unsupported Explore bundle type: ",
      manifest$bundle_type %||% "<missing>"
    )
  }

  validate_scspotlight_explore_bundle_files(bundle_root, manifest)

  features_path <- file.path(bundle_root, "features.parquet")
  features <- arrow::read_parquet(features_path)
  structure(
    list(
      root = bundle_root,
      manifest = manifest,
      features = as.data.frame(features, stringsAsFactors = FALSE)
    ),
    class = "scspotlight_explore_bundle"
  )
}

validate_scspotlight_explore_bundle_files <- function(bundle_root, manifest) {
  required_files <- c(
    "cells.parquet",
    "metadata.parquet",
    "features.parquet"
  )
  missing_files <- required_files[
    !file.exists(file.path(bundle_root, required_files))
  ]
  if (length(missing_files)) {
    stop(
      "Explore bundle is missing required file(s): ",
      paste(missing_files, collapse = ", ")
    )
  }

  metadata_cols <- explore_parquet_columns(file.path(
    bundle_root,
    "metadata.parquet"
  ))
  if (!".scspotlight_cell_idx" %in% metadata_cols) {
    stop(
      "Explore bundle metadata.parquet is missing required column: ",
      ".scspotlight_cell_idx"
    )
  }
  cell_count <- validate_scspotlight_explore_cells_file(
    file.path(bundle_root, "cells.parquet"),
    expected_cell_count = manifest$cell_count
  )
  validate_scspotlight_explore_metadata_cell_index(
    file.path(bundle_root, "metadata.parquet"),
    file.path(bundle_root, "cells.parquet"),
    expected_cell_count = cell_count
  )

  reductions <- as.character(manifest$reductions %||% character())
  if (!length(reductions)) {
    stop("Explore bundle manifest must include at least one reduction")
  }
  reduction_files <- file.path(
    bundle_root,
    "reductions",
    paste0(reductions, ".parquet")
  )
  missing_reductions <- reductions[!file.exists(reduction_files)]
  if (length(missing_reductions)) {
    stop(
      "Explore bundle is missing reduction file(s): ",
      paste(missing_reductions, collapse = ", ")
    )
  }

  for (i in seq_along(reductions)) {
    reduction_cols <- explore_parquet_columns(reduction_files[[i]])
    if (!"cell_idx" %in% reduction_cols) {
      stop(
        "Explore bundle reduction is missing required column cell_idx: ",
        reductions[[i]]
      )
    }
    validate_scspotlight_explore_reduction_cell_index(
      reduction_files[[i]],
      expected_cell_count = cell_count
    )
  }

  features_path <- file.path(bundle_root, "features.parquet")
  feature_cols <- explore_parquet_columns(features_path)
  if (!"block" %in% feature_cols) {
    stop("Explore bundle features.parquet is missing required column: block")
  }
  features <- arrow::read_parquet(features_path, col_select = "block")
  blocks <- sort(unique(as.integer(features$block)))
  missing_blocks <- blocks[
    !file.exists(file.path(
      bundle_root,
      "expression",
      sprintf("block_%05d.parquet", blocks)
    ))
  ]
  if (length(missing_blocks)) {
    stop(
      "Explore bundle is missing expression block file(s): ",
      paste(sprintf("block_%05d.parquet", missing_blocks), collapse = ", ")
    )
  }

  invisible(TRUE)
}

explore_bundle_path <- function(bundle, ...) {
  file.path(bundle$root, ...)
}

explore_bundle_metadata_path <- function(bundle) {
  explore_bundle_path(bundle, "metadata.parquet")
}

explore_bundle_cells_path <- function(bundle) {
  explore_bundle_path(bundle, "cells.parquet")
}

explore_bundle_reduction_path <- function(bundle, reduction) {
  explore_bundle_path(bundle, "reductions", paste0(reduction, ".parquet"))
}

explore_bundle_pca_stdev_path <- function(bundle) {
  explore_bundle_path(bundle, "reductions", "pca_stdev.parquet")
}

explore_bundle_expression_block_path <- function(bundle, block) {
  explore_bundle_path(
    bundle,
    "expression",
    sprintf("block_%05d.parquet", as.integer(block))
  )
}

explore_prepare_metadata <- function(meta) {
  meta <- as.data.frame(meta, stringsAsFactors = FALSE)
  rownames(meta) <- NULL

  meta$.scspotlight_cell_idx <- seq_len(nrow(meta)) - 1L

  for (col in colnames(meta)) {
    if (is.numeric(meta[[col]])) {
      v <- meta[[col]]
      v[is.nan(v) | is.infinite(v)] <- NA
      meta[[col]] <- v
    } else if (is.logical(meta[[col]])) {
      meta[[col]] <- as.character(meta[[col]])
    } else if (is.factor(meta[[col]])) {
      meta[[col]] <- as.character(meta[[col]])
    }
  }

  meta
}

explore_write_parquet <- function(x, path, compression = "zstd") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(x, path, compression = compression)
  invisible(path)
}

explore_sparse_summary <- function(mat) {
  sparse <- if (inherits(mat, "dgCMatrix")) {
    mat
  } else {
    tryCatch(
      methods::as(mat, Class = "dgCMatrix"),
      error = function(...) NULL
    )
  }

  if (is.null(sparse)) {
    dense <- as.matrix(mat)
    sparse <- methods::as(
      Matrix::Matrix(dense, sparse = TRUE),
      Class = "dgCMatrix"
    )
  }

  sparse <- methods::as(
    methods::as(sparse, Class = "generalMatrix"),
    Class = "TsparseMatrix"
  )
  if (!length(sparse@x)) {
    return(explore_empty_expression_frame())
  }

  return(data.frame(
    i = sparse@i + 1L,
    j = sparse@j + 1L,
    x = sparse@x
  ))
}

explore_expression_parquet_schema <- function() {
  arrow::schema(
    feature_idx = arrow::int32(),
    cell_idx = arrow::int32(),
    value = arrow::float64()
  )
}

explore_write_expression_block <- function(
  mat,
  row_idx,
  path,
  compression = "zstd",
  cell_chunk_size = scspotlight_expression_export_cell_chunk_size
) {
  cell_chunk_size <- suppressWarnings(as.integer(cell_chunk_size))
  if (is.na(cell_chunk_size) || cell_chunk_size < 1L) {
    stop("cell_chunk_size must be a positive integer")
  }

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path)) {
    file.remove(path)
  }

  sink <- arrow::FileOutputStream$create(path)
  sink_closed <- FALSE
  writer <- NULL
  writer_closed <- FALSE
  on.exit(
    {
      if (!is.null(writer) && !writer_closed) {
        try(writer$Close(), silent = TRUE)
      }
      if (!sink_closed) {
        try(sink$close(), silent = TRUE)
      }
    },
    add = TRUE
  )
  writer <- arrow::ParquetFileWriter$create(
    schema = explore_expression_parquet_schema(),
    sink = sink,
    properties = arrow::ParquetWriterProperties$create(
      column_names = c("feature_idx", "cell_idx", "value"),
      compression = compression
    )
  )

  cell_count <- ncol(mat)
  if (cell_count > 0L) {
    for (cell_start in seq.int(1L, cell_count, by = cell_chunk_size)) {
      cell_end <- min(cell_count, cell_start + cell_chunk_size - 1L)
      chunk_mat <- mat[
        row_idx,
        seq.int(cell_start, cell_end),
        drop = FALSE
      ]
      sparse_summary <- explore_sparse_summary(chunk_mat)

      if (nrow(sparse_summary)) {
        expression_table <- arrow::arrow_table(
          feature_idx = arrow::Array$create(
            as.integer(row_idx[sparse_summary$i] - 1L),
            type = arrow::int32()
          ),
          cell_idx = arrow::Array$create(
            as.integer(cell_start + sparse_summary$j - 2L),
            type = arrow::int32()
          ),
          value = arrow::Array$create(
            sparse_summary$x,
            type = arrow::float64()
          )
        )
        writer$WriteTable(expression_table, chunk_size = nrow(sparse_summary))
        rm(expression_table)
      }

      rm(sparse_summary, chunk_mat)
      gc()
    }
  }

  writer$Close()
  writer_closed <- TRUE
  sink$close()
  sink_closed <- TRUE

  invisible(path)
}

explore_empty_expression_frame <- function() {
  data.frame(
    feature_idx = integer(),
    cell_idx = integer(),
    value = numeric()
  )
}

write_scspotlight_explore_bundle <- function(
  object,
  bundle_dir,
  assay = NULL,
  layer = NULL,
  block_size = 1024L,
  compression = "zstd",
  progress = NULL,
  expression_cell_chunk_size = scspotlight_expression_export_cell_chunk_size
) {
  progress <- progress %||% (function(...) NULL)

  if (!inherits(object, "Seurat")) {
    stop("object must be a Seurat object")
  }
  if (!is.numeric(block_size) || length(block_size) != 1L || block_size < 1L) {
    stop("block_size must be a positive integer")
  }
  block_size <- as.integer(block_size)
  expression_cell_chunk_size <- suppressWarnings(
    as.integer(expression_cell_chunk_size)
  )
  if (is.na(expression_cell_chunk_size) || expression_cell_chunk_size < 1L) {
    stop("expression_cell_chunk_size must be a positive integer")
  }

  assay <- assay %||% DefaultAssay(object)
  if (!assay %in% Assays(object)) {
    stop("Assay not found: ", assay)
  }
  layer <- layer %||% preferred_expr_layer(object, assay)

  assert_processed_input_requirements(
    object,
    assay = assay,
    input_label = "Explore bundle source"
  )

  dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
  cell_count <- ncol(object)

  progress(message = "Writing cell index")
  cells <- data.frame(
    cell_idx = seq_len(cell_count) - 1L,
    cell_id = colnames(object),
    stringsAsFactors = FALSE
  )
  explore_write_parquet(
    cells,
    file.path(bundle_dir, "cells.parquet"),
    compression
  )
  rm(cells)
  gc()

  progress(message = "Writing metadata")
  meta <- explore_prepare_metadata(object[[]])
  explore_write_parquet(
    meta,
    file.path(bundle_dir, "metadata.parquet"),
    compression
  )
  rm(meta)
  gc()

  progress(message = "Writing reductions")
  reduction_names <- SeuratObject::Reductions(object)
  for (reduction in reduction_names) {
    emb <- Seurat::Embeddings(object[[reduction]])
    reduction_df <- data.frame(
      cell_idx = seq_len(nrow(emb)) - 1L,
      as.data.frame(emb, check.names = FALSE),
      check.names = FALSE
    )
    explore_write_parquet(
      reduction_df,
      file.path(bundle_dir, "reductions", paste0(reduction, ".parquet")),
      compression
    )
    rm(reduction_df, emb)
    gc()
  }

  if ("pca" %in% reduction_names) {
    pca_stdev <- tryCatch(object[["pca"]]@stdev, error = function(...) {
      numeric()
    })
    if (length(pca_stdev)) {
      explore_write_parquet(
        data.frame(stdev = as.numeric(pca_stdev)),
        file.path(bundle_dir, "reductions", "pca_stdev.parquet"),
        compression
      )
    }
    rm(pca_stdev)
    gc()
  }

  progress(message = "Writing feature index")
  mat <- SeuratObject::LayerData(object, assay = assay, layer = layer)
  feature_names <- rownames(mat)
  feature_index <- seq_along(feature_names) - 1L
  feature_blocks <- feature_index %/% block_size
  features <- data.frame(
    feature_idx = as.integer(feature_index),
    feature = feature_names,
    assay = assay,
    layer = layer,
    block = as.integer(feature_blocks),
    stringsAsFactors = FALSE
  )
  explore_write_parquet(
    features,
    file.path(bundle_dir, "features.parquet"),
    compression
  )
  rm(features, feature_index)
  gc()

  progress(message = "Writing expression blocks")
  expression_dir <- file.path(bundle_dir, "expression")
  dir.create(expression_dir, recursive = TRUE, showWarnings = FALSE)
  blocks <- split(seq_along(feature_names), feature_blocks)
  rm(feature_blocks, object)
  gc()

  for (block_name in names(blocks)) {
    row_idx <- blocks[[block_name]]
    # Build the file in bounded cell batches. A whole 1M+ cell feature block
    # can otherwise require several gigabytes of temporary sparse data.
    explore_write_expression_block(
      mat = mat,
      row_idx = row_idx,
      path = file.path(
        expression_dir,
        sprintf("block_%05d.parquet", as.integer(block_name))
      ),
      compression = compression,
      cell_chunk_size = expression_cell_chunk_size
    )
  }
  rm(blocks, mat)
  gc()

  progress(message = "Writing Explore bundle manifest")
  manifest <- list(
    bundle_type = scspotlight_explore_bundle_type,
    schema_version = scspotlight_explore_schema_version,
    created_at = as.character(Sys.time()),
    scspotlight_version = as.character(utils::packageVersion("scSpotlight")),
    assay = assay,
    layer = layer,
    assays = list(list(name = assay, layers = list(layer))),
    default_assay = assay,
    cell_count = cell_count,
    feature_count = length(feature_names),
    block_size = block_size,
    expression_compression = compression,
    reductions = reduction_names
  )
  jsonlite::write_json(
    manifest,
    file.path(bundle_dir, "manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )

  normalizePath(bundle_dir, winslash = "/", mustWork = TRUE)
}

read_explore_conversion_source <- function(input_file, backend_root = NULL) {
  if (grepl("\\.[Rr][Dd][Ss]$", input_file)) {
    return(tryCatch(load_scspotlight_bundle(input_file), error = function(...) {
      readRDS(input_file)
    }))
  }

  if (grepl("\\.[Hh]5[Aa][Dd]$", input_file)) {
    backend_root <- backend_root %||%
      scspotlight_temp_path("scspotlight_explore_h5ad_backend_")
    dir.create(backend_root, recursive = TRUE, showWarnings = FALSE)
    return(import_h5ad_as_seurat_bpcells(
      input_file,
      backend_root = backend_root
    ))
  }

  stop("input_file must point to a .Rds or .h5ad file")
}

#' Convert a file to a Parquet Explore bundle archive
#'
#' Reads a processed Seurat `.Rds` or Scanpy/AnnData `.h5ad` file and writes a
#' portable, read-optimized scSpotlight Explore bundle as a `.zip` archive. The
#' bundle stores metadata, reductions, and sparse normalized expression as
#' versioned Parquet files for low-memory Explore Mode loading.
#'
#' @param input_file Path to an input Seurat `.Rds` or `.h5ad` file.
#' @param output_file Path to the output `.explore-parquet.zip` bundle file. If
#'   `NULL`, the archive is created next to `input_file` with
#'   `.explore-parquet.zip` appended.
#' @param assay Assay to export. Defaults to the object's default assay.
#' @param layer Assay layer to export. Defaults to the preferred expression
#'   layer, usually `data` when available.
#' @param block_size Number of features per expression Parquet block.
#' @param compression Parquet compression codec passed to `arrow::write_parquet()`.
#'
#' @return The normalized output archive path.
#'
#' @examples
#' \dontrun{
#' convert_to_explore_bundle("pbmc3k.Rds")
#' convert_to_explore_bundle("pbmc3k.h5ad", "pbmc3k.explore-parquet.zip")
#' }
#' @export
convert_to_explore_bundle <- function(
  input_file,
  output_file = NULL,
  assay = NULL,
  layer = NULL,
  block_size = 1024L,
  compression = "zstd"
) {
  if (!file.exists(input_file)) {
    stop("Input file does not exist: ", input_file)
  }

  if (is.null(output_file)) {
    output_file <- sub("\\.[^.]+$", ".explore-parquet.zip", input_file)
  }
  if (!grepl(scspotlight_explore_archive_pattern, output_file)) {
    stop("output_file must end with .explore-parquet.zip")
  }
  if (!is_absolute_bundle_path(output_file)) {
    output_file <- file.path(getwd(), output_file)
  }
  output_file <- normalizePath(output_file, winslash = "/", mustWork = FALSE)
  output_dir <- dirname(output_file)
  if (!dir.exists(output_dir)) {
    stop("Output directory does not exist: ", output_dir)
  }

  work_root <- scspotlight_temp_path("scspotlight_explore_bundle_work_")
  dir.create(work_root, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(work_root, recursive = TRUE, force = TRUE), add = TRUE)

  bundle_name <- sub("\\.[Zz][Ii][Pp]$", "", basename(output_file))
  bundle_dir <- file.path(work_root, bundle_name)
  write_scspotlight_explore_bundle(
    object = ensure_normalized_layer(
      read_explore_conversion_source(
        input_file,
        backend_root = file.path(work_root, "h5ad_backend")
      ),
      assay = assay,
      input_label = "Explore bundle source"
    ),
    bundle_dir = bundle_dir,
    assay = assay,
    layer = layer,
    block_size = block_size,
    compression = compression
  )

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(work_root)
  create_bundle_archive(
    tarfile = output_file,
    files = bundle_name
  )

  normalizePath(output_file, winslash = "/", mustWork = FALSE)
}

explore_bundle_assays <- function(bundle) {
  assays <- bundle$manifest$assays
  if (is.data.frame(assays) && "name" %in% colnames(assays)) {
    return(as.character(assays$name))
  }
  if (is.list(assays) && length(assays)) {
    names <- vapply(assays, function(x) x$name %||% NA_character_, character(1))
    return(stats::na.omit(names))
  }
  bundle$manifest$assay %||% bundle$manifest$default_assay
}

explore_bundle_default_assay <- function(bundle) {
  bundle$manifest$default_assay %||% bundle$manifest$assay
}

explore_bundle_cell_count <- function(bundle) {
  as.integer(
    bundle$manifest$cell_count %||%
      nrow(arrow::read_parquet(explore_bundle_cells_path(bundle)))
  )
}

explore_bundle_reduction_names <- function(bundle) {
  reductions <- bundle$manifest$reductions %||% character()
  as.character(reductions)
}

explore_bundle_features <- function(bundle, assay = NULL, layer = NULL) {
  features <- bundle$features
  assay <- assay %||% explore_bundle_default_assay(bundle)
  if (isTruthy(assay) && "assay" %in% colnames(features)) {
    features <- features[features$assay == assay, , drop = FALSE]
  }
  if (isTruthy(layer) && "layer" %in% colnames(features)) {
    features <- features[features$layer == layer, , drop = FALSE]
  }
  features$feature
}

explore_bundle_metadata <- function(bundle, cols = NULL) {
  meta <- as.data.frame(
    arrow::read_parquet(explore_bundle_metadata_path(bundle)),
    stringsAsFactors = FALSE
  )
  if (".scspotlight_cell_idx" %in% colnames(meta)) {
    meta <- meta[order(meta$.scspotlight_cell_idx), , drop = FALSE]
  }
  cells <- as.data.frame(
    arrow::read_parquet(explore_bundle_cells_path(bundle)),
    stringsAsFactors = FALSE
  )
  cell_ids <- as.character(
    cells$cell_id[match(meta$.scspotlight_cell_idx, cells$cell_idx)]
  )
  if (any(is.na(cell_ids) | !nzchar(cell_ids))) {
    stop(
      "Explore bundle metadata could not be joined to canonical Cell IDs.",
      call. = FALSE
    )
  }
  meta$.scspotlight_cell_idx <- NULL
  meta$.scspotlight_cell_id <- NULL
  if (isTruthy(cols)) {
    cols <- intersect(cols, colnames(meta))
    meta <- meta[, cols, drop = FALSE]
  }
  rownames(meta) <- cell_ids
  meta
}

clean_meta_transfer_chunk <- function(d) {
  d <- as.data.frame(d, stringsAsFactors = FALSE)

  if ("cells" %in% colnames(d)) {
    d$cells <- as.character(d$cells)
  }

  for (col in colnames(d)) {
    if (is.numeric(d[[col]])) {
      v <- d[[col]]
      v[is.nan(v) | is.infinite(v)] <- NA
      d[[col]] <- v
    } else if (
      col != "cells" &&
        (is.factor(d[[col]]) || is.logical(d[[col]]))
    ) {
      d[[col]] <- as.character(d[[col]])
    }
  }

  d
}

metadata_transfer_column_array <- function(values, dictionary_encode = FALSE) {
  if (dictionary_encode && is.character(values)) {
    levels <- unique(values[!is.na(values)])
    indices <- as.integer(match(values, levels) - 1L)
    return(arrow::DictionaryArray$create(
      arrow::Array$create(indices, type = arrow::int32()),
      arrow::Array$create(levels)
    ))
  }
  if (is.integer(values)) {
    return(arrow::Array$create(values, type = arrow::int32()))
  }
  arrow::Array$create(values)
}

metadata_transfer_arrow_table <- function(d) {
  arrays <- Map(
    function(values, column) {
      metadata_transfer_column_array(
        values,
        dictionary_encode = !identical(column, "cells")
      )
    },
    d,
    colnames(d)
  )
  do.call(arrow::arrow_table, arrays)
}

metadata_transfer_arrow_array <- function(values) {
  value_type <- values$type
  if (inherits(value_type, c("Utf8", "LargeUtf8"))) {
    return(values$cast(arrow::dictionary(arrow::int32(), arrow::utf8())))
  }
  if (inherits(value_type, "Boolean")) {
    return(metadata_transfer_column_array(
      as.character(values$as_vector()),
      dictionary_encode = TRUE
    ))
  }
  if (inherits(value_type, c("Float16", "Float32", "Float64"))) {
    is_finite <- arrow::call_function("is_finite", values)
    all_finite <- arrow::call_function("all", is_finite)$as_vector()
    if (!isTRUE(all_finite)) {
      numeric_values <- values$as_vector()
      invalid_values <- !is.finite(numeric_values)
      numeric_values[invalid_values] <- NA_real_
      return(arrow::Array$create(numeric_values, type = value_type))
    }
  }
  values
}

write_metadata_transfer_chunks <- function(
  output_file,
  next_chunk,
  empty_chunk
) {
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(output_file)) {
    file.remove(output_file)
  }

  sink <- arrow::FileOutputStream$create(output_file)
  writer <- NULL
  writer_closed <- FALSE
  sink_closed <- FALSE
  on.exit(
    {
      if (!is.null(writer) && !writer_closed) {
        try(writer$close(), silent = TRUE)
      }
      if (!sink_closed) {
        try(sink$close(), silent = TRUE)
      }
    },
    add = TRUE
  )

  wrote_chunk <- FALSE
  repeat {
    chunk <- next_chunk()
    if (is.null(chunk) || !nrow(chunk)) {
      break
    }
    chunk <- clean_meta_transfer_chunk(chunk)
    table <- metadata_transfer_arrow_table(chunk)
    if (is.null(writer)) {
      writer <- arrow::RecordBatchStreamWriter$create(sink, table$schema)
    }
    writer$write(table)
    wrote_chunk <- TRUE
  }

  if (!wrote_chunk) {
    table <- metadata_transfer_arrow_table(clean_meta_transfer_chunk(
      empty_chunk
    ))
    writer <- arrow::RecordBatchStreamWriter$create(sink, table$schema)
  }

  writer$close()
  writer_closed <- TRUE
  sink$close()
  sink_closed <- TRUE

  invisible(output_file)
}

try_extract_canonical_explore_metadata_to_ipc <- function(
  metadata_path,
  cells_path,
  output_file,
  selected_cols,
  chunk_size,
  expected_cell_count
) {
  metadata_idx_name <- ".scspotlight_cell_idx"
  metadata_scanner <- arrow::open_dataset(
    metadata_path,
    format = "parquet"
  )$NewScan()
  metadata_scanner$Project(c(selected_cols, metadata_idx_name))
  metadata_scanner$BatchSize(chunk_size)
  metadata_reader <- arrow::as_record_batch_reader(metadata_scanner$Finish())
  on.exit(try(metadata_reader$Close(), silent = TRUE), add = TRUE)

  cells_scanner <- arrow::open_dataset(cells_path, format = "parquet")$NewScan()
  cells_scanner$Project(c("cell_idx", "cell_id"))
  cells_scanner$BatchSize(chunk_size)
  cells_reader <- arrow::as_record_batch_reader(cells_scanner$Finish())
  on.exit(try(cells_reader$Close(), silent = TRUE), add = TRUE)

  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(output_file)) {
    file.remove(output_file)
  }

  sink <- arrow::FileOutputStream$create(output_file)
  writer <- NULL
  writer_closed <- FALSE
  sink_closed <- FALSE
  completed <- FALSE
  on.exit(
    {
      if (!is.null(writer) && !writer_closed) {
        try(writer$close(), silent = TRUE)
      }
      if (!sink_closed) {
        try(sink$close(), silent = TRUE)
      }
      if (!completed) {
        unlink(output_file, force = TRUE)
      }
    },
    add = TRUE
  )

  next_cell_idx <- 0L
  repeat {
    metadata_batch <- metadata_reader$read_next_batch()
    cells_batch <- cells_reader$read_next_batch()
    if (is.null(metadata_batch) && is.null(cells_batch)) {
      break
    }
    if (
      is.null(metadata_batch) ||
        is.null(cells_batch) ||
        nrow(metadata_batch) != nrow(cells_batch)
    ) {
      return(FALSE)
    }

    batch_rows <- nrow(metadata_batch)
    expected_values <- seq.int(next_cell_idx, length.out = batch_rows)
    metadata_values <- as.integer(metadata_batch[[metadata_idx_name]])
    cell_values <- as.integer(cells_batch[["cell_idx"]])
    if (
      !identical(metadata_values, expected_values) ||
        !identical(cell_values, expected_values)
    ) {
      return(FALSE)
    }

    arrays <- lapply(
      selected_cols,
      function(column) metadata_transfer_arrow_array(metadata_batch[[column]])
    )
    names(arrays) <- selected_cols
    arrays$cells <- cells_batch[["cell_id"]]
    output_schema <- do.call(
      arrow::schema,
      lapply(arrays, function(values) values$type)
    )
    output_batch <- do.call(
      arrow::RecordBatch$create,
      c(arrays, list(schema = output_schema))
    )
    if (is.null(writer)) {
      writer <- arrow::RecordBatchStreamWriter$create(sink, output_schema)
    }
    writer$write(output_batch)
    next_cell_idx <- as.integer(next_cell_idx + batch_rows)
  }

  if (is.null(writer) || next_cell_idx != expected_cell_count) {
    return(FALSE)
  }

  writer$close()
  writer_closed <- TRUE
  sink$close()
  sink_closed <- TRUE
  completed <- TRUE
  TRUE
}

explore_bundle_metadata_query_plan <- function(bundle, cols = NULL) {
  metadata_path <- explore_bundle_metadata_path(bundle)
  if (!file.exists(metadata_path)) {
    stop("Explore bundle metadata.parquet is missing: ", metadata_path)
  }

  list(
    metadata_path = normalizePath(
      metadata_path,
      winslash = "/",
      mustWork = TRUE
    ),
    cols = cols,
    cell_count = explore_bundle_cell_count(bundle)
  )
}

extract_explore_metadata_to_ipc <- function(
  metadata_path,
  output_file,
  cols = NULL,
  chunk_size = scspotlight_metadata_transfer_chunk_size,
  expected_cell_count = NULL
) {
  if (!file.exists(metadata_path)) {
    stop("Metadata Parquet file not found: ", metadata_path)
  }
  chunk_size <- suppressWarnings(as.integer(chunk_size))
  if (is.na(chunk_size) || chunk_size < 1L) {
    chunk_size <- scspotlight_metadata_transfer_chunk_size
  }

  metadata_columns <- arrow::open_dataset(
    metadata_path,
    format = "parquet"
  )$schema$names
  if (!".scspotlight_cell_idx" %in% metadata_columns) {
    stop(
      "Metadata Parquet file is missing required column: ",
      ".scspotlight_cell_idx"
    )
  }
  selected_cols <- metadata_columns
  if (isTruthy(cols)) {
    selected_cols <- intersect(cols, selected_cols)
  }
  selected_cols <- setdiff(
    selected_cols,
    c("cells", ".scspotlight_cell_idx", ".scspotlight_cell_id")
  )

  cells_path <- file.path(dirname(metadata_path), "cells.parquet")
  if (is.null(expected_cell_count)) {
    cell_count <- validate_scspotlight_explore_cells_file(cells_path)
    validate_scspotlight_explore_metadata_cell_index(
      metadata_path,
      cells_path,
      expected_cell_count = cell_count
    )
  } else {
    cell_count <- suppressWarnings(as.integer(expected_cell_count[[1]]))
    if (is.na(cell_count) || cell_count < 1L || !file.exists(cells_path)) {
      stop(
        "Explore metadata transfer requires validated canonical Cell IDs.",
        call. = FALSE
      )
    }
  }

  if (
    try_extract_canonical_explore_metadata_to_ipc(
      metadata_path = metadata_path,
      cells_path = cells_path,
      output_file = output_file,
      selected_cols = selected_cols,
      chunk_size = chunk_size,
      expected_cell_count = cell_count
    )
  ) {
    return(invisible(output_file))
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  sql_path <- duckdb_parquet_sql_path(metadata_path)
  schema <- DBI::dbGetQuery(
    con,
    sprintf("SELECT * FROM read_parquet('%s') LIMIT 0", sql_path)
  )
  empty_chunk <- schema[selected_cols]
  empty_chunk$cells <- character()
  metadata_alias <- "meta_src"
  cell_alias <- "cell_index"
  order_expr <- sprintf(
    "%s.%s",
    metadata_alias,
    duckdb_quote_identifier(".scspotlight_cell_idx")
  )
  select_expr <- c(
    vapply(
      selected_cols,
      function(column) {
        sprintf(
          "%s.%s",
          metadata_alias,
          duckdb_quote_identifier(column)
        )
      },
      character(1)
    )
  )

  from_expr <- sprintf(
    paste(
      "read_parquet('%s') AS %s",
      "INNER JOIN read_parquet('%s') AS %s",
      "ON %s = %s.%s"
    ),
    sql_path,
    metadata_alias,
    duckdb_parquet_sql_path(cells_path),
    cell_alias,
    order_expr,
    cell_alias,
    duckdb_quote_identifier("cell_idx")
  )
  cell_id_expr <- sprintf(
    "CAST(%s.%s AS VARCHAR)",
    cell_alias,
    duckdb_quote_identifier("cell_id")
  )
  select_expr <- c(select_expr, sprintf("%s AS cells", cell_id_expr))
  sql <- sprintf(
    "SELECT %s FROM %s ORDER BY %s",
    paste(select_expr, collapse = ", "),
    from_expr,
    order_expr
  )

  result <- DBI::dbSendQuery(con, sql)
  on.exit(try(DBI::dbClearResult(result), silent = TRUE), add = TRUE)

  write_metadata_transfer_chunks(
    output_file = output_file,
    next_chunk = function() {
      chunk <- DBI::dbFetch(result, n = chunk_size)
      if (!nrow(chunk)) {
        return(NULL)
      }
      chunk
    },
    empty_chunk = empty_chunk
  )

  invisible(output_file)
}

explore_bundle_reduction <- function(bundle, reduction, n_components = 2L) {
  reduction_path <- explore_bundle_reduction_path(bundle, reduction)
  if (!file.exists(reduction_path)) {
    stop("Reduction not found in Explore bundle: ", reduction)
  }

  reduction_df <- as.data.frame(arrow::read_parquet(reduction_path))
  if ("cell_idx" %in% colnames(reduction_df)) {
    reduction_df <- reduction_df[order(reduction_df$cell_idx), , drop = FALSE]
  }
  reduction_cols <- setdiff(colnames(reduction_df), "cell_idx")
  keep <- utils::head(reduction_cols, n_components)
  out <- reduction_df[, keep, drop = FALSE]
  if (ncol(out) == 1L) {
    out$V2 <- 0
  }
  colnames(out)[1:2] <- c("X", "Y")
  out[, c("X", "Y"), drop = FALSE]
}

explore_bundle_reduction_query_plan <- function(
  bundle,
  reduction,
  n_components = 2L
) {
  reduction_path <- explore_bundle_reduction_path(bundle, reduction)
  if (!file.exists(reduction_path)) {
    stop("Reduction not found in Explore bundle: ", reduction)
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sql_path <- duckdb_parquet_sql_path(reduction_path)
  schema <- DBI::dbGetQuery(
    con,
    sprintf("SELECT * FROM read_parquet('%s') LIMIT 0", sql_path)
  )
  reduction_cols <- setdiff(colnames(schema), "cell_idx")
  keep <- utils::head(reduction_cols, n_components)
  if (!length(keep)) {
    stop("Reduction has no component columns: ", reduction)
  }
  if (length(keep) == 1L) {
    keep <- c(keep, NA_character_)
  }
  cell_count <- explore_bundle_cell_count(bundle)
  validate_scspotlight_explore_reduction_cell_index(
    reduction_path,
    expected_cell_count = cell_count
  )

  list(
    reduction_path = normalizePath(
      reduction_path,
      winslash = "/",
      mustWork = TRUE
    ),
    x_col = keep[[1]],
    y_col = keep[[2]],
    cell_count = cell_count
  )
}

extract_explore_reduction_to_ipc <- function(
  reduction_path,
  x_col,
  y_col = NA_character_,
  output_file,
  chunk_size = scspotlight_reduction_transfer_chunk_size,
  expected_cell_count = NULL
) {
  if (!file.exists(reduction_path)) {
    stop("Reduction Parquet file not found: ", reduction_path)
  }
  chunk_size <- suppressWarnings(as.integer(chunk_size))
  if (is.na(chunk_size) || chunk_size < 1L) {
    chunk_size <- scspotlight_reduction_transfer_chunk_size
  }
  validate_scspotlight_explore_reduction_cell_index(
    reduction_path,
    expected_cell_count = expected_cell_count
  )

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sql_path <- duckdb_parquet_sql_path(reduction_path)
  x_expr <- duckdb_quote_identifier(x_col)
  y_expr <- if (is.na(y_col) || !nzchar(y_col)) {
    "0"
  } else {
    duckdb_quote_identifier(y_col)
  }
  sql <- sprintf(
    "SELECT %s AS X, %s AS Y FROM read_parquet('%s') ORDER BY cell_idx",
    x_expr,
    y_expr,
    sql_path
  )

  result <- DBI::dbSendQuery(con, sql)
  on.exit(DBI::dbClearResult(result), add = TRUE)

  if (file.exists(output_file)) {
    file.remove(output_file)
  }

  sink <- arrow::FileOutputStream$create(output_file)
  writer <- arrow::RecordBatchStreamWriter$create(
    sink,
    arrow::schema(X = arrow::float32(), Y = arrow::float32())
  )
  writer_closed <- FALSE
  sink_closed <- FALSE
  on.exit(
    {
      if (!writer_closed) {
        try(writer$close(), silent = TRUE)
      }
      if (!sink_closed) {
        try(sink$close(), silent = TRUE)
      }
    },
    add = TRUE
  )

  repeat {
    chunk <- DBI::dbFetch(result, n = chunk_size)
    if (!nrow(chunk)) {
      break
    }
    writer$write(
      arrow::arrow_table(
        X = arrow::Array$create(chunk$X, type = arrow::float32()),
        Y = arrow::Array$create(chunk$Y, type = arrow::float32())
      )
    )
    if (DBI::dbHasCompleted(result)) {
      break
    }
  }

  writer$close()
  writer_closed <- TRUE
  sink$close()
  sink_closed <- TRUE

  invisible(output_file)
}

explore_bundle_pca_stdev <- function(bundle) {
  pca_path <- explore_bundle_pca_stdev_path(bundle)
  if (!file.exists(pca_path)) {
    return(numeric())
  }
  as.numeric(arrow::read_parquet(pca_path)$stdev)
}

explore_bundle_feature_record <- function(
  bundle,
  feature,
  assay = NULL,
  layer = NULL
) {
  features <- bundle$features
  assay <- assay %||% explore_bundle_default_assay(bundle)
  if (isTruthy(assay) && "assay" %in% colnames(features)) {
    features <- features[features$assay == assay, , drop = FALSE]
  }
  if (isTruthy(layer) && "layer" %in% colnames(features)) {
    features <- features[features$layer == layer, , drop = FALSE]
  }
  hit <- features[features$feature == feature, , drop = FALSE]
  if (!nrow(hit)) {
    stop("Feature not found in Explore bundle: ", feature)
  }
  hit[1, , drop = FALSE]
}

explore_read_expression_sparse_duckdb <- function(block_path, feature_idx) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sql_path <- duckdb_parquet_sql_path(block_path)
  DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT cell_idx, value FROM read_parquet('%s') WHERE feature_idx = %d ORDER BY cell_idx",
      sql_path,
      as.integer(feature_idx)
    )
  )
}

validate_scspotlight_explore_expression_feature_rows <- function(
  block_path,
  feature_idx,
  cell_count
) {
  if (!file.exists(block_path)) {
    stop("Expression block Parquet file not found: ", block_path)
  }
  feature_idx <- suppressWarnings(as.integer(feature_idx[[1]]))
  cell_count <- suppressWarnings(as.integer(cell_count[[1]]))
  if (is.na(feature_idx) || is.na(cell_count) || cell_count < 0L) {
    stop(
      "Explore expression validation requires valid feature and cell indexes."
    )
  }

  required_cols <- c("feature_idx", "cell_idx", "value")
  missing_cols <- setdiff(required_cols, explore_parquet_columns(block_path))
  if (length(missing_cols)) {
    stop(
      "Explore expression block is missing required column(s): ",
      paste(missing_cols, collapse = ", ")
    )
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sql_path <- duckdb_parquet_sql_path(block_path)
  feature_col <- duckdb_quote_identifier("feature_idx")
  cell_col <- duckdb_quote_identifier("cell_idx")
  value_col <- duckdb_quote_identifier("value")
  summary <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT COUNT(*) AS row_count, ",
      "COUNT(DISTINCT TRY_CAST(",
      cell_col,
      " AS BIGINT)) AS distinct_cell_count, ",
      "SUM(CASE WHEN TRY_CAST(",
      cell_col,
      " AS DOUBLE) IS NULL ",
      "OR TRY_CAST(",
      cell_col,
      " AS DOUBLE) <> FLOOR(TRY_CAST(",
      cell_col,
      " AS DOUBLE)) ",
      "OR TRY_CAST(",
      cell_col,
      " AS BIGINT) < 0 ",
      "OR TRY_CAST(",
      cell_col,
      " AS BIGINT) >= ",
      cell_count,
      " THEN 1 ELSE 0 END) AS invalid_cell_count, ",
      "SUM(CASE WHEN TRY_CAST(",
      value_col,
      " AS DOUBLE) IS NULL ",
      "OR NOT isfinite(TRY_CAST(",
      value_col,
      " AS DOUBLE)) THEN 1 ELSE 0 END) AS invalid_value_count ",
      "FROM read_parquet('",
      sql_path,
      "') ",
      "WHERE ",
      feature_col,
      " = ",
      feature_idx
    )
  )

  row_count <- as.numeric(summary$row_count[[1]])
  distinct_cell_count <- as.numeric(summary$distinct_cell_count[[1]])
  invalid_cell_count <- as.numeric(summary$invalid_cell_count[[1]])
  invalid_value_count <- as.numeric(summary$invalid_value_count[[1]])
  if (is.na(invalid_cell_count)) {
    invalid_cell_count <- 0
  }
  if (is.na(invalid_value_count)) {
    invalid_value_count <- 0
  }

  if (
    !is.finite(row_count) ||
      !is.finite(distinct_cell_count) ||
      invalid_cell_count != 0 ||
      invalid_value_count != 0 ||
      distinct_cell_count != row_count
  ) {
    stop(
      paste(
        "Explore expression block contains duplicate, invalid, or non-finite",
        "values for the requested feature."
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

explore_bundle_expression_query_plan <- function(
  bundle,
  feature,
  assay = NULL,
  layer = NULL
) {
  feature_record <- explore_bundle_feature_record(bundle, feature, assay, layer)
  block_path <- explore_bundle_expression_block_path(
    bundle,
    feature_record$block[[1]]
  )
  if (!file.exists(block_path)) {
    stop("Expression block not found in Explore bundle: ", block_path)
  }

  list(
    block_path = normalizePath(block_path, winslash = "/", mustWork = TRUE),
    feature_idx = as.integer(feature_record$feature_idx[[1]]),
    cell_count = explore_bundle_cell_count(bundle)
  )
}

explore_expr_vector_from_query <- function(
  block_path,
  feature_idx,
  cell_count
) {
  validate_scspotlight_explore_expression_feature_rows(
    block_path,
    feature_idx,
    cell_count
  )
  sparse <- explore_read_expression_sparse_duckdb(block_path, feature_idx)
  expr <- numeric(as.integer(cell_count))
  if (nrow(sparse)) {
    expr[as.integer(sparse$cell_idx) + 1L] <- as.numeric(sparse$value)
  }
  expr
}

explore_bundle_expr_vector <- function(
  bundle,
  feature,
  assay = NULL,
  layer = NULL
) {
  query_plan <- explore_bundle_expression_query_plan(
    bundle,
    feature,
    assay = assay,
    layer = layer
  )
  explore_expr_vector_from_query(
    block_path = query_plan$block_path,
    feature_idx = query_plan$feature_idx,
    cell_count = query_plan$cell_count
  )
}

extract_explore_query_expr_to_ipc <- function(
  block_path,
  feature_idx,
  cell_count,
  output_file,
  chunk_size = scspotlight_expression_transfer_chunk_size
) {
  if (!file.exists(block_path)) {
    stop("Expression block Parquet file not found: ", block_path)
  }
  cell_count <- as.integer(cell_count)
  if (is.na(cell_count) || cell_count < 0L) {
    stop("cell_count must be a non-negative integer")
  }
  chunk_size <- suppressWarnings(as.integer(chunk_size))
  if (is.na(chunk_size) || chunk_size < 1L) {
    chunk_size <- scspotlight_expression_transfer_chunk_size
  }
  validate_scspotlight_explore_expression_feature_rows(
    block_path,
    feature_idx,
    cell_count
  )

  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(output_file)) {
    file.remove(output_file)
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sql_path <- duckdb_parquet_sql_path(block_path)
  sparse_result <- DBI::dbSendQuery(
    con,
    sprintf(
      "SELECT cell_idx, value FROM read_parquet('%s') WHERE feature_idx = %d ORDER BY cell_idx",
      sql_path,
      as.integer(feature_idx)
    )
  )
  on.exit(try(DBI::dbClearResult(sparse_result), silent = TRUE), add = TRUE)

  sink <- arrow::FileOutputStream$create(output_file)
  writer <- arrow::RecordBatchStreamWriter$create(
    sink,
    arrow::schema(expr = arrow::float32())
  )
  writer_closed <- FALSE
  sink_closed <- FALSE
  on.exit(
    {
      if (!writer_closed) {
        try(writer$close(), silent = TRUE)
      }
      if (!sink_closed) {
        try(sink$close(), silent = TRUE)
      }
    },
    add = TRUE
  )

  sparse_chunk <- DBI::dbFetch(sparse_result, n = chunk_size)
  sparse_offset <- 1L
  chunk_start <- 0L

  while (chunk_start < cell_count) {
    chunk_len <- min(chunk_size, cell_count - chunk_start)
    expr_chunk <- numeric(chunk_len)
    chunk_end <- chunk_start + chunk_len - 1L

    repeat {
      while (
        sparse_offset > nrow(sparse_chunk) &&
          !DBI::dbHasCompleted(sparse_result)
      ) {
        sparse_chunk <- DBI::dbFetch(sparse_result, n = chunk_size)
        sparse_offset <- 1L
      }
      if (sparse_offset > nrow(sparse_chunk)) {
        break
      }

      cell_idx <- as.integer(sparse_chunk$cell_idx[[sparse_offset]])
      if (cell_idx > chunk_end) {
        break
      }
      if (cell_idx >= chunk_start) {
        expr_chunk[[cell_idx - chunk_start + 1L]] <- as.numeric(
          sparse_chunk$value[[sparse_offset]]
        )
      }
      sparse_offset <- sparse_offset + 1L
    }

    writer$write(
      arrow::arrow_table(
        expr = arrow::Array$create(expr_chunk, type = arrow::float32())
      )
    )
    chunk_start <- chunk_start + chunk_len
  }

  writer$close()
  writer_closed <- TRUE
  sink$close()
  sink_closed <- TRUE

  invisible(output_file)
}

extract_explore_bundle_expr_to_ipc <- function(
  bundle,
  feature,
  output_file,
  assay = NULL,
  layer = NULL
) {
  expr <- explore_bundle_expr_vector(
    bundle,
    feature,
    assay = assay,
    layer = layer
  )

  if (file.exists(output_file)) {
    file.remove(output_file)
  }

  write_ipc_stream(
    arrow_table(expr = Array$create(expr, type = float32())),
    output_file
  )

  invisible(output_file)
}
