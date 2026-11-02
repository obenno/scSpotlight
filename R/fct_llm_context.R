#' LLM assistant context helpers
#'
#' @noRd

scspotlight_llm_context_max_chars <- 12000L
scspotlight_llm_context_max_vector_items <- 100L
scspotlight_llm_group_summary_max_rows <- 50L
scspotlight_llm_group_summary_max_distinct_values <- 50L
scspotlight_llm_group_summary_max_value_chars <- 64L
scspotlight_llm_group_summary_batch_size <- 4096L
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

llm_truncate_vector <- function(
  x,
  max_items = scspotlight_llm_context_max_vector_items
) {
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

llm_safe_context_values <- function(x, allowed = NULL) {
  values <- unique(as.character(x %||% character()))
  values <- values[!is.na(values) & nzchar(values)]
  if (!is.null(allowed)) {
    values <- intersect(values, as.character(allowed))
  }
  if (!length(values)) {
    return(character())
  }

  safe_shape <- grepl(
    "^[A-Za-z][A-Za-z0-9_.+-]{0,63}$",
    values,
    perl = TRUE
  )
  values[
    safe_shape &
      !llm_instruction_like_labels(values) &
      !llm_identifier_like_flags(values)
  ]
}

llm_safe_context_scalar <- function(x, allowed = NULL, default = NULL) {
  value <- llm_clean_scalar(x, default = default)
  if (!isTruthy(value) || identical(value, "None")) {
    return(default)
  }

  values <- llm_safe_context_values(value, allowed = allowed)
  if (!length(values)) {
    return(default)
  }
  values[[1]]
}

llm_safe_selected_features <- function(x, allowed) {
  values <- unique(as.character(x %||% character()))
  values <- values[!is.na(values) & nzchar(values)]
  values <- intersect(values, as.character(allowed %||% character()))
  values[llm_safe_feature_labels(values)]
}

llm_authorized_metadata_columns <- function(
  object,
  group_by = NULL,
  split_by = NULL
) {
  available <- tryCatch(
    get_backend_metadata_columns(object),
    error = function(...) character()
  )
  requested <- c(
    llm_clean_scalar(group_by, default = NULL),
    llm_clean_scalar(split_by, default = NULL)
  )
  requested <- requested[!is.na(requested) & requested != "None"]
  llm_safe_context_values(requested, allowed = available)
}

llm_view_filter_summary <- function(object, view_filter = NULL) {
  view_filter <- tryCatch(
    normalize_view_filter_spec(view_filter),
    error = function(...) NULL
  )
  if (is.null(view_filter)) {
    return(list(
      active = FALSE,
      visible_cells = tryCatch(
        get_backend_cell_count(object),
        error = function(...) NA_integer_
      )
    ))
  }

  list(
    active = TRUE,
    visible_cells = tryCatch(
      sum(view_filter_cell_mask(object, view_filter)),
      error = function(...) NA_integer_
    ),
    nFeature = view_filter$nFeature,
    percentMt = view_filter$percentMt
  )
}

llm_feature_count <- function(object, assay = NULL) {
  if (!isTruthy(object)) {
    return(NA_integer_)
  }

  if (is_scspotlight_explore_bundle(object)) {
    manifest_count <- suppressWarnings(as.integer(
      object$manifest$feature_count %||% NA_integer_
    ))
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
  view_filter = NULL,
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
  assays <- tryCatch(get_backend_assays(object), error = function(...) {
    character()
  })
  default_assay <- tryCatch(
    get_backend_default_assay(object),
    error = function(...) NULL
  )
  reductions <- tryCatch(
    get_backend_reduction_names(object),
    error = function(...) character()
  )
  cell_count <- tryCatch(get_backend_cell_count(object), error = function(...) {
    NA_integer_
  })
  assay <- llm_safe_context_scalar(assay, allowed = assays, default = NULL)
  default_assay <- llm_safe_context_scalar(
    default_assay,
    allowed = assays,
    default = NULL
  )
  selected_reduction <- llm_safe_context_scalar(
    selected_reduction,
    allowed = reductions,
    default = NULL
  )
  authorized_metadata_columns <- llm_authorized_metadata_columns(
    object,
    group_by = group_by,
    split_by = split_by
  )
  group_by <- llm_safe_context_scalar(
    group_by,
    allowed = authorized_metadata_columns,
    default = "None"
  )
  split_by <- llm_safe_context_scalar(
    split_by,
    allowed = authorized_metadata_columns,
    default = "None"
  )
  safe_features <- tryCatch(
    llm_safe_selected_features(
      selected_features,
      allowed = get_backend_features(object, assay = assay)
    ),
    error = function(...) character()
  )
  feature_count <- tryCatch(
    llm_feature_count(object, assay = assay),
    error = function(...) NA_integer_
  )
  view_filter_summary <- llm_view_filter_summary(object, view_filter)

  deg_available <- is.data.frame(deg_markers) && nrow(deg_markers) > 0L
  deg_columns <- if (deg_available) colnames(deg_markers) else character()
  deg_clusters <- if (deg_available && "cluster" %in% deg_columns) {
    llm_safe_category_values(
      deg_markers$cluster,
      column = "cluster",
      max_items = 30L
    )
  } else {
    list(
      values = character(),
      total = 0L,
      total_capped = FALSE,
      truncated = FALSE,
      values_included = TRUE,
      values_omitted_reason = NULL,
      limits = list(
        max_distinct_values = scspotlight_llm_group_summary_max_distinct_values,
        max_value_chars = scspotlight_llm_group_summary_max_value_chars
      )
    )
  }

  list(
    context_version = context_version %||% 0L,
    running_mode = running_mode,
    dataset_loaded = TRUE,
    dataset = list(
      backend = if (is_scspotlight_explore_bundle(object)) {
        "explore_bundle"
      } else {
        "seurat"
      },
      cells = cell_count,
      features = feature_count,
      assays = llm_truncate_vector(
        llm_safe_context_values(assays),
        max_items = 30L
      ),
      default_assay = default_assay,
      selected_assay = assay,
      reductions = llm_truncate_vector(
        llm_safe_context_values(reductions),
        max_items = 30L
      )
    ),
    current_view = list(
      reduction = selected_reduction,
      group_by = group_by,
      split_by = split_by,
      selected_features = llm_truncate_vector(safe_features, max_items = 40L),
      view_filter = view_filter_summary
    ),
    metadata = list(
      columns = llm_truncate_vector(
        authorized_metadata_columns,
        max_items = 2L
      )
    ),
    available_results = list(
      deg_available = deg_available,
      deg_rows = if (deg_available) nrow(deg_markers) else 0L,
      deg_columns = llm_truncate_vector(
        llm_safe_context_values(deg_columns),
        max_items = 30L
      ),
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

llm_escape_chat_response <- function(response) {
  htmltools::htmlEscape(
    paste(as.character(response %||% ""), collapse = "\n"),
    attribute = FALSE
  )
}

llm_text_only_chat_response <- function(response) {
  htmltools::tags$div(
    class = "scspotlight-llm-text-response",
    style = "white-space: pre-wrap;",
    htmltools::HTML(llm_escape_chat_response(response))
  )
}

truncate_llm_text <- function(
  text,
  max_chars = scspotlight_llm_context_max_chars
) {
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

build_llm_prompt <- function(
  user_input,
  context,
  max_chars = scspotlight_llm_context_max_chars
) {
  context_json <- truncate_llm_text(
    llm_json(context, pretty = TRUE),
    max_chars = max_chars
  )
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

llm_bounded_distinct_values <- function(
  values,
  max_distinct = scspotlight_llm_group_summary_max_distinct_values
) {
  max_distinct <- suppressWarnings(as.integer(max_distinct))
  if (is.na(max_distinct) || max_distinct < 1L) {
    max_distinct <- scspotlight_llm_group_summary_max_distinct_values
  }

  distinct <- character()
  has_missing <- FALSE
  chunk_size <- 4096L
  value_count <- length(values)
  if (value_count == 0L) {
    return(list(values = character(), count = 0L, capped = FALSE))
  }

  for (start in seq.int(1L, value_count, by = chunk_size)) {
    end <- min(start + chunk_size - 1L, value_count)
    chunk <- as.character(values[start:end])
    has_missing <- has_missing || anyNA(chunk)
    distinct <- unique(c(distinct, chunk[!is.na(chunk)]))
    distinct_count <- length(distinct) + as.integer(has_missing)

    if (distinct_count > max_distinct) {
      return(list(
        values = character(),
        count = max_distinct + 1L,
        capped = TRUE
      ))
    }
  }

  list(
    values = distinct,
    count = length(distinct) + as.integer(has_missing),
    capped = FALSE
  )
}

llm_identifier_like_column <- function(column) {
  column <- llm_clean_scalar(column, default = "")
  column <- gsub("([a-z0-9])([A-Z])", "\\1_\\2", column, perl = TRUE)
  column <- tolower(gsub("[^A-Za-z0-9]+", "_", column))

  column %in%
    c(
      "cell",
      "cells",
      "name",
      "names",
      "rowname",
      "rownames",
      "patient",
      "patients",
      "subject",
      "subjects",
      "participant",
      "participants",
      "donor",
      "donors",
      "sample",
      "samples"
    ) ||
    grepl(
      "(^|_)(id|ids|ident|identifier|identifiers|uuid|guid|barcode|barcodes|accession|accessions)($|_)",
      column,
      perl = TRUE
    )
}

llm_identifier_like_flags <- function(values) {
  values <- trimws(as.character(values %||% character()))
  present <- !is.na(values) & nzchar(values)
  flags <- rep(FALSE, length(values))
  if (!any(present)) {
    return(flags)
  }
  values <- values[present]

  uuid_like <- grepl(
    "^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    values,
    ignore.case = TRUE,
    perl = TRUE
  )
  prefixed_id <- grepl(
    "^(patient|subject|participant|donor|sample|cell|barcode|record|accession)[-_:]?[A-Za-z0-9.]+$",
    values,
    ignore.case = TRUE,
    perl = TRUE
  )
  compact_code <- grepl(
    "^[A-Za-z]{1,4}[-_:]?[0-9]{3,}$",
    values,
    perl = TRUE
  )
  numeric_id <- grepl("^[0-9]{8,}$", values, perl = TRUE)
  cell_barcode <- grepl(
    "^[ACGTN]{12,}[-_][0-9]+$",
    values,
    ignore.case = TRUE,
    perl = TRUE
  )
  email_like <- grepl(
    "^[^[:space:]@]+@[^[:space:]@]+\\.[^[:space:]@]+$",
    values,
    perl = TRUE
  )
  path_like <- grepl("^(~?/|[A-Za-z]:[\\\\/])", values, perl = TRUE)
  long_hex <- grepl("^[0-9a-f]{16,}$", values, ignore.case = TRUE, perl = TRUE)
  long_token <- nchar(values, type = "chars") >= 20L &
    grepl("^[A-Za-z0-9_.:-]+$", values, perl = TRUE) &
    grepl("[A-Za-z]", values, perl = TRUE) &
    grepl("[0-9]", values, perl = TRUE)

  flags[present] <-
    uuid_like |
    prefixed_id |
    compact_code |
    numeric_id |
    cell_barcode |
    email_like |
    path_like |
    long_hex |
    long_token
  flags
}

llm_identifier_like_values <- function(values) {
  any(llm_identifier_like_flags(values))
}

llm_instruction_like_labels <- function(values) {
  values <- trimws(as.character(values %||% character()))
  normalized_values <- gsub(
    "([[:lower:][:digit:]])([[:upper:]])",
    "\\1 \\2",
    values,
    perl = TRUE
  )
  normalized_values <- tolower(gsub("[^A-Za-z0-9]+", " ", normalized_values))
  compact_values <- gsub("[^a-z0-9]+", "", tolower(values))

  token_match <- grepl(
    "(^|[[:space:]])(ignore|disregard|forget|instruction(s)?|prompt(s)?|assistant|system|previous|override)([[:space:]]|$)",
    normalized_values,
    perl = TRUE
  )
  compact_compound_match <- grepl(
    paste0(
      "^(?:",
      "(?:ignore|disregard|forget)(?:all|any|the)?(?:previous|prior)?",
      "(?:instruction|instructions|prompt|prompts)|",
      "(?:system|assistant)(?:instruction|instructions|prompt|prompts)|",
      "override(?:instruction|instructions|prompt|prompts)",
      ")$"
    ),
    compact_values,
    perl = TRUE
  )
  token_match | compact_compound_match
}

llm_safe_category_labels <- function(
  values,
  max_value_chars = scspotlight_llm_group_summary_max_value_chars
) {
  values <- trimws(as.character(values %||% character()))
  word_count <- lengths(strsplit(values, "[[:space:]]+", perl = TRUE))
  safe <- !is.na(values) &
    nzchar(values) &
    nchar(values, type = "chars") <= max_value_chars &
    word_count <= 5L &
    grepl("^[A-Za-z0-9][A-Za-z0-9_. +()-]*$", values, perl = TRUE) &
    !llm_instruction_like_labels(values)
  safe[is.na(safe)] <- FALSE
  safe
}

llm_safe_category_values <- function(
  values,
  column = NULL,
  max_items = 30L,
  max_distinct = scspotlight_llm_group_summary_max_distinct_values,
  max_value_chars = scspotlight_llm_group_summary_max_value_chars
) {
  max_items <- suppressWarnings(as.integer(max_items))
  if (is.na(max_items) || max_items < 1L) {
    max_items <- 30L
  }
  max_value_chars <- suppressWarnings(as.integer(max_value_chars))
  if (is.na(max_value_chars) || max_value_chars < 1L) {
    max_value_chars <- scspotlight_llm_group_summary_max_value_chars
  }

  values <- as.character(values %||% character())
  values <- values[!is.na(values) & nzchar(values)]
  distinct <- llm_bounded_distinct_values(values, max_distinct = max_distinct)
  distinct_values <- distinct$values

  omitted_reason <- NULL
  if (isTruthy(column) && llm_identifier_like_column(column)) {
    omitted_reason <- "identifier_like_column"
  } else if (isTRUE(distinct$capped)) {
    omitted_reason <- "too_many_distinct_values"
  } else if (any(nchar(distinct_values, type = "chars") > max_value_chars)) {
    omitted_reason <- "value_length_limit"
  } else if (any(!llm_safe_category_labels(distinct_values, max_value_chars))) {
    omitted_reason <- "unsafe_category_labels"
  } else if (llm_identifier_like_values(distinct_values)) {
    omitted_reason <- "identifier_like_values"
  }

  values_included <- is.null(omitted_reason)
  list(
    values = if (values_included) {
      utils::head(distinct_values, max_items)
    } else {
      character()
    },
    total = distinct$count,
    total_capped = isTRUE(distinct$capped),
    truncated = isTRUE(distinct$capped) || distinct$count > max_items,
    values_included = values_included,
    values_omitted_reason = omitted_reason,
    limits = list(
      max_distinct_values = as.integer(max_distinct),
      max_value_chars = max_value_chars
    )
  )
}

llm_safe_feature_labels <- function(
  values,
  max_value_chars = scspotlight_llm_group_summary_max_value_chars
) {
  values <- as.character(values %||% character())
  safe <- !is.na(values) &
    nzchar(values) &
    nchar(values, type = "chars") <= max_value_chars &
    grepl(
      "^[A-Za-z0-9][A-Za-z0-9_.+-]*(/[A-Za-z0-9][A-Za-z0-9_.+-]*)*$",
      values,
      perl = TRUE
    ) &
    !llm_instruction_like_labels(values)
  safe[is.na(safe)] <- FALSE
  safe
}

apply_llm_group_summary_boundary <- function(
  column,
  total_cells,
  distinct_values,
  distinct_values_capped,
  rows,
  top_n
) {
  limits <- list(
    max_rows = scspotlight_llm_group_summary_max_rows,
    max_distinct_values = scspotlight_llm_group_summary_max_distinct_values,
    max_value_chars = scspotlight_llm_group_summary_max_value_chars
  )
  values <- if (is.data.frame(rows) && "value" %in% colnames(rows)) {
    rows$value
  } else {
    character()
  }

  omitted_reason <- NULL
  if (llm_identifier_like_column(column)) {
    omitted_reason <- "identifier_like_column"
  } else if (
    isTRUE(distinct_values_capped) ||
      distinct_values > scspotlight_llm_group_summary_max_distinct_values
  ) {
    omitted_reason <- "too_many_distinct_values"
  } else if (
    any(
      nchar(as.character(values), type = "chars") >
        scspotlight_llm_group_summary_max_value_chars,
      na.rm = TRUE
    )
  ) {
    omitted_reason <- "value_length_limit"
  } else if (any(!llm_safe_category_labels(values))) {
    omitted_reason <- "unsafe_category_labels"
  } else if (llm_identifier_like_values(values)) {
    omitted_reason <- "identifier_like_values"
  }

  values_included <- is.null(omitted_reason)
  visible_rows <- if (values_included) {
    compact_llm_table(rows, max_rows = top_n)
  } else {
    data.frame()
  }

  list(
    column = column,
    total_cells = total_cells,
    distinct_values = distinct_values,
    distinct_values_capped = isTRUE(distinct_values_capped),
    values_included = values_included,
    values_omitted_reason = omitted_reason,
    limits = limits,
    rows = visible_rows,
    truncated = isTRUE(distinct_values_capped) || nrow(rows) > top_n
  )
}

llm_group_summary <- function(object, column, top_n = 20L, view_filter = NULL) {
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

  view_filter <- tryCatch(
    normalize_view_filter_spec(view_filter),
    error = function(...) NULL
  )
  if (is_scspotlight_explore_bundle(object)) {
    if (!is.null(view_filter)) {
      return(list(
        error = "View-filtered metadata summaries are unavailable in Explore Mode."
      ))
    }
    return(explore_bundle_metadata_group_summary(object, column, top_n = top_n))
  }

  meta <- tryCatch(
    get_backend_metadata(object, cols = column),
    error = function(...) NULL
  )
  if (!is.data.frame(meta) || !column %in% colnames(meta)) {
    return(list(error = paste0("Metadata column is not available: ", column)))
  }

  if (!is.null(view_filter)) {
    mask <- tryCatch(
      view_filter_cell_mask(object, view_filter),
      error = function(...) NULL
    )
    if (is.null(mask) || length(mask) != nrow(meta)) {
      return(list(error = "View-filtered metadata summary is unavailable."))
    }
    meta <- meta[mask, , drop = FALSE]
  }
  values <- meta[[column]]
  distinct <- llm_bounded_distinct_values(values)

  if (isTRUE(distinct$capped)) {
    return(apply_llm_group_summary_boundary(
      column = column,
      total_cells = length(values),
      distinct_values = distinct$count,
      distinct_values_capped = TRUE,
      rows = data.frame(),
      top_n = top_n
    ))
  }

  values <- as.character(values)
  counts <- sort(table(values, useNA = "ifany"), decreasing = TRUE)
  total <- sum(counts)
  out <- data.frame(
    value = names(counts),
    cells = as.integer(counts),
    fraction = as.numeric(counts) / total,
    stringsAsFactors = FALSE
  )

  apply_llm_group_summary_boundary(
    column = column,
    total_cells = total,
    distinct_values = distinct$count,
    distinct_values_capped = FALSE,
    rows = out,
    top_n = top_n
  )
}

llm_bounded_metadata_value_counts <- function(
  next_batch,
  column,
  max_distinct = scspotlight_llm_group_summary_max_distinct_values
) {
  max_distinct <- suppressWarnings(as.integer(max_distinct))
  if (is.na(max_distinct) || max_distinct < 1L) {
    max_distinct <- scspotlight_llm_group_summary_max_distinct_values
  }

  counts <- numeric()
  missing_count <- 0
  repeat {
    batch <- next_batch()
    if (is.null(batch)) {
      break
    }

    values <- as.character(batch[[column]])
    if (!length(values)) {
      next
    }
    missing <- is.na(values)
    missing_count <- missing_count + sum(missing)
    present_values <- values[!missing]
    batch_distinct <- unique(present_values)
    new_values <- setdiff(batch_distinct, names(counts))
    if (
      length(counts) + length(new_values) + as.integer(missing_count > 0) >
        max_distinct
    ) {
      return(list(
        rows = data.frame(),
        distinct_values = max_distinct + 1L,
        distinct_values_capped = TRUE
      ))
    }

    if (length(present_values)) {
      batch_counts <- table(present_values)
      count_names <- names(batch_counts)
      existing_counts <- counts[count_names]
      existing_counts[is.na(existing_counts)] <- 0
      counts[count_names] <- existing_counts + as.numeric(batch_counts)
    }
  }

  values <- names(counts)
  cell_counts <- as.numeric(counts)
  if (missing_count > 0) {
    values <- c(values, NA_character_)
    cell_counts <- c(cell_counts, missing_count)
  }

  list(
    rows = data.frame(
      value = values,
      cells = cell_counts,
      stringsAsFactors = FALSE
    ),
    distinct_values = length(values),
    distinct_values_capped = FALSE
  )
}

explore_bundle_metadata_group_summary <- function(bundle, column, top_n = 20L) {
  tryCatch(
    {
      metadata_path <- explore_bundle_metadata_path(bundle)
      if (!file.exists(metadata_path)) {
        return(list(error = "Explore bundle metadata.parquet is missing."))
      }

      cols <- explore_parquet_columns(metadata_path)
      if (!column %in% cols) {
        return(list(
          error = paste0("Metadata column is not available: ", column)
        ))
      }

      scanner <- arrow::open_dataset(
        metadata_path,
        format = "parquet"
      )$NewScan()
      scanner$Project(column)
      scanner$BatchSize(scspotlight_llm_group_summary_batch_size)
      reader <- arrow::as_record_batch_reader(scanner$Finish())
      on.exit(try(reader$Close(), silent = TRUE), add = TRUE)

      summary <- llm_bounded_metadata_value_counts(
        next_batch = function() reader$read_next_batch(),
        column = column
      )
      total <- explore_bundle_cell_count(bundle)
      out <- summary$rows
      if (nrow(out)) {
        out <- out[order(out$cells, decreasing = TRUE), , drop = FALSE]
      }
      out$fraction <- out$cells / total

      apply_llm_group_summary_boundary(
        column = column,
        total_cells = total,
        distinct_values = summary$distinct_values,
        distinct_values_capped = summary$distinct_values_capped,
        rows = out,
        top_n = top_n
      )
    },
    error = function(...) {
      list(error = "Metadata summary is unavailable for this Explore dataset.")
    }
  )
}

llm_deg_summary <- function(
  markers,
  cluster = NULL,
  top_n = 10L,
  p_adj_max = NULL
) {
  if (!is.data.frame(markers) || nrow(markers) == 0L) {
    return(list(
      error = "DEG analysis has not been run or produced no markers."
    ))
  }
  required <- c("gene", "cluster")
  missing <- setdiff(required, colnames(markers))
  if (length(missing)) {
    return(list(
      error = paste(
        "DEG results are missing columns:",
        paste(missing, collapse = ", ")
      )
    ))
  }

  fc_col <- if ("avg_log2FC" %in% colnames(markers)) {
    "avg_log2FC"
  } else if ("avg_logFC" %in% colnames(markers)) {
    "avg_logFC"
  } else {
    NULL
  }
  if (is.null(fc_col)) {
    return(list(
      error = "DEG results do not include a supported log fold-change column."
    ))
  }

  cluster_values <- llm_safe_category_values(
    markers$cluster,
    column = "cluster",
    max_items = scspotlight_llm_group_summary_max_distinct_values
  )
  if (!isTRUE(cluster_values$values_included)) {
    return(list(
      error = paste(
        "DEG results are grouped by metadata labels that are not available",
        "to the assistant under the category safety limits."
      ),
      cluster_values = cluster_values
    ))
  }

  cluster <- llm_clean_scalar(cluster, default = NULL)
  if (isTruthy(cluster) && !cluster %in% cluster_values$values) {
    return(list(error = "The requested DEG group is unavailable."))
  }

  top_n <- suppressWarnings(as.integer(top_n))
  if (is.na(top_n) || top_n < 1L) {
    top_n <- 10L
  }
  top_n <- min(top_n, scspotlight_llm_deg_summary_max_rows)
  top_n <- as.integer(top_n)

  filtered <- markers
  if (isTruthy(cluster)) {
    filtered <- filtered[
      as.character(filtered$cluster) == cluster,
      ,
      drop = FALSE
    ]
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

  safe_feature_labels <- llm_safe_feature_labels(filtered$gene)
  unsafe_feature_labels_omitted <- any(!safe_feature_labels)
  unsafe_feature_labels_omitted_count <- sum(!safe_feature_labels)
  filtered <- filtered[safe_feature_labels, , drop = FALSE]
  if (!nrow(filtered)) {
    return(list(
      error = "No safe DEG rows match the requested filters.",
      unsafe_feature_labels_omitted = unsafe_feature_labels_omitted,
      unsafe_feature_labels_omitted_count = unsafe_feature_labels_omitted_count
    ))
  }

  filtered <- filtered[
    order(filtered[[fc_col]], decreasing = TRUE),
    ,
    drop = FALSE
  ]
  keep_cols <- intersect(
    c(
      "cluster",
      "gene",
      "p_val",
      "p_val_adj",
      "avg_log2FC",
      "avg_logFC",
      "pct.1",
      "pct.2"
    ),
    colnames(filtered)
  )
  out <- compact_llm_table(
    filtered[, keep_cols, drop = FALSE],
    max_rows = top_n
  )

  list(
    cluster = cluster %||% "all",
    rows_returned = nrow(out),
    total_matching_rows = nrow(filtered),
    ordered_by = fc_col,
    rows = out,
    truncated = nrow(filtered) > top_n,
    unsafe_feature_labels_omitted = unsafe_feature_labels_omitted,
    unsafe_feature_labels_omitted_count = unsafe_feature_labels_omitted_count
  )
}

create_llm_chat <- function(config, system_prompt = llm_base_system_prompt) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop(
      "The optional package 'ellmer' is required for the LLM assistant.",
      call. = FALSE
    )
  }

  provider <- normalize_llm_provider(config$provider %||% "ollama")
  model <- config$model %||% "llama3.2"
  if (
    !is.character(model) ||
      length(model) != 1L ||
      is.na(model) ||
      !nzchar(model)
  ) {
    stop("llmModel must be a non-empty string", call. = FALSE)
  }

  if (identical(provider, "ollama")) {
    return(ellmer::chat_ollama(
      system_prompt = system_prompt,
      model = model,
      base_url = config$base_url %||%
        Sys.getenv("OLLAMA_BASE_URL", "http://localhost:11434"),
      echo = "none"
    ))
  }

  stop("Unsupported LLM provider: ", provider, call. = FALSE)
}
