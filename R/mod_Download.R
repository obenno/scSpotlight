#' Download UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_Download_ui <- function(id){
  ns <- NS(id)

  tagList(
      selectizeInput(
          inputId = ns("downloadFormat"),
          label = "Result Format",
          choices = "",
          selected = "",
          options = list(dropdownParent = "body"),
          width = NULL
      ),
      actionButton(
          ns("downloadTrigger"),
          "Download",
          style = "width:200px",
          class = "border border-1 border-primary shadow"
      ),
      shinyjs::hidden(
          downloadButton(
              ns("downloadData"),
              "Download",
              style = "width:200px"
          )
      )
  )
}

#' Download Server Functions
#'
#' @importFrom dplyr case_when
#' @importFrom stringr str_detect
#' @importFrom SeuratObject SaveSeuratRds Layers
#'
#' @noRd
mod_Download_server <- function(id,
                                seuratObj){
    moduleServer( id, function(input, output, session){
        ns <- session$ns
        ## Download code

        should_warn_rds_export <- function(object) {
            if (!isTruthy(object)) {
                return(FALSE)
            }

            is_large_object <- tryCatch(ncol(object) >= 1e+05, error = function(...) FALSE)
            is_large_object || is_seurat_bpcells(object)
        }

        observe({
            runningMode <- golem::get_golem_options("runningMode")
            message("download, runningMode: ", runningMode)
            if(runningMode == "processing" && isTruthy(seuratObj())){
                downloadFormat <- c("BPCells", "h5ad", "Rds", "metaData")
            }else{
                downloadFormat <- c("metaData")
            }

            if(!isTruthy(seuratObj())){
                downloadFormat <- character(0)
            }
            updateSelectizeInput(
                session = session,
                inputId = "downloadFormat",
                label = "Result Format",
                selected = if (length(downloadFormat)) downloadFormat[[1]] else character(0),
                choices = downloadFormat
            )
        })

        trigger_download <- function() {
            shinyjs::click("downloadData")
        }

        observeEvent(input$downloadTrigger, {
            obj <- seuratObj()
            req(isTruthy(obj), isTruthy(input$downloadFormat))

            if (!identical(input$downloadFormat, "Rds") || !should_warn_rds_export(obj)) {
                trigger_download()
                return()
            }

            showModal(
                modalDialog(
                    title = "Confirm standard Rds export",
                    "This export materializes BPCells-backed layers and can be slow or memory-intensive for large objects.",
                    footer = tagList(
                        modalButton("Cancel"),
                        actionButton(ns("confirmRdsExport"), "Download Rds")
                    ),
                    easyClose = TRUE
                )
            )
        }, ignoreNULL = TRUE)

        observeEvent(input$confirmRdsExport, {
            removeModal()
            trigger_download()
        }, ignoreNULL = TRUE)

        output$downloadData <- downloadHandler(
            filename = function(){
                obj <- seuratObj()
                prefix <- "scSpotlight."
                outFile <- case_when(
                    input$downloadFormat == "metaData" ~ paste0(prefix, "metaData.", Sys.Date(), ".tsv.gz"),
                    input$downloadFormat == "BPCells" ~ paste0(prefix, Sys.Date(), ".tar.gz"),
                    input$downloadFormat == "h5ad" ~ paste0(prefix, Sys.Date(), ".h5ad"),
                    TRUE ~ paste0(prefix, Sys.Date(), ".Rds")
                )
                outFile
            },
            content = function(file){
                obj <- seuratObj()
                req(isTruthy(obj), isTruthy(input$downloadFormat))
                prefix <- "scSpotlight."
                message("file: ", file)
                if(str_detect(file, "\\.Rds$")){
                    message("Saving Rds...")
                    progressr::withProgressShiny(
                        {
                            rds_progress <- progressr::progressor(steps = 3)
                            rds_progress(message = "Preparing Rds export")
                            obj <- materialize_bpcells_layers(obj)
                            rds_progress(message = "Writing Rds file")
                            saveRDS(obj, file)
                            rds_progress(message = "Rds export ready")
                        },
                        message = "Saving Rds...",
                        detail = "Preparing export"
                    )
                }else if(input$downloadFormat == "metaData"){
                    metaData <- get_backend_metadata(obj) %>%
                        tibble::rownames_to_column("cell")
                    readr::write_tsv(metaData, file)
                }else if(input$downloadFormat == "BPCells"){
                    bundleDir <- tempfile(pattern = "scspotlight_bundle_")
                    dir.create(bundleDir)
                    on.exit(unlink(bundleDir, recursive = TRUE, force = TRUE), add = TRUE)
                    progressr::withProgressShiny(
                        {
                            bundle_progress <- progressr::progressor(steps = 6)
                            write_scspotlight_bundle(
                                obj,
                                bundleDir,
                                file_name = paste0(prefix, Sys.Date(), ".Rds"),
                                progress = bundle_progress
                            )
                            bundle_progress(message = "Creating archive")
                            old_wd <- getwd()
                            on.exit(setwd(old_wd), add = TRUE)
                            setwd(dirname(bundleDir))
                            tar(tarfile = file, files = basename(bundleDir), compression = "gzip")
                        },
                        message = "Saving BPCells bundle...",
                        detail = "Preparing bundle"
                    )
                }else if(input$downloadFormat == "h5ad"){
                    progressr::withProgressShiny(
                        {
                            h5ad_progress <- progressr::progressor(steps = 4)
                            h5ad_progress(message = "Preparing h5ad export")
                            write_h5ad_scanpy(
                                obj,
                                output_file = file
                            )
                            h5ad_progress(message = "h5ad export ready")
                        },
                        message = "Saving h5ad...",
                        detail = "Preparing Scanpy export"
                    )
                }else{
                    stop("Format is not supported")
                }
            },
            contentType = NULL,
            outputArgs = list()
        )

        outputOptions(output, "downloadData", suspendWhenHidden = FALSE)

  })
}

#' showSpinnerNotification
#'
#' @importFrom shiny showNotification
#'
#' @noRd
showSpinnerNotification <- function(message,
                                    action = NULL,
                                    duration = NULL,
                                    closeButton = FALSE,
                                    type = "default",
                                    id,
                                    session = getDefaultReactiveDomain()){
    showNotification(
        ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                     role = "status",
                     span(class = "sr-only", "Loading...")),
                 message),
        action = action,
        duration = duration,
        closeButton = closeButton,
        type = type,
        id = id,
        session = session
    )
}
## To be copied in the UI
# mod_Download_ui("Download_1")
    
## To be copied in the server
# mod_Download_server("Download_1")
