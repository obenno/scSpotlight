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
                                       scatterReductionIndicator,
                                       scatterColorIndicator,
                                       group.by,
                                       split.by,
                                       filteredInputFeatures,
                                       moduleScore){
  moduleServer( id, function(input, output, session){
      ns <- session$ns

      previous_plottingMode <- reactiveVal(NULL)
      plottingMode <- eventReactive(list(
          filteredInputFeatures(),
          split.by()
      ), {
          ##req(duckdbConnection())
          if(isTruthy(filteredInputFeatures()) && split.by() == "None"){
              mode <- "cluster+expr+noSplit"
          }else if(isTruthy(filteredInputFeatures()) &&
                   split.by() != "None"){
            split.by.length <- queryDuckMeta(
              con = duckdbConnection()
            ) %>%
              pull(split.by()) %>%
              unique() %>%
              length()
              if(split.by.length <= 2){
                  mode <- "cluster+expr+twoSplit"
              }else{
                  mode <- "cluster+expr+multiSplit"
              }
          }else if(!isTruthy(filteredInputFeatures()) &&
                   split.by() != "None"){
              mode <- "cluster+multiSplit"
          }else{
              mode <- "clusterOnly"
          }
          message("Plotting mode => ", mode)

          return(mode)
      })

      observeEvent(plottingMode(), {
        ## here we only observe plottingMode() value change, not state change
        if (!identical(previous_plottingMode(), plottingMode())) {
          message("Plotting mode changed and indicator increased")
          scatterReductionIndicator(scatterReductionIndicator()+1)
          scatterColorIndicator(scatterColorIndicator()+1)
        }
        previous_plottingMode(plottingMode())
      },
      priority = -10,
      ignoreNULL = TRUE,
      ignoreInit = TRUE)

      observeEvent(moduleScore(),{
          message("moduleScore switch changed scatterColorIndicator")
          scatterColorIndicator(scatterColorIndicator()+1)
      }, ignoreInit = TRUE)


      observeEvent(list(
          ## Include trigger events
          ##selectedReduction(),
          ##group.by(),
          ##split.by(),
          ##selectedFeature(),
          ##filteredInputFeatures(),
          ##moduleScore()
          scatterReductionIndicator(),
          scatterColorIndicator()
      ), {
          ## Update plots when group.by and split.by changes
          req(group.by(), split.by())
          message("Selected group.by is ", isolate(group.by()))
          message("Selected split.by is ", isolate(split.by()))
          message("scatterReductionIndicator() is ", isolate(scatterReductionIndicator()))
          message("scatterColorIndicator() is ", isolate(scatterColorIndicator()))
          message("Updating plotMetaData")
          d <- prepare_scatterMeta(con = duckdbConnection(),
                                   group.by = group.by(),
                                   mode = plottingMode(),
                                   split.by = split.by(),
                                   inputFeatures = filteredInputFeatures(),
                                   selectedFeature = NULL,
                                   moduleScore = moduleScore())

          message("indicators changed, plotting clusters...")

          reglScatter_plot(d, session)

      }, priority = -1000, ignoreInit = TRUE)

  })
}


## To be copied in the UI
# mod_mainClusterPlot_ui("mainClusterPlot_1")

## To be copied in the server
# mod_mainClusterPlot_server("mainClusterPlot_1")
