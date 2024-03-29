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
mod_UpdateReduction_server <- function(id,
                                       obj,
                                       scatterReductionIndicator, scatterColorIndicator){

  moduleServer( id, function(input, output, session){
      ns <- session$ns

      reduction_list <- reactive({
          req(obj())
          k <- Reductions(obj())
          idx <- na.omit(match(c("umap", "tsne", "pca"), k))
          ordered_reduction <- k[c(idx, setdiff(1:length(k), idx))]
          return(ordered_reduction)
      })

      observeEvent(reduction_list(),{
          req(obj())
          ## update input list
          updateSelectInput(
            session = session,
            inputId = "reduction",
            label = "Choose reduction",
            choices = reduction_list(),
            selected = NULL
          )

      })

      observeEvent(list(obj(), input$reduction), {
          req(obj())
          req(input$reduction!="None")
          message("UpdateReduction module increased scatter indicator")
          scatterReductionIndicator(scatterReductionIndicator()+1)
          scatterColorIndicator(scatterColorIndicator()+1)
          d <- Embeddings(obj()[[input$reduction]]) %>% as.data.frame()
          colnames(d) <- c("X", "Y")
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
          transfer_reduction(d, session)
          removeNotification(id = "update_reduction_notification", session)
      }, priority = -10)

      selectedReduction <- reactive({
          req(obj())
          input$reduction
      })

      return(selectedReduction)
  })
}

## To be copied in the UI
# mod_UpdateReduction_ui("UpdateReduction_1")
    
## To be copied in the server
# mod_UpdateReduction_server("UpdateReduction_1")
