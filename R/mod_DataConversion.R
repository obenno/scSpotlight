#' DataConversion UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList fileInput selectInput actionButton downloadButton
mod_DataConversion_ui <- function(id){
  ns <- NS(id)

  tagList(
    fileInput(
      ns("conversionInput"),
      tagList(
        "Upload Source File",
        infoIcon("Convert processed Seurat RDS or Scanpy/AnnData h5ad files into BPCells bundles or Scanpy-standard h5ad exports", "right")
      ),
      multiple = FALSE,
      width = "100%",
      accept = c(".rds", ".h5ad")
    ),
    selectizeInput(
      inputId = ns("conversionFormat"),
      label = "Output Format",
      choices = c("BPCells" = "bpcells", "h5ad" = "h5ad"),
      selected = "bpcells",
      multiple = FALSE,
      options = list(dropdownParent = "body"),
      width = NULL
    ),
    actionButton(
      ns("conversionTrigger"),
      "Convert",
      style = "width:200px",
      class = "border border-1 border-primary shadow"
    ),
    shinyjs::hidden(
      downloadButton(
        ns("conversionDownload"),
        "Download Converted File",
        style = "width:200px"
      )
    )
  )
}

#' DataConversion Server Functions
#'
#' @noRd
mod_DataConversion_server <- function(id){
  moduleServer(id, function(input, output, session){
    ns <- session$ns

    source_file_path <- reactive({
      req(isTruthy(input$conversionInput), isTruthy(input$conversionInput$datapath))
      input$conversionInput$datapath
    })

    source_file_name <- reactive({
      req(isTruthy(input$conversionInput), isTruthy(input$conversionInput$name))
      input$conversionInput$name
    })

    trigger_download <- function() {
      shinyjs::click("conversionDownload")
    }

    observeEvent(input$conversionTrigger, {
      req(isTruthy(source_file_path()), isTruthy(input$conversionFormat))
      trigger_download()
    }, ignoreNULL = TRUE)

    output$conversionDownload <- downloadHandler(
      filename = function() {
        req(isTruthy(source_file_name()), isTruthy(input$conversionFormat))
        base_name <- sub("\\.[^.]+$", "", basename(source_file_name()))

        if (identical(input$conversionFormat, "h5ad")) {
          return(paste0(base_name, ".h5ad"))
        }

        paste0(base_name, ".tar.gz")
      },
      content = function(file) {
        req(isTruthy(source_file_path()), isTruthy(input$conversionFormat))

        if (identical(input$conversionFormat, "h5ad")) {
          progressr::withProgressShiny(
            {
              convert_progress <- progressr::progressor(steps = 2)
              convert_progress(message = "Preparing Scanpy export")
              convert_to_scanpy_h5ad(source_file_path(), output_file = file)
              convert_progress(message = "h5ad conversion ready")
            },
            message = "Converting to h5ad...",
            detail = "Preparing export"
          )
          return(invisible(NULL))
        }

        progressr::withProgressShiny(
          {
            convert_progress <- progressr::progressor(steps = 2)
            convert_progress(message = "Preparing BPCells bundle")
            convert_to_bpcells_bundle(source_file_path(), output_file = file)
            convert_progress(message = "BPCells bundle ready")
          },
          message = "Converting to BPCells bundle...",
          detail = "Preparing export"
        )
      },
      contentType = NULL,
      outputArgs = list()
    )

    outputOptions(output, "conversionDownload", suspendWhenHidden = FALSE)
  })
}
