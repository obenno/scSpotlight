#' Run the Shiny Application
#'
#' @param ... arguments to pass to golem_opts.
#' See `?golem::get_golem_options` for more details.
#' @inheritParams shiny::shinyApp
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
  runningMode = "viewer", # processing mode or viewer mode
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
    golem_opts = list(dataDir = dataDir, runningMode = runningMode, ...)
  )
}
