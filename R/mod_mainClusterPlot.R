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
         height = "500px",
         class = c("border", "border-primary", "border-2", "mb-1", "shadow"),
         ## add resize property
         style = "resize:both;",
         card_body(
             id = ns("clusterPlot"),
             height="600px",
             class = "align-items-center m-0 p-1",
             div(id = ns("note"), class = "mainClusterPlotNote shadow"),
             mod_FeaturePlot_ui(ns("featurePlot"))
         )
     )
  )
}

#' mainClusterPlot Server Functions
#'
#' @noRd 
mod_mainClusterPlot_server <- function(id,
                                       obj,
                                       scatterReductionIndicator, scatterColorIndicator,
                                       scatterReductionInput, scatterColorInput,
                                       selectedReduction,
                                       group.by,
                                       split.by,
                                       filteredInputFeatures){
  moduleServer( id, function(input, output, session){
      ns <- session$ns

      selectedFeature <- reactiveVal(NULL)
      observeEvent(filteredInputFeatures(), {
          message("Filtered Input Features are: ", paste(filteredInputFeatures(), collapse=", "))
          ##scatterReductionIndicator(scatterReductionIndicator()+1)
          ##scatterColorIndicator(scatterColorIndicator()+1)
          ##if(isTruthy(filteredInputFeatures())){
          ##    selectedFeature(filteredInputFeatures()[1])
          ##}
      }, priority = 10, ignoreNULL = FALSE)

      plottingMode <- reactive({
          req(obj())
          req(selectedReduction())
          req(group.by())
          ##req(categoryInfo$split.by())
          if(isTruthy(filteredInputFeatures()) && split.by() == "None"){
              mode <- "cluster+expr+noSplit"
          }else if(isTruthy(filteredInputFeatures()) &&
                   split.by() != "None"){
              split.by.length <- obj()[[split.by()]] %>%
                  pull() %>%
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


      ## Update scatterReductionInput only when scatterReductionIndicator changes
      observeEvent(scatterReductionIndicator(), {
          req(obj())
          validate(
              need(selectedReduction() %in% Reductions(obj()),
                   paste0(selectedReduction(), " is not in object reductions"))
          )
          message("Updating scatterReductionInput")
          d <- prepare_scatterReductionInput(obj(),
                                             reduction = selectedReduction(),
                                             mode = plottingMode(),
                                             split.by = split.by())

          scatterReductionInput(d)
          message("Finished Updating scatterReductionInput")
      }, priority = -10)

      ## Update scatterColorInput only when scatterReductionIndicator changes
      observeEvent(scatterColorIndicator(), {
          req(obj())
          validate(
              need(selectedReduction() %in% Reductions(obj()),
                   paste0(selectedReduction(), " is not in object reductions"))
          )
          message("Updating scatterColorInput")
          d <- prepare_scatterCatColorInput(obj(),
                                            col_name = group.by(),
                                            mode = plottingMode(),
                                            split.by = split.by(),
                                            feature = selectedFeature())

          scatterColorInput(d)
          message("Finished Updating scatterColorInput")
      }, priority = -20)

      ## Plotting with the last priority
      ##observeEvent( scatterReductionIndicator(), {
      ##    ##message("scatterReductionIndicator() is ", scatterReductionIndicator())
      ##    ##message("scatterReductionInput() is ", is.null(scatterReductionInput()))
      ##    req(scatterReductionIndicator() > 0)
      ##    reglScatter_reduction(scatterReductionInput(), session)
      ##}, priority = -100)
      ##
      ##observeEvent( scatterColorIndicator(), {
      ##    req(scatterColorIndicator() > 0)
      ##    reglScatter_color(scatterColorInput(), session)
      ##}, priority = -100)



      ## Invoke multiFeaturePlot module
      observe({
          if(is.null(selectedFeature()) && length(filteredInputFeatures())>1){
              mod_FeaturePlot_server("featurePlot",
                                     obj,
                                     selectedReduction,
                                     split.by,
                                     selectedFeature,
                                     filteredInputFeatures)
          }else{
              reglScatter_reduction(scatterReductionInput(), session)
              reglScatter_color(scatterColorInput(), session)
          }

      }, priority = -100)
  })
}


## To be copied in the UI
# mod_mainClusterPlot_ui("mainClusterPlot_1")
    
## To be copied in the server
# mod_mainClusterPlot_server("mainClusterPlot_1")
