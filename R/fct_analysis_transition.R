#' Normalize a server-owned Analysis Version value
#'
#' @noRd
normalize_analysis_version <- function(value) {
  if (
    length(value) != 1L ||
      !is.numeric(value) ||
      !is.finite(value) ||
      value < 0 ||
      value > .Machine$integer.max ||
      value != floor(value)
  ) {
    return(NULL)
  }

  as.integer(value)
}

#' Create the initial logical Analysis Version state
#'
#' @noRd
new_analysis_transition_state <- function(version = 0L, lineage_id = 1L) {
  version <- normalize_analysis_version(version)
  lineage_id <- normalize_analysis_version(lineage_id)
  if (is.null(version) || is.null(lineage_id) || lineage_id < 1L) {
    stop(
      "Analysis Version and lineage ID must be valid integer scalars.",
      call. = FALSE
    )
  }

  initial_record <- list(
    version = version,
    lineage_id = lineage_id,
    parent_version = NULL,
    operation = "initial",
    source_version = version
  )

  list(
    version = version,
    lineage_id = lineage_id,
    parent_version = NULL,
    operation = "initial",
    source_version = version,
    restore_source_version = NULL,
    lineage = list(initial_record)
  )
}

#' Normalize one browser-facing analysis context value
#'
#' @noRd
normalize_analysis_context_value <- function(value, default = "None") {
  if (is.null(value) || length(value) == 0L) {
    return(default)
  }
  if (
    length(value) != 1L ||
      (!is.character(value) && !is.factor(value)) ||
      is.na(value[[1]])
  ) {
    return(NULL)
  }

  value <- trimws(as.character(value[[1]]))
  if (!nzchar(value)) default else value
}

#' Normalize bounded browser-facing category levels
#'
#' @noRd
normalize_analysis_context_levels <- function(value, allow_empty = FALSE) {
  if (is.null(value) || length(value) == 0L) {
    return(if (isTRUE(allow_empty)) character(0) else NULL)
  }
  if (
    is.list(value) ||
      !is.atomic(value) ||
      (!is.character(value) && !is.factor(value))
  ) {
    return(NULL)
  }

  value <- trimws(as.character(value))
  if (
    any(is.na(value) | !nzchar(value) | value == "None") ||
      anyDuplicated(value)
  ) {
    return(NULL)
  }

  value
}

#' Resolve a bounded category selection using canonical Analysis metadata
#'
#' @noRd
resolve_analysis_category_cells <- function(object, category) {
  invalid <- function() list(reason_code = "invalid_category_context")
  if (!is.list(category)) {
    return(invalid())
  }

  group_col <- normalize_analysis_context_value(
    category$groupBy,
    default = NULL
  )
  split_col <- normalize_analysis_context_value(category$splitBy)
  group_levels <- normalize_analysis_context_levels(category$groupLevels)
  if (
    is.null(group_col) ||
      identical(group_col, "None") ||
      is.null(split_col) ||
      is.null(group_levels)
  ) {
    return(invalid())
  }

  split_levels <- normalize_analysis_context_levels(
    category$splitLevels,
    allow_empty = identical(split_col, "None")
  )
  if (
    is.null(split_levels) ||
      (identical(split_col, "None") && length(split_levels) > 0L)
  ) {
    return(invalid())
  }

  meta <- tryCatch(object[[]], error = function(...) NULL)
  object_cells <- colnames(object)
  if (
    !is.data.frame(meta) ||
      !length(object_cells) ||
      nrow(meta) != length(object_cells) ||
      !group_col %in% colnames(meta)
  ) {
    return(invalid())
  }

  meta_cells <- rownames(meta)
  if (
    is.null(meta_cells) ||
      length(meta_cells) != nrow(meta) ||
      !identical(as.character(meta_cells), as.character(object_cells))
  ) {
    return(invalid())
  }

  group_values <- as.character(meta[[group_col]])
  available_group_levels <- unique(group_values[!is.na(group_values)])
  if (any(!group_levels %in% available_group_levels)) {
    return(invalid())
  }
  matched <- !is.na(group_values) & group_values %in% group_levels

  if (!identical(split_col, "None")) {
    if (!split_col %in% colnames(meta) || !length(split_levels)) {
      return(invalid())
    }

    split_values <- as.character(meta[[split_col]])
    available_split_levels <- unique(split_values[!is.na(split_values)])
    if (any(!split_levels %in% available_split_levels)) {
      return(invalid())
    }
    matched <- matched & !is.na(split_values) & split_values %in% split_levels
  }

  selected_cells <- object_cells[matched]
  if (!length(selected_cells)) {
    return(list(reason_code = "no_valid_cells"))
  }

  list(reason_code = NULL, cells = selected_cells)
}

#' Apply one atomic Analysis Mutation
#'
#' @noRd
apply_analysis_transition <- function(
  current_state,
  intent,
  backend_root = NULL
) {
  if (!is.list(current_state) || !inherits(current_state$object, "Seurat")) {
    stop("Analysis Transition requires a Seurat Analysis.", call. = FALSE)
  }

  transition_state <- current_state$transition_state %||%
    new_analysis_transition_state()

  reject <- function(reason_code) {
    list(
      committed = FALSE,
      reason_code = reason_code,
      state = current_state,
      change_set = NULL
    )
  }

  if (!is.list(intent)) {
    return(reject("invalid_intent"))
  }

  cancelled <- intent$cancelled
  if (
    !is.null(cancelled) &&
      (length(cancelled) != 1L || !is.logical(cancelled) || is.na(cancelled))
  ) {
    return(reject("invalid_intent"))
  }
  if (isTRUE(cancelled)) {
    return(reject("cancelled"))
  }

  expected_version <- normalize_analysis_version(intent$expected_version)
  current_version <- normalize_analysis_version(transition_state$version)
  if (is.null(expected_version) || is.null(current_version)) {
    return(reject("invalid_intent"))
  }
  if (!identical(expected_version, current_version)) {
    return(reject("stale_analysis_version"))
  }

  expected_lineage_id <- normalize_analysis_version(intent$lineage_id)
  current_lineage_id <- normalize_analysis_version(transition_state$lineage_id)
  if (is.null(expected_lineage_id) || is.null(current_lineage_id)) {
    return(reject("invalid_intent"))
  }
  if (!identical(expected_lineage_id, current_lineage_id)) {
    return(reject("stale_analysis_lineage"))
  }
  if (current_version >= .Machine$integer.max) {
    return(reject("version_exhausted"))
  }

  operation <- intent$operation %||% ""
  if (
    length(operation) != 1L ||
      !is.character(operation) ||
      is.na(operation) ||
      !nzchar(operation)
  ) {
    return(reject("invalid_intent"))
  }
  operation <- tolower(operation)
  if (!operation %in% c("subset", "restore")) {
    return(reject("invalid_operation"))
  }

  object <- current_state$object
  original_object <- current_state$original_object %||% NULL
  object_cells <- colnames(object)

  if (identical(operation, "subset")) {
    if (!is.null(original_object)) {
      return(reject("already_subsetted"))
    }

    has_cells <- !is.null(intent$cells)
    has_category <- !is.null(intent$category)
    if (has_cells && has_category) {
      return(reject("invalid_intent"))
    }

    if (has_category) {
      category_result <- resolve_analysis_category_cells(
        object,
        intent$category
      )
      if (!is.null(category_result$reason_code)) {
        return(reject(category_result$reason_code))
      }
      valid_cells <- category_result$cells
    } else {
      raw_cells <- intent$cells %||% character(0)
      if (
        !is.character(raw_cells) || is.list(raw_cells) || !is.atomic(raw_cells)
      ) {
        return(reject("invalid_intent"))
      }
      if (
        !length(raw_cells) ||
          any(is.na(raw_cells) | !nzchar(raw_cells)) ||
          anyDuplicated(raw_cells) ||
          any(!raw_cells %in% object_cells)
      ) {
        return(reject("no_valid_cells"))
      }
      valid_cells <- object_cells[object_cells %in% raw_cells]
    }

    subset_object <- tryCatch(
      safe_subset_seurat_object(
        object,
        cells = valid_cells,
        backend_root = backend_root,
        input_label = "Selected cells"
      ),
      error = function(...) NULL
    )
    if (is.null(subset_object)) {
      return(reject("subset_failed"))
    }

    original_object <- tryCatch(
      {
        cleaned_original <- drop_dense_scale_data(object)
        assert_no_dense_scale_data(cleaned_original)
        cleaned_original
      },
      error = function(...) NULL
    )
    if (is.null(original_object)) {
      return(reject("original_state_failed"))
    }

    next_object <- subset_object
    next_original_object <- original_object
    source_version <- current_version
    restore_source_version <- current_version
  } else {
    if (is.null(original_object)) {
      return(reject("not_subsetted"))
    }

    restored_object <- tryCatch(
      {
        restored <- drop_dense_scale_data(original_object)
        assert_no_dense_scale_data(restored)
        restored
      },
      error = function(...) NULL
    )
    if (is.null(restored_object)) {
      return(reject("restore_failed"))
    }

    next_object <- restored_object
    next_original_object <- NULL
    source_version <- normalize_analysis_version(
      transition_state$restore_source_version %||%
        transition_state$source_version
    ) %||%
      current_version
    restore_source_version <- NULL
  }

  next_version <- current_version + 1L
  lineage_record <- list(
    version = next_version,
    lineage_id = current_lineage_id,
    parent_version = current_version,
    operation = operation,
    source_version = source_version
  )
  next_transition_state <- transition_state
  next_transition_state$version <- next_version
  next_transition_state$parent_version <- current_version
  next_transition_state$operation <- operation
  next_transition_state$source_version <- source_version
  next_transition_state$restore_source_version <- restore_source_version
  next_transition_state$lineage <- c(
    transition_state$lineage %||% list(),
    list(lineage_record)
  )

  list(
    committed = TRUE,
    reason_code = NULL,
    state = list(
      object = next_object,
      original_object = next_original_object,
      transition_state = next_transition_state
    ),
    change_set = list(
      lineage_id = current_lineage_id,
      analysis_version = next_version,
      parent_version = current_version,
      source_version = source_version,
      operation = operation,
      cell_population_changed = TRUE,
      metadata_changed = TRUE,
      reduction_changed = TRUE,
      expression_invalidated = TRUE,
      selection_reconciliation = "visible_cell_ids"
    )
  )
}

#' Create a Session-scoped Analysis Transition controller
#'
#' @noRd
new_analysis_transition_controller <- function(seuratObj) {
  if (!is.function(seuratObj)) {
    stop("Analysis Transition requires a reactive Seurat value.", call. = FALSE)
  }

  originalObject <- shiny::reactiveVal(NULL)
  lineage_id <- 1L
  transitionState <- shiny::reactiveVal(
    new_analysis_transition_state(lineage_id = lineage_id)
  )
  changeSet <- shiny::reactiveVal(NULL)
  mutation_in_progress <- FALSE
  reset_replaces_active_analysis <- FALSE

  current_state <- function() {
    list(
      object = shiny::isolate(seuratObj()),
      original_object = shiny::isolate(originalObject()),
      transition_state = shiny::isolate(transitionState())
    )
  }

  apply <- function(intent, backend_root = NULL) {
    if (isTRUE(mutation_in_progress)) {
      return(list(
        committed = FALSE,
        reason_code = "mutation_in_progress",
        state = current_state(),
        change_set = NULL
      ))
    }

    mutation_in_progress <<- TRUE
    on.exit(
      mutation_in_progress <<- FALSE,
      add = TRUE
    )

    state_snapshot <- current_state()
    result <- tryCatch(
      apply_analysis_transition(
        current_state = state_snapshot,
        intent = intent,
        backend_root = backend_root
      ),
      error = function(error) {
        message("Analysis Transition failed: ", conditionMessage(error))
        list(
          committed = FALSE,
          reason_code = "transition_failed",
          state = state_snapshot,
          change_set = NULL
        )
      }
    )

    if (isTRUE(result$committed)) {
      ## Calculate first, then publish all Session state from one owner.
      seuratObj(result$state$object)
      originalObject(result$state$original_object)
      transitionState(result$state$transition_state)
      changeSet(result$change_set)
    }

    result
  }

  reset <- function(object) {
    if (!inherits(object, "Seurat")) {
      stop(
        "Analysis Transition reset requires a Seurat Analysis.",
        call. = FALSE
      )
    }
    if (isTRUE(mutation_in_progress)) {
      return(invisible(FALSE))
    }

    if (lineage_id >= .Machine$integer.max) {
      stop("Analysis lineage counter is exhausted.", call. = FALSE)
    }
    reset_replaces_active_analysis <<- !is.null(shiny::isolate(seuratObj()))
    lineage_id <<- lineage_id + 1L
    seuratObj(object)
    originalObject(NULL)
    transitionState(new_analysis_transition_state(lineage_id = lineage_id))
    changeSet(NULL)
    invisible(TRUE)
  }

  list(
    apply = apply,
    reset = reset,
    state = current_state,
    change_set = function() shiny::isolate(changeSet()),
    version = function() shiny::isolate(transitionState()$version),
    lineage_id = function() shiny::isolate(transitionState()$lineage_id),
    intent_context = function() {
      shiny::isolate(list(
        expected_version = transitionState()$version,
        lineage_id = transitionState()$lineage_id
      ))
    },
    lineage_signal = function() transitionState()$lineage_id,
    reset_replaces_active_analysis = function() {
      isTRUE(reset_replaces_active_analysis)
    },
    is_subsetted = function() !is.null(shiny::isolate(originalObject())),
    is_busy = function() isTRUE(mutation_in_progress)
  )
}
