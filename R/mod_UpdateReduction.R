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
#' @importFrom qs qsave
mod_UpdateReduction_server <- function(id,
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
      }, priority = -200)

      observeEvent(input$reduction, {
         reductionUpdateIndicator(reductionUpdateIndicator()+1)
      }, ignoreNULL = TRUE)

      extract_reduction <- ExtendedTask$new(function(reduction, filePath){
          future_promise({

              con <- duckConnect(session)
              on.exit(DBI::dbDisconnect(con))

              d <- queryDuckReduction(
                  con = con,
                  reduction = reduction
              )
              colnames(d) <- c("X", "Y")
              if(file.exists(filePath)){
                  file.remove(filePath)
              }
              qsave(d, filePath, preset = "high")
              return(basename(filePath))
          })

      })

      observeEvent(reductionUpdateIndicator(), {
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
          promise_filePath <- file.path(session$userData$tempDir, hash_md5(input$reduction))
          extract_reduction$invoke(reduction = promise_reduction,
                                   filePath = promise_filePath)

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
