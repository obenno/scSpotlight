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
