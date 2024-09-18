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
                                       selectedFeatures,
                                       moduleScore){
  moduleServer( id, function(input, output, session){
      ns <- session$ns

      previous_plottingMode <- reactiveVal(NULL)
      previous_selectedFeatures <- reactiveVal(NULL)

      ##plottingMode <- eventReactive(list(
      ##    selectedFeatures(),
      ##    split.by()
      ##), {
      ##
      ##    message("selectedFeatures(): ", selectedFeatures())
      ##    if(isTruthy(selectedFeatures()) &&
      ##       length(selectedFeatures()) == 1 &&
      ##       split.by() == "None"){
      ##        mode <- "cluster+expr+noSplit"
      ##    }else if(isTruthy(selectedFeatures()) &&
      ##             length(selectedFeatures()) == 1 &&
      ##             split.by() != "None"){
      ##        split.by.length <- queryDuckMeta(
      ##            con = duckdbConnection()
      ##        ) %>%
      ##        pull(split.by()) %>%
      ##        unique() %>%
      ##        length()
      ##        if(split.by.length <= 2){
      ##            mode <- "cluster+expr+twoSplit"
      ##        }else{
      ##            mode <- "cluster+expr+multiSplit"
      ##        }
      ##    }else if(!isTruthy(selectedFeatures()) &&
      ##             split.by() != "None"){
      ##        mode <- "cluster+multiSplit"
      ##    }else{
      ##        mode <- "clusterOnly"
      ##    }
      ##    message("Plotting mode => ", mode)
      ##
      ##    return(mode)
      ##})

      ##observeEvent(list(plottingMode(), selectedFeatures()), {
      ##  ## here we only observe plottingMode() value change, not state change
      ##  if (!identical(previous_plottingMode(), plottingMode())) {
      ##    ## Expression related plot will be triggered by "plotFeature" button
      ##    ## Here only automatically trigger plot event with no expression plottingMode()
      ##    ## selectedFeature > 1 will return clusterOnly mode, we will not automatically trigger plot then
      ##    if(plottingMode() %in% c("clusterOnly", "cluster+multiSplit") &&
      ##       length(selectedFeatures())==0){
      ##      message("Plotting mode changed and indicator increased")
      ##      scatterReductionIndicator(scatterReductionIndicator()+1)
      ##      scatterColorIndicator(scatterColorIndicator()+1)
      ##    }
      ##  }
      ##  previous_plottingMode(plottingMode())
      ##}, priority = -10, ignoreNULL = TRUE, ignoreInit = TRUE)

      observeEvent(moduleScore(),{
          message("moduleScore switch changed scatterColorIndicator")
          scatterColorIndicator(scatterColorIndicator()+1)
      }, ignoreInit = TRUE)


      observeEvent(list(
          scatterReductionIndicator(),
          scatterColorIndicator()
      ), {
        ## Update plots when group.by and split.by changes
          req(duckdbConnection())
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
          ##d <- prepare_scatterMeta(con = duckdbConnection(),
          ##                         group.by = group.by(),
          ##                         mode = plottingMode(),
          ##                         split.by = split.by(),
          ##                         moduleScore = moduleScore())
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
