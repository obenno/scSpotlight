#' LLM assistant context helpers
#'
#' @noRd

scspotlight_llm_context_max_chars <- 12000L
scspotlight_llm_context_max_vector_items <- 100L
scspotlight_llm_group_summary_max_rows <- 50L
scspotlight_llm_deg_summary_max_rows <- 50L

llm_base_system_prompt <- paste(
  "You are scSpotlight Assistant, a cautious single-cell RNA-seq analysis helper.",
  "Answer only from app-provided context and tool results.",
  "Do not invent genes, clusters, p-values, labels, or biological claims.",
  "If data is missing, say which analysis must be run.",
  "Never request API keys, local paths, or private data.",
  "Never ask for or emit full cell-level data.",
  sep = "\n"
)

llm_is_enabled <- function() {
  isTRUE(golem::get_golem_options("enableLLM"))
}

llm_provider_config <- function() {
  list(
    provider = golem::get_golem_options("llmProvider") %||% "ollama",
    model = golem::get_golem_options("llmModel") %||% "llama3.2",
    base_url = golem::get_golem_options("llmBaseUrl") %||%
      Sys.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
  )
}

llm_clean_scalar <- function(x, default = NULL) {
  if (is.null(x) || length(x) == 0L || is.na(x[[1]])) {
    return(default)
  }
  as.character(x[[1]])
}

llm_truncate_vector <- function(x, max_items = scspotlight_llm_context_max_vector_items) {
  x <- unique(as.character(x %||% character()))
  x <- x[!is.na(x) & nzchar(x)]
  max_items <- suppressWarnings(as.integer(max_items))
  if (is.na(max_items) || max_items < 1L) {
    max_items <- scspotlight_llm_context_max_vector_items
  }

  list(
    values = utils::head(x, max_items),
    total = length(x),
    truncated = length(x) > max_items
  )
}

llm_feature_count <- function(object, assay = NULL) {
  if (!isTruthy(object)) {
    return(NA_integer_)
  }

  if (is_scspotlight_explore_bundle(object)) {
    manifest_count <- suppressWarnings(as.integer(object$manifest$feature_count %||% NA_integer_))
    if (!is.na(manifest_count)) {
      return(manifest_count)
    }
  }

  length(get_backend_features(object, assay = assay))
}

build_llm_analysis_context <- function(
  object,
  running_mode,
  selected_assay = NULL,
  selected_reduction = NULL,
  group_by = NULL,
  split_by = NULL,
  selected_features = NULL,
  meta_cols = NULL,
  deg_markers = NULL,
  p_adj_cutoff = NULL,
  context_version = NULL
) {
  if (!isTruthy(object)) {
    return(list(
      context_version = context_version %||% 0L,
      running_mode = running_mode,
      dataset_loaded = FALSE,
      message = "No dataset is currently loaded."
    ))
  }

  assay <- llm_clean_scalar(selected_assay, default = NULL)
  assays <- tryCatch(get_backend_assays(object), error = function(...) character())
  default_assay <- tryCatch(get_backend_default_assay(object), error = function(...) NULL)
  reductions <- tryCatch(get_backend_reduction_names(object), error = function(...) character())
  cell_count <- tryCatch(get_backend_cell_count(object), error = function(...) NA_integer_)
  feature_count <- tryCatch(llm_feature_count(object, assay = assay), error = function(...) NA_integer_)

  deg_available <- is.data.frame(deg_markers) && nrow(deg_markers) > 0L
  deg_columns <- if (deg_available) colnames(deg_markers) else character()
  deg_clusters <- if (deg_available && "cluster" %in% deg_columns) {
    llm_truncate_vector(deg_markers$cluster, max_items = 30L)
  } else {
    list(values = character(), total = 0L, truncated = FALSE)
  }

  list(
    context_version = context_version %||% 0L,
    running_mode = running_mode,
    dataset_loaded = TRUE,
    dataset = list(
      backend = if (is_scspotlight_explore_bundle(object)) "explore_bundle" else "seurat",
      cells = cell_count,
      features = feature_count,
      assays = llm_truncate_vector(assays, max_items = 30L),
      default_assay = default_assay,
      selected_assay = assay,
      reductions = llm_truncate_vector(reductions, max_items = 30L)
    ),
    current_view = list(
      reduction = llm_clean_scalar(selected_reduction, default = NULL),
      group_by = llm_clean_scalar(group_by, default = "None"),
      split_by = llm_clean_scalar(split_by, default = "None"),
      selected_features = llm_truncate_vector(selected_features, max_items = 40L)
    ),
    metadata = list(
      columns = llm_truncate_vector(meta_cols, max_items = 100L)
    ),
    available_results = list(
      deg_available = deg_available,
      deg_rows = if (deg_available) nrow(deg_markers) else 0L,
      deg_columns = llm_truncate_vector(deg_columns, max_items = 30L),
      deg_clusters = deg_clusters,
      deg_p_adj_cutoff = p_adj_cutoff
    )
  )
}

llm_json <- function(x, pretty = FALSE) {
  jsonlite::toJSON(
    x,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    dataframe = "rows",
    pretty = pretty
  ) |>
    as.character()
}

truncate_llm_text <- function(text, max_chars = scspotlight_llm_context_max_chars) {
  max_chars <- suppressWarnings(as.integer(max_chars))
  if (is.na(max_chars) || max_chars < 1L) {
    max_chars <- scspotlight_llm_context_max_chars
  }
  if (nchar(text, type = "chars") <= max_chars) {
    return(text)
  }

  paste0(
    substr(text, 1L, max_chars),
    "\n... [truncated to ",
    max_chars,
    " characters by scSpotlight]"
  )
}

build_llm_prompt <- function(user_input, context, max_chars = scspotlight_llm_context_max_chars) {
  context_json <- truncate_llm_text(llm_json(context, pretty = TRUE), max_chars = max_chars)
  paste(
    "Current scSpotlight app context follows. Use it for orientation only;",
    "call registered tools when you need detailed summaries.",
    "This context supersedes any earlier app context in the conversation.",
    "",
    "```json",
    context_json,
    "```",
    "",
    "User question:",
    as.character(user_input %||% ""),
    sep = "\n"
  )
}

compact_llm_table <- function(d, max_rows = 20L, digits = 4L) {
  if (!is.data.frame(d) || nrow(d) == 0L) {
    return(data.frame())
  }
  max_rows <- suppressWarnings(as.integer(max_rows))
  if (is.na(max_rows) || max_rows < 1L) {
    max_rows <- 20L
  }

  out <- utils::head(d, max_rows)
  for (col in colnames(out)) {
    if (is.numeric(out[[col]])) {
      out[[col]] <- signif(out[[col]], digits)
    }
  }
  rownames(out) <- NULL
  out
}

llm_group_summary <- function(object, column, top_n = 20L) {
  if (!isTruthy(object)) {
    return(list(error = "No dataset is currently loaded."))
  }
  column <- llm_clean_scalar(column)
  if (!isTruthy(column) || identical(column, "None")) {
    return(list(error = "A metadata column is required."))
  }

  top_n <- suppressWarnings(as.integer(top_n))
  if (is.na(top_n) || top_n < 1L) {
    top_n <- 20L
  }
  top_n <- min(top_n, scspotlight_llm_group_summary_max_rows)
  top_n <- as.integer(top_n)

  if (is_scspotlight_explore_bundle(object)) {
    return(explore_bundle_metadata_group_summary(object, column, top_n = top_n))
  }

  available_cols <- tryCatch(colnames(get_backend_metadata(object, cols = column)), error = function(...) character())
  if (!column %in% available_cols) {
    return(list(error = paste0("Metadata column is not available: ", column)))
  }

  meta <- get_backend_metadata(object, cols = column)
  values <- meta[[column]]
  values <- ifelse(is.na(values), NA_character_, as.character(values))
  counts <- sort(table(values, useNA = "ifany"), decreasing = TRUE)
  total <- sum(counts)
  out <- data.frame(
    value = names(counts),
    cells = as.integer(counts),
    fraction = as.numeric(counts) / total,
    stringsAsFactors = FALSE
  )

  list(
    column = column,
    total_cells = total,
    distinct_values = nrow(out),
    rows = compact_llm_table(out, max_rows = top_n),
    truncated = nrow(out) > top_n
  )
}

explore_bundle_metadata_group_summary <- function(bundle, column, top_n = 20L) {
  metadata_path <- explore_bundle_metadata_path(bundle)
  if (!file.exists(metadata_path)) {
    return(list(error = "Explore bundle metadata.parquet is missing."))
  }

  cols <- explore_parquet_columns(metadata_path)
  if (!column %in% cols) {
    return(list(error = paste0("Metadata column is not available: ", column)))
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  sql_path <- duckdb_parquet_sql_path(metadata_path)
  value_expr <- duckdb_quote_identifier(column)
  limit_n <- as.integer(top_n) + 1L
  query <- sprintf(
    paste(
      "SELECT CAST(%s AS VARCHAR) AS value, COUNT(*) AS cells",
      "FROM read_parquet('%s')",
      "GROUP BY %s",
      "ORDER BY cells DESC",
      "LIMIT %d"
    ),
    value_expr,
    sql_path,
    value_expr,
    limit_n
  )
  out <- DBI::dbGetQuery(con, query)
  total <- explore_bundle_cell_count(bundle)
  visible <- utils::head(out, top_n)
  visible$fraction <- visible$cells / total

  list(
    column = column,
    total_cells = total,
    distinct_values = NA_integer_,
    rows = compact_llm_table(visible, max_rows = top_n),
    truncated = nrow(out) > top_n
  )
}

llm_deg_summary <- function(markers, cluster = NULL, top_n = 10L, p_adj_max = NULL) {
  if (!is.data.frame(markers) || nrow(markers) == 0L) {
    return(list(error = "DEG analysis has not been run or produced no markers."))
  }
  required <- c("gene", "cluster")
  missing <- setdiff(required, colnames(markers))
  if (length(missing)) {
    return(list(error = paste("DEG results are missing columns:", paste(missing, collapse = ", "))))
  }

  fc_col <- if ("avg_log2FC" %in% colnames(markers)) {
    "avg_log2FC"
  } else if ("avg_logFC" %in% colnames(markers)) {
    "avg_logFC"
  } else {
    NULL
  }
  if (is.null(fc_col)) {
    return(list(error = "DEG results do not include a supported log fold-change column."))
  }

  top_n <- suppressWarnings(as.integer(top_n))
  if (is.na(top_n) || top_n < 1L) {
    top_n <- 10L
  }
  top_n <- min(top_n, scspotlight_llm_deg_summary_max_rows)
  top_n <- as.integer(top_n)

  filtered <- markers
  if (isTruthy(cluster)) {
    cluster <- as.character(cluster)
    filtered <- filtered[as.character(filtered$cluster) == cluster, , drop = FALSE]
  }
  if (isTruthy(p_adj_max) && "p_val_adj" %in% colnames(filtered)) {
    p_adj_max <- suppressWarnings(as.numeric(p_adj_max))
    if (!is.na(p_adj_max)) {
      keep <- !is.na(filtered$p_val_adj) & filtered$p_val_adj <= p_adj_max
      filtered <- filtered[keep, , drop = FALSE]
    }
  }
  if (!nrow(filtered)) {
    return(list(error = "No DEG rows match the requested filters."))
  }

  filtered <- filtered[order(filtered[[fc_col]], decreasing = TRUE), , drop = FALSE]
  keep_cols <- intersect(
    c("cluster", "gene", "p_val", "p_val_adj", "avg_log2FC", "avg_logFC", "pct.1", "pct.2"),
    colnames(filtered)
  )
  out <- compact_llm_table(filtered[, keep_cols, drop = FALSE], max_rows = top_n)

  list(
    cluster = cluster %||% "all",
    rows_returned = nrow(out),
    total_matching_rows = nrow(filtered),
    ordered_by = fc_col,
    rows = out,
    truncated = nrow(filtered) > top_n
  )
}

create_llm_chat <- function(config, system_prompt = llm_base_system_prompt) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("The optional package 'ellmer' is required for the LLM assistant.", call. = FALSE)
  }

  provider <- normalize_llm_provider(config$provider %||% "ollama")
  model <- config$model %||% "llama3.2"
  if (!is.character(model) || length(model) != 1L || is.na(model) || !nzchar(model)) {
    stop("llmModel must be a non-empty string", call. = FALSE)
  }

  if (identical(provider, "ollama")) {
    return(ellmer::chat_ollama(
      system_prompt = system_prompt,
      model = model,
      base_url = config$base_url %||% Sys.getenv("OLLAMA_BASE_URL", "http://localhost:11434"),
      echo = "none"
    ))
  }

  stop("Unsupported LLM provider: ", provider, call. = FALSE)
}
