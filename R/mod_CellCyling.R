#' CellCyling UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList 
mod_CellCycling_ui <- function(id){
    ns <- NS(id)
    tagList(
        actionButton(
            inputId = ns("addCycling"),
            label = "Assign Cycling Phase",
            icon = icon("clock-rotate-left"),
            style = "width:200px",
            class = "border border-1 border-primary shadow"
        )
    )
}

#' CellCyling Server Functions
#'
#' @noRd
mod_CellCycling_server <- function(id,
                                  seuratObj){
    moduleServer( id, function(input, output, session){
        ns <- session$ns
        observeEvent(input$addCycling, {
            s.genes <- Seurat::cc.genes$s.genes
            g2m.genes <- Seurat::cc.genes$g2m.genes
            if(!isTruthy(seuratObj())){
                showNotification(
                    ui = "Please input single cell data before adding cycling phase...",
                    action = NULL,
                    duration = 3,
                    closeButton = TRUE,
                    type = "default",
                    session = session
                )
            }else if( all(GetAssayData(seuratObj(), layer = "counts")@x == GetAssayData(seuratObj(), layer = "data")@x) ||
                      dim(GetAssayData(seuratObj(), layer = "data"))[1] == 0 ){
                showNotification(
                    ui = "Please normalize data before adding cycling phase...",
                    action = NULL,
                    duration = 3,
                    closeButton = TRUE,
                    type = "default",
                    session = session
                )
            }else{
                obj <- seuratObj()
                ## only use the features has expression
                ##geneExpr <- GetAssayData(obj, assay = NULL, layer = "counts") %>%
                ##    Matrix::rowSums()
                ##pool2 <- which(geneExpr > 0) %>% names
                ##message("head(pool2): ", paste(head(pool2), collapse = ","))
                ##pool <- rownames(obj)
                ##message("pool2 %in% pool: ", all(pool2 %in% pool))
                ##message("pool %in% pool2: ", all(pool %in% pool2))
                ##message("length(pool): ", length(pool))
                ##message("length(pool2): ", length(pool2))
                ##message("head(pool): ", paste(pool, collapse=","))

                ## use the seurat original CellCycling function for now
                withProgress(
                    message = "Calculating Cell Cycling Score...",
                    tryCatch(
                    {
                        obj <- Seurat::CellCycleScoring(
                                           obj,
                                           s.features = s.genes,
                                           g2m.features = g2m.genes,
                                           ctrl = NULL,
                                           set.ident = FALSE
                                           ##pool = pool2
                                       )
                        seuratObj(obj)
                        showNotification(
                            ui = "Successfully Added!",
                            action = NULL,
                            duration = 3,
                            closeButton = TRUE,
                            type = "default",
                            session = session
                        )
                    },
                    error = function(cond){
                        showNotification(
                            ui = paste0("CellCycleScoring failed: ", cond),
                            action = NULL,
                            duration = 3,
                            closeButton = TRUE,
                            type = "default",
                            session = session
                        )
                    }
                    )
                )
            }
        })
    })
}

#' CellCycleScoring_2
#'
#' function to overcome Seurat CellCycleScoring() issue
#' cut_number() used in AddModuleScore() has some internal issues to generate bins
#' https://stackoverflow.com/questions/61263203/how-does-ggplot2-split-groups-using-cut-number-if-you-have-a-small-number-of-dat
#' user will have to decrease bin numbers when encountering error: "Insufficient data values to produce 24 bins"
#' This is a tryCatch wrapper of the original CellCycleScoring() with different nbin
#'
#' @importFrom Seurat CellCycleScoring
#' @noRd
CellCycleScoring_2 <- function(
    object,
    s.features,
    g2m.features,
    ctrl = NULL,
    set.ident = FALSE,
    nbin = 24,
    ...
    ){
    startBin <- nbin
    obj <- NULL
    while(startBin >= 4){
        obj <- tryCatch(
        {
            message("Using nbin: ", startBin)
            seuratObj <- CellCycleScoring(
                object = object,
                s.features = s.features,
                g2m.features = g2m.features,
                ctrl = ctrl,
                set.ident = set.ident,
                nbin = startBin,
                ...
            )
            ## if the function works, break the loop
            message("succeed")
            return(seuratObj)
            ##break
        },
        error=function(cond) {
            message(cond)
            startBin <<- startBin-1
            message("Decreasing nbin: ", startBin)
            return(NULL)
        },
        finally={
            message("Done.")
        }
        )
        if(!is.null(obj)){
            break
        }
    }
    return(obj)
}


## To be copied in the UI
# mod_CellCycling_ui("CellCyling_1")
    
## To be copied in the server
# mod_CellCycling_server("CellCyling_1")
