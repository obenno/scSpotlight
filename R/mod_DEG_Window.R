#' DEG Window UI Function
#'
#' @description Floating DEG analysis window.
#'
#' @param id Internal parameters for `{shiny}`.
#'
#' @importFrom shiny NS tagList plotOutput div
#' @noRd
mod_DEG_Window_ui <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "deg-floating-layout",
      div(
        class = "plot-floating-select-wrap deg-floating-settings",
        mod_FindMarkers_ui(ns("settings"))
      ),
      div(
        class = "deg-floating-tabs",
        bslib::navset_card_pill(
          id = ns("degTabs"),
          full_screen = FALSE,
          height = "100%",
          bslib::nav_panel(
            title = "Marker list",
            mod_DEG_Table_ui(ns("table"))
          ),
          bslib::nav_panel(
            title = "Heatmap",
            plotOutput(ns("heatmap"), width = "100%", height = "100%")
          )
        )
      )
    )
  )
}

#' DEG Window Server Functions
#'
#' @importFrom shiny moduleServer renderPlot validate need isTruthy
#' @noRd
mod_DEG_Window_server <- function(id, seuratObj, group.by) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    DEG_state <- mod_FindMarkers_server(
      "settings",
      seuratObj,
      group.by
    )

    mod_DEG_Table_server(
      "table",
      DEG_state$markers,
      DEG_state$pAdjCutoff
    )

    plot_width <- reactive({
      width <- session$clientData[[paste0("output_", ns("heatmap"), "_width")]]
      if (
        length(width) != 1 || is.null(width) || !is.finite(width) || width <= 0
      ) {
        return(NULL)
      }
      width
    })

    plot_height <- reactive({
      height <- session$clientData[[paste0(
        "output_",
        ns("heatmap"),
        "_height"
      )]]
      if (
        length(height) != 1 ||
          is.null(height) ||
          !is.finite(height) ||
          height <= 0
      ) {
        return(NULL)
      }
      height
    })

    output$heatmap <- renderPlot(
      {
        obj <- seuratObj()
        markers <- DEG_state$markers()
        group_by_value <- group.by()
        p_adj_cutoff <- DEG_state$pAdjCutoff()
        width <- plot_width()
        height <- plot_height()

        validate(
          need(
            isTruthy(obj),
            "Please input single cell data before generating DEG heatmap"
          ),
          need(
            isTruthy(group_by_value) && group_by_value != "None",
            "Choose a grouping metadata column before running DEG analysis"
          ),
          need(
            isTruthy(markers) && nrow(markers) > 0,
            'Please use "Find Markers" to generate DEG marker list'
          ),
          need(!is.null(width) && width > 0, ""),
          need(!is.null(height) && height > 0, "")
        )

        fc_col <- if ("avg_log2FC" %in% colnames(markers)) {
          "avg_log2FC"
        } else if ("avg_logFC" %in% colnames(markers)) {
          "avg_logFC"
        } else {
          NULL
        }

        adj_p_col <- if ("p_val_adj" %in% colnames(markers)) {
          "p_val_adj"
        } else {
          NULL
        }

        validate(
          need(
            !is.null(fc_col),
            "DEG results do not include a supported log fold-change column"
          ),
          need(
            !is.null(adj_p_col),
            "DEG results do not include an adjusted p-value column"
          )
        )

        markers_filtered <- markers[
          markers[[adj_p_col]] < p_adj_cutoff,
          ,
          drop = FALSE
        ]

        validate(
          need(
            nrow(markers_filtered) > 0,
            paste0("No DEG features pass adjusted p-value < ", p_adj_cutoff)
          )
        )

        marker_groups <- split(markers_filtered, markers_filtered$cluster)
        top_markers <- lapply(marker_groups, function(df) {
          df[order(df[[fc_col]], decreasing = TRUE), , drop = FALSE] |>
            utils::head(10)
        }) |>
          dplyr::bind_rows()

        features <- unique(top_markers$gene)

        validate(
          need(length(features) > 0, "No DEG features available for heatmap")
        )

        if (group_by_value != "ident") {
          Seurat::Idents(obj) <- group_by_value
        }

        Seurat::DoHeatmap(
          object = obj,
          features = features,
          group.by = group_by_value,
          raster = TRUE,
          size = 3.5
        ) +
          ggplot2::guides(color = "none") +
          ggplot2::theme(
            axis.text.y = ggplot2::element_text(size = 7),
            axis.text.x = ggplot2::element_blank(),
            axis.ticks.x = ggplot2::element_blank()
          )
      },
      res = 144
    )

    outputOptions(output, "heatmap", suspendWhenHidden = FALSE)

    invisible(list(
      markers = DEG_state$markers,
      pAdjCutoff = DEG_state$pAdjCutoff
    ))
  })
}
