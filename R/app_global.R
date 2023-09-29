## This script includes all the preload functions to mimic the previous global.R

#' Function to define default bs theme
#'
#' candidate font: Rajdhani
#'
#' @importFrom bslib bs_theme bs_add_variables
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

#' Default waiter loading screen
#'
#' @importFrom waiter spin_folding_cube
#' @noRd
waiting_screen <- function(){
    tagList(
        spin_folding_cube(),
        h4("Data Loading...")
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


#' WithSpinner
#'
#' @description A modified withSpinner function from shinycssloaders package,
#'              refer to: https://github.com/daattali/shinycssloaders/pull/77
#'
#' @import shinycssloaders
withSpinner <- function(
    ui_element,
    type = getOption("spinner.type", default = 3),
    color = getOption("spinner.color", default = "#2c3e50"),
    size = getOption("spinner.size", default = 0.5),
    color.background = getOption("spinner.color.background", "#ffffff"),
    custom.css = FALSE,
    proxy.height = NULL,
    id = NULL,
    image = NULL, image.width = NULL, image.height = NULL,
    hide.ui = TRUE,
    fill_container = FALSE
    ) {

    if (!inherits(ui_element, "shiny.tag") && !inherits(ui_element, "shiny.tag.list")) {
        stop("`ui_element` must be a Shiny tag", call. = FALSE)
    }
    if (!type %in% 0:8) {
        stop("`type` must be an integer from 0 to 8", call. = FALSE)
    }
    if (grepl("rgb", color, fixed = TRUE)) {
        stop("Color should be given in hex format")
    }
    if (is.character(custom.css)) {
        stop("It looks like you provided a string to 'custom.css', but it needs to be either `TRUE` or `FALSE`. ",
             "The actual CSS needs to added to the app's UI.")
    }

    ## each spinner will have a unique id to allow separate sizing
    if (is.null(id)) {
        id <- paste0("spinner-", digest::digest(ui_element))
    }

    if (is.null(image)) {
        css_size_color <- shiny::tagList()
        if (!custom.css && type != 0) {
            if (type %in% c(2, 3) && is.null(color.background)) {
                stop("For spinner types 2 & 3 you need to specify manually a background color.")
            }

            color.rgb <- paste(grDevices::col2rgb(color), collapse = ",")
            color.alpha0 <- sprintf("rgba(%s, 0)", color.rgb)
            color.alpha2 <- sprintf("rgba(%s, 0.2)", color.rgb)

            css_file <- system.file(glue::glue("loaders-templates/load{type}.css"), package="shinycssloaders")
            base_css <- ""
            if (file.exists(css_file)) {
                base_css <- paste(readLines(css_file), collapse = " ")
                base_css <- glue::glue(base_css, .open = "{{", .close = "}}")
            }

                                        # get default font-size from css, and cut it by 25%, as for outputs we usually need something smaller
            size <- round(c(11, 11, 10, 20, 25, 90, 10, 10)[type] * size * 0.75)
            base_css <- paste(base_css, glue::glue("#{id} {{ font-size: {size}px; }}"))
            css_size_color <- add_style(base_css)
        }
    }

    proxy_element <- get_proxy_element(ui_element, proxy.height, hide.ui)

    deps <- list(
        htmltools::htmlDependency(
            name = "shinycssloaders-binding",
            version = as.character(utils::packageVersion("shinycssloaders")),
            package = "shinycssloaders",
            src = "assets",
            script = "spinner.js",
            stylesheet = "spinner.css"
        )
    )

    if (is.null(image)) {
        deps <- append(deps, list(htmltools::htmlDependency(
            name = "cssloaders",
            version = as.character(utils::packageVersion("shinycssloaders")),
            package = "shinycssloaders",
            src = "assets",
            stylesheet = "css-loaders.css"
        )))
    }

    shiny::tagList(
        deps,
        if (is.null(image)) css_size_color,
        shiny::div(
            class = paste(
                "shiny-spinner-output-container",
                if (hide.ui) "shiny-spinner-hideui" else "",
                if (is.null(image)) "" else "shiny-spinner-custom",
                if(fill_container) "html-fill-item html-fill-container" else ""
            ),
            shiny::div(
                class = paste(
                    "load-container",
                    "shiny-spinner-hidden",
                    if (is.null(image)) paste0("load",type)
                ),
                if (is.null(image))
                    shiny::div(id = id, class = "loader", (if (type == 0) "" else "Loading..."))
                else
                    shiny::tags$img(id = id, src = image, alt = "Loading...", width = image.width, height = image.height)
            ),
            proxy_element,
            ui_element
        )
    )
}

#' add_style
#'
#' @noRd
add_style <- function(x) {
    shiny::tags$head(
        shiny::tags$style(
            shiny::HTML(x)
        )
    )
}

#' get_proxy_element
#'
#' @noRd
get_proxy_element <- function(ui_element, proxy.height, hide.ui) {
    if (!hide.ui) {
        return(shiny::tagList())
    }

    if (is.null(proxy.height)) {
        if (!grepl("height:\\s*\\d", ui_element)) {
            proxy.height <- "400px"
        }
    } else {
        if (is.numeric(proxy.height)) {
            proxy.height <- paste0(proxy.height, "px")
        }
    }

    if (is.null(proxy.height)) {
        proxy_element <- shiny::tagList()
    } else {
        proxy_element <- shiny::div(style=glue::glue("height:{proxy.height}"),
                                    class="shiny-spinner-placeholder")
    }
}

