test_that("running modes normalize canonical names and legacy aliases", {
  normalize_running_mode <- getFromNamespace(
    "normalize_running_mode",
    "scSpotlight"
  )

  expect_equal(normalize_running_mode("analysis"), "analysis")
  expect_equal(normalize_running_mode("explore"), "explore")
  expect_equal(normalize_running_mode("processing"), "analysis")
  expect_equal(normalize_running_mode("viewer"), "explore")
  expect_equal(normalize_running_mode(" Analysis "), "analysis")
})

test_that("running modes reject invalid values", {
  normalize_running_mode <- getFromNamespace(
    "normalize_running_mode",
    "scSpotlight"
  )

  expect_error(
    normalize_running_mode("browse"),
    "runningMode must be one of 'analysis' or 'explore'",
    fixed = TRUE
  )
  expect_error(
    normalize_running_mode(c("analysis", "explore")),
    "runningMode must be one of 'analysis' or 'explore'",
    fixed = TRUE
  )
})

test_that("Explore Mode server does not register Analysis-only modules", {
  skip_if_not_installed("shiny")

  app_server <- getFromNamespace("app_server", "scSpotlight")
  calls <- character()
  work_dir <- tempfile("app_server_explore_")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
  withr::local_dir(work_dir)

  testthat::local_mocked_bindings(
    mod_dataInput_server = function(...) {
      list(selectedAssay = shiny::reactive("RNA"))
    },
    mod_ClusterSetting_server = function(...) {
      calls <<- c(calls, "cluster")
      NULL
    },
    mod_FilterCell_server = function(...) {
      calls <<- c(calls, "filter")
      NULL
    },
    mod_CellCycling_server = function(...) {
      calls <<- c(calls, "cell_cycle")
      NULL
    },
    mod_UpdateMetaData_server = function(...) NULL,
    mod_UpdateReduction_server = function(...) NULL,
    mod_UpdateCategory_server = function(...) {
      list(
        group.by = shiny::reactive("None"),
        split.by = shiny::reactive("None")
      )
    },
    mod_DEG_Window_server = function(...) {
      calls <<- c(calls, "deg")
      NULL
    },
    mod_InputFeature_server = function(...) {
      list(moduleScore = shiny::reactive(NULL))
    },
    mod_mainClusterPlot_server = function(...) NULL,
    mod_AssignCellCluster_server = function(...) {
      calls <<- c(calls, "rename")
      NULL
    },
    mod_Download_server = function(...) {
      calls <<- c(calls, "download")
      NULL
    },
    mod_DataConversion_server = function(...) {
      calls <<- c(calls, "conversion")
      NULL
    },
    .package = "scSpotlight"
  )
  session <- shiny::MockShinySession$new()
  session$options$golem_options <- list(
    runningMode = "explore",
    dataDir = NULL,
    nCores = 1L
  )

  testServer(app_server, session = session, {
    session$flushReact()
  })

  expect_equal(calls, character())
})
