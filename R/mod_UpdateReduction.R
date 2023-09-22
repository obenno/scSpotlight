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

      obj_reduction <- reactive({
          k <- Reductions(obj())
          idx <- na.omit(match(c("umap", "tsne", "pca"), k))
          ordered_reduction <- k[c(idx, setdiff(1:length(k), idx))]
          return(ordered_reduction)
      })

      observeEvent(obj_reduction(),{
          req(obj())
          ## update input list
          updateSelectInput(
            session = session,
            inputId = "reduction",
            label = "Choose reduction",
            choices = obj_reduction(),
            selected = NULL
          )

      })

      observeEvent(input$reduction, {
          scatterReductionIndicator(scatterReductionIndicator()+1)
          scatterColorIndicator(scatterColorIndicator()+1)
      })

      selectionReduction <- reactive({
          input$reduction
      })

      return(selectionReduction)
  })
}

## To be copied in the UI
# mod_UpdateReduction_ui("UpdateReduction_1")
    
## To be copied in the server
# mod_UpdateReduction_server("UpdateReduction_1")
