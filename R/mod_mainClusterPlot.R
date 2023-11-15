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
             style = "position: relative",
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
#'
#' @importFrom promises future_promise %...>% %...!%
mod_mainClusterPlot_server <- function(id,
                                       obj,
                                       scatterReductionIndicator, scatterColorIndicator,
                                       scatterReductionInput, scatterColorInput,
                                       selectedReduction,
                                       group.by,
                                       split.by,
                                       filteredInputFeatures,
                                       moduleScore,
                                       goBack){
  moduleServer( id, function(input, output, session){
      ns <- session$ns
      ## waiter spinner for mainClusterPlot
      ##w <- Waiter$new(id = ns("clusterPlot"))
      selectedFeature <- reactiveVal(NULL)
      observeEvent(filteredInputFeatures(), {
          ##req(filteredInputFeatures())
          message("Filtered Input Features are: ", paste(filteredInputFeatures(), collapse=", "))
          ## Reset selectedFeature() when filteredInputFeatures() changes
          if(length(filteredInputFeatures())==1){
              selectedFeature(filteredInputFeatures()[1])
          }else if(!isTruthy(filteredInputFeatures())){
              ## If filteredInputFeatures() was changed to NULL
              ## reset selectedFeature also
              selectedFeature(NULL)
              ##if(isTruthy(goBack())){
              ##    scatterReductionIndicator(scatterReductionIndicator()+1)
              ##    scatterColorIndicator(scatterColorIndicator()+1)
              ##}
          }
          ##if(!isTruthy(filteredInputFeatures())){
          ##    message("filteredInputFeatures() changed to NULL")
          ##    scatterReductionIndicator(scatterReductionIndicator()+1)
          ##    scatterColorIndicator(scatterColorIndicator()+1)
          ##}
      }, priority = 20, ignoreNULL = FALSE)

      observeEvent(selectedFeature(), {
          req(obj())
          ## show spinner when evaluating selectedFeature()
          ##w$show()
          if(isTruthy(selectedFeature())){
              scatterColorIndicator(scatterColorIndicator()+1)
              message("selectedFeature() changed colorIndicator: ", scatterColorIndicator())
          }

      }, priority = 10, ignoreNULL = FALSE) ## ignore shall be adjusted

      plottingMode <- eventReactive(list(
          filteredInputFeatures(),
          split.by()
      ), {
          ##req(obj())
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

      observeEvent(plottingMode(), {
          message("Plotting mode changed and indicator increased")
          scatterReductionIndicator(scatterReductionIndicator()+1)
          scatterColorIndicator(scatterColorIndicator()+1)
      }, priority = -10)

      observeEvent(moduleScore(),{
          message("moduleScore switch changed scatterColorIndicator")
          scatterColorIndicator(scatterColorIndicator()+1)
      }, ignoreInit = TRUE)
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
      }, priority = -20)

      ## Update scatterColorInput only when scatterColorIndicator changes
      observeEvent(scatterColorIndicator(), {
          req(obj())
          validate(
              need(selectedReduction() %in% Reductions(obj()),
                   paste0(selectedReduction(), " is not in object reductions"))
          )
          message("Updating scatterColorInput")
          if(isTruthy(filteredInputFeatures()) &&
             isTruthy(moduleScore())){
              exprData <- AddModuleScore(obj(), features = filteredInputFeatures()) %>% pull()
          }else{
              exprData <- NULL
          }
          d <- prepare_scatterCatColorInput(obj(),
                                            col_name = group.by(),
                                            mode = plottingMode(),
                                            split.by = split.by(),
                                            feature = selectedFeature(),
                                            exprData = exprData)

          scatterColorInput(d)
          message("Finished Updating scatterColorInput")
      }, priority = -30)

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

      ## input$goBack was set in javacript code
      observeEvent(goBack(), {
          message("goBack is ", goBack())
          selectedFeature(NULL)
          message("selectedFeature() is NULL")
      }, ignoreNULL= TRUE, priority = 20)


      ## Invoke multiFeaturePlot module
      mod_FeaturePlot_server("featurePlot",
                             obj,
                             selectedReduction,
                             split.by,
                             selectedFeature,
                             filteredInputFeatures)


      observeEvent(list(
          ## Include trigger events
          ##selectedReduction(),
          ##group.by(),
          ##split.by(),
          ##selectedFeature(),
          ##filteredInputFeatures(),
          ##moduleScore()
          ##goBack()
          scatterReductionInput(),
          scatterColorInput()
      ), {
          ## Update plots when group.by and split.by changes
          req(group.by(), split.by())
          ##w$show()
          if(isTruthy(filteredInputFeatures()) && length(filteredInputFeatures())>1){
              if(!is.null(selectedFeature())){
                  message("Plotting clusters")
                  reglScatter_reduction(scatterReductionInput(), session)
                  reglScatter_color(scatterColorInput(), session)
                  ## Add goBack button and goBack() value
                  reglScatter_addGoBack(session)
              }
          }else{
              reglScatter_reduction(scatterReductionInput(), session)
              reglScatter_color(scatterColorInput(), session)
          }
          ##on.exit({
          ##    w$hide()
          ##})
      }, priority = -100)

      return(reactive(selectedFeature()))
  })
}


## To be copied in the UI
# mod_mainClusterPlot_ui("mainClusterPlot_1")

## To be copied in the server
# mod_mainClusterPlot_server("mainClusterPlot_1")
