#' FilterCell UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
#'
mod_FilterCell_ui <- function(id) {
  ns <- NS(id)
  tagList(
    p(
      "View filters only change the cells shown in the current plot. ",
      "Use Subset to create a new Analysis from selected cells."
    ),
    list(
      numericInput(
        inputId = ns("nFeature_min"),
        label = "nFeature min value",
        value = 200,
        step = 100
      ),
      numericInput(
        inputId = ns("nFeature_max"),
        label = "nFeature max value",
        value = 20000,
        step = 100
      ),
      numericInput(
        inputId = ns("percent.mt_max"),
        label = "Mitochondrial nCount Percentage cutoff",
        value = 50,
        step = 5
      ),
      actionButton(
        inputId = ns("filter_cell"),
        label = "Apply View Filter",
        icon = icon("filter"),
        style = "width:200px",
        class = "border border-1 border-primary shadow"
      ),
      actionButton(
        inputId = ns("clear_view_filter"),
        label = "Clear View Filter",
        icon = icon("times-circle"),
        style = "width:200px",
        class = "border border-1 border-secondary shadow"
      )
    )
  )
}

#' FilterCell Server Functions
#'
#' @noRd
normalize_view_filter_number <- function(value, label) {
  if (
    length(value) != 1L ||
      !is.numeric(value) ||
      !is.finite(value)
  ) {
    stop(paste0(label, " must be a finite number."), call. = FALSE)
  }

  as.numeric(value)
}

#' @noRd
normalize_view_filter_column <- function(value, label) {
  if (
    length(value) != 1L ||
      !is.character(value) ||
      is.na(value) ||
      !nzchar(value)
  ) {
    stop(paste0(label, " must be a metadata column name."), call. = FALSE)
  }

  value
}

#' @noRd
view_filter_metadata <- function(object) {
  metadata <- tryCatch(object[[]], error = function(...) NULL)
  cells <- colnames(object)
  metadata_cells <- rownames(metadata)
  if (
    !is.data.frame(metadata) ||
      !length(cells) ||
      nrow(metadata) != length(cells) ||
      is.null(metadata_cells) ||
      !identical(as.character(metadata_cells), as.character(cells))
  ) {
    stop(
      "View filtering requires metadata aligned to the active Analysis.",
      call. = FALSE
    )
  }

  list(metadata = metadata, cells = cells)
}

#' @noRd
normalize_view_filter_spec <- function(view_filter) {
  if (is.null(view_filter)) {
    return(NULL)
  }
  if (!is.list(view_filter)) {
    stop("View filter is invalid.", call. = FALSE)
  }

  n_feature <- view_filter$nFeature
  percent_mt <- view_filter$percentMt
  if (!is.list(n_feature) || !is.list(percent_mt)) {
    stop("View filter is invalid.", call. = FALSE)
  }

  n_feature_column <- normalize_view_filter_column(
    n_feature$column,
    "nFeature filter"
  )
  n_feature_min <- normalize_view_filter_number(
    n_feature$min,
    "nFeature minimum"
  )
  n_feature_max <- normalize_view_filter_number(
    n_feature$max,
    "nFeature maximum"
  )
  percent_mt_column <- normalize_view_filter_column(
    percent_mt$column,
    "Mitochondrial filter"
  )
  percent_mt_max <- normalize_view_filter_number(
    percent_mt$max,
    "Mitochondrial maximum"
  )

  if (n_feature_min >= n_feature_max) {
    stop(
      "nFeature minimum must be smaller than the maximum.",
      call. = FALSE
    )
  }

  list(
    nFeature = list(
      column = n_feature_column,
      min = n_feature_min,
      max = n_feature_max
    ),
    percentMt = list(
      column = percent_mt_column,
      max = percent_mt_max
    )
  )
}

#' @noRd
validate_view_filter_spec <- function(object, view_filter) {
  view_filter <- normalize_view_filter_spec(view_filter)
  if (is.null(view_filter)) {
    return(NULL)
  }

  filter_metadata <- view_filter_metadata(object)
  metadata <- filter_metadata$metadata
  required_columns <- c(
    view_filter$nFeature$column,
    view_filter$percentMt$column
  )
  missing_columns <- setdiff(required_columns, colnames(metadata))
  if (length(missing_columns)) {
    stop(
      "View filtering requires the selected assay QC metadata.",
      call. = FALSE
    )
  }
  if (
    !is.numeric(metadata[[view_filter$nFeature$column]]) ||
      !is.numeric(metadata[[view_filter$percentMt$column]])
  ) {
    stop(
      "View filtering requires numeric QC metadata.",
      call. = FALSE
    )
  }

  view_filter
}

#' @noRd
view_filter_cell_mask <- function(object, view_filter) {
  view_filter <- validate_view_filter_spec(object, view_filter)
  filter_metadata <- view_filter_metadata(object)
  if (is.null(view_filter)) {
    return(rep(TRUE, length(filter_metadata$cells)))
  }

  metadata <- filter_metadata$metadata
  n_feature <- metadata[[view_filter$nFeature$column]]
  percent_mt <- metadata[[view_filter$percentMt$column]]
  is.finite(n_feature) &
    is.finite(percent_mt) &
    n_feature > view_filter$nFeature$min &
    n_feature < view_filter$nFeature$max &
    percent_mt < view_filter$percentMt$max
}

#' @noRd
resolve_view_filter_cells <- function(object, view_filter) {
  filter_metadata <- view_filter_metadata(object)
  filter_metadata$cells[view_filter_cell_mask(object, view_filter)]
}

#' @noRd
new_view_filter_spec <- function(
  object,
  assay,
  n_feature_min,
  n_feature_max,
  percent_mt_max
) {
  assay <- normalize_view_filter_column(assay, "Selected assay")
  validate_view_filter_spec(
    object,
    list(
      nFeature = list(
        column = paste0("nFeature_", assay),
        min = n_feature_min,
        max = n_feature_max
      ),
      percentMt = list(
        column = "percent.mt",
        max = percent_mt_max
      )
    )
  )
}

#' @noRd
new_view_filter_controller <- function() {
  view_filter <- shiny::reactiveVal(NULL)
  version <- shiny::reactiveVal(0L)

  set_filter <- function(next_filter) {
    next_filter <- normalize_view_filter_spec(next_filter)
    if (identical(shiny::isolate(view_filter()), next_filter)) {
      return(invisible(FALSE))
    }
    view_filter(next_filter)
    version(version() + 1L)
    invisible(TRUE)
  }

  list(
    value = function() view_filter(),
    version = function() version(),
    state = shiny::reactive(list(
      filter = view_filter(),
      version = version()
    )),
    set = set_filter,
    clear = function() set_filter(NULL)
  )
}

#' @noRd
mod_FilterCell_server <- function(
  id,
  seuratObj,
  selectedAssay,
  setViewFilter
) {
  moduleServer(id, function(input, output, session) {
    if (!is.function(setViewFilter)) {
      stop("FilterCell requires a View Filter state setter.", call. = FALSE)
    }

    observeEvent(input$filter_cell, {
      req(seuratObj())
      tryCatch(
        {
          view_filter <- new_view_filter_spec(
            object = seuratObj(),
            assay = selectedAssay(),
            n_feature_min = input$nFeature_min,
            n_feature_max = input$nFeature_max,
            percent_mt_max = input$percent.mt_max
          )
          setViewFilter(view_filter)
          showNotification(
            ui = "View filter applied. The active Analysis is unchanged.",
            action = NULL,
            duration = 5,
            closeButton = TRUE,
            type = "message",
            session = session
          )
        },
        error = function(error) {
          message("View filter rejected: ", conditionMessage(error))
          showNotification(
            ui = "View filter could not be applied. Check the QC thresholds and selected assay.",
            action = NULL,
            duration = 6,
            closeButton = TRUE,
            type = "error",
            session = session
          )
        }
      )
    })

    observeEvent(input$clear_view_filter, {
      if (isTRUE(setViewFilter(NULL))) {
        showNotification(
          ui = "View filter cleared. The active Analysis is unchanged.",
          action = NULL,
          duration = 5,
          closeButton = TRUE,
          type = "message",
          session = session
        )
      }
    })
  })
}

## To be copied in the UI
# mod_FilterCell_ui("FilterCell_1")

## To be copied in the server
# mod_FilterCell_server("FilterCell_1")
