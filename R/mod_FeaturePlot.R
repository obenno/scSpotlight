#' FeaturePlot UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
#' @importFrim shinyjs hide show
mod_FeaturePlot_ui <- function(id){
    ns <- NS(id)
    tagList(
        shinyjs::hidden(
        plotOutput(
            ns("multiFeaturePlot"),
            dblclick = dblclickOpts(
                id = ns("multiFeaturePlot_dblclick")
            )
        ) ##%>% withSpinner(fill_container = T)
        )
    )
}

#' FeaturePlot Server Functions
#'
#' @noRd 
mod_FeaturePlot_server <- function(id,
                                   obj,
                                   reduction,
                                   split.by,
                                   selectedFeature,
                                   inputFeatures){
    moduleServer( id, function(input, output, session){
        ns <- session$ns

        ## Then draw multiFeaturePlot
        observe({
            if(!isTruthy(selectedFeature()) && length(inputFeatures())>1){
                removeUI(
                        selector = "#parent-wrapper",
                        multiple = FALSE,
                        immediate = TRUE,
                        session = session
                    )

                shinyjs::show("multiFeaturePlot")

                output$multiFeaturePlot <- renderPlot({
                    req(obj())
                    validate(
                        need(reduction(), "redcution not defined"),
                        need(inputFeatures(), "Please specify inputFeatures()")
                    )
                    ## Remove scatterplot grid
                    if(split.by() == "None"){
                        split.by <- NULL
                    }else{
                        split.by <- split.by()
                    }
                    p <- FeaturePlot(
                        obj(),
                        features = inputFeatures(),
                        reduction = reduction(),
                        split.by = split.by,
                        ncol = min(length(inputFeatures()), 3),
                        cols = c("lightgrey", "#5D3FD3"),
                        combine = TRUE
                    )
                    p
                })
            }else{
                message("should be no output")
                output$multiFeaturePlot <- NULL
                shinyjs::hide("multiFeaturePlot")
            }
        })

    })
}

## To be copied in the UI
# mod_FeaturePlot_ui("FeaturePlot_1")

## To be copied in the server
# mod_FeaturePlot_server("FeaturePlot_1")
