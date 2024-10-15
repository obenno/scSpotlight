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
        selectInput(
            ns("featureInputMode"),
            "Choose Input Mode",
            choices = c("Manual Select", "Upload Feature List"),
            selected = "Manual Select",
            multiple = FALSE,
            selectize = TRUE,
            width = NULL
        ),
        selectInput(
            ns("features"),
            "Input Gene Names",
            selected = NULL,
            choices = NULL,
            multiple = FALSE,
            selectize = TRUE,
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
              selectInput(
                  ns("geneSet"),
                  "Choose Gene Set",
                  choices = NULL,
                  selected = NULL,
                  multiple = FALSE,
                  selectize = TRUE,
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
#' @importFrom promises future_promise %...>% %...!%
#' @importFrom cli hash_md5
#' @importFrom qs qsave
#' @noRd
mod_InputFeature_server <- function(id, duckdbConnection, assay, scatterColorIndicator){
  moduleServer( id, function(input, output, session){
      ns <- session$ns

      ## Two input mode: upload feature list or manually input
      observeEvent(input$featureInputMode, {
          if(input$featureInputMode == "Manual Select"){
              shinyjs::show("features")
              shinyjs::hide("featureList")
              shinyjs::hide("geneSet")
              updateSelectizeInput(
                  session = session,
                  inputId = 'features',
                  selected = NULL
                  ##server = TRUE
              )
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

      genes <- reactive({
          req(duckdbConnection(), assay())
          genes <- queryDuckFeatures(
              con = duckdbConnection(),
              assay = assay()
          )
      })

      observeEvent(genes(), {
          updateSelectizeInput(
              session = session,
              inputId = 'features',
              selected = "",
              choices = genes()
              ##server = TRUE
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

          updateSelectInput(
              session = session,
              inputId = "geneSet",
              choices = geneSet,
              selected = ""
          )
      })

      ## Extracting gene expression or calculating module score
      ## Init expression extraction as extendedTask class
      ## Note DBI connection cannot be shared accross R threads
      ## https://github.com/rstudio/pool/issues/83
      ## https://cran.r-project.org/web/packages/future/vignettes/future-4-non-exportable-objects.html
      ## future codes needs to be installed before testing:
      ## https://github.com/HenrikBengtsson/future/issues/206
      extract_expression <- ExtendedTask$new(function(dbFile, assay, features, layer = "data", filePath) {
          future_promise({

              con <- DBI::dbConnect(duckdb::duckdb(),
                                    dbdir = dbFile,
                                    read_only = TRUE)
              on.exit(DBI::dbDisconnect(con))
              expr <- queryDuckExpr(
                  con = con,
                  assay = assay,
                  layer = layer,
                  features = features,
                  populateZero = TRUE, # populate zero
                  cellNames = FALSE # remove cellnames to shrink object size
              )

              if(file.exists(filePath)){
                  file.remove(filePath)
              }
              qsave(expr, filePath, preset = "high")
              return(basename(filePath))
          })
      })

      observeEvent(input$geneSet, {
          req(uploadedFeatureList(), input$geneSet,
              duckdbConnection(), assay(), genes())
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

          selectedFeatures <- setdiff(filteredFeatures, storedFeatures())
          promise_dbFile <- session$userData$duckdb
          promise_assay <- assay()

          for(feature in selectedFeatures){
              start_extract_expr(feature, session)
              promise_feature <- feature
              promise_filePath <- file.path(session$userData$tempDir, hash_md5(promise_feature))
              extract_expression$invoke(dbFile = promise_dbFile,
                                        assay = promise_assay,
                                        features = promise_feature,
                                        filePath = promise_filePath)
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

     extracted_expr <- reactiveVal(NULL)
      observeEvent(input$features, {

          req(duckdbConnection(), assay(), input$features)

          ##if(isTruthy(moduleScore())){
          ##    tryCatch({
          ##        moduleScore <- duckModuleScore(
          ##            con = duckdbConnection(),
          ##            assay = assay(),
          ##            features = filteredInputFeatures()
          ##        )
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
          if(input$features %in% storedFeatures()){
              showNotification(
                  ui = paste0("Features already queried: ", input$features),
                  action = NULL,
                  duration = 3,
                  closeButton = TRUE,
                  type = "default",
                  session = session
              )
          }else{

              start_extract_expr(input$features, session)
              promise_dbFile <- session$userData$duckdb
              promise_assay <- assay()
              promise_features <- input$features[1]
              promise_filePath <- file.path(session$userData$tempDir, hash_md5(promise_features))
              extract_expression$invoke(dbFile = promise_dbFile,
                                        assay = promise_assay,
                                        features = promise_features,
                                        filePath = promise_filePath)
          }

          ##scatterColorIndicator(scatterColorIndicator()+1)
      }, priority = -10, ignoreNULL = FALSE) # lower priority than plottingMode()

      observeEvent(input$plotFeature, {
          message("Plotting featuerPlot...")
          scatterColorIndicator(scatterColorIndicator()+1)
      })


      observeEvent(extract_expression$status(), {

          if(extract_expression$status() == "success"){
              session$sendCustomMessage(type = "expr_ready", extract_expression$result())
          }else{
              message("extract_expression error: ", extract_expression$result())
          }
      }, ignoreNULL = FALSE)

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
