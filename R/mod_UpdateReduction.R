#' UpdateReduction UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_UpdateReduction_ui <- function(id){
    ns <- NS(id)
    tagList(
        selectizeInput(
            ns("reduction"),
            "Choose reduction",
            choices = "None",
            selected = "None",
            multiple = FALSE,
            options = list(dropdownParent = "body"),
            width = NULL
        )
    )
}
    
#' UpdateReduction Server Functions
#'
#' @noRd
#'
#' @importFrom cli hash_md5
#' @importFrom arrow arrow_table write_ipc_stream float32 Array
#' @importFrom promises future_promise %...>% %...!% finally
mod_UpdateReduction_server <- function(id,
                                       seuratObj,
                                       reductionUpdateIndicator,
                                       reductionProcessed){

  moduleServer( id, function(input, output, session){
      ns <- session$ns
      prefetchingReductionVersion <- reactiveVal(NULL)

      observeEvent(reductionUpdateIndicator(), {
          req(isTruthy(seuratObj()))
          k <- get_backend_reduction_names(seuratObj())
          idx <- na.omit(match(c("umap", "tsne", "pca"), k))
          ordered_reduction <- k[c(idx, setdiff(seq_along(k), idx))]
          selected_reduction <- if (isTruthy(input$reduction) && input$reduction %in% ordered_reduction) {
              input$reduction
          } else if (length(ordered_reduction)) {
              ordered_reduction[[1]]
          } else {
              character(0)
          }
          ## update input list
          updateSelectizeInput(
            session = session,
            inputId = "reduction",
            label = "Choose reduction",
            choices = ordered_reduction,
            selected = selected_reduction
          )

          obj <- seuratObj()
          reductionVersion <- reductionUpdateIndicator()
          pcaFileName <- hash_md5(paste0("pca_stdev_", reductionVersion))
          pcaFilePath <- file.path(session$userData$tempDir, "reduction", pcaFileName)

          if(isTruthy(obj) && "pca" %in% SeuratObject::Reductions(obj)){
              write_ipc_stream(
                  arrow_table(stdev = Array$create(obj[["pca"]]@stdev, type = float32())),
                  pcaFilePath
              )
              session$sendCustomMessage(
                  type = "pca_ready",
                  message = list(
                      stdevFile = pcaFileName,
                      reductionVersion = reductionVersion
                  )
              )
          } else {
              if(file.exists(pcaFilePath)){
                  file.remove(pcaFilePath)
              }
              session$sendCustomMessage(
                  type = "pca_ready",
                  message = list(
                      stdevFile = NULL,
                      reductionVersion = reductionVersion
                  )
              )
          }

          prefetched_reductions <- utils::head(ordered_reduction, 5L)
          if (length(prefetched_reductions) > 0) {
              invoke_all_reduction_transfer(prefetched_reductions, selected_reduction)
          }
       }, priority = -200)

      ##observeEvent(input$reduction, {
      ##   reductionUpdateIndicator(reductionUpdateIndicator()+1)
      ##}, ignoreNULL = TRUE)

      write_reduction_ipc <- function(reduction_name, reduction_data, reduction_version, dir_path) {
          reduction_file_name <- hash_md5(paste0("reduction_", reduction_name, "_", reduction_version))
          write_ipc_stream(
              arrow_table(
                  X = Array$create(reduction_data$X, type = float32()),
                  Y = Array$create(reduction_data$Y, type = float32())
              ),
              file.path(dir_path, reduction_file_name)
          )
          list(
              reductionFile = reduction_file_name,
              reductionName = reduction_name,
              reductionVersion = reduction_version
          )
      }

      invoke_reduction_transfer <- function(reduction_name){
          showNotification(
              ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                           role = "status",
                           span(class = "sr-only", "Loading...")),
                       "Updating reduction data..."),
              action = NULL,
              duration = NULL,
              closeButton = FALSE,
              type = "default",
              id = "update_reduction_notification",
              session = session
          )
          message("Transferring reductionData...")
          reductionProcessed(FALSE)
          dirPath <- file.path(session$userData$tempDir, "reduction")
          reductionVersion <- reductionUpdateIndicator()
          # Keep BPCells/Seurat access on the main thread; only file export is delegated.
          d <- get_backend_reduction(seuratObj(), reduction = reduction_name)
          reduction_promise <- future_promise({
              write_reduction_ipc(reduction_name, d, reductionVersion, dirPath)
          }) %...>% (
              function(result) {
                  session$sendCustomMessage(type = "reduction_ready", message = result)
                  result
              }
          ) %...!% (
              function(error) {
                  showNotification(
                      ui = paste("Reduction export failed:", conditionMessage(error)),
                      action = NULL,
                      duration = 6,
                      closeButton = TRUE,
                      type = "error",
                      session = session
                  )
              }
          )

          promises::finally(
              reduction_promise,
              function() {
                  removeNotification(id = "update_reduction_notification", session = session)
              }
          )
      }

      invoke_all_reduction_transfer <- function(reduction_names, active_reduction_name){
          req(length(reduction_names) > 0)
          showNotification(
              ui = div(div(class = c("spinner-border", "spinner-border-sm", "text-primary"),
                           role = "status",
                           span(class = "sr-only", "Loading...")),
                       "Preparing all reduction data..."),
              action = NULL,
              duration = NULL,
              closeButton = FALSE,
              type = "default",
              id = "update_reduction_notification",
              session = session
          )
          message("Transferring all reductionData...")
          reductionProcessed(FALSE)
          dirPath <- file.path(session$userData$tempDir, "reduction")
          reductionVersion <- reductionUpdateIndicator()
          prefetchingReductionVersion(reductionVersion)
          reduction_payloads <- lapply(reduction_names, function(reduction_name) {
              get_backend_reduction(seuratObj(), reduction = reduction_name)
          })
          names(reduction_payloads) <- reduction_names

          reductions_promise <- future_promise({
              lapply(reduction_names, function(reduction_name) {
                  write_reduction_ipc(
                      reduction_name,
                      reduction_payloads[[reduction_name]],
                      reductionVersion,
                      dirPath
                  )
              })
          }) %...>% (
              function(result) {
                  session$sendCustomMessage(
                      type = "reductions_ready",
                      message = list(
                          reductions = result,
                          activeReduction = active_reduction_name,
                          reductionVersion = reductionVersion
                      )
                  )
                  result
              }
          ) %...!% (
              function(error) {
                  showNotification(
                      ui = paste("Reduction export failed:", conditionMessage(error)),
                      action = NULL,
                      duration = 6,
                      closeButton = TRUE,
                      type = "error",
                      session = session
                  )
              }
          )

          promises::finally(
              reductions_promise,
              function() {
                  prefetchingReductionVersion(NULL)
                  removeNotification(id = "update_reduction_notification", session = session)
              }
          )
      }

      observeEvent(input$reduction, {
          req(isTruthy(seuratObj()))
          req(input$reduction!="None")

          reductionVersion <- reductionUpdateIndicator()
          cacheKey <- paste0(reductionVersion, cache_key_delim, input$reduction)

          if (isTruthy(input$cachedReductionKeys) && cacheKey %in% input$cachedReductionKeys) {
              reductionProcessed(FALSE)
              session$sendCustomMessage(
                  type = "reduction_cached",
                  message = list(
                      reductionName = input$reduction,
                      reductionVersion = reductionVersion
                  )
              )
              return()
          }

          if (identical(prefetchingReductionVersion(), reductionVersion)) {
              reductionProcessed(FALSE)
              return()
          }

          invoke_reduction_transfer(input$reduction)

      }, priority = -500)

      observeEvent(input$cacheMissReduction, {
          req(isTruthy(seuratObj()))
          req(isTruthy(input$cacheMissReduction), input$cacheMissReduction != "None")
          invoke_reduction_transfer(input$cacheMissReduction)
      }, priority = -500)

      ##selectedReduction <- reactive({
      ##  input$reduction
      ##})

  })
}

## To be copied in the UI
# mod_UpdateReduction_ui("UpdateReduction_1")
    
## To be copied in the server
# mod_UpdateReduction_server("UpdateReduction_1")
