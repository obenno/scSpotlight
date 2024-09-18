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
      div(
          span(
              textOutput(ns("selectedCellsText")),
              class = "badge text-bg-primary mb-2",
              style = "font-size: 1em;"
          )
      ),
      p(id = ns("selectCellFromCat"),
        tags$b("Select Cells from Category")),
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
      ),
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
      mod_SubsetCells_ui(ns("subsetCells"))
  )
}

#' AssignCellCluster Server Functions
#'
#' @importFrom scales label_comma
#' @importFrom arrow arrow_table
#' @importFrom dplyr pull filter mutate
#' @importFrom tibble tibble column_to_rownames
#'
#' @noRd 
mod_AssignCellCluster_server <- function(id,
                                         duckdbConnection,
                                         selectedPoints,
                                         categorySelectedCells,
                                         group.by,
                                         split.by,
                                         metaColLevels,
                                         scatterReductionIndicator,
                                         scatterColorIndicator){
  moduleServer( id, function(input, output, session){
    ns <- session$ns

    newMetaData <- reactiveVal(NULL)

    observe({
        if(isTruthy(manuallySelectedCells())){

            shinyjs::hide("selectCellFromCat")
            shinyjs::hide("chosenGroup")
            shinyjs::hide("chosenSplit")

        }else if(split.by() == "None" && group.by() == "None"){

            shinyjs::show("selectCellFromCat")
            shinyjs::show("chosenGroup")
            shinyjs::hide("chosenSplit")

        }else if(split.by() == "None" && group.by() != "None"){

            updateSelectInput(
                inputId = "chosenGroup",
                label = "Identities from group.by",
                choices = metaColLevels()[["groupBy"]],
                selected = NULL
            )

            shinyjs::show("selectCellFromCat")
            shinyjs::show("chosenGroup")
            shinyjs::hide("chosenSplit")

        }else if(split.by() != "None" && group.by() != "None"){
            updateSelectInput(
                inputId = "chosenGroup",
                label = "Identities from group.by",
                choices = metaColLevels()[["groupBy"]],
                selected = NULL
            )
            updateSelectInput(
                inputId = "chosenSplit",
                label = "Identities from split.by",
                choices = metaColLevels()[["splitBy"]],
                selected = NULL
            )

            shinyjs::show("selectCellFromCat")
            shinyjs::show("chosenGroup")
            shinyjs::show("chosenSplit")
        }
    })

    input_group.by <- reactive({

        if(group.by() == "None"){
            NULL
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

    observeEvent(list(
        input$chosenGroup,
        input$chosenSplit
    ), {
        req(duckdbConnection())
        req(input_group.by())
        req(!isTruthy(selectedPoints()))

        if(isTruthy(input_split.by())){
           req(input$chosenSplit)
        }
        message("processing selectPointsByCategory")
        message("input$chosenGroup: ", isolate(input$chosenGroup))
        message("input$chosenSplit: ", isolate(input$chosenSplit))
        session$sendCustomMessage(
                    type = "selectPointsByCategory",
                    list(groupBy = input_group.by(),
                         splitBy = input_split.by(),
                         selectedGroupBy = input$chosenGroup,
                         selectedSplitBy = input$chosenSplit)
                )
    })

    manuallySelectedCells <- reactive({
        req(duckdbConnection())
        if(isTruthy(selectedPoints())){
            d <- queryDuckMeta(duckdbConnection())
            cells <- d %>%
                mutate(idx = row_number()) %>%
                filter(idx %in% selectedPoints()) %>%
                rownames()
        }else{
            cells <- NULL
        }
        cells
    })

    selectedCells <- eventReactive(list(
        manuallySelectedCells(),
        categorySelectedCells()
    ),{
        req(duckdbConnection())
        req(group.by())
        req(split.by())
        if(isTruthy(manuallySelectedCells())){
            cells <- manuallySelectedCells()
        }else if(isTruthy(categorySelectedCells())){
            cells <- categorySelectedCells()
        }else{
            cells <- NULL
        }
        ##message("selectedCells: ", cells)
        cells
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

    output$selectedCellsText <- renderText({
        nCells <- 0
        if(isTruthy(selectedCells())){
            nCells <- length(selectedCells()) %>%
                label_comma()()
        }
        paste0(nCells, " Cells Selected")
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
        }else if(!isTruthy(manuallySelectedCells()) && (!isTruthy(input$chosenGroup) || isTruthy(input$chosenGroup == "None"))){
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
            ## check if category name already exists
            message("Initializing new meta column...")
            ## ask client to update metaData
            session$sendCustomMessage(
                      type = "addNewMeta",
                      list(
                        colName = input$newMeta,
                        colValue = input$assignAs
                      )
                    )

            ## show finishing notification
            showNotification(
                ui = "Successfully assigned...",
                action = NULL,
                duration = 3,
                closeButton = TRUE,
                type = "default",
                session = session
            )

            ## Ask regl-scatter to deselect
            ##message("Deselect points...")
            ##reglScatter_deselect(session)
        }

    })

    ##seuratObj_orig <- reactiveVal(NULL)
    ##subset_obj <- mod_SubsetCells_server(
    ##    "subsetCells",
    ##    seuratObj,
    ##    seuratObj_orig,
    ##    selectedCells,
    ##    scatterReductionIndicator,
    ##    scatterColorIndicator
    ##)

    ##return(newMetaData)
  })
}

## To be copied in the UI
# mod_AssignCellCluster_ui("AssignCellCluster_1")

## To be copied in the server
# mod_AssignCellCluster_server("AssignCellCluster_1")
