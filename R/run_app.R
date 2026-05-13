#' Run the scSpotlight App
#'
#'
#'
#' @param runningMode The running mode of the app. Use "analysis" (default) for
#' full data processing and analysis, or "explore" for read-only exploration of
#' processed data. Legacy aliases "processing" and "viewer" are accepted.
#' @param dataDir Direcotry path of the input data, user could put the large dataset in the
#' direcoty to avoid uploading files
#' @param nCores Number of the threads to use (by [future::plan()]).
#' @param maxSize Maximum allowed total size (in bytes) of global variables identified, see future.globals.maxSize.
#' @param ... arguments to pass to golem_opts.
#' See `?golem::get_golem_options` for more details.
#' @inheritParams shiny::shinyApp
#'
#' @examples
#' \dontrun{
#'  ## Run app in Analysis Mode
#'  run_app()
#'
#'  ## Run app in Explore Mode and load data in dataDir
#'  run_app(runningMode = "explore", dataDir = "/path/to/data")
#'
#'  ## Run app on port 8081, shiny::runApp() options need to be wrapped in a list
#'  run_app(options = list(port = 8081, host ="0.0.0.0", launch.browser = FALSE), runningMode = "analysis")
#' }
#'
#' @export
#' @importFrom shiny shinyApp
#' @importFrom golem with_golem_options
run_app <- function(
  onStart = set_options,
  options = list(),
  enableBookmarking = NULL,
  uiPattern = "/",
  dataDir = NULL,
  runningMode = "analysis",
  maxSize = 20 * 1000 * 1024^2,
  nCores = 2,
  ...
) {
  runningMode <- normalize_running_mode(runningMode)

  with_golem_options(
    app = shinyApp(
      ui = app_ui,
      server = app_server,
      onStart = onStart(nCores = nCores, maxSize = maxSize),
      options = options,
      enableBookmarking = enableBookmarking,
      uiPattern = uiPattern
    ),
    golem_opts = list(
      dataDir = dataDir,
      runningMode = runningMode,
      nCores = nCores,
      ...
    )
  )
}

#' @noRd
normalize_running_mode <- function(runningMode = "analysis") {
  if (is.null(runningMode) || length(runningMode) == 0L) {
    runningMode <- "analysis"
  }
  if (
    !is.character(runningMode) ||
      length(runningMode) != 1L ||
      is.na(runningMode)
  ) {
    stop("runningMode must be one of 'analysis' or 'explore'", call. = FALSE)
  }

  mode <- tolower(trimws(runningMode))
  mode_aliases <- c(
    analysis = "analysis",
    explore = "explore",
    processing = "analysis",
    viewer = "explore"
  )
  normalized <- unname(mode_aliases[mode])
  if (is.na(normalized)) {
    stop("runningMode must be one of 'analysis' or 'explore'", call. = FALSE)
  }
  normalized
}
