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
  analysisTransition = NULL
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    ##observeEvent(moduleScore(),{
    ##    message("moduleScore switch changed scatterColorIndicator")
    ##    scatterColorIndicator(scatterColorIndicator()+1)
    ##}, ignoreInit = TRUE)

    observeEvent(
      list(
        plotRefreshIndicator(),
        scatterUpdateIndicator()
      ),
      {
        ## Update plots when group.by and split.by changes
        req(metaProcessed())
        req(reductionProcessed())
        req(group.by() != "None")

        message("-----")
        message("Selected group.by is ", isolate(group.by()))
        message("Selected split.by is ", isolate(split.by()))
        message("Updating plotMetaData")
        message("moduleScore is ", moduleScore())
        message("-----")

        if (group.by() == "None") {
          group_by = NULL
        } else {
          group_by = group.by()
        }
        if (split.by() == "None") {
          split_by = NULL
        } else {
          split_by = split.by()
        }
        d <- list(
          group_by = group_by,
          split_by = split_by,
          moduleScore = moduleScore()
        )
        if (!is.null(analysisTransition)) {
          analysis_context <- analysisTransition$intent_context()
          d$analysisVersion <- analysis_context$expected_version
          d$analysisLineageId <- analysis_context$lineage_id
        }
        message("invoking regl")
        reglScatter_plot(d, session)
      },
      priority = -1000,
      ignoreInit = TRUE
    )
  })
}

## To be copied in the UI
# mod_mainClusterPlot_ui("mainClusterPlot_1")

## To be copied in the server
# mod_mainClusterPlot_server("mainClusterPlot_1")
