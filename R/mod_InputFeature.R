#' InputFeature UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
#' @importFrom shinyWidgets switchInput
mod_InputFeature_ui <- function(id){
    ns <- NS(id)
    tagList(
        selectizeInput(
            ns("featureInputMode"),
            "Choose Input Mode",
            choices = c("Manual Select", "Upload Feature List"),
            selected = "Manual Select",
            multiple = FALSE,
            options = list(dropdownParent = "body"),
            width = NULL
        ),
        selectizeInput(
            ns("features"),
            "Input Gene Names",
            selected = NULL,
            choices = "",
            multiple = FALSE,
            options = list(dropdownParent = "body"),
            width = NULL
        ),
        shinyjs::hidden(
          tagList(
            fileInput(
              ns("featureList"),
              "or Upload Gene Set List",
              multiple = FALSE,
              width = "100%",
              accept = c(".xlsx", ".csv", ".tsv", ".txt")
            ),
            tagAppendAttributes(
              selectizeInput(
                  ns("geneSet"),
                  "Choose Gene Set",
                  choices = "",
                  selected = NULL,
                  multiple = FALSE,
                  options = list(dropdownParent = "body"),
                  width = NULL
              ),
              class = c("mb-1")
            )
          )
        ),
        div(id = "featureSparkLine"),
        div(
            ## button needs to be wrapped in a div element to make
            ## the float:right style work
            actionButton(
                ns("plotFeature"),
                "Plot",
                width = "75px",
                style = "position:relative; float:left;",
                class = "border border-1 border-primary shadow mb-2"
            ),
            actionButton(
                ns("clearFeature"),
                "Clear",
                width = "75px",
                style = "position:relative; float:right;",
                class = "border border-1 border-primary shadow mb-2"
            )
        ),
        ##uiOutput(ns("uploadedFeatureSet")),
        span(
            "Calculate Program Expression Score", style = "display: inline-block; margin-bottom: 0.5rem",
            infoIcon("This will use AddModuleScore() function to generate program expression score. ref: Tirosh et al, Science (2016)", "left")
        ),
        switchInput(
            inputId = ns("moduleScore"),
            label = NULL,
            size = "mini",
            value = FALSE
        )

    )
}

#' InputFeature Server Functions
#'
#' @importFrom stringr str_detect
#' @importFrom readr read_tsv read_csv
#' @importFrom readxl read_excel
#' @importFrom htmltools tagAppendAttributes
#' @importFrom shinyWidgets updateSwitchInput
#' @import shiny
#' @importFrom promises future_promise %...>% %...!% finally
#' @importFrom cli hash_md5
#' @importFrom arrow arrow_table write_ipc_stream float32 Array
#' @importFrom future plan availableCores multisession nbrOfWorkers
#' @noRd
mod_InputFeature_server <- function(id,
                                    seuratObj,
                                    assay,
                                    geneUpdateIndicator,
                                    scatterUpdateIndicator){
  moduleServer( id, function(input, output, session){
      ns <- session$ns

      ensure_async_workers <- function() {
          current_plan <- future::plan()
          if (!inherits(current_plan, "sequential")) {
              return(invisible(NULL))
          }

          configured_workers <- suppressWarnings(as.integer(session$userData$nCores %||% 2L))
          if (is.na(configured_workers) || configured_workers < 1L) {
              configured_workers <- 2L
          }

          future::plan(
              future::multisession,
              workers = min(configured_workers, future::availableCores())
          )
      }

      ## Two input mode: upload feature list or manually input
      observeEvent(input$featureInputMode, {
          if(input$featureInputMode == "Manual Select"){
              shinyjs::show("features")
              shinyjs::hide("featureList")
              shinyjs::hide("geneSet")
              ##updateSelectizeInput(
              ##    session = session,
              ##    inputId = 'features',
              ##    selected = NULL,
              ##    server = TRUE
              ##)
          }else{
              shinyjs::hide("features")
              shinyjs::show("geneSet")
              shinyjs::show("featureList")
          }
          updateSwitchInput(
              session = session,
              inputId = "moduleScore",
              value = FALSE
          )
      }, priority = -10)

      genes <- eventReactive(geneUpdateIndicator(), {
          req(isTruthy(seuratObj()), assay())
          get_backend_features(seuratObj(), assay = assay())
      })

      observeEvent(genes(), {
          updateSelectizeInput(
              session = session,
              inputId = 'features',
              selected = "",
              choices = genes(),
              server = TRUE
          )
      })

      storedFeatures <- reactive({
          ## values set from javascript
          ## indicates feature names already stored in javascript
          input$storedFeatures
      })

      uploadedFeatureList <- reactive({
          req(input$featureInputMode == "Upload Feature List")
          message("Updating featureList")
          if(!is.null(input$featureList)){
              if(str_detect(input$featureList$name, "\\.(tsv|txt)$")){
                  featureList <- read_tsv(input$featureList$datapath, col_names = c("geneSet", "geneName"))
              }else if(str_detect(input$featureList$name, "\\.csv$")){
                  featureList <- read_csv(input$featureList$datapath, col_names = c("geneSet", "geneName"))
              }else if(str_detect(input$featureList$name, "\\.xlsx$")){
                  featureList <- read_excel(input$featureList$datapath, col_names = c("geneSet", "geneName"))
              }else{
                  featureList <- NULL
              }
          }else{
              featureList <- NULL
          }
          featureList
      })

      observeEvent(uploadedFeatureList(), {
          req(uploadedFeatureList())

          geneSet <- unique(uploadedFeatureList()$geneSet)

          updateSelectizeInput(
              session = session,
              inputId = "geneSet",
              choices = geneSet,
              selected = "",
              server = TRUE
          )
      })

      cachedExprKeys <- reactive({
          input$cachedExprKeys
      })

      invoke_expression_transfer <- function(feature, create_sparkline = TRUE){
          req(isTruthy(seuratObj()), assay(), isTruthy(feature))
          ensure_async_workers()

          if (create_sparkline) {
              start_extract_expr(feature, session)
          }

          exprVersion <- geneUpdateIndicator()
          promise_assay <- assay()
          layer_ref <- tryCatch(
              get_bpcells_layer_ref(
                  seuratObj(),
                  assay = promise_assay,
                  backend_root = session$userData$backendDir
              ),
              error = function(error) {
                  showNotification(
                      ui = paste("Expression extraction failed:", conditionMessage(error)),
                      action = NULL,
                      duration = 6,
                      closeButton = TRUE,
                      type = "error",
                      session = session
                  )
                  removeNotification(id = "extract_expr_notification", session = session)
                  NULL
              }
          )
          if (is.null(layer_ref)) {
              return(invisible(NULL))
          }
          promise_filePath <- file.path(
              session$userData$tempDir,
              "expr",
               hash_md5(paste0("expr_", layer_ref$assay, "_", layer_ref$layer, "_", feature, "_", exprVersion))
           )

          expr_promise <- future_promise({
              extract_bpcells_expr_to_ipc(
                  matrix_dir = layer_ref$matrix_dir,
                  feature = feature,
                  output_file = promise_filePath
              )
              list(
                  geneName = feature,
                  assay = layer_ref$assay,
                  exprVersion = exprVersion,
                  exprFile = basename(promise_filePath)
              )
          }) %...>% (
              function(result) {
                  session$sendCustomMessage(type = "expr_ready", message = result)
                  result
              }
          ) %...!% (
              function(error) {
                  showNotification(
                      ui = paste("Expression export failed:", conditionMessage(error)),
                      action = NULL,
                      duration = 6,
                      closeButton = TRUE,
                      type = "error",
                      session = session
                  )
              }
          )

          promises::finally(
              expr_promise,
              function() {
                  removeNotification(id = "extract_expr_notification", session = session)
              }
          )
      }

      observeEvent(input$geneSet, {
          req(uploadedFeatureList(), input$geneSet,
              isTruthy(seuratObj()), assay(), genes())
          geneSetFeatures <- uploadedFeatureList() %>%
              filter(`geneSet` == input$geneSet) %>%
              pull(`geneName`)

          featuresNotDetected <- setdiff(geneSetFeatures, genes())
          if(length(featuresNotDetected)>0){
              showNotification(
                  ui = paste0("Features not detected: ", paste0(featuresNotDetected, collapse = ", ")),
                  action = NULL,
                  duration = 3,
                  closeButton = TRUE,
                  type = "default",
                  session = session
              )
          }

          filteredFeatures <- intersect(geneSetFeatures, genes())

          existFeatures <- intersect(filteredFeatures, storedFeatures())
          if(length(existFeatures)>0){
              showNotification(
                  ui = paste0("Features already queried: ", paste0(existFeatures, collapse = ", ")),
                  action = NULL,
                  duration = 3,
                  closeButton = TRUE,
                  type = "default",
                  session = session
              )
          }

          promise_assay <- assay()
          exprVersion <- geneUpdateIndicator()
          cacheKeys <- if (isTruthy(cachedExprKeys())) cachedExprKeys() else character()
          cachedFeatures <- filteredFeatures[vapply(filteredFeatures, function(feature) {
              paste0(exprVersion, cache_key_delim, promise_assay, cache_key_delim, feature) %in% cacheKeys
          }, logical(1))]

          for(feature in cachedFeatures){
              start_extract_expr(feature, session)
              session$sendCustomMessage(
                  type = "expr_cached",
                  message = list(
                      geneName = feature,
                      assay = promise_assay,
                      exprVersion = exprVersion
                  )
              )
          }

          selectedFeatures <- setdiff(filteredFeatures, union(storedFeatures(), cachedFeatures))

          for(feature in selectedFeatures){
              invoke_expression_transfer(feature, create_sparkline = TRUE)
              message("invoked extendedTask")
          }
      }, priority = -10, ignoreNULL = FALSE)

      observeEvent(input$clearFeature, {

          updateSwitchInput(
              session = session,
              inputId = "moduleScore",
              value = FALSE
          )
          ## clear gene expression stored
          session$sendCustomMessage(type = "clear_expr", "")

      }, priority = 10)


      moduleScore <- reactive({
          input$moduleScore
      })

      observeEvent(input$features, {

          req(isTruthy(seuratObj()), assay(), input$features)

          ##if(isTruthy(moduleScore())){
          ##    tryCatch({
          ##        moduleScore <- NULL
          ##        ## transfer moduleScore data
          ##        transfer_expression(moduleScore, session)
          ##        rm(moduleScore)
          ##        removeNotification(id = "extract_expr_notification", session)
          ##    }, error = function(e) {
          ##        removeNotification(id = "extract_expr_notification", session)
          ##        showNotification("ModuleScore Calculation failed, please check your gene list")
          ##        message("moduleScore failed:", "\n", e)
          ##    })
          ##}else{
          exprVersion <- geneUpdateIndicator()
          cacheKey <- paste0(exprVersion, cache_key_delim, assay(), cache_key_delim, input$features[1])

          if(input$features %in% storedFeatures()){
              showNotification(
                  ui = paste0("Features already queried: ", input$features),
                  action = NULL,
                  duration = 3,
                  closeButton = TRUE,
                  type = "default",
                  session = session
              )
          }else if (isTruthy(cachedExprKeys()) && cacheKey %in% cachedExprKeys()){
              start_extract_expr(input$features[1], session)
              session$sendCustomMessage(
                  type = "expr_cached",
                  message = list(
                      geneName = input$features[1],
                      assay = assay(),
                      exprVersion = exprVersion
                  )
              )
          }else{
              invoke_expression_transfer(input$features[1], create_sparkline = TRUE)
          }

      }, priority = -10, ignoreNULL = FALSE) # lower priority than plottingMode()

      observeEvent(input$cacheMissFeature, {
          req(isTruthy(seuratObj()), assay(), isTruthy(input$cacheMissFeature))
          invoke_expression_transfer(input$cacheMissFeature, create_sparkline = FALSE)
      }, priority = -10, ignoreNULL = TRUE)

      observeEvent(input$plotFeature, {
          message("Plotting featuerPlot...")
          scatterUpdateIndicator(scatterUpdateIndicator()+1)
      })

      filteredInputFeatures <- reactive({
          input$features
      })

      return(
          list(
              filteredInputFeatures = filteredInputFeatures,
              moduleScore = moduleScore
          )
      )

  })
}

## To be copied in the UI
# mod_InputFeature_ui("FeaturePlot_1")

## To be copied in the server
# mod_InputFeature_server("FeaturePlot_1")
