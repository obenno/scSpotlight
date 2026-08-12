make_assignment_safety_object <- function() {
  counts <- Matrix::Matrix(
    c(
      1, 0, 2, 0,
      0, 3, 0, 4,
      5, 0, 6, 0
    ),
    nrow = 3,
    sparse = TRUE
  )
  rownames(counts) <- c("GeneA", "GeneB", "GeneC")
  colnames(counts) <- paste0("Cell", seq_len(ncol(counts)))

  object <- Seurat::CreateSeuratObject(counts = counts)
  object$cluster <- factor(c("A", "A", "B", "B"))
  object$batch <- c("batch1", "batch2", "batch1", "batch2")
  object
}

assignment_context <- function() {
  list(groupBy = "cluster", splitBy = "batch", metaVersion = 7L)
}

selected_cells_intent <- function(...) {
  utils::modifyList(
    list(
      type = "selected_cells",
      newMetaCol = "assigned_cluster",
      assignAs = "T cell",
      selectedCells = c("Cell1", "Cell3"),
      context = assignment_context()
    ),
    list(...)
  )
}

category_context_intent <- function(...) {
  utils::modifyList(
    list(
      type = "category_context",
      newMetaCol = "assigned_cluster",
      assignAs = "T cell",
      category = list(
        groupBy = "cluster",
        groupLevels = "A",
        splitBy = "batch",
        splitLevels = "batch1"
      ),
      context = assignment_context()
    ),
    list(...)
  )
}

test_that("selected-cell assignment intent validates bounded payloads", {
  skip_if_not_installed("Seurat")
  object <- make_assignment_safety_object()
  validate_assignment_intent <- getFromNamespace(
    "validate_assignment_intent",
    "scSpotlight"
  )

  result <- validate_assignment_intent(
    object,
    selected_cells_intent(),
    current_context = assignment_context()
  )

  expect_equal(result$type, "selected_cells")
  expect_equal(result$cells, c("Cell1", "Cell3"))
  expect_equal(result$colName, "assigned_cluster")
  expect_equal(result$colValue, "T cell")
  expect_null(result$metadataVector)
})

test_that("assignment intent rejects unsafe selected-cell payloads", {
  skip_if_not_installed("Seurat")
  object <- make_assignment_safety_object()
  validate_assignment_intent <- getFromNamespace(
    "validate_assignment_intent",
    "scSpotlight"
  )

  expect_error(
    validate_assignment_intent(
      object,
      selected_cells_intent(newMetaCol = "bad column"),
      current_context = assignment_context()
    ),
    "metadata column"
  )
  expect_error(
    validate_assignment_intent(
      object,
      selected_cells_intent(assignAs = ""),
      current_context = assignment_context()
    ),
    "assignment value"
  )
  expect_error(
    validate_assignment_intent(
      object,
      selected_cells_intent(
        context = list(groupBy = "other", splitBy = "batch", metaVersion = 7L)
      ),
      current_context = assignment_context()
    ),
    "stale"
  )
  expect_error(
    validate_assignment_intent(
      object,
      selected_cells_intent(selectedCells = c("Cell1", "Cell1")),
      current_context = assignment_context()
    ),
    "duplicate"
  )
  expect_error(
    validate_assignment_intent(
      object,
      selected_cells_intent(selectedCells = c("Cell1", "MissingCell")),
      current_context = assignment_context()
    ),
    "unknown"
  )
  expect_error(
    validate_assignment_intent(
      object,
      selected_cells_intent(metadataVector = rep("T cell", ncol(object))),
      current_context = assignment_context()
    ),
    "full metadata vector"
  )
})

test_that("category assignment intent resolves cells from current Seurat metadata", {
  skip_if_not_installed("Seurat")
  object <- make_assignment_safety_object()
  validate_assignment_intent <- getFromNamespace(
    "validate_assignment_intent",
    "scSpotlight"
  )

  result <- validate_assignment_intent(
    object,
    category_context_intent(),
    current_context = assignment_context()
  )

  expect_equal(result$type, "category_context")
  expect_equal(result$cells, "Cell1")
  expect_equal(result$colName, "assigned_cluster")
  expect_equal(result$colValue, "T cell")
  expect_null(result$metadataVector)
})

test_that("category assignment intent rejects stale or incomplete context", {
  skip_if_not_installed("Seurat")
  object <- make_assignment_safety_object()
  validate_assignment_intent <- getFromNamespace(
    "validate_assignment_intent",
    "scSpotlight"
  )
  missing_split_intent <- category_context_intent()
  missing_split_intent$category$splitBy <- NULL
  missing_split_intent$category$splitLevels <- NULL

  expect_error(
    validate_assignment_intent(
      object,
      missing_split_intent,
      current_context = assignment_context()
    ),
    "split"
  )
  expect_error(
    validate_assignment_intent(
      object,
      category_context_intent(
        category = list(
          groupBy = "missing_column",
          groupLevels = "A",
          splitBy = "batch",
          splitLevels = "batch1"
        )
      ),
      current_context = assignment_context()
    ),
    "metadata column"
  )
  expect_error(
    validate_assignment_intent(
      object,
      category_context_intent(
        category = list(
          groupBy = "cluster",
          groupLevels = "Z",
          splitBy = "batch",
          splitLevels = "batch1"
        )
      ),
      current_context = assignment_context()
    ),
    "no cells"
  )
  expect_error(
    validate_assignment_intent(
      object,
      category_context_intent(
        context = list(groupBy = "cluster", splitBy = "batch", metaVersion = 6L)
      ),
      current_context = assignment_context()
    ),
    "stale"
  )
})

test_that("assignment validation rejects browser-trusted current-version fallback", {
  skip_if_not_installed("Seurat")
  object <- make_assignment_safety_object()
  validate_assignment_intent <- getFromNamespace(
    "validate_assignment_intent",
    "scSpotlight"
  )

  expect_error(
    validate_assignment_intent(
      object,
      selected_cells_intent(),
      current_context = list(groupBy = "cluster", splitBy = "batch", metaVersion = NULL)
    ),
    "stale assignment context",
    fixed = TRUE
  )

  app_source <- paste(
    readLines(scspotlight_test_source_path("R", "app_server.R"), warn = FALSE),
    collapse = "\n"
  )
  expect_false(
    grepl(
      "metaVersion\\s*=\\s*\\(metaSidebarState\\(\\)[\\s\\S]*assignmentIntent\\$context[\\s\\S]*metaVersion",
      app_source,
      perl = TRUE
    ),
    info = "server current metadata version must never fall back to the browser-submitted assignment context"
  )
})
