#' Run the scSpotlight App
#'
#' 
#'
#' @param runningMode The running mode of the app. This could be "processing" (default) or "viewer".
#' The "processing" mode allows users to process input data by Seurat package while in "viewer" mode,
#' user will only be able to view the dimension reduction result and query gene expressions.
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
#'  ## Run app in processing mode
#'  run_app()
#'
#'  ## Run app in viewer mode and load data in dataDir
#'  run_app(runningMode = "viewer", dataDir = "/path/to/data")
#'
#'  ## Run app on port 8081, shiny::runApp() options need to be wrapped in a list
#'  run_app(options = list(port = 8081, host ="0.0.0.0", launch.browser = FALSE), runningMode = "processing")
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
  runningMode = "processing", # processing mode or viewer mode
  maxSize = 20 * 1000 * 1024^2,
  nCores = 2,
  ...
) {
  with_golem_options(
    app = shinyApp(
      ui = app_ui,
      server = app_server,
      onStart = onStart(nCores = nCores, maxSize = maxSize),
      options = options,
      enableBookmarking = enableBookmarking,
      uiPattern = uiPattern
    ),
    golem_opts = list(dataDir = dataDir,
                      runningMode = runningMode,
                      nCores = nCores, ...)
  )
}
