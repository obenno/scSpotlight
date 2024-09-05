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
            multiple = TRUE,
            selectize = TRUE,
            width = NULL
        ),
        div(
            ## button needs to be wrapped in a div element to make
            ## the float:right style work
            actionButton(
                ns("clearFeature"),
                "Clear",
                style = "position:relative; float:right;",
                class = "border border-1 border-primary shadow mb-2"
            )
        ),
        shinyjs::hidden(fileInput(
            ns("featureList"),
            "or Upload Gene Set List",
            multiple = FALSE,
            width = "100%",
            accept = c(".xlsx", ".csv", ".tsv", ".txt")
        )),
        uiOutput(ns("uploadedFeatureSet")),
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
        ##uiOutput("exprCutoff")

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
#' @noRd
mod_InputFeature_server <- function(id, duckdbConnection, assay){
  moduleServer( id, function(input, output, session){
      ns <- session$ns


      observe({
          if(input$featureInputMode == "Manual Select"){
              if(isTruthy(duckdbConnection()) &&
                 isTruthy(assay())){
                  genes <- queryDuckFeatures(
                      con = duckdbConnection(),
                      assay = assay()
                  )
                  message("genes: ", length(genes))
              }else{
                  genes <- NULL
              }

              updateSelectizeInput(
                  session = session,
                  inputId = 'features',
                  selected = NULL,
                  choices = genes,
                  server = TRUE
              )
          }
      }, priority = 10)

      ## Two input mode: upload feature list or manually input
      observeEvent(input$featureInputMode, {
          if(input$featureInputMode == "Manual Select"){
              shinyjs::show("features")
              shinyjs::show("clearFeature")
              shinyjs::hide("featureList")


          }else{
              shinyjs::hide("features")
              shinyjs::hide("clearFeature")
              shinyjs::show("featureList")
          }
          updateSwitchInput(
              session = session,
              inputId = "moduleScore",
              value = FALSE
          )
      }, priority = -10)

      uploadedFeatureList <- reactive({
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

      output$uploadedFeatureSet <- renderUI({

          if(isTruthy(uploadedFeatureList()) &&
             input$featureInputMode == "Upload Feature List"){

              selectedGeneSet <- unique(uploadedFeatureList()$geneSet)[1]
              geneSet <- unique(uploadedFeatureList()$geneSet)

              selectInput(
                  ns("geneSet"),
                  "Choose Gene Set",
                  choices = geneSet,
                  selected = selectedGeneSet,
                  multiple = FALSE,
                  selectize = TRUE,
                  width = NULL
              ) %>%
                  tagAppendAttributes(class = c("mb-1"))
          }else{
              NULL
          }

      })

      observeEvent(input$clearFeature, {

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
              selected = NULL,
              choices = genes,
              server = TRUE
          )
          updateSwitchInput(
              session = session,
              inputId = "moduleScore",
              value = FALSE
          )

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

          if(isTruthy(userInputFeatures()) &&
             isTruthy(duckdbConnection()) &&
             isTruthy(assay())){
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
