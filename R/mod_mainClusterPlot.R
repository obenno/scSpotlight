#' mainClusterPlot UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_mainClusterPlot_ui <- function(id){
  ns <- NS(id)
  tagList(
     card(
         id = ns("mainClusterPlot"),
         full_screen = TRUE,
         class = c("border", "border-primary", "border-2", "mb-1", "shadow"),
         ## add resize property
         style = "resize:both; width:100%",
         card_body(
             id = ns("clusterPlot"),
             height="600px",
             style = "position: relative",
             class = "align-items-center m-0 p-1",
           tags$canvas(
                  id = "featurePlotCanvas",
                  style = "display: none;")
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
mod_mainClusterPlot_server <- function(id,
                                       duckdbConnection,
                                       assay,
                                       extract_reduction,
                                       extract_meta,
                                       scatterReductionIndicator,
                                       scatterColorIndicator,
                                       group.by,
                                       split.by,
                                       selectedFeatures,
                                       moduleScore){
  moduleServer( id, function(input, output, session){
      ns <- session$ns

      previous_plottingMode <- reactiveVal(NULL)
      previous_selectedFeatures <- reactiveVal(NULL)

      observeEvent(moduleScore(),{
          message("moduleScore switch changed scatterColorIndicator")
          scatterColorIndicator(scatterColorIndicator()+1)
      }, ignoreInit = TRUE)


      observeEvent(list(
          scatterReductionIndicator(),
          scatterColorIndicator(),
          extract_meta$status(),
          extract_reduction$status()
      ), {
          ## Update plots when group.by and split.by changes
          req(duckdbConnection())
          req(extract_meta$status() == "success")
          req(extract_reduction$status() == "success")
          req(group.by()!="None")

          message("Selected group.by is ", isolate(group.by()))
          message("Selected split.by is ", isolate(split.by()))
          message("scatterReductionIndicator() is ", isolate(scatterReductionIndicator()))
          message("scatterColorIndicator() is ", isolate(scatterColorIndicator()))
          message("Updating plotMetaData")
          message("-----")
          message("group.by is ", group.by());
          ##message("plottingMode() is ", plottingMode())
          message("split.by is ", split.by())
          message("moduleScore is ", moduleScore())

          if(group.by()=="None"){
            group_by = NULL
          }else{
            group_by = group.by()
          }
          if(split.by()=="None"){
            split_by = NULL
          }else{
            split_by = split.by()
          }
          d <- list(
            group_by = group_by,
            split_by = split_by,
            moduleScore = moduleScore()
          )
          message("invoking regl")
          reglScatter_plot(d, session)

      }, priority = -1000, ignoreInit = TRUE)

  })
}


## To be copied in the UI
# mod_mainClusterPlot_ui("mainClusterPlot_1")

## To be copied in the server
# mod_mainClusterPlot_server("mainClusterPlot_1")
