#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @import bslib
#' @import bsicons
#' @import shinyjs
#' @import waiter
#' @importFrom htmltools tagAppendAttributes
#' @noRd
app_ui <- function(request) {

    ## app title
    app_title <- get_golem_config(value = "name")

    sca_mainUI <- scaffold_sca_mainUI()

    ui <- page_fillable(
        title = app_title,
        theme = global_theme(),
        class = "p-0",
        sca_mainUI,
        useShinyjs()
    )

    ## modify some elements' attributes
    ##ui <- tagAppendAttributes(ui, .cssSelector = ".selectize-control", class = "mb-0")
    ## code above not working, maybe .selectize elements were added by js after generating shiny ui, use css instead
    ui <- tagAppendAttributes(ui, .cssSelector = ".shiny-input-container", class = "mb-2")

    ## remove margin and padding in firefox
    ui <- tagAppendAttributes(ui, .cssSelector = ".tab-pane", class = "p-0 m-0")
    ui <- tagAppendAttributes(ui, .cssSelector = ".container-fluid", class = "p-0 m-0")

    ## returned taglist by golem
    tagList(
        ## Leave this function for adding external resources
        golem_add_external_resources(),
        useWaiter(),
        ## Your application UI logic
        ui
    )
}

#' Add external Resources to the Application
#'
#' This function is internally used to add external
#' resources inside the Shiny application.
#'
#' @import shiny
#' @importFrom golem add_resource_path activate_js favicon bundle_resources
#' @noRd
golem_add_external_resources <- function() {
  add_resource_path(
    "www",
    app_sys("app/www")
  )

  tags$head(
    favicon(),
    bundle_resources(
      path = app_sys("app/www"),
      app_title = "scSpotlight"
    )
    # Add here other external resources
    # for example, you can add shinyalert::useShinyalert()
  )
}


#' function to scaffold single cell analysis main ui skeleton
#'
#' @noRd
scaffold_sca_mainUI <- function(){

    ## main ui skeleton
    sca_view <- div(
        class = "sca-root-layout",
        style = "position: relative; width: 100%; height: 100vh; overflow: hidden;",
        layout_sidebar(
            sidebar = sidebar(
                id = "leftSidebar",
                left_sidebar_ui(),
                ##bg = "#1E1E1E",
                class = "bg-primary",
                width = 300
            ),
            layout_sidebar(
                sidebar = sidebar(
                    right_sidebar_ui(),
                    fill = TRUE,
                    fillable = TRUE,
                    width = 300,
                    position = "right",
                    open = TRUE,
                    class = "bg-primary"
                ),
                class = "align-items-center",
                border = FALSE,
                border_radius = FALSE,
                ##border_color = "black",
                fillable = TRUE,
                fill = TRUE,
                class = c("p-0", "sca-main-layout"),
                div(
                    class = "sca-main-stack",
                    style = "position: relative; width: 100%; height: 100%;",
                    mainPlots_ui(),
                    infoBox_ui()
                )
            ),
            border_radius = FALSE,
            border = FALSE,
            ##border_color = "black",
            fillable = TRUE,
            class = c("p-0", "sca-outer-layout")
        ),
        left_sidebar_rail_ui()
    )

    sca_view <- tagAppendAttributes(sca_view, .cssSelector = ".accordion-item", class = c("bg-dark"))

}


#' function to scaffold left side bar ui
#'
#' @importFrom bslib accordion
#' @importFrom bslib accordion_panel
#' @noRd
left_sidebar_ui <- function(){

    brand_header <- div(
        class = "d-flex align-items-center gap-2 px-2 py-1 mb-1",
        style = "border-bottom: 1px solid rgba(255,255,255,0.35);",
        tags$img(
            src = "www/favicon.ico",
            alt = "scSpotlight",
            style = paste(
                "width: 42px;",
                "height: 42px;",
                "border-radius: 0.4rem;",
                "background: rgba(255,255,255,0.16);",
                "padding: 0.2rem;",
                sep = " "
            )
        ),
        div(
            tags$span(
                "scSpotlight",
                style = paste(
                    "display: block;",
                    "font-size: 1.15rem;",
                    "font-weight: 700;",
                    "color: #fff;",
                    "line-height: 1;",
                    "letter-spacing: 0.015rem;",
                    sep = " "
                )
            ),
            tags$span(
                "Single-cell RNA-seq explorer",
                style = paste(
                    "display: block;",
                    "font-size: 0.72rem;",
                    "color: rgba(255,255,255,0.85);",
                    "line-height: 1.1;",
                    "margin-top: 0.15rem;",
                    sep = " "
                )
            )
        )
    )

    ## accodion for left side bar
    runningMode <- golem::get_golem_options("runningMode")
    if(runningMode == "viewer"){
        combined_settings <- accordion(
            id = "left_sidebar",
            accordion_panel(
                "File Input",
                icon = bsicons::bs_icon("file-earmark-arrow-up"),
                mod_dataInput_inputUI("dataInput"),
                class = "bg-light text-black"
            )
        )
    }else if(runningMode == "processing"){
        combined_settings <- accordion(
            id = "left_sidebar",
            accordion_panel(
                "File Input",
                icon = bsicons::bs_icon("file-earmark-arrow-up"),
                mod_dataInput_inputUI("dataInput"),
                class = "bg-light text-black"
            ),
            accordion_panel(
                "Cell Filtering",
                icon = bsicons::bs_icon("filter"),
                mod_FilterCell_ui("filterCells"),
                class = "bg-light text-black"
            ),
            accordion_panel(
                "Clustering Settings",
                icon = bsicons::bs_icon("sliders"),
                mod_ClusterSetting_ui("clusterSettings"),
                class = "bg-light text-black"
            ),
            accordion_panel(
                "Cell Cycling",
                icon = bsicons::bs_icon("clock-history"),
                mod_CellCycling_ui("cellCycling"),
                class = "bg-light text-black"
            ),
            accordion_panel(
                "Download Result",
                icon = bsicons::bs_icon("cloud-download"),
                mod_Download_ui("downloadObj"),
                class = "bg-light text-black"
            )
        )
    }else{
        stop("runningMode not supported")
    }
    return(tagList(brand_header, combined_settings))
}

#' Left sidebar icon rail when collapsed
#'
#' @noRd
left_sidebar_rail_ui <- function(){
    runningMode <- golem::get_golem_options("runningMode")

    rail_buttons <- list(
        tags$button(
            type = "button",
            class = "left-sidebar-rail-btn",
            title = "File Input",
            `data-panel-index` = "0",
            bsicons::bs_icon("file-earmark-arrow-up")
        )
    )

    if(runningMode == "processing"){
        rail_buttons <- append(rail_buttons, list(
            tags$button(type = "button", class = "left-sidebar-rail-btn", title = "Cell Filtering", `data-panel-index` = "1", bsicons::bs_icon("filter")),
            tags$button(type = "button", class = "left-sidebar-rail-btn", title = "Clustering Settings", `data-panel-index` = "2", bsicons::bs_icon("sliders")),
            tags$button(type = "button", class = "left-sidebar-rail-btn", title = "Cell Cycling", `data-panel-index` = "3", bsicons::bs_icon("clock-history")),
            tags$button(type = "button", class = "left-sidebar-rail-btn", title = "Download Result", `data-panel-index` = "4", bsicons::bs_icon("cloud-download"))
        ))
    }

    tags$div(
        id = "leftSidebarRail",
        class = "left-sidebar-rail",
        do.call(tagList, rail_buttons)
    )
}


#' function to scaffold right side bar ui
#'
#' @noRd
right_sidebar_ui <- function(){

    runningMode <- golem::get_golem_options("runningMode")

    if(runningMode == "viewer"){
        right_sidebar <- accordion(
            id = "right_sidebar",
            open = c("analysis_reduction", "analysis_category", "analysis_features"),
            ## Reduction Update
            accordion_panel(
                title = "Reduction",
                value = "analysis_reduction",
                icon = bsicons::bs_icon("signpost"),
                mod_UpdateReduction_ui("updateReduction"),
                class = "bg-light text-black"
            ),
            ## Category options
            accordion_panel(
                title = "Category",
                value = "analysis_category",
                icon = bsicons::bs_icon("qr-code"),
                mod_UpdateCategory_ui("updateCategory"),
                class = "bg-light text-black"
            ),
            ## Input FeatureList
            accordion_panel(
                title = "Feature Expression",
                value = "analysis_features",
                icon = bsicons::bs_icon("bar-chart-line"),
                mod_InputFeature_ui("inputFeatures"),
                class = "bg-light text-black"
            )
        )
    }else if(runningMode == "processing"){

        right_sidebar <- accordion(
            id = "right_sidebar",
            open = c("analysis_reduction", "analysis_category", "analysis_features"),
            ## Reduction Update
            accordion_panel(
                title = "Reduction",
                value = "analysis_reduction",
                icon = bsicons::bs_icon("signpost"),
                mod_UpdateReduction_ui("updateReduction"),
                class = "bg-light text-black"
            ),
            ## Category options
            accordion_panel(
                title = "Category",
                value = "analysis_category",
                icon = bsicons::bs_icon("qr-code"),
                mod_UpdateCategory_ui("updateCategory"),
                class = "bg-light text-black"
            ),
            ## Input FeatureList
            accordion_panel(
                title = "Feature Expression",
                value = "analysis_features",
                icon = bsicons::bs_icon("bar-chart-line"),
                mod_InputFeature_ui("inputFeatures"),
                class = "bg-light text-black"
            ),
            accordion_panel(
                title = "Rename Clusters",
                value = "rename_options",
                icon = bsicons::bs_icon("tags"),
                mod_AssignCellCluster_ui("renameCluster"),
                ##rename_options,
                class = "bg-light text-black"
            )
        )
    }else{
        stop("runningMode not supported")
    }
    return(right_sidebar)
}

#' function for main scatter plots
#'
#' This will include two plots, main cluster plot and the feature plot, with each
#' in a separate box div
#'
#' @noRd
mainPlots_ui <- function(){
    mod_mainClusterPlot_ui("mainClusterPlot")
}

#' Function for floating plot windows ui
#'
#' @noRd
#'
#' @importFrom shinyWidgets prettySwitch
infoBox_ui <- function(){

    runningMode <- golem::get_golem_options("runningMode")
    rail_buttons <- list(
        tags$button(
            type = "button",
            class = "plot-rail-btn",
            `data-target` = "floatingVlnPlot",
            title = "Open VlnPlot",
            tags$i(class = "bi bi-bar-chart")
        ),
        tags$button(
            type = "button",
            class = "plot-rail-btn",
            `data-target` = "floatingDotPlot",
            title = "Open DotPlot",
            tags$i(class = "bi bi-grid-3x3-gap")
        ),
        tags$button(
            type = "button",
            class = "plot-rail-btn",
            `data-target` = "floatingFeaturePlot",
            title = "Open FeaturePlot",
            tags$i(class = "bi bi-image")
        )
    )

    floating_panels <- list(
        tags$div(
            id = "floatingVlnPlot",
            class = "plot-floating-panel",
            style = "display:none;",
                tags$div(
                    class = "plot-floating-header plot-floating-header-vln",
                    tags$span("VlnPlot"),
                    tags$div(
                        class = "plot-floating-header-actions",
                        tags$span(
                            id = "floatingVlnPlotStatus",
                            class = "plot-floating-status-inline"
                        ),
                    tags$button(
                        type = "button",
                        class = "plot-floating-close",
                        `data-close-target` = "floatingVlnPlot",
                        tags$i(class = "bi bi-x-lg")
                    )
                )
            ),
            tags$div(
                id = "floatingVlnPlotBody",
                class = "plot-floating-body",
                tags$canvas(id = "VlnPlot", style = "height: 100%;")
            )
        ),
        tags$div(
            id = "floatingDotPlot",
            class = "plot-floating-panel",
            style = "display:none;",
            tags$div(
                class = "plot-floating-header",
                tags$span("DotPlot"),
                tags$div(
                    class = "plot-floating-header-actions",
                    tags$button(
                        id = "floatingDotPlotAction",
                        type = "button",
                        class = "plot-floating-action",
                        title = "Plot",
                        tags$i(class = "bi bi-play-circle")
                    ),
                    tags$button(
                        type = "button",
                        class = "plot-floating-close",
                        `data-close-target` = "floatingDotPlot",
                        tags$i(class = "bi bi-x-lg")
                    )
                )
            ),
            tags$div(
                id = "floatingDotPlotBody",
                class = "plot-floating-body",
                tags$div(
                    id = "floatingDotPlotStatus",
                    class = "plot-floating-status"
                ),
                tags$div(
                    class = "plot-floating-toolbar plot-floating-toolbar-stack",
                    tags$div(
                        class = "plot-floating-toolbar-heading",
                        tags$label(
                            `for` = "floatingDotPlotOrderList",
                            class = "plot-floating-toolbar-label",
                            "Cluster order"
                        ),
                        tags$span(
                            class = "plot-floating-toolbar-hint",
                            "Drag clusters to reorder them, or reset to use the default order."
                        )
                    ),
                    tags$div(
                        class = "plot-floating-select-wrap",
                        tags$div(
                            class = "plot-floating-order-toolbar",
                            tags$span(
                                id = "floatingDotPlotOrderMode",
                                class = "plot-floating-order-mode",
                                "Default order"
                            ),
                            tags$button(
                                id = "floatingDotPlotOrderReset",
                                type = "button",
                                class = "plot-floating-order-reset",
                                "Reset"
                            )
                        ),
                        tags$div(
                            id = "floatingDotPlotOrderList",
                            class = "plot-floating-order-list",
                            tabindex = "0"
                        )
                    )
                ),
                tags$div(
                    id = "floatingDotPlotCanvasWrap",
                    class = "plot-floating-canvas-wrap",
                    tags$canvas(id = "DotPlot", style = "height: 100%;")
                )
            )
        ),
        tags$div(
            id = "floatingFeaturePlot",
            class = "plot-floating-panel",
            style = "display:none;",
            tags$div(
                class = "plot-floating-header",
                tags$span("FeaturePlot"),
                tags$div(
                    class = "plot-floating-header-actions",
                    tags$button(
                        id = "floatingFeaturePlotAction",
                        type = "button",
                        class = "plot-floating-action",
                        title = "Plot",
                        tags$i(class = "bi bi-play-circle")
                    ),
                    tags$button(
                        type = "button",
                        class = "plot-floating-close",
                        `data-close-target` = "floatingFeaturePlot",
                        tags$i(class = "bi bi-x-lg")
                    )
                )
            ),
            tags$div(
                id = "floatingFeaturePlotBody",
                class = "plot-floating-body",
                tags$div(
                    id = "floatingFeaturePlotStatus",
                    class = "plot-floating-status"
                ),
                tags$div(
                    class = "plot-floating-toolbar",
                    tags$label(
                        `for` = "floatingFeaturePlotNcol",
                        class = "plot-floating-toolbar-label",
                        "Columns"
                    ),
                    tags$input(
                        id = "floatingFeaturePlotNcol",
                        class = "plot-floating-toolbar-input",
                        type = "number",
                        min = "1",
                        max = "6",
                        step = "1",
                        value = "3"
                    )
                ),
                tags$div(
                    id = "floatingFeaturePlotCanvasWrap",
                    class = "plot-floating-canvas-wrap",
                    tags$canvas(id = "featurePlotCanvas", style = "height: 100%;")
                )
            )
        )
    )

    if(runningMode == "processing"){
        rail_buttons <- append(rail_buttons, list(
            tags$button(
                type = "button",
                class = "plot-rail-btn",
                `data-target` = "floatingElbowPlot",
                title = "Open ElbowPlot",
                tags$i(class = "bi bi-graph-up")
            ),
            tags$button(
                type = "button",
                class = "plot-rail-btn",
                `data-target` = "floatingDEGList",
                title = "Open DEG Analysis",
                tags$i(class = "bi bi-bar-chart-steps")
            )
        ))

        floating_panels <- append(floating_panels, list(
            tags$div(
                id = "floatingElbowPlot",
                class = "plot-floating-panel",
                style = "display:none;",
                tags$div(
                    class = "plot-floating-header",
                    tags$span("ElbowPlot"),
                    tags$button(
                        type = "button",
                        class = "plot-floating-close",
                        `data-close-target` = "floatingElbowPlot",
                        tags$i(class = "bi bi-x-lg")
                    )
                ),
                tags$div(
                    class = "plot-floating-body",
                    tags$div(
                        id = "floatingElbowPlotStatus",
                        class = "plot-floating-status"
                    ),
                    tags$div(
                        id = "floatingElbowPlotCanvasWrap",
                        class = "plot-floating-canvas-wrap",
                        tags$canvas(id = "elbowPlotCanvas", style = "height: 100%;")
                    )
                )
            ),
            tags$div(
                id = "floatingDEGList",
                class = "plot-floating-panel",
                style = "display:none;",
                tags$div(
                    class = "plot-floating-header",
                    tags$span("DEG Analysis"),
                    tags$button(
                        type = "button",
                        class = "plot-floating-close",
                        `data-close-target` = "floatingDEGList",
                        tags$i(class = "bi bi-x-lg")
                    )
                ),
                tags$div(
                    class = "plot-floating-body",
                    mod_DEG_Window_ui("DEGWindow")
                )
            )
        ))
    }

    tags$div(
        id = "plotFloatingHost",
        class = "plot-floating-host",
        tags$div(
            id = "plotRail",
            class = "plot-rail",
            do.call(tagList, rail_buttons)
        ),
        do.call(tagList, floating_panels)
    )
}
