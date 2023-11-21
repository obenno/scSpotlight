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
    fill_container = TRUE
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

            ## get default font-size from css, and cut it by 25%, as for outputs we usually need something smaller
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

#' withWaiter
#'
#' @description A modified version of withWaiter. The spinner will be
#' shown on the target element (by id) instead of the original element.
#' Parse target element ID (e.g. body element ID of the navset_card_tab())
#'
#' @noRd
withWaiterOnElement <- function(
  element,
  target_element_ID,
  html = spin_1(),
  color = "#333e48",
  image = ""
){
  if(missing(element))
    stop("Missing `element`", call. = FALSE)

  id <- element$attribs$id
  targetID <- target_element_ID
  html <- as.character(html)
  html <- gsub("\n", "", html)

  script <- paste0(
    "$(document).on('shiny:outputinvalidated', function(event) {
      if(event.target.id != '", id, "')
        return;

      scSpotlight.myWaiter.show({
        id: '", targetID, "',
        html: '", html, "',
        color: '", color, "',
        image: '", image, "'
      });
    });
    
    $(document).on('shiny:value shiny:error shiny:recalculated shiny:visualchange', function(event) {
      if(event.target.id != '", id, "')
        return;
      waiter.hide('", targetID, "');
    });"
  )

  tagList(
    singleton(
      HTML(
        paste0("<script>", script, "</script>")
      )
    ),
    element
  )
}


#' AddModuleScore
#'
#' @description A modified version of seurat AddModuleScore(), used data layer
#' and value the pool argument
#'
#' @importFrom SeuratObject CheckGC
#' @noRd
AddModuleScore <- function(
    object,
    features,
    pool = NULL,
    nbin = 24,
    ctrl = 100,
    k = FALSE,
    assay = NULL,
    name = 'Cluster',
    seed = 1,
    search = FALSE,
    ...
    ) {
    if (!is.null(x = seed)) {
        set.seed(seed = seed)
    }
    assay.old <- DefaultAssay(object = object)
    assay <- assay %||% assay.old
    DefaultAssay(object = object) <- assay
    assay.data <- GetAssayData(object = object, assay = assay, slot = "data")
    ##assay.data <- LayerData(object = object, layer = "data")
    ##message("str(assay.data): ", str(assay.data))
    ##message("dim(assay.data): ", paste(dim(assay.data),collapse = " "))
    features.old <- features
    pool <- pool %||% rownames(x = object)
    if (k) {
        .NotYetUsed(arg = 'k')
        features <- list()
        for (i in as.numeric(x = names(x = table(object@kmeans.obj[[1]]$cluster)))) {
            features[[i]] <- names(x = which(x = object@kmeans.obj[[1]]$cluster == i))
        }
        cluster.length <- length(x = features)
    } else {
        if (is.null(x = features)) {
            stop("Missing input feature list")
        }
        features <- lapply(
            X = features,
            FUN = function(x, pool) {
                missing.features <- setdiff(x = x, y = pool)
                if (length(x = missing.features) > 0) {
                    warning(
                        "The following features are not present in the object: ",
                        paste(missing.features, collapse = ", "),
                        ifelse(
                            test = search,
                            yes = ", attempting to find updated synonyms",
                            no = ", not searching for symbol synonyms"
                        ),
                        call. = FALSE,
                        immediate. = TRUE
                    )
                    if (search) {
                        tryCatch(
                            expr = {
                                updated.features <- UpdateSymbolList(symbols = missing.features, ...)
                                names(x = updated.features) <- missing.features
                                for (miss in names(x = updated.features)) {
                                    index <- which(x == miss)
                                    x[index] <- updated.features[miss]
                                }
                            },
                            error = function(...) {
                                warning(
                                    "Could not reach HGNC's gene names database",
                                    call. = FALSE,
                                    immediate. = TRUE
                                )
                            }
                        )
                        missing.features <- setdiff(x = x, y = pool)
                        if (length(x = missing.features) > 0) {
                            warning(
                                "The following features are still not present in the object: ",
                                paste(missing.features, collapse = ", "),
                                call. = FALSE,
                                immediate. = TRUE
                            )
                        }
                    }
                }
                return(intersect(x = x, y = pool))
            },
            pool = pool
        )
        cluster.length <- length(x = features)
    }
    if (!all(Seurat:::LengthCheck(values = features))) {
        warning(paste(
            'Could not find enough features in the object from the following feature lists:',
            paste(names(x = which(x = !Seurat:::LengthCheck(values = features)))),
            'Attempting to match case...'
        ))
        features <- lapply(
            X = features.old,
            FUN = CaseMatch,
            match = rownames(x = object)
        )
    }
    if (!all(Seurat:::LengthCheck(values = features))) {
        stop(paste(
            'The following feature lists do not have enough features present in the object:',
            paste(names(x = which(x = !Seurat:::LengthCheck(values = features)))),
            'exiting...'
        ))
    }
    ##pool <- pool %||% rownames(x = object)
    message("length(pool): ", length(pool))
    data.avg <- Matrix::rowMeans(x = assay.data[pool, ])
    data.avg <- data.avg[order(data.avg)]
    message("length(data.avg): ", length(data.avg))
    data.cut <- cut_number(x = data.avg + rnorm(n = length(data.avg))/1e30, n = nbin, labels = FALSE, right = FALSE)
                                        #data.cut <- as.numeric(x = Hmisc::cut2(x = data.avg, m = round(x = length(x = data.avg) / (nbin + 1))))
    names(x = data.cut) <- names(x = data.avg)
    message("head(data.cut) :",  head(data.cut))
    ctrl.use <- vector(mode = "list", length = cluster.length)
    message("length(cluster.length): ", length(cluster.length))
    for (i in 1:cluster.length) {
        features.use <- features[[i]]
        for (j in 1:length(x = features.use)) {
            ctrl.use[[i]] <- c(
                ctrl.use[[i]],
                names(x = sample(
                          x = data.cut[which(x = data.cut == data.cut[features.use[j]])],
                          size = ctrl,
                          replace = FALSE
                      ))
            )
        }
    }
    ctrl.use <- lapply(X = ctrl.use, FUN = unique)
    ctrl.scores <- matrix(
        data = numeric(length = 1L),
        nrow = length(x = ctrl.use),
        ncol = ncol(x = object)
    )
    for (i in 1:length(ctrl.use)) {
        features.use <- ctrl.use[[i]]
        ctrl.scores[i, ] <- Matrix::colMeans(x = assay.data[features.use, ])
    }
    features.scores <- matrix(
        data = numeric(length = 1L),
        nrow = cluster.length,
        ncol = ncol(x = object)
    )
    for (i in 1:cluster.length) {
        features.use <- features[[i]]
        data.use <- assay.data[features.use, , drop = FALSE]
        features.scores[i, ] <- Matrix::colMeans(x = data.use)
    }
    features.scores.use <- features.scores - ctrl.scores
    rownames(x = features.scores.use) <- paste0(name, 1:cluster.length)
    features.scores.use <- as.data.frame(x = t(x = features.scores.use))
    rownames(x = features.scores.use) <- colnames(x = object)
    ##object[[colnames(x = features.scores.use)]] <- features.scores.use
    SeuratObject::CheckGC()
    ##DefaultAssay(object = object) <- assay.old
    ##return(object)

    ## return features.scores.use instead of seurat object
    return(features.scores.use)
}
