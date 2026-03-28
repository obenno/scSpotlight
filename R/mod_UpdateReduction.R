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
        selectInput(
            ns("reduction"),
            "Choose reduction",
            choices = "None",
            selected = "None",
            multiple = FALSE,
            selectize = TRUE,
            width = NULL
        )
    )
}
    
#' UpdateReduction Server Functions
#'
#' @noRd
#'
#' @importFrom arrow arrow_table write_ipc_stream float32 Array
mod_UpdateReduction_server <- function(id,
                                       seuratObj,
                                       reductionUpdateIndicator,
                                       reductionProcessed){

  moduleServer( id, function(input, output, session){
      ns <- session$ns

      observeEvent(reductionUpdateIndicator(), {
          req(file.exists(session$userData$duckdb))
          con <- duckConnect(session)
          on.exit(dbDisconnect(con))
          k <- listDuckReduction(con)
          idx <- na.omit(match(c("umap", "tsne", "pca"), k))
          ordered_reduction <- k[c(idx, setdiff(1:length(k), idx))]
          ## update input list
          updateSelectInput(
            session = session,
            inputId = "reduction",
            label = "Choose reduction",
            choices = ordered_reduction,
            selected = NULL
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
      }, priority = -200)

      ##observeEvent(input$reduction, {
      ##   reductionUpdateIndicator(reductionUpdateIndicator()+1)
      ##}, ignoreNULL = TRUE)

      extract_reduction <- ExtendedTask$new(function(reduction, dirPath, reductionVersion){
          future_promise({

              con <- duckConnect(session)
              on.exit(DBI::dbDisconnect(con))

              d <- queryDuckReduction(
                  con = con,
                  reduction = reduction
              )
              colnames(d) <- c("X", "Y")
              if(!file.exists(dirPath)){
                  stop(paste0(dirPath, " does not exist."))
              }
              reductionFileName <- hash_md5(paste0("reduction_", reduction, "_", reductionVersion))
              write_ipc_stream(
                  arrow_table(
                      X = Array$create(d$X, type = float32()),
                      Y = Array$create(d$Y, type = float32())
                  ),
                  file.path(dirPath, reductionFileName)
              )
              return(list(
                  reductionFile = reductionFileName,
                  reductionName = reduction,
                  reductionVersion = reductionVersion
              ))
          })

      })

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
          promise_dirPath <- file.path(session$userData$tempDir, "reduction")
          extract_reduction$invoke(reduction = reduction_name,
                                   dirPath = promise_dirPath,
                                   reductionVersion = reductionUpdateIndicator())
      }

      observeEvent(input$reduction, {
          req(file.exists(session$userData$duckdb))
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

          invoke_reduction_transfer(input$reduction)

      }, priority = -500)

      observeEvent(input$cacheMissReduction, {
          req(file.exists(session$userData$duckdb))
          req(isTruthy(input$cacheMissReduction), input$cacheMissReduction != "None")
          invoke_reduction_transfer(input$cacheMissReduction)
      }, priority = -500)

      observeEvent(extract_reduction$status(), {
          if(extract_reduction$status() == "success"){
              removeNotification(id = "update_reduction_notification", session)
              session$sendCustomMessage(type = "reduction_ready", extract_reduction$result())
          }else{
              message("extract_reduction error: ", extract_reduction$result())
          }
      }, ignoreNULL = FALSE)

      ##selectedReduction <- reactive({
      ##  input$reduction
      ##})

  })
}

## To be copied in the UI
# mod_UpdateReduction_ui("UpdateReduction_1")
    
## To be copied in the server
# mod_UpdateReduction_server("UpdateReduction_1")
