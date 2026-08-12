#' mainClusterPlot UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_mainClusterPlot_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      id = ns("mainClusterPlot"),
      fill = TRUE,
      full_screen = FALSE,
      border_radius = FALSE,
      class = NULL,
      ## add resize property
      style = "width: 100%; height: 100%; border-radius: 0;",
      card_body_fill(
        id = ns("clusterPlot"),
        style = "position: relative",
        class = "align-items-center m-0 p-0"
        ##mod_FeaturePlot_ui(ns("featurePlot"))
      )
    )
  )
}

#' mainClusterPlot Server Functions
#'
#' @noRd
#'
#' @importFrom promises future_promise %...>% %...!%
mod_mainClusterPlot_server <- function(
  id,
  reductionProcessed,
  metaProcessed,
  plotRefreshIndicator,
  scatterUpdateIndicator,
  group.by,
  split.by,
  moduleScore,
  analysisTransition = NULL,
  viewFilterState = function() list(filter = NULL, version = 0L)
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    render_plot <- function(view_filter_only = FALSE) {
      req(metaProcessed())
      req(reductionProcessed())
      req(group.by() != "None")

      message("-----")
      message("Selected group.by is ", isolate(group.by()))
      message("Selected split.by is ", isolate(split.by()))
      message("Updating plotMetaData")
      message("moduleScore is ", moduleScore())
      message("-----")

      group_by <- if (group.by() == "None") NULL else group.by()
      split_by <- if (split.by() == "None") NULL else split.by()
      view_filter_state <- viewFilterState()
      d <- list(
        group_by = group_by,
        split_by = split_by,
        moduleScore = moduleScore(),
        viewFilter = view_filter_state$filter,
        viewFilterVersion = view_filter_state$version
      )
      if (isTRUE(view_filter_only)) {
        d$viewFilterOnly <- TRUE
      }
      if (!is.null(analysisTransition)) {
        analysis_context <- analysisTransition$intent_context()
        d$analysisVersion <- analysis_context$expected_version
        d$analysisLineageId <- analysis_context$lineage_id
      }
      message("invoking regl")
      reglScatter_plot(d, session)
    }

    observeEvent(
      list(plotRefreshIndicator(), scatterUpdateIndicator()),
      render_plot(),
      priority = -1000,
      ignoreInit = TRUE
    )

    observeEvent(
      viewFilterState(),
      render_plot(view_filter_only = TRUE),
      priority = -1000,
      ignoreInit = TRUE
    )
  })
}

## To be copied in the UI
# mod_mainClusterPlot_ui("mainClusterPlot_1")

## To be copied in the server
# mod_mainClusterPlot_server("mainClusterPlot_1")
