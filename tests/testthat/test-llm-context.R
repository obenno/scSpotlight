test_that("LLM context reports unloaded dataset without data payloads", {
  build_llm_analysis_context <- getFromNamespace(
    "build_llm_analysis_context",
    "scSpotlight"
  )

  context <- build_llm_analysis_context(
    object = NULL,
    running_mode = "analysis",
    context_version = "0:0:0"
  )

  expect_equal(context$dataset_loaded, FALSE)
  expect_equal(context$running_mode, "analysis")
  expect_equal(context$context_version, "0:0:0")
  expect_named(context, c("context_version", "running_mode", "dataset_loaded", "message"))
})

test_that("LLM vector truncation preserves total counts", {
  llm_truncate_vector <- getFromNamespace("llm_truncate_vector", "scSpotlight")

  out <- llm_truncate_vector(letters, max_items = 5L)

  expect_equal(out$values, letters[1:5])
  expect_equal(out$total, length(letters))
  expect_equal(out$truncated, TRUE)
})

test_that("LLM group summary is aggregated and capped", {
  llm_group_summary <- getFromNamespace("llm_group_summary", "scSpotlight")
  obj <- data.frame(cluster = c("a", "a", "b", "c", "c", "c"))

  testthat::local_mocked_bindings(
    is_scspotlight_explore_bundle = function(...) FALSE,
    get_backend_metadata = function(object, cols = NULL) {
      object[, cols, drop = FALSE]
    },
    .package = "scSpotlight"
  )

  summary <- llm_group_summary(obj, column = "cluster", top_n = 2L)

  expect_equal(summary$total_cells, 6L)
  expect_equal(summary$distinct_values, 3L)
  expect_equal(nrow(summary$rows), 2L)
  expect_equal(summary$rows$value, c("c", "a"))
  expect_equal(summary$rows$cells, c(3L, 2L))
  expect_equal(summary$truncated, TRUE)
})

test_that("LLM DEG summary filters and caps marker rows", {
  llm_deg_summary <- getFromNamespace("llm_deg_summary", "scSpotlight")
  markers <- data.frame(
    cluster = c("0", "0", "1"),
    gene = c("A", "B", "C"),
    avg_log2FC = c(2, 3, 5),
    p_val_adj = c(0.01, 0.2, 0.001),
    stringsAsFactors = FALSE
  )

  summary <- llm_deg_summary(
    markers,
    cluster = "0",
    top_n = 10L,
    p_adj_max = 0.05
  )

  expect_equal(summary$cluster, "0")
  expect_equal(summary$rows_returned, 1L)
  expect_equal(summary$rows$gene, "A")
  expect_equal(summary$ordered_by, "avg_log2FC")
})

test_that("LLM prompt truncates oversized context", {
  build_llm_prompt <- getFromNamespace("build_llm_prompt", "scSpotlight")

  prompt <- build_llm_prompt(
    user_input = "What is loaded?",
    context = list(big = paste(rep("x", 1000), collapse = "")),
    max_chars = 100L
  )

  expect_match(prompt, "truncated to 100 characters", fixed = TRUE)
  expect_match(prompt, "User question:", fixed = TRUE)
})
