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
                                       duckdbConnection,
                                       assay,
                                       scatterReductionIndicator,
                                       scatterColorIndicator,
                                       scatterReductionInput,
                                       scatterColorInput,
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
              ##    message("goBack button increased scatter indicator")
              ##    scatterReductionIndicator(scatterReductionIndicator()+1)
              ##    scatterColorIndicator(scatterColorIndicator()+1)
              ##}
          }else if(length(filteredInputFeatures())>1){
              selectedFeature(NULL)
          }

      }, priority = 20, ignoreNULL = FALSE)

      ## Extract gene expressions
      observeEvent(selectedFeature(), {
          req(duckdbConnection())
          if(isTruthy(selectedFeature())){
              ## Transfer expressionData
              showNotification(
                  ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                               role = "status",
                               span(class = "sr-only", "Loading...")),
                           "Extracting expression values..."),
                  action = NULL,
                  duration = NULL,
                  closeButton = FALSE,
                  type = "default",
                  id = "extract_expr_notification",
                  session = session
              )
              if(isTruthy(moduleScore())){
                expr <- duckModuleScore(
                  con = duckdbConnection(),
                  assay = assay(),
                  features = filteredInputFeatures()
                )
              }else{
                expr <- queryDuckExpr(con = duckdbConnection(),
                                      assay = assay(),
                                      layer = "data",
                                      feature = selectedFeature(),
                                      populateZero = TRUE) %>%
                  as.data.frame() %>%
                  pull()
              }
              transfer_expression(expr, session)
              removeNotification(id = "extract_expr_notification", session)
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
          message("Plotting mode changed and indicator increased")
          scatterReductionIndicator(scatterReductionIndicator()+1)
          scatterColorIndicator(scatterColorIndicator()+1)
      }, priority = -10)

      observeEvent(moduleScore(),{
          message("moduleScore switch changed scatterColorIndicator")
          scatterColorIndicator(scatterColorIndicator()+1)
      }, ignoreInit = TRUE)

      ## Update scatterColorInput only when scatterColorIndicator changes
      observeEvent(scatterColorIndicator(), {
          req(duckdbConnection())
          validate(
              need(selectedReduction() %in% listDuckReduction(con = duckdbConnection()),
                   paste0(selectedReduction(), " is not in object reductions"))
          )
          message("Updating scatterColorInput")
          if(isTruthy(filteredInputFeatures()) &&
             isTruthy(moduleScore())){
            exprData <- duckModuleScore(
              con = duckdbConnection(),
              assay = assay(),
              features = filteredInputFeatures()
            ) %>%
              pull()
          }else{
              exprData <- NULL
          }

          d <- prepare_scatterMeta(con = duckdbConnection(),
                                   group.by = group.by(),
                                   mode = plottingMode(),
                                   split.by = split.by(),
                                   inputFeatures = filteredInputFeatures(),
                                   selectedFeature = selectedFeature(),
                                   moduleScore = moduleScore())

          scatterColorInput(d)
          message("Finished Updating scatterColorInput")
      }, priority = -20)

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
          scatterReductionIndicator(),
          scatterColorIndicator()
      ), {
          ## Update plots when group.by and split.by changes
          req(group.by(), split.by())
          message("indicators changed, plotting clusters...")
          ##w$show()
          if(isTruthy(filteredInputFeatures()) && length(filteredInputFeatures())>1){
              if(!is.null(selectedFeature())){
                  reglScatter_plot(scatterColorInput(), session)
                  ## Add goBack button and goBack() value
                  reglScatter_addGoBack(session)
              }
          }else{
              reglScatter_plot(scatterColorInput(), session)
          }
          ##on.exit({
          ##    w$hide()
          ##})
      }, priority = -1000)

      return(reactive(selectedFeature()))
  })
}


## To be copied in the UI
# mod_mainClusterPlot_ui("mainClusterPlot_1")

## To be copied in the server
# mod_mainClusterPlot_server("mainClusterPlot_1")
