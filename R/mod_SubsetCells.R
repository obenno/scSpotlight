#' SubsetCells UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
mod_SubsetCells_ui <- function(id){
  ns <- NS(id)
  tagList(
      switchInput(
          inputId = ns("subsetData"),
          label = NULL,
          size = "mini",
          value = FALSE
      )
  )
}

#' SubsetCells Server Functions
#'
#' @noRd
mod_SubsetCells_server <- function(id,
                                   seuratObj,
                                   seuratObj_orig,
                                   selectedCells){
  moduleServer( id, function(input, output, session){
    ns <- session$ns
## Subset dataset code
observeEvent(input$subsetData, {
    req(seuratObj())
    ##req(selectedCells())

    if(input$subsetData){
        if(!isTruthy(selectedCells())){
            showNotification(
                ui = "Please select some cells before subsetting...",
                action = NULL,
                duration = 3,
                closeButton = TRUE,
                type = "default",
                session = session
            )
            ## Reset subset switch
            updateSwitchInput(
                session = session,
                inputId = "subsetData",
                value = FALSE,
                label = NULL
            )
        }else{
            obj <- seuratObj()
            obj_sub <- subset(obj, cells = selectedCells())
            ##DefaultAssay(seuratObj) <- "subsetData"
            showNotification(
                ui = "Subsetted Dataset to Only Keep Selected Cells...",
                action = NULL,
                duration = 3,
                closeButton = TRUE,
                type = "default",
                session = session
            )
            seuratObj_orig(obj)
            seuratObj(obj_sub)
            ## Reset manuallySelectedCells()
            manuallySelectedCells(NULL)
        }
    }else{
        obj <- seuratObj_orig()
        seuratObj(obj)
        ## clear seuratObj_orig()
        seuratObj_orig(NULL)
    }

    list(
        seuratObj = seuratObj,
        seuratObj_orig = seuratObj_orig
    )
}) 
  })
}
   
## To be copied in the UI
# mod_SubsetCells_ui("SubsetCells_1")
    
## To be copied in the server
# mod_SubsetCells_server("SubsetCells_1")
