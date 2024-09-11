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
                  choices = "",
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
#' @noRd
mod_InputFeature_server <- function(id, duckdbConnection, assay){
  moduleServer( id, function(input, output, session){
      ns <- session$ns

      ## Two input mode: upload feature list or manually input
      observeEvent(
          list(
              input$featureInputMode,
              duckdbConnection(),
              assay()
          ), {
          if(input$featureInputMode == "Manual Select"){
              shinyjs::show("features")
              shinyjs::hide("featureList")
              shinyjs::hide("geneSet")

              req(duckdbConnection(), assay())
              genes <- queryDuckFeatures(
                  con = duckdbConnection(),
                  assay = assay()
              )
              updateSelectizeInput(
                  session = session,
                  inputId = 'features',
                  selected = "",
                  choices = c("", genes),
                  server = TRUE
              )
          }else{
              shinyjs::hide("features")
              shinyjs::show("geneSet")
              shinyjs::show("featureList")

              ##selectedGeneSet <- unique(uploadedFeatureList()$geneSet)[1]
              ##geneSet <- unique(uploadedFeatureList()$geneSet)

          }
          updateSwitchInput(
              session = session,
              inputId = "moduleScore",
              value = FALSE
          )
      }, priority = -10)


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

      observeEvent(input$clearFeature, {
          req(duckdbConnection(), assay())
          if(isTruthy(duckdbConnection()) &&
             isTruthy(assay())){
              genes <- queryDuckFeatures(
                  con = duckdbConnection(),
                  assay = assay()
              )
          }else{
              genes <- NULL
          }
          updateSelectizeInput(
              session = session,
              inputId = 'features',
              selected = "",
              choices = c("", genes),
              server = TRUE
          )
          updateSwitchInput(
              session = session,
              inputId = "moduleScore",
              value = FALSE
          )
          ## clear gene expression stored
          session$sendCustomMessage(type = "clear_expr", "")

      }, priority = 10)

      ## selectedFeatures return user input feature list or uploaded list
      ## feature not included in the dataset will be discarded
      userInputFeatures <- reactive({

          if(input$featureInputMode == "Upload Feature List" &&
             isTruthy(input$geneSet)){
              userInputFeatures <- uploadedFeatureList() %>%
                  filter(`geneSet` == input$geneSet) %>%
                  pull(`geneName`)
          }else if(input$featureInputMode == "Manual Select"){ ##&&
              userInputFeatures <- input$features
          }else{
              userInputFeatures <- NULL
          }

          userInputFeatures

      })

      ## Check if featuers exist in the object
      filteredInputFeatures <- eventReactive(userInputFeatures(), {
          req(duckdbConnection(), assay())
          if(isTruthy(userInputFeatures())){
              genes <- queryDuckFeatures(
                  con = duckdbConnection(),
                  assay = assay()
              )
              featuresNotDetected <- setdiff(userInputFeatures(), genes)
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
              filteredFeatures <- intersect(userInputFeatures(), genes)
          }else{
              filteredFeatures <- NULL
          }

          return(filteredFeatures)
      }, ignoreNULL = FALSE)

      moduleScore <- reactive({
          input$moduleScore
      })

      ## Extracting gene expression or calculating module score
      ## Init expression extraction as extendedTask class
      extract_expression <- ExtendedTask$new(function(con, assay, features, layer = "data", filePath) {
        future_promise({
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
          write_expr_raw(expr, filePath)
          return(basename(filePath))
        })
      })

      observeEvent(filteredInputFeatures(), {

          req(duckdbConnection())
          message("filteredInputFeatures() : ", paste(filteredInputFeatures(), collapse=","))

          if(isTruthy(filteredInputFeatures())){
              ##showNotification(
              ##    ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
              ##                 role = "status",
              ##                 span(class = "sr-only", "Loading...")),
              ##             "Extracting expression values..."),
              ##    action = NULL,
              ##    duration = NULL,
              ##    closeButton = FALSE,
              ##    type = "default",
              ##    id = "extract_expr_notification",
              ##    session = session
              ##)

              if(isTruthy(moduleScore())){
                  tryCatch({
                      moduleScore <- duckModuleScore(
                          con = duckdbConnection(),
                          assay = assay(),
                          features = filteredInputFeatures()
                      )
                      ## transfer moduleScore data
                      transfer_expression(moduleScore, session)
                      rm(moduleScore)
                      removeNotification(id = "extract_expr_notification", session)
                  }, error = function(e) {
                      removeNotification(id = "extract_expr_notification", session)
                      showNotification("ModuleScore Calculation failed, please check your gene list")
                      message("moduleScore failed:", "\n", e)
                  })
              }else{
                con <- duckdbConnection()
                selectedAssay <- assay()
                inputFeatures <- filteredInputFeatures()

                extract_expression$invoke(con = con,
                                          assay = selectedAssay,
                                          features = inputFeatures,
                                          filePath = file.path(session$userData$exprTempDir, hash_md5(inputFeatures[1])))
                message("invoked extendedTask")
                start_extract_expr(inputFeatures, session)
              }

          }
          ##scatterColorIndicator(scatterColorIndicator()+1)
      }, priority = -10, ignoreNULL = FALSE) # lower priority than plottingMode()

      observe({
        message("ExtendedTask finished...")
        session$sendCustomMessage(type = "expr_ready", extract_expression$result())
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
