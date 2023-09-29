#' FeaturePlot UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
#' @importFrom shinyjs hide show hidden
#' @importFrom promises future_promise
#' @importFrom waiter withWaiter
mod_FeaturePlot_ui <- function(id){
    ns <- NS(id)

    tagList(
        shinyjs::hidden(
            plotOutput(
                ns("multiFeaturePlot"),
                dblclick = dblclickOpts(
                    id = ns("multiFeaturePlot_dblclick")
                )
            )
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

        w <- Waiter$new(id = ns("multiFeaturePlot"))

        ## Then draw multiFeaturePlot
        observeEvent(list(
            selectedFeature(),
            inputFeatures(),
            reduction(),
            split.by()
        ), {
            req(obj())
            if(isTruthy(inputFeatures()) &&
               length(inputFeatures())>1 &&
               !isTruthy(selectedFeature())){
                removeUI(
                    selector = "#parent-wrapper",
                    multiple = FALSE,
                    immediate = TRUE,
                    session = session
                )

                shinyjs::show("multiFeaturePlot")
                ## show spinner
                w$show()
                output$multiFeaturePlot <- renderCachedPlot({
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

                    seuratObj <- obj()
                    features <- inputFeatures()
                    selectedReduction <- reduction()
                    message("featureplot reduction is ", selectedReduction)
                    message("featureplot split.by is ", split.by)
                    ##future_promise({
                    p <- FeaturePlot(
                        seuratObj,
                        features = features,
                        ##features = inputFeatures(),
                        ##reduction = reduction(),
                        reduction = selectedReduction,
                        split.by = split.by,
                        ##ncol = min(length(inputFeatures()), 3),
                        ncol = min(length(features), 3),
                        cols = c("lightgrey", "#5D3FD3"),
                        combine = TRUE
                    )
                    p
                    ##})
                },
                cacheKeyExpr = {
                    list(
                        obj(),
                        split.by(),
                        inputFeatures(),
                        reduction()
                    )
                },
                cache = "session"
                ##,
                ##sizePolicy = sizeGrowthRatio(
                ##    width = min(length(inputFeatures()), 3)*480,
                ##    height = ceiling(length(inputFeatures())/3)*480,
                ##    growthRate = 1.2
                ##)
                )
                on.exit({
                    w$hide()
                })
            }else{
                message("should be no output")
                output$multiFeaturePlot <- NULL
                shinyjs::hide("multiFeaturePlot")
            }
        })

        featurePlot_ncol <- reactive({
            req(obj())
            req(inputFeatures())
            req(input$multiFeaturePlot_dblclick$x)
            if(split.by() == "None"){
                min(length(inputFeatures()), 3)
            }else{
                obj()[[]] %>%
                    pull(split.by()) %>%
                    unique() %>%
                    length()
            }
        })

        featurePlot_nrow <- reactive({
            req(obj())
            req(inputFeatures())
            req(input$multiFeaturePlot_dblclick$x)
            if(split.by() == "None"){
                nFeature <- length(inputFeatures())
                if(nFeature <= 3){
                    rowNum <- 1
                }else{
                    rowNum <- ceiling(nFeature/3)
                }
            }else{
                rowNum <- length(inputFeatures())
            }
            rowNum
        })

        fig_idx <- reactive({
            req(input$multiFeaturePlot_dblclick$x, input$multiFeaturePlot_dblclick$y,
                featurePlot_ncol(), featurePlot_nrow())
            ##req(input$multiFeaturePlot_dblclick$y)
            ##req(featurePlot_ncol())
            ##req(featurePlot_nrow())
            retrieve_panel_idx(
                input$multiFeaturePlot_dblclick$x,
                input$multiFeaturePlot_dblclick$y,
                featurePlot_ncol(),
                featurePlot_nrow()
            )
        })

        observeEvent(fig_idx(), {
            req(fig_idx())
            ##message("fig_idx: ", paste(fig_idx(), collapse=", "))
            ## Assign selectedFeature()
            fig_idx <- fig_idx()
            if(split.by() == "None"){
                feature_idx <- (fig_idx[1]-1) * featurePlot_ncol() + fig_idx[2]
            }else{
                feature_idx <- fig_idx[1]
            }
            selected <- inputFeatures()[feature_idx]
            message("Selected Feature: ", selected)
            selectedFeature(selected)
        })

    })
}

## To be copied in the UI
# mod_FeaturePlot_ui("FeaturePlot_1")

## To be copied in the server
# mod_FeaturePlot_server("FeaturePlot_1")

#' retrieve_panel_idx
#'
#' @description Function to retrieve subfig index when clicking multiFeaturePlot panel
#'
#' @noRd
retrieve_panel_idx <- function(x, y, panel_ncol, panel_nrow){
    ## This function is to retrieve subfig index when clicking on the panel

    ## Set panel index to locate selected subfigure
    ## from top-left to bottom-right
    panel_idx_row <- 0
    panel_idx_col <- 0

    for(i in 1:panel_nrow){
        ymax <- 1- (i-1)*(1/panel_nrow)
        ymin <- ymax - 1/panel_nrow
        if(y > ymin && y < ymax){
            panel_idx_row <- i
        }
    }
    for(i in 1:panel_ncol){
        xmin <- (i-1)*(1/panel_ncol)
        xmax <- xmin + 1/panel_ncol
        if(x > xmin && x < xmax){
            panel_idx_col <- i
        }
    }

    fig_idx <- c(panel_idx_row, panel_idx_col)

    return(fig_idx)
}
