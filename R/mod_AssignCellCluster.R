#' AssignCellCluster UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_AssignCellCluster_ui <- function(id){
  ns <- NS(id)
  tagList(
      uiOutput(ns("selectCellUI")),
      textInput(
          ns("newMeta"),
          "New Category Name",
          value = NULL,
          width = NULL,
          placeholder = "cellType"
      ),
      textInput(
          ns("assignAs"),
          "Assign As",
          value = NULL,
          width = NULL,
          placeholder = "T cell"
      ),
      actionButton(
          ns("assign"),
          "Assign",
          icon = icon("pencil", lib = "glyphicon"),
          width = "100px",
          style = "position:relative; float:right;",
          class = c("border", "border-1", "border-primary", "shadow", "mb-2")
      ),
      span(
          "Subset Dataset to Selected Cells", style = "display: inline-block; margin-bottom: 0.5rem",
          infoIcon("Switch on to subset original dataset and only keep the selected cells", "left")
      ),
      switchInput(
          inputId = ns("subsetData"),
          label = NULL,
          size = "mini",
          value = FALSE
      )
  )
}

#' AssignCellCluster Server Functions
#'
#' @importFrom stringr str_sort
#'
#' @noRd 
mod_AssignCellCluster_server <- function(id,
                                         seuratObj,
                                         selectedPoints,
                                         group.by,
                                         split.by){
  moduleServer( id, function(input, output, session){
    ns <- session$ns


    output$selectCellUI <- renderUI({
        if(isTruthy(manuallySelectedCells())){
            tagList(
                span(
                    textOutput("manuallySelectedCellsText"),
                    class = "badge text-bg-primary mb-2",
                    style = "font-size: 1em;"
                )
            )
            ##verbatimTextOutput("manuallySelectedCellsText")
        }else if(split.by() == "None"){
            if(group.by() == "None"){
                tagList(
                    p(tags$b("Select Cells from Category")),
                    selectInput(
                        inputId = ns("chosenGroup"),
                        label = "Identities from group.by",
                        choices = "None",
                        selected = "None",
                        multiple = TRUE,
                        selectize = TRUE,
                        width = NULL
                    )
                )
            }else{
                group.by.levels <- seuratObj()[[group.by()]] %>%
                    pull() %>%
                    as.factor() %>% levels()
                tagList(
                    p(
                        tags$b("Select Cells from Category")##,
                        ##class = "mb-2"
                    ),
                    selectInput(
                        inputId = ns("chosenGroup"),
                        label = "Identities from group.by",
                        choices = group.by.levels,
                        selected = NULL,
                        multiple = TRUE,
                        selectize = TRUE,
                        width = NULL
                    )
                )
            }
        }else{
            tagList(
                p(
                    tags$b("Select Cells from Category")##,
                    ##class = "mb-2"
                ),
                selectInput(
                    inputId = ns("chosenGroup"),
                    label = "Identities from group.by",
                    choices = "None",
                    selected = "None",
                    multiple = TRUE,
                    selectize = TRUE,
                    width = NULL
                ),
                selectInput(
                    inputId = ns("chosenSplit"),
                    label = "Identities from split.by",
                    choices = "None",
                    selected = "None",
                    multiple = TRUE,
                    selectize = TRUE,
                    width = NULL
                )
            )
        }
    })

    input_group.by <- reactive({

        if(group.by() == "None"){
            "orig.ident"
        }else{
            group.by()
        }
    })

    input_split.by <- reactive({

        if(split.by() == "None"){
            NULL
        }else{
            split.by()
        }
    })

    categorySelectedCells <- reactive({
        req(seuratObj())
        req(input$chosenGroup)
        req(group.by())
        req(split.by())
        req(!isTruthy(manuallySelectedCells()))

        if(isTruthy(input_split.by()) &&
           isTruthy(input$chosenSplit)){
            selectedCells <- seuratObj()[[c(input_group.by(), input_split.by())]] %>%
                filter(
                    !!as.symbol(input_group.by()) %in% input$chosenGroup,
                    !!as.symbol(input_split.by()) %in% input$chosenSplit
                ) %>%
                rownames()
        }else{
            selectedCells <- seuratObj()[[input_group.by()]] %>%
                filter(!!as.symbol(input_group.by()) %in% input$chosenGroup) %>%
                rownames()
        }
    })

    manuallySelectedCells <- reactive({
        selectedPoints()
    })

    ##observe({
    ##    ##req(event_data("plotly_selected"))
    ##    selectedData <- event_data("plotly_selected")
    ##    if(isTruthy(selectedData) && length(selectedData)>0){
    ##        cells <- event_data("plotly_selected") %>%
    ##            pull(customdata)
    ##        manuallySelectedCells(cells)
    ##    }else{
    ##        manuallySelectedCells(NULL)
    ##    }
    ##})

    selectedCells <- reactive({
        ##req(seuratObj_final())
        req(group.by())
        req(split.by())
        if(isTruthy(manuallySelectedCells())){
            manuallySelectedCells()
        }else{
            categorySelectedCells()
        }

    })

    ## Always shoot a notification for number of selected cells
    observeEvent(selectedCells(), {
        req(selectedCells())
        nCells <- length(selectedCells())
        showNotification(
            ui = paste0(nCells, " Cells Selected."),
            action = NULL,
            duration = 3,
            closeButton = TRUE,
            type = "warning",
            session = session
        )
    })

    ## update group.by and split.by widget when manuallySelectedCells() changes
    observe({

        req(seuratObj())
        req(input_group.by())
        req(!(seuratObj()[[input_group.by()]] %>% pull() %>% is.numeric))

        manuallySelectedCells()

        group.by.levels <- seuratObj()[[input_group.by()]] %>%
            pull() %>%
            as.factor() %>% levels()
        updateSelectInput(
            session = session,
            inputId = "chosenGroup",
            label = "Identities from group.by",
            choices = group.by.levels,
            selected = NULL
        )

        req(input_split.by())
        req(!(seuratObj()[[input_split.by()]] %>% pull() %>% is.numeric))
        split.by.levels <- seuratObj()[[input_split.by()]] %>%
            pull() %>%
            as.factor() %>% levels()
        updateSelectInput(
            session = session,
            inputId = "chosenSplit",
            label = "Identities from split.by",
            choices = split.by.levels,
            selected = NULL
        )
    })

    output$manuallySelectedCellsText <- renderText({
        ##req(manuallySelectedCells())
        ##nCells <- length(manuallySelectedCells())
        ##message("nCells: ", nCells)
        ##paste0(nCells, " Cells Selected")
        ##"Yes"
        111
    })

    metaCols <- reactive({
        req(seuratObj())
        seuratObj()[[]] %>%
            ##select(-starts_with(c("nFeature_", "nCount_", "percent.mt"))) %>%
            colnames()
    })

    observeEvent(input$assign, {
        message("Triggered...")
        if(!isTruthy(input$newMeta)){
            showNotification(
                ui = "Please input a new category name...",
                action = NULL,
                duration = 3,
                closeButton = TRUE,
                type = "default",
                session = session
            )
        }else if((!isTruthy(input$chosenGroup) || input$chosenGroup =="None") && !isTruthy(manuallySelectedCells())){
            showNotification(
                ui = "Please choose a group before assigning",
                action = NULL,
                duration = 3,
                closeButton = TRUE,
                type = "default",
                session = session
            )
        }else if(!isTruthy(input$assignAs)){
            showNotification(
                ui = "Please input a valid label for the new cell type",
                action = NULL,
                duration = 3,
                closeButton = TRUE,
                type = "default",
                session = session
            )
        }else{
            req(selectedCells())
            message("input$chosenGroup is ", input$chosenGroup)
            ## check if category name already exists
            message("Initializing new meta column...")
            if(!(input$newMeta %in% metaCols())){
                cell_ids <- Cells(seuratObj())
                obj <- AddMetaData(seuratObj(), rep("unknown", length(cell_ids)), col.name = input$newMeta)
            }else{
                obj <- seuratObj()
            }


            message("selected Cells: ", length(selectedCells()))
            obj[[input$newMeta]][selectedCells(), ] <- input$assignAs

            ## Reset manuallySelectedCells
            manuallySelectedCells(NULL)
            ## assign seuratObj_final()
            seuratObj(obj)
            ## show finishing notification
            showNotification(
                ui = "Successfully assigned...",
                action = NULL,
                duration = 3,
                closeButton = TRUE,
                type = "default",
                session = session
            )
        }

    })
  })
}

## To be copied in the UI
# mod_AssignCellCluster_ui("AssignCellCluster_1")

## To be copied in the server
# mod_AssignCellCluster_server("AssignCellCluster_1")
