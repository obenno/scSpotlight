#' AssignCellCluster UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_AssignCellCluster_ui <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      span(
        span(id = ns("selectedCellsText"), "0 Cells Selected"),
        class = "badge text-bg-primary mb-2",
        style = "font-size: 1em;"
      )
    ),
    p(id = ns("selectCellFromCat"), tags$b("Select Cells from Category")),
    selectInput(
      inputId = ns("chosenGroup"),
      label = "Identities from group.by",
      choices = "None",
      selected = "None",
      multiple = TRUE,
      selectize = FALSE,
      width = NULL
    ),
    selectInput(
      inputId = ns("chosenSplit"),
      label = "Identities from split.by",
      choices = "None",
      selected = "None",
      multiple = TRUE,
      selectize = FALSE,
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
      "Subset Dataset to Selected Cells",
      style = "display: inline-block; margin-bottom: 0.5rem",
      infoIcon(
        "Switch on to subset original dataset and only keep the selected cells",
        "left"
      )
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
#' @importFrom DBI dbDisconnect
#'
#' @noRd
mod_AssignCellCluster_server <- function(
  id,
  seuratObj,
  selectedPoints,
  geneUpdateIndicator,
  metaUpdateIndicator,
  reductionUpdateIndicator
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    seuratObj_orig <- reactiveVal(NULL)

    manuallySelectedCells <- reactive({
      ## Do not use req() here, or it will block the validation chain
      if (isTruthy(selectedPoints()) && isTruthy(seuratObj())) {
        all_cells <- rownames(seuratObj()[[]])
        selected_idx <- as.integer(selectedPoints()) + 1L
        selected_idx <- selected_idx[
          selected_idx >= 1L & selected_idx <= length(all_cells)
        ]
        cells <- all_cells[selected_idx]
      } else {
        cells <- NULL
      }
      message("cells is: ", paste0(cells, collapse = ","))
      cells
    })

    selectedCellsPayload <- reactive({
      input$selectedCellsPayload
    })

    selectedCells <- eventReactive(
      list(
        manuallySelectedCells(),
        selectedCellsPayload()
      ),
      {
        if (isTruthy(manuallySelectedCells())) {
          cells <- manuallySelectedCells()
        } else if (isTruthy(selectedCellsPayload())) {
          cells <- selectedCellsPayload()
        } else {
          cells <- NULL
        }
        ##message("selectedCells: ", cells)
        cells
      },
      ignoreNULL = FALSE
    )

    observeEvent(input$assign, {
      message("Triggered...")
      if (!isTruthy(input$newMeta)) {
        showNotification(
          ui = "Please input a new category name...",
          action = NULL,
          duration = 3,
          closeButton = TRUE,
          type = "default",
          session = session
        )
      } else if (!isTruthy(selectedCells())) {
        showNotification(
          ui = "Please select cells before assigning",
          action = NULL,
          duration = 3,
          closeButton = TRUE,
          type = "default",
          session = session
        )
      } else if (!isTruthy(input$assignAs)) {
        showNotification(
          ui = "Please input a valid label for the new cell type",
          action = NULL,
          duration = 3,
          closeButton = TRUE,
          type = "default",
          session = session
        )
      } else {
        req(selectedCells())
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

    mod_SubsetCells_server(
      "subsetCells",
      seuratObj,
      seuratObj_orig,
      selectedCells,
      geneUpdateIndicator,
      metaUpdateIndicator,
      reductionUpdateIndicator
    )
  })
}

## To be copied in the UI
# mod_AssignCellCluster_ui("AssignCellCluster_1")

## To be copied in the server
# mod_AssignCellCluster_server("AssignCellCluster_1")
