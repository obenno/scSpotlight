#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @import bslib
#' @import bsicons
#' @import shinyjs
#' @importFrom htmltools tagAppendAttributes
#' @noRd
app_ui <- function(request) {

    ## app title
    app_title <- get_golem_config(value = "name")

    sca_mainUI <- scaffold_sca_mainUI()

    sca_navPanel <- nav_panel(
        title = "Main Panel", sca_mainUI, icon = icon("binoculars")
    )

    ui <- page_navbar(
        id = "navbar",
        title = app_title,
        window_title = app_title,
        bg = NULL,
        collapsible = TRUE,
        ##fluid = TRUE,
        theme = global_theme(),
        inverse  = FALSE,
        fillable = TRUE,
        selected = "Main Panel",
        nav_panel(title = "Home", "Landing Page", icon = icon("house")),
        sca_navPanel,
        ##nav_panel(title = "Recluster", "Here for reclustering the subset cells of your data", icon = icon("compress-alt")),
        tags$link(rel = "stylesheet", type = "text/css", href = "www/css/fira-sans.css"),
        tags$link(rel = "stylesheet", type = "text/css", href = "www/css/app.css"),
        useShinyjs(),
        ##use_waitress(),
        tags$script(src = "www/js/myscript.js") # custom javascript code here
    )
    ## modify some elements' attributes
    ui <- tagAppendAttributes(ui, .cssSelector = ".navbar", class = c("pt-1", "pb-1"))
    ##ui <- tagAppendAttributes(ui, .cssSelector = ".selectize-control", class = "mb-0")
    ## code above not working, maybe .selectize elements were added by js after generating shiny ui, use css instead
    ui <- tagAppendAttributes(ui, .cssSelector = ".shiny-input-container", class = "mb-2")

    ## returned taglist by golem
    tagList(
        ## Leave this function for adding external resources
        golem_add_external_resources(),
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
    sca_view <-  layout_sidebar(
        sidebar = sidebar(
            left_sidebar_ui(),
            ##bg = "#1E1E1E",
            class = "bg-primary",
            width = 300
        ),
        layout_sidebar(
            sidebar(
                right_sidebar_ui(),
                fill = TRUE,
                fillable = TRUE,
                position = "right",
                open = FALSE,
                class = "bg-primary"
            ),
            class = "align-items-center",
            border = FALSE,
            border_radius = FALSE,
            ##border_color = "black",
            fillable = TRUE,
            fill = TRUE,
            class = "p-2",
            mainPlots_ui(),
            infoBox_ui()
        ),
        border_radius = FALSE,
        border = FALSE,
        ##border_color = "black",
        fillable = TRUE,
        class = "p-0"
    )

    sca_view <- tagAppendAttributes(sca_view, .cssSelector = ".accordion-item", class = c("bg-dark"))

}


#' function to scaffold left side bar ui
#'
#' @importFrom bslib accordion
#' @importFrom bslib accordion_panel
#' @noRd
left_sidebar_ui <- function(){
    ##combined_settings <- mod_left_sidebar_accordion_ui("left_sidebar_accordion")
    ## accodion for left side bar
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
          list(),
          class = "bg-light text-black"
       ),
       accordion_panel(
          "Clustering Settings",
          icon = bsicons::bs_icon("sliders"),
          list(),
          class = "bg-light text-black"
       ),
       accordion_panel(
          "Cell Cycling",
          icon = bsicons::bs_icon("clock-history"),
          list(),
          class = "bg-light text-black"
       ),
       accordion_panel(
          "Find Markers",
          icon = bsicons::bs_icon("bar-chart-steps"),
          list(),
          class = "bg-light text-black"
       ),
       accordion_panel(
          "Download Result",
          icon = bsicons::bs_icon("cloud-download"),
          output_settings = list(),
          class = "bg-light text-black"
       )
    )

}


#' function to scaffold right side bar ui
#'
#' @noRd
right_sidebar_ui <- function(){
    ##right_sidebar <- tagList()
    right_sidebar <- accordion(
        id = "right_sidebar",
        ## Reduction Update
        accordion_panel(
            title = "Reduction",
            value = "analysis_reduction",
            icon = bsicons::bs_icon("signpost"),
            mod_UpdateReduction_ui("reductionUpdate"),
            class = "bg-light text-black"
        ),
        ##category options
        accordion_panel(
            title = "Category",
            value = "analysis_category",
            icon = bsicons::bs_icon("qr-code"),
            mod_UpdateCategory_ui("categoryUpdate"),
            class = "bg-light text-black"
        ),
        accordion_panel(
            title = "Feature Expression",
            value = "analysis_features",
            icon = bsicons::bs_icon("bar-chart-line"),
            list(),
            ##feature_options,
            class = "bg-light text-black"
        ),
        accordion_panel(
            title = "Rename Clusters",
            value = "rename_options",
            icon = bsicons::bs_icon("tags"),
            list(),
            ##rename_options,
            class = "bg-light text-black"
        )
    )
}

#' function for main scatter plots
#'
#' This will include two plots, main cluster plot and the feature plot, with each
#' in a separate box div
#'
#' @importFrom bslib layout_columns
#' @noRd
mainPlots_ui <- function(){
    ##taegList()
    mod_mainClusterPlot_ui("mainClusterPlot")
}

#' Function for bottom info box ui
#'
#' @noRd
infoBox_ui <- function(){
    bottom_box <- navset_card_pill(
        id = "bottom_box",
        full_screen = TRUE,
        height = "200px",
        ##title = "",
        nav_panel(
            title = "VlnPlot",
            tagList(),
            ##plotOutput("vlnPlot") %>% withSpinner(fill_container = T)
        ),
        ## seurat5 VariableFeaturePlot() has bug on pulling data
        ##nav_panel(
        ##    title = "HVGPlot",
        ##    plotOutput("HVGPlot") %>% withSpinner(fill_container = T)
        ##),
        nav_panel(
            title = "ElbowPlot",
            tagList(),
            ##plotOutput("elbowPlot") %>% withSpinner(fill_container = T)
        ),
        nav_panel(
            title = "DotPlot",
            tagList(),
            ##plotOutput("dotPlot") %>% withSpinner(fill_container = T)
        ),
        nav_panel(
            title = "DEG Heatmap",
            tagList(),
            ##plotOutput("DEG_heatmap") %>% withSpinner(fill_container = T)
        ),
        nav_panel(
            title = "DEG List",
            tagList(),
            ##DTOutput("DEG_list", width = "100%", height = "auto", fill = TRUE) %>% withSpinner(fill_container = T)
        )
    )

    bottom_box <- tagAppendAttributes(bottom_box,
                                      class = c("border", "border-2",
                                                "border-primary", "shadow"))
    bottom_box <- tagAppendAttributes(bottom_box,
                                      style = c("resize:both"))

}