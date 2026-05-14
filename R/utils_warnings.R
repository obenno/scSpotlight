#' Capture warnings while evaluating an expression
#'
#' @noRd
capture_warnings <- function(expr) {
  warnings <- character(0)
  value <- withCallingHandlers(
    expr,
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  list(
    value = value,
    warnings = unique(warnings)
  )
}

#' Show captured warnings as a detailed Shiny notification
#'
#' @noRd
show_captured_warnings <- function(
  warnings,
  title = "Operation completed with warnings",
  session = shiny::getDefaultReactiveDomain(),
  duration = 20
) {
  warnings <- unique(Filter(nzchar, warnings %||% character(0)))
  if (!length(warnings)) {
    return(invisible(NULL))
  }

  shiny::showNotification(
    ui = shiny::HTML(paste0(
      "<b>",
      htmltools::htmlEscape(title),
      "</b><br>",
      paste(htmltools::htmlEscape(warnings), collapse = "<br>")
    )),
    action = NULL,
    duration = duration,
    closeButton = TRUE,
    type = "warning",
    session = session
  )

  invisible(NULL)
}
