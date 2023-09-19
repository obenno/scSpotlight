## This script includes all the preload functions to mimic the previous global.R

#' Function to define default bs theme
#'
#' candidate font: Rajdhani
#'
#' @importFrom bslib bs_theme
#'
#' @noRd
global_theme <- function(){
    bs_theme(
        version = "5",
        bootswatch = "flatly",
        ##primary = "#191970",
        base_font = "Fira Sans",
        ##base_font = font_collection(font_google("Fira+Sans", wght = "200..900", local = TRUE), "Roboto", "sans-serif"),
        ##code_font = font_collection(font_google("Fira+Code", wght = "200..900", local = FALSE), "Roboto", "sans-serif"),
        ##heading_font = font_collection(font_google("Fredoka+One", wght = "200..900", local = FALSE), "Roboto", "sans-serif"),
        ## https://community.rstudio.com/t/simplest-way-to-get-local-fonts-in-your-shiny-app/148326
        font_scale = NULL
    )
}

#' Function to define info icon
#'
#' @importFrom bsicons bs_icon
#' @noRd
infoIcon <- function(info, placement = "auto"){
    div(
        style = "display: inline-block; margin-left: 2px; margin-right: 2px;",
        `data-bs-toggle`="tooltip",
        `data-bs-placement`= placement,
        title = info,
        bsicons::bs_icon("info-circle-fill", size = "1.2em", class = "text-primary")
    )
}
#' Function to theme plotly figures
#'
#' @importFrom plotly config
#' @noRd
config_plotly_fig <- function(fig){
    config(
        fig,
        displaylogo = FALSE,
        modeBarButtonsToRemove = c('zoom', 'pan', 'select', 'zoomIn', 'zoomOut', 'autoScale',
                                   'hoverClosestCartesian', 'hoverCompareCartesian'),
        toImageButtonOptions = list(height= NULL, width= NULL, scale= 2)
    )
}