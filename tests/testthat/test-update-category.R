test_that("update category seeds default selection from sidebar metadata state", {
  scatter_indicator <- reactiveVal(0)

  testServer(
    mod_UpdateCategory_server,
    args = list(
      metaCols = reactive(NULL),
      metaSidebarState = reactive(list(
        cols = c("sample", "seurat_clusters"),
        groupBy = NULL,
        splitBy = NULL
      )),
      scatterUpdateIndicator = scatter_indicator
    ),
    {
      session$flushReact()
    }
  )

  expect_equal(isolate(scatter_indicator()), 1)
})

test_that("update category ignores no-op effective group and split selections", {
  scatter_indicator <- reactiveVal(0)
  sidebar_state <- reactiveVal(list(
    cols = c("sample", "seurat_clusters", "batch"),
    groupBy = "seurat_clusters",
    splitBy = "batch"
  ))

  testServer(
    mod_UpdateCategory_server,
    args = list(
      metaCols = reactive(NULL),
      metaSidebarState = reactive(sidebar_state()),
      scatterUpdateIndicator = scatter_indicator
    ),
    {
      session$flushReact()
      expect_equal(isolate(scatter_indicator()), 1)

      session$setInputs(group.by = "seurat_clusters", split.by = "batch")
      session$flushReact()
      expect_equal(isolate(scatter_indicator()), 1)
    }
  )
})

test_that("update category increments when batched sidebar split changes", {
  scatter_indicator <- reactiveVal(0)
  sidebar_state <- reactiveVal(list(
    cols = c("sample", "seurat_clusters", "batch", "donor"),
    groupBy = "seurat_clusters",
    splitBy = "batch"
  ))

  testServer(
    mod_UpdateCategory_server,
    args = list(
      metaCols = reactive(NULL),
      metaSidebarState = reactive(sidebar_state()),
      scatterUpdateIndicator = scatter_indicator
    ),
    {
      session$flushReact()
      expect_equal(isolate(scatter_indicator()), 1)

      sidebar_state(list(
        cols = c("sample", "seurat_clusters", "batch", "donor"),
        groupBy = "seurat_clusters",
        splitBy = "donor"
      ))
      session$flushReact()
      expect_equal(isolate(scatter_indicator()), 2)
    }
  )
})
