#' DEG_Table UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd 
#'
#' @importFrom shiny NS tagList
#' @importFrom DT renderDT DTOutput datatable
mod_DEG_Table_ui <- function(id){
  ns <- NS(id)
  tagList(
      DTOutput(ns("DEG_list"), width = "100%", height = "auto", fill = TRUE)
      ##withWaiterOnElement(
      ##    target_element_ID = ns("DEG_list"), # defined in infoBox_ui()
      ##    html = waiter::spin_loaders(5, color = "var(--bs-primary)"),
      ##    color = "#ffffff"
      ##)

  )
}
    
#' DEG_Table Server Functions
#'
#' @noRd 
mod_DEG_Table_server <- function(id,
                                 DEG_markers,
                                 pAdjCutoff){
  moduleServer( id, function(input, output, session){
      ns <- session$ns
      output$DEG_list <- renderDT({
          markers <- DEG_markers()
          cutoff <- pAdjCutoff()

          validate(
              need(markers, 'Please use "Find Markers" to generate DEG marker list'),
              need("p_val_adj" %in% colnames(markers), "DEG results do not include an adjusted p-value column")
          )

          markers_filtered <- markers[markers[["p_val_adj"]] < cutoff, , drop = FALSE]

          validate(
              need(nrow(markers_filtered) > 0, paste0("No DEG rows pass adjusted p-value < ", cutoff))
          )

          DT::datatable(
              markers_filtered,
              rownames = FALSE,
              extensions = "Buttons",
              options = list(
                  pageLength = 10,
                  lengthMenu = c(10, 25, 50, 100),
                  dom = "Bfrtip",
                  buttons = c("csv")
              )
          )
      })

  })
}
    
## To be copied in the UI
# mod_DEG_Table_ui("DEG_Table_1")
    
## To be copied in the server
# mod_DEG_Table_server("DEG_Table_1")
