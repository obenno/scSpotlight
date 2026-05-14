test_that("Explore Mode left sidebar only exposes file input", {
  left_sidebar_ui <- getFromNamespace("left_sidebar_ui", "scSpotlight")

  shiny::shinyOptions(
    golem_options = list(runningMode = "explore", dataDir = NULL)
  )
  on.exit(shiny::shinyOptions(golem_options = NULL), add = TRUE)
  ui <- left_sidebar_ui()
  html <- paste(as.character(ui), collapse = "\n")

  expect_match(html, "File Input", fixed = TRUE)
  expect_no_match(html, "Data Conversion", fixed = TRUE)
  expect_no_match(html, "dataConversion", fixed = TRUE)
})

test_that("Explore Mode file input accepts only Explore Parquet archives", {
  mod_dataInput_inputUI <- getFromNamespace(
    "mod_dataInput_inputUI",
    "scSpotlight"
  )

  shiny::shinyOptions(
    golem_options = list(runningMode = "explore", dataDir = NULL)
  )
  on.exit(shiny::shinyOptions(golem_options = NULL), add = TRUE)
  ui <- mod_dataInput_inputUI("dataInput")
  html <- paste(as.character(ui), collapse = "\n")

  expect_match(html, "Upload Explore Parquet Bundle", fixed = TRUE)
  expect_match(html, ".explore-parquet.zip", fixed = TRUE)
  expect_no_match(html, ".rds", fixed = TRUE)
  expect_no_match(html, ".h5ad", fixed = TRUE)
})

test_that("Explore Mode dataDir only lists Explore Parquet archives", {
  data_dir <- tempfile("explore_mode_inputs_")
  dir.create(data_dir)
  on.exit(unlink(data_dir, recursive = TRUE, force = TRUE), add = TRUE)
  file.create(file.path(data_dir, "good.explore-parquet.zip"))
  file.create(file.path(data_dir, "plain.zip"))
  file.create(file.path(data_dir, "object.Rds"))
  file.create(file.path(data_dir, "manifest.json"))

  selected_choices <- list.files(
    path = data_dir,
    pattern = getFromNamespace(
      "scspotlight_explore_archive_pattern",
      "scSpotlight"
    ),
    recursive = TRUE
  )

  expect_equal(selected_choices, "good.explore-parquet.zip")
})

test_that("Analysis Mode file input does not accept Explore Parquet archives", {
  mod_dataInput_inputUI <- getFromNamespace(
    "mod_dataInput_inputUI",
    "scSpotlight"
  )

  shiny::shinyOptions(
    golem_options = list(runningMode = "analysis", dataDir = NULL)
  )
  on.exit(shiny::shinyOptions(golem_options = NULL), add = TRUE)
  ui <- mod_dataInput_inputUI("dataInput")
  html <- paste(as.character(ui), collapse = "\n")

  expect_match(html, "Upload Input File", fixed = TRUE)
  expect_match(html, ".rds", fixed = TRUE)
  expect_match(html, ".h5ad", fixed = TRUE)
  expect_no_match(html, ".explore-parquet.zip", fixed = TRUE)
})

test_that("Analysis Mode dataDir excludes Explore Parquet archives", {
  data_dir <- tempfile("analysis_mode_inputs_")
  dir.create(data_dir)
  on.exit(unlink(data_dir, recursive = TRUE, force = TRUE), add = TRUE)
  file.create(file.path(data_dir, "good.Rds"))
  file.create(file.path(data_dir, "matrix.zip"))
  file.create(file.path(data_dir, "blocked.explore-parquet.zip"))

  session <- shiny::MockShinySession$new()
  session$options$golem_options <- list(
    runningMode = "analysis",
    dataDir = data_dir,
    nCores = 1L
  )
  sent_choices <- NULL

  testthat::local_mocked_bindings(
    assert_bpcells_available = function(...) TRUE,
    updateSelectizeInput = function(
      session,
      inputId,
      label = NULL,
      choices = NULL,
      selected = NULL,
      ...
    ) {
      if (identical(inputId, "dataDirFile")) {
        sent_choices <<- choices
      }
      invisible(NULL)
    },
    .package = "scSpotlight"
  )

  testServer(
    getFromNamespace("mod_dataInput_server", "scSpotlight"),
    session = session,
    args = list(
      obj = shiny::reactiveVal(NULL),
      hvgSelectMethod = shiny::reactive("vst"),
      clusterDims = shiny::reactive(30),
      clusterResolution = shiny::reactive(0.5),
      geneUpdateIndicator = shiny::reactiveVal(0),
      metaUpdateIndicator = shiny::reactiveVal(0),
      reductionUpdateIndicator = shiny::reactiveVal(0)
    ),
    {
      session$flushReact()
    }
  )

  expect_equal(sort(sent_choices), c("good.Rds", "matrix.zip"))
})
