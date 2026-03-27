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
          pcaFileName <- hash_md5("pca_stdev")
          pcaFilePath <- file.path(session$userData$tempDir, "reduction", pcaFileName)

          if(isTruthy(obj) && "pca" %in% SeuratObject::Reductions(obj)){
              write_ipc_stream(
                  arrow_table(stdev = Array$create(obj[["pca"]]@stdev, type = float32())),
                  pcaFilePath
              )
              session$sendCustomMessage(
                  type = "pca_ready",
                  message = list(stdevFile = pcaFileName)
              )
          } else {
              if(file.exists(pcaFilePath)){
                  file.remove(pcaFilePath)
              }
              session$sendCustomMessage(
                  type = "pca_ready",
                  message = list(stdevFile = NULL)
              )
          }
      }, priority = -200)

      ##observeEvent(input$reduction, {
      ##   reductionUpdateIndicator(reductionUpdateIndicator()+1)
      ##}, ignoreNULL = TRUE)

      extract_reduction <- ExtendedTask$new(function(reduction, dirPath){
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
              reductionFileName <- hash_md5("reduction")
              write_ipc_stream(
                  arrow_table(
                      X = Array$create(d$X, type = float32()),
                      Y = Array$create(d$Y, type = float32())
                  ),
                  file.path(dirPath, reductionFileName)
              )
              return(list(reductionFile = reductionFileName))
          })

      })

      observeEvent(input$reduction, {
          req(file.exists(session$userData$duckdb))
          req(input$reduction!="None")

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
          promise_reduction <- input$reduction
          promise_dirPath <- file.path(session$userData$tempDir, "reduction")
          extract_reduction$invoke(reduction = promise_reduction,
                                   dirPath = promise_dirPath)

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
