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
            choices = c("Manual Input", "Upload Feature List"),
            selected = "Manual Input",
            multiple = FALSE,
            selectize = TRUE,
            width = NULL
        ),
        textAreaInput(
            ns("features"),
            "Input Gene Names",
            value = NULL,
            width = NULL,
            height = "200px",
            placeholder = paste("MS4A1", "GNLY","CD3E", "CD14",
                                "FCGR3A", "LYZ", "PPBP", sep="\n")
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
        ##actionButton(
        ##    ns("checkFeature"),
        ##    "Check",
        ##    style = "position:relative; float:right",
        ##    class = "border border-1 border-primary shadow mb-2"
        ##),
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
mod_InputFeature_server <- function(id, obj){
  moduleServer( id, function(input, output, session){
      ns <- session$ns

      observeEvent(input$featureInputMode, {
          if(input$featureInputMode == "Manual Input"){
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
      })

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

      ## Not sure if the reactiveVal inited here is global, guess not
      inputFeatureList <- reactive({
          if(isTruthy(input$features)){
              featureList <- input$features %>%
                  strsplit(split = "\n") %>%
                  unlist()
              featureList <- featureList[featureList != ""] %>%
                  unique()
          }else{
              featureList <- NULL
          }
          ##message("inputFeatureList is ", inputFeatureList())
      })

      observeEvent(input$clearFeature, {

          updateTextAreaInput(
              session = session,
              inputId = "features",
              label = "Input Gene Names",
              value = ""
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
          }else if(input$featureInputMode == "Manual Input"){ ##&&
                   ##isTruthy(inputFeatureList())){
              ##message("inputFeatureList() is ", inputFeatureList())
              userInputFeatures <- inputFeatureList()
          }else{
              userInputFeatures <- NULL
          }
          userInputFeatures
          ##intersect(selectedFeatures, rownames(seuratObj_final()))
      }) %>% debounce(millis = 1000)

      ## Check if featuers exist in the object
      filteredInputFeatures <- eventReactive(userInputFeatures(), {

          if(isTruthy(userInputFeatures()) && isTruthy(obj())){
              genes <- rownames(obj())
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

      ## Check if any group of genes not in the dataset
      ##geneSet <- unique(uploadedFeatureList()$geneSet)
      ##removedGroup <- c()
      ##for(i in geneSet){
      ##    genes <- uploadedFeatureList() %>%
      ##        filter(`geneSet` == {{ i }}) %>%
      ##        pull(`geneName`)
      ##    if(!any(genes %in% rownames(seuratObj_final()))){
      ##        removedGroup <- c(removedGroup, i)
      ##    }
      ##}
      ##geneSet <- setdiff(geneSet, removedGroup)
      ##if(length(removedGroup)>0){
      ##    showNotification(
      ##        ui = paste0("Group ", paste(removedGroup, collapse = ", "), " has no feature detected."),
      ##        action = NULL,
      ##        duration = 3,
      ##        closeButton = TRUE,
      ##        type = "default",
      ##        session = session
      ##    )
      ##}

  })
}

## To be copied in the UI
# mod_InputFeature_ui("FeaturePlot_1")

## To be copied in the server
# mod_InputFeature_server("FeaturePlot_1")
