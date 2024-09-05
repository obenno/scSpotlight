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

      ## Extracting gene expression or calculating module score
      observeEvent(filteredInputFeatures(), {

          req(duckdbConnection())
          message("filteredInputFeatures() : ", paste(filteredInputFeatures(), collapse=","))

          if(isTruthy(filteredInputFeatures())){
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
                  tryCatch({
                      moduleScore <- duckModuleScore(
                          con = duckdbConnection(),
                          assay = assay(),
                          features = filteredInputFeatures()
                      )
                      ## transfer moduleScore data
                      transfer_expression(moduleScore, session)
                      removeNotification(id = "extract_expr_notification", session)
                  }, error = function(e) {
                      removeNotification(id = "extract_expr_notification", session)
                      showNotification("ModuleScore Calculation failed, please check your gene list")
                      message("moduleScore failed:", "\n", e)
                  })
              }else{
                  expr <- queryDuckExpr(
                      con = duckdbConnection(),
                      assay = assay(),
                      layer = "data",
                      features = filteredInputFeatures(),
                      populateZero = TRUE, # populate zero
                      cellNames = FALSE) # remove cellnames to shrink object size
                  transfer_expression(expr, session)
                  removeNotification(id = "extract_expr_notification", session)
              }

          }else{
            ## purge javascript expression data
            message("Purging expressions...")
              transfer_expression("", session)
          }
          scatterColorIndicator(scatterColorIndicator()+1)
      }, priority = -10, ignoreNULL = FALSE) # lower priority than plottingMode()

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
