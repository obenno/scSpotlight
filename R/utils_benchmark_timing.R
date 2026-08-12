#' @noRd
scspotlight_benchmark_timing_enabled <- function() {
  value <- tolower(trimws(Sys.getenv("SCSPOTLIGHT_BENCHMARK_STARTUP_TIMING", "")))
  value %in% c("1", "true", "yes")
}

#' @noRd
scspotlight_benchmark_timing_epoch_ms <- function() {
  as.numeric(Sys.time()) * 1000
}

#' @noRd
scspotlight_benchmark_timing_event_file <- function() {
  path <- trimws(Sys.getenv("SCSPOTLIGHT_BENCHMARK_STARTUP_TIMING_EVENT_FILE", ""))
  if (!nzchar(path)) {
    return(NULL)
  }

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

#' @noRd
scspotlight_benchmark_timing_event <- function(
  session,
  phase,
  state = "mark",
  elapsed_ms = NULL,
  details = list()
) {
  if (!scspotlight_benchmark_timing_enabled()) {
    return(invisible(NULL))
  }

  event <- c(
    list(
      source = "server",
      phase = as.character(phase)[[1]],
      state = as.character(state)[[1]],
      serverTimestampEpochMs = scspotlight_benchmark_timing_epoch_ms()
    ),
    if (is.null(elapsed_ms)) {
      list()
    } else {
      list(elapsedMs = as.numeric(elapsed_ms)[[1]])
    },
    details
  )

  event_file <- scspotlight_benchmark_timing_event_file()
  if (!is.null(event_file)) {
    cat(
      jsonlite::toJSON(event, auto_unbox = TRUE, null = "null"),
      "\n",
      file = event_file,
      append = TRUE,
      sep = ""
    )
  }

  try(
    session$sendCustomMessage("benchmark_timing", event),
    silent = TRUE
  )
  invisible(event)
}

#' @noRd
scspotlight_benchmark_timing_measure <- function(
  session,
  phase,
  expr,
  details = list()
) {
  if (!scspotlight_benchmark_timing_enabled()) {
    return(force(expr))
  }

  started <- proc.time()[["elapsed"]]
  scspotlight_benchmark_timing_event(
    session,
    phase = phase,
    state = "start",
    details = details
  )

  tryCatch(
    {
      value <- force(expr)
      scspotlight_benchmark_timing_event(
        session,
        phase = phase,
        state = "end",
        elapsed_ms = (proc.time()[["elapsed"]] - started) * 1000,
        details = details
      )
      value
    },
    error = function(error) {
      scspotlight_benchmark_timing_event(
        session,
        phase = phase,
        state = "error",
        elapsed_ms = (proc.time()[["elapsed"]] - started) * 1000,
        details = details
      )
      stop(error)
    }
  )
}
