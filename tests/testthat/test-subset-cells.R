make_subset_counts <- function(n_genes = 6L, n_cells = 5L) {
  counts <- matrix(
    seq_len(n_genes * n_cells),
    nrow = n_genes,
    dimnames = list(
      paste0("Gene", seq_len(n_genes)),
      paste0("Cell", seq_len(n_cells))
    )
  )
  Matrix::Matrix(counts, sparse = TRUE)
}

make_subset_object <- function() {
  object <- Seurat::CreateSeuratObject(counts = make_subset_counts())
  object$cluster <- factor(c("A", "B", "A", "B", "A"))
  object <- Seurat::NormalizeData(object, verbose = FALSE)
  SeuratObject::LayerData(
    object,
    assay = SeuratObject::DefaultAssay(object),
    layer = "scale.data"
  ) <- matrix(
    0,
    nrow = length(SeuratObject::Features(object)),
    ncol = ncol(object),
    dimnames = list(SeuratObject::Features(object), colnames(object))
  )
  object
}

make_analysis_transition <- function(seurat_value) {
  getFromNamespace(
    "new_analysis_transition_controller",
    "scSpotlight"
  )(seurat_value)
}

make_subset_selection_intent <- function(
  cells = character(0),
  expected_version = 0L,
  lineage_id = 1L,
  reason_code = NULL
) {
  intent <- list(
    cells = cells,
    expected_version = expected_version,
    lineage_id = lineage_id
  )
  if (!is.null(reason_code)) {
    intent$reason_code <- reason_code
  }
  intent
}

expect_subset_indicator_values <- function(gene, meta, reduction, expected) {
  expect_identical(shiny::isolate(gene()), expected)
  expect_identical(shiny::isolate(meta()), expected)
  expect_identical(shiny::isolate(reduction()), expected)
}

test_that("subset switch rejects empty, invalid, and stale selections without mutation", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  selection_intent <- shiny::reactiveVal(make_subset_selection_intent())
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)

  testServer(
    mod_SubsetCells_server,
    args = list(
      seuratObj = seurat_value,
      selectionIntent = selection_intent,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator,
      analysisTransition = analysis_transition
    ),
    {
      session$setInputs(subsetData = TRUE)
      expect_identical(colnames(seurat_value()), colnames(object))
      expect_null(analysis_transition$state()$original_object)
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        0
      )

      selection_intent(make_subset_selection_intent(
        c("missing-cell", "also-missing")
      ))
      session$setInputs(subsetData = FALSE)
      session$setInputs(subsetData = TRUE)
      expect_identical(colnames(seurat_value()), colnames(object))
      expect_null(analysis_transition$state()$original_object)
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        0
      )

      selection_intent(make_subset_selection_intent(
        c("Cell1", "missing-cell")
      ))
      session$setInputs(subsetData = FALSE)
      session$setInputs(subsetData = TRUE)
      expect_identical(colnames(seurat_value()), colnames(object))
      expect_null(analysis_transition$state()$original_object)
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        0
      )
    }
  )
})

test_that("valid subset stores the original once, preserves cell order, drops scale.data, and refreshes indicators", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  selection_intent <- shiny::reactiveVal(make_subset_selection_intent(
    c("Cell5", "Cell2")
  ))
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)
  assert_no_dense_scale_data <- getFromNamespace(
    "assert_no_dense_scale_data",
    "scSpotlight"
  )

  testServer(
    mod_SubsetCells_server,
    args = list(
      seuratObj = seurat_value,
      selectionIntent = selection_intent,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator,
      analysisTransition = analysis_transition
    ),
    {
      session$setInputs(subsetData = TRUE)
      expect_identical(colnames(seurat_value()), c("Cell2", "Cell5"))
      expect_identical(
        colnames(analysis_transition$state()$original_object),
        colnames(object)
      )
      expect_silent(assert_no_dense_scale_data(seurat_value()))
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        1
      )

      stored_original <- analysis_transition$state()$original_object
      selection_intent(make_subset_selection_intent(c("Cell2")))
      session$setInputs(subsetData = TRUE)
      expect_identical(
        analysis_transition$state()$original_object,
        stored_original
      )
      expect_identical(colnames(seurat_value()), c("Cell2", "Cell5"))
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        1
      )
    }
  )
})

test_that("restore replaces subset state with original, clears backup, and repeated off toggles are safe", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  selection_intent <- shiny::reactiveVal(make_subset_selection_intent(
    c("Cell1", "Cell3")
  ))
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)

  testServer(
    mod_SubsetCells_server,
    args = list(
      seuratObj = seurat_value,
      selectionIntent = selection_intent,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator,
      analysisTransition = analysis_transition
    ),
    {
      session$setInputs(subsetData = TRUE)
      expect_identical(colnames(seurat_value()), c("Cell1", "Cell3"))
      expect_false(is.null(analysis_transition$state()$original_object))
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        1
      )

      session$setInputs(subsetData = FALSE)
      expect_identical(colnames(seurat_value()), colnames(object))
      expect_null(analysis_transition$state()$original_object)
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        2
      )

      session$setInputs(subsetData = FALSE)
      expect_identical(colnames(seurat_value()), colnames(object))
      expect_null(analysis_transition$state()$original_object)
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        2
      )
    }
  )
})

test_that("browser Cell ID payloads flow through assignment module into subset selection", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  metadata_version <- shiny::reactiveVal(0L)
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)

  testServer(
    mod_AssignCellCluster_server,
    args = list(
      seuratObj = seurat_value,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator,
      analysisTransition = analysis_transition,
      currentMetadataVersion = metadata_version
    ),
    {
      session$setInputs(selectedCellsPayload = list(
        cells = c("Cell3", "Cell1"),
        metaVersion = 0L,
        analysisVersion = 0L,
        analysisLineageId = 1L
      ))
      session$setInputs("subsetCells-subsetData" = TRUE)

      expect_identical(
        colnames(shiny::isolate(seurat_value())),
        c("Cell1", "Cell3")
      )
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        1
      )
    }
  )
})

test_that("Analysis plot messages carry the current selection identity", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  reduction_processed <- shiny::reactiveVal(TRUE)
  meta_processed <- shiny::reactiveVal(TRUE)
  plot_refresh_indicator <- shiny::reactiveVal(0)
  scatter_update_indicator <- shiny::reactiveVal(0)
  plot_message <- NULL

  testthat::local_mocked_bindings(
    reglScatter_plot = function(plotMetaData, session) {
      plot_message <<- plotMetaData
    },
    .package = "scSpotlight"
  )

  testServer(
    mod_mainClusterPlot_server,
    args = list(
      reductionProcessed = reduction_processed,
      metaProcessed = meta_processed,
      plotRefreshIndicator = plot_refresh_indicator,
      scatterUpdateIndicator = scatter_update_indicator,
      group.by = shiny::reactive("cluster"),
      split.by = shiny::reactive("None"),
      moduleScore = shiny::reactive(FALSE),
      analysisTransition = analysis_transition
    ),
    {
      session$flushReact()
      plot_refresh_indicator(1)
      session$flushReact()
    }
  )

  expect_identical(
    plot_message,
    list(
      group_by = "cluster",
      split_by = NULL,
      moduleScore = FALSE,
      analysisVersion = 0L,
      analysisLineageId = 1L
    )
  )
})

test_that("browser Cell ID payloads reject empty, mixed, and stale selections", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  metadata_version <- shiny::reactiveVal(0L)
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)

  testServer(
    mod_AssignCellCluster_server,
    args = list(
      seuratObj = seurat_value,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator,
      analysisTransition = analysis_transition,
      currentMetadataVersion = metadata_version
    ),
    {
      session$setInputs(selectedCellsPayload = list(
        cells = character(0),
        metaVersion = 0L,
        analysisVersion = 0L,
        analysisLineageId = 1L
      ))
      session$setInputs("subsetCells-subsetData" = TRUE)
      expect_identical(colnames(shiny::isolate(seurat_value())), colnames(object))
      expect_identical(analysis_transition$version(), 0L)

      session$setInputs("subsetCells-subsetData" = FALSE)
      session$setInputs(selectedCellsPayload = list(
        cells = c("Cell1", "missing-cell"),
        metaVersion = 0L,
        analysisVersion = 0L,
        analysisLineageId = 1L
      ))
      session$setInputs("subsetCells-subsetData" = TRUE)
      expect_identical(colnames(shiny::isolate(seurat_value())), colnames(object))
      expect_identical(analysis_transition$version(), 0L)

      session$setInputs("subsetCells-subsetData" = FALSE)
      session$setInputs(selectedCellsPayload = list(
        cells = "Cell1",
        metaVersion = 0L,
        analysisVersion = 1L,
        analysisLineageId = 1L
      ))
      session$setInputs("subsetCells-subsetData" = TRUE)
      expect_identical(colnames(shiny::isolate(seurat_value())), colnames(object))
      expect_identical(analysis_transition$version(), 0L)

      session$setInputs("subsetCells-subsetData" = FALSE)
      session$setInputs(selectedCellsPayload = list(
        cells = "Cell1",
        metaVersion = 1L,
        analysisVersion = 0L,
        analysisLineageId = 1L
      ))
      session$setInputs("subsetCells-subsetData" = TRUE)
      expect_identical(colnames(shiny::isolate(seurat_value())), colnames(object))
      expect_identical(analysis_transition$version(), 0L)

      session$setInputs("subsetCells-subsetData" = FALSE)
      session$setInputs(selectedCellsPayload = list(
        cells = "Cell1",
        metaVersion = 0L,
        analysisVersion = 0L,
        analysisLineageId = 2L
      ))
      session$setInputs("subsetCells-subsetData" = TRUE)
      expect_identical(colnames(shiny::isolate(seurat_value())), colnames(object))
      expect_identical(analysis_transition$version(), 0L)
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        0
      )
    }
  )
})

test_that("subset module threads the session backend root into BPCells-safe subset backing", {
  subset_source <- paste(
    readLines(
      testthat::test_path("..", "..", "R", "mod_SubsetCells.R"),
      warn = FALSE
    ),
    collapse = "\n"
  )
  app_source <- paste(
    readLines(
      testthat::test_path("..", "..", "R", "app_server.R"),
      warn = FALSE
    ),
    collapse = "\n"
  )

  expect_true(
    grepl(
      "mod_SubsetCells_server\\s*<-\\s*function[\\s\\S]*analysisTransition",
      subset_source,
      perl = TRUE
    ),
    info = "subset module should accept a session cleanup-root backend path"
  )
  expect_true(
    grepl(
      "analysisTransition\\$apply[\\s\\S]*backend_root",
      subset_source,
      perl = TRUE
    ),
    info = "Analysis Transition must receive the subset backend root"
  )
  expect_match(
    subset_source,
    "message = list(invalidateVersion = geneUpdateIndicator())",
    fixed = TRUE
  )
  expect_true(
    grepl(
      "mod_AssignCellCluster_server[\\s\\S]*backend_root\\s*=\\s*session\\$userData\\$backendDir",
      app_source,
      perl = TRUE
    ),
    info = "app_server should thread session$userData$backendDir into the assignment/subset module tree"
  )
  expect_true(
    grepl(
      "new_analysis_transition_controller\\(seuratObj\\)",
      app_source,
      perl = TRUE
    )
  )
  expect_match(
    app_source,
    "analysisTransition = analysisTransition",
    fixed = TRUE
  )
})

test_that("Analysis Transition publishes monotonic versions for Subset and Restore", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)

  subset_result <- analysis_transition$apply(
    intent = list(
      operation = "subset",
      expected_version = 0L,
      lineage_id = 1L,
      cells = c("Cell5", "Cell2")
    )
  )

  expect_true(subset_result$committed)
  expect_identical(analysis_transition$version(), 1L)
  expect_identical(
    analysis_transition$state()$transition_state$parent_version,
    0L
  )
  expect_identical(
    analysis_transition$state()$transition_state$lineage[[2]]$operation,
    "subset"
  )
  expect_identical(
    colnames(shiny::isolate(seurat_value())),
    c("Cell2", "Cell5")
  )
  expect_identical(
    colnames(analysis_transition$state()$original_object),
    colnames(object)
  )
  expect_identical(
    analysis_transition$change_set()[c(
      "lineage_id",
      "analysis_version",
      "parent_version",
      "operation",
      "cell_population_changed",
      "metadata_changed",
      "reduction_changed",
      "expression_invalidated"
    )],
    list(
      lineage_id = 1L,
      analysis_version = 1L,
      parent_version = 0L,
      operation = "subset",
      cell_population_changed = TRUE,
      metadata_changed = TRUE,
      reduction_changed = TRUE,
      expression_invalidated = TRUE
    )
  )

  restore_result <- analysis_transition$apply(
    intent = list(
      operation = "restore",
      expected_version = 1L,
      lineage_id = 1L
    )
  )

  expect_true(restore_result$committed)
  expect_identical(analysis_transition$version(), 2L)
  expect_identical(
    analysis_transition$state()$transition_state$parent_version,
    1L
  )
  expect_identical(
    analysis_transition$state()$transition_state$lineage[[3]]$source_version,
    0L
  )
  expect_identical(
    colnames(shiny::isolate(seurat_value())),
    colnames(object)
  )
  expect_null(analysis_transition$state()$original_object)
  expect_identical(
    analysis_transition$change_set()[c(
      "lineage_id",
      "analysis_version",
      "parent_version",
      "source_version",
      "operation"
    )],
    list(
      lineage_id = 1L,
      analysis_version = 2L,
      parent_version = 1L,
      source_version = 0L,
      operation = "restore"
    )
  )
})

test_that("stale and empty Analysis Mutations preserve the current state", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  empty_transition <- make_analysis_transition(shiny::reactiveVal(object))

  empty_result <- empty_transition$apply(
    intent = list(
      operation = "subset",
      expected_version = 0L,
      lineage_id = 1L,
      cells = character(0)
    )
  )
  expect_false(empty_result$committed)
  expect_identical(empty_result$reason_code, "no_valid_cells")
  expect_identical(empty_transition$version(), 0L)

  mixed_transition <- make_analysis_transition(shiny::reactiveVal(object))
  mixed_result <- mixed_transition$apply(
    intent = list(
      operation = "subset",
      expected_version = 0L,
      lineage_id = 1L,
      cells = c("Cell1", "missing-cell")
    )
  )
  expect_false(mixed_result$committed)
  expect_identical(mixed_result$reason_code, "no_valid_cells")
  expect_identical(mixed_transition$version(), 0L)

  subset_result <- analysis_transition$apply(
    intent = list(
      operation = "subset",
      expected_version = 0L,
      lineage_id = 1L,
      cells = "Cell1"
    )
  )
  expect_true(subset_result$committed)

  stale_result <- analysis_transition$apply(
    intent = list(
      operation = "restore",
      expected_version = 0L,
      lineage_id = 1L
    )
  )
  expect_false(stale_result$committed)
  expect_identical(stale_result$reason_code, "stale_analysis_version")
  expect_identical(analysis_transition$state()$transition_state$version, 1L)
})

test_that("invalid and cancelled Mutation Intents publish no version", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)

  cancelled_result <- analysis_transition$apply(
    intent = list(
      operation = "subset",
      expected_version = 0L,
      lineage_id = 1L,
      cancelled = TRUE,
      cells = "Cell1"
    )
  )
  expect_false(cancelled_result$committed)
  expect_identical(cancelled_result$reason_code, "cancelled")
  expect_identical(analysis_transition$state()$transition_state$version, 0L)

  fractional_version_result <- analysis_transition$apply(
    intent = list(
      operation = "subset",
      expected_version = 0.5,
      lineage_id = 1L,
      cells = "Cell1"
    )
  )
  expect_false(fractional_version_result$committed)
  expect_identical(fractional_version_result$reason_code, "invalid_intent")
  expect_identical(analysis_transition$state()$transition_state$version, 0L)

  invalid_operation_result <- analysis_transition$apply(
    intent = list(
      operation = "recluster",
      expected_version = 0L,
      lineage_id = 1L
    )
  )
  expect_false(invalid_operation_result$committed)
  expect_identical(invalid_operation_result$reason_code, "invalid_operation")
  expect_identical(analysis_transition$state()$transition_state$version, 0L)
})

test_that("Analysis Version validation rejects overflow values", {
  expect_error(
    getFromNamespace(
      "new_analysis_transition_state",
      "scSpotlight"
    )(version = .Machine$integer.max + 1),
    "valid integer scalars",
    fixed = TRUE
  )

  object <- make_subset_object()
  transition <- getFromNamespace("apply_analysis_transition", "scSpotlight")
  result <- transition(
    current_state = list(
      object = object,
      original_object = NULL,
      transition_state = getFromNamespace(
        "new_analysis_transition_state",
        "scSpotlight"
      )(version = .Machine$integer.max)
    ),
    intent = list(
      operation = "restore",
      expected_version = .Machine$integer.max,
      lineage_id = 1L
    )
  )
  expect_false(result$committed)
  expect_identical(result$reason_code, "version_exhausted")
})

test_that("the Analysis Transition controller owns commits and Change-sets", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)

  result <- analysis_transition$apply(
    intent = list(
      operation = "subset",
      expected_version = 0L,
      lineage_id = 1L,
      cells = c("Cell1", "Cell3")
    )
  )

  expect_true(result$committed)
  expect_identical(
    analysis_transition$state()$transition_state$version,
    1L
  )
  expect_identical(
    colnames(shiny::isolate(seurat_value())),
    c("Cell1", "Cell3")
  )
  expect_identical(
    analysis_transition$change_set()[c(
      "analysis_version",
      "parent_version",
      "operation"
    )],
    list(
      analysis_version = 1L,
      parent_version = 0L,
      operation = "subset"
    )
  )
  expect_false(analysis_transition$is_busy())

  stale_result <- analysis_transition$apply(
    intent = list(
      operation = "restore",
      expected_version = 0L,
      lineage_id = 1L
    )
  )
  expect_false(stale_result$committed)
  expect_identical(stale_result$reason_code, "stale_analysis_version")
  expect_identical(analysis_transition$state()$transition_state$version, 1L)
  expect_identical(
    analysis_transition$change_set()$analysis_version,
    1L
  )

  captured_lineage_id <- analysis_transition$lineage_id()
  old_lineage_result <- list(
    operation = "subset",
    expected_version = 0L,
    lineage_id = captured_lineage_id,
    cells = "Cell1"
  )
  analysis_transition$reset(object)
  expect_identical(analysis_transition$state()$transition_state$version, 0L)
  expect_null(analysis_transition$state()$original_object)
  expect_null(analysis_transition$change_set())

  stale_lineage_result <- analysis_transition$apply(old_lineage_result)
  expect_false(stale_lineage_result$committed)
  expect_identical(stale_lineage_result$reason_code, "stale_analysis_lineage")
  expect_identical(analysis_transition$state()$transition_state$version, 0L)
})

test_that("failed transitions preserve the active Analysis and publish no version", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)

  testthat::local_mocked_bindings(
    safe_subset_seurat_object = function(...) {
      stop("forced subset failure", call. = FALSE)
    },
    .package = "scSpotlight"
  )

  result <- analysis_transition$apply(
    intent = list(
      operation = "subset",
      expected_version = 0L,
      lineage_id = 1L,
      cells = "Cell1"
    )
  )

  expect_false(result$committed)
  expect_identical(result$reason_code, "subset_failed")
  expect_identical(
    colnames(shiny::isolate(seurat_value())),
    colnames(object)
  )
  expect_identical(analysis_transition$state()$transition_state$version, 0L)
  expect_null(analysis_transition$state()$original_object)
  expect_null(analysis_transition$change_set())
  expect_false(analysis_transition$is_busy())
})

test_that("the Analysis Transition controller rejects re-entrant mutations", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  nested_result <- NULL
  reset_result <- NULL

  testthat::local_mocked_bindings(
    apply_analysis_transition = function(
      current_state,
      intent,
      backend_root = NULL
    ) {
      reset_result <<- analysis_transition$reset(object)
      nested_result <<- analysis_transition$apply(
        intent = list(
          operation = "subset",
          expected_version = 0L,
          lineage_id = 1L,
          cells = "Cell1"
        )
      )
      list(
        committed = FALSE,
        reason_code = "transition_failed",
        state = current_state,
        change_set = NULL
      )
    },
    .package = "scSpotlight"
  )

  result <- analysis_transition$apply(
    intent = list(
      operation = "subset",
      expected_version = 0L,
      lineage_id = 1L,
      cells = "Cell1"
    )
  )

  expect_false(result$committed)
  expect_identical(result$reason_code, "transition_failed")
  expect_false(is.null(nested_result))
  expect_identical(nested_result$reason_code, "mutation_in_progress")
  expect_false(reset_result)
  expect_identical(analysis_transition$state()$transition_state$version, 0L)
})

test_that("Subset module commits the server-owned Analysis Transition state", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  selection_intent <- shiny::reactiveVal(make_subset_selection_intent(
    c("Cell1", "Cell3")
  ))
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)

  testServer(
    mod_SubsetCells_server,
    args = list(
      seuratObj = seurat_value,
      selectionIntent = selection_intent,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator,
      analysisTransition = analysis_transition
    ),
    {
      session$setInputs(subsetData = TRUE)
      expect_identical(
        analysis_transition$state()$transition_state$version,
        1L
      )
      expect_identical(
        analysis_transition$state()$transition_state$parent_version,
        0L
      )

      session$setInputs(subsetData = FALSE)
      expect_identical(
        analysis_transition$state()$transition_state$version,
        2L
      )
      expect_identical(
        analysis_transition$state()$transition_state$parent_version,
        1L
      )
      expect_identical(
        analysis_transition$change_set()[c(
          "lineage_id",
          "analysis_version",
          "parent_version",
          "source_version",
          "operation"
        )],
        list(
          lineage_id = 1L,
          analysis_version = 2L,
          parent_version = 1L,
          source_version = 0L,
          operation = "restore"
        )
      )
    }
  )
})

test_that("Subset adapter rejects non-boolean switch values without mutation", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  selection_intent <- shiny::reactiveVal(make_subset_selection_intent(
    c("Cell1", "Cell3")
  ))
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)

  testServer(
    mod_SubsetCells_server,
    args = list(
      seuratObj = seurat_value,
      selectionIntent = selection_intent,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator,
      analysisTransition = analysis_transition
    ),
    {
      session$setInputs(subsetData = "unexpected")
      expect_identical(analysis_transition$version(), 0L)
      expect_identical(
        colnames(shiny::isolate(seurat_value())),
        colnames(object)
      )
      expect_subset_indicator_values(
        gene_indicator,
        meta_indicator,
        reduction_indicator,
        0
      )
    }
  )
})

test_that("Subset adapter rejects a queued toggle across an Analysis reset", {
  object <- make_subset_object()
  seurat_value <- shiny::reactiveVal(object)
  analysis_transition <- make_analysis_transition(seurat_value)
  selection_intent <- shiny::reactiveVal(make_subset_selection_intent(
    c("Cell1", "Cell3")
  ))
  gene_indicator <- shiny::reactiveVal(0)
  meta_indicator <- shiny::reactiveVal(0)
  reduction_indicator <- shiny::reactiveVal(0)

  testServer(
    mod_SubsetCells_server,
    args = list(
      seuratObj = seurat_value,
      selectionIntent = selection_intent,
      geneUpdateIndicator = gene_indicator,
      metaUpdateIndicator = meta_indicator,
      reductionUpdateIndicator = reduction_indicator,
      analysisTransition = analysis_transition
    ),
    {
      analysis_transition$reset(object)
      session$flushReact()

      session$setInputs(subsetData = TRUE)
      expect_identical(analysis_transition$version(), 0L)
      expect_identical(
        colnames(shiny::isolate(seurat_value())),
        colnames(object)
      )

      session$setInputs(subsetData = FALSE)
      selection_intent(make_subset_selection_intent(
        c("Cell1", "Cell3"),
        lineage_id = analysis_transition$lineage_id()
      ))
      session$setInputs(subsetData = TRUE)
      expect_identical(analysis_transition$version(), 1L)
      expect_identical(
        colnames(shiny::isolate(seurat_value())),
        c("Cell1", "Cell3")
      )
    }
  )
})
