#' CellCyling UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_CellCycling_ui <- function(id) {
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
#' @importFrom Seurat CellCycleScoring
#'
#' @noRd
cell_cycle_patch_cols <- c("S.Score", "G2M.Score", "Phase")

#' @noRd
score_cell_cycle_safely <- function(
  object,
  s.features,
  g2m.features,
  ctrl = NULL,
  set.ident = FALSE,
  primary_scoring = Seurat::CellCycleScoring,
  fallback_scoring = CellCycleScoring_2,
  ...
) {
  scored <- tryCatch(
    primary_scoring(
      object = object,
      s.features = s.features,
      g2m.features = g2m.features,
      ctrl = ctrl,
      set.ident = set.ident,
      ...
    ),
    error = function(error) {
      message(
        "Primary cell-cycle scoring failed; trying fallback scoring. ",
        conditionMessage(error)
      )
      fallback_scoring(
        object = object,
        s.features = s.features,
        g2m.features = g2m.features,
        ctrl = ctrl,
        set.ident = set.ident,
        ...
      )
    }
  )

  if (!inherits(scored, "Seurat")) {
    stop("Cell-cycle scoring did not produce a valid Seurat object.", call. = FALSE)
  }
  missing_cols <- setdiff(cell_cycle_patch_cols, colnames(scored[[]]))
  if (length(missing_cols)) {
    stop("Cell-cycle scoring did not produce required metadata columns.", call. = FALSE)
  }

  scored <- drop_dense_scale_data(scored)
  assert_no_dense_scale_data(scored)
  scored
}

#' @noRd
mod_CellCycling_server <- function(
  id,
  seuratObj,
  assay,
  metaPatchRequest,
  metaPatchVersion
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    observeEvent(input$addCycling, {
      s.genes <- Seurat::cc.genes$s.genes
      g2m.genes <- Seurat::cc.genes$g2m.genes
      if (!isTruthy(seuratObj())) {
        showNotification(
          ui = "Please input single cell data before adding cycling phase...",
          action = NULL,
          duration = 3,
          closeButton = TRUE,
          type = "default",
          session = session
        )
      } else if (!dataNormalized(seuratObj())) {
        showNotification(
          ui = "Please normalize data before adding cycling phase...",
          action = NULL,
          duration = 3,
          closeButton = TRUE,
          type = "default",
          session = session
        )
      } else {
        obj <- seuratObj()
        selected_assay <- assay()
        if (isTruthy(selected_assay) && selected_assay %in% Assays(obj)) {
          DefaultAssay(obj) <- selected_assay
        }

        withProgress(
          message = "Calculating Cell Cycling Score...",
          tryCatch(
            {
              obj <- score_cell_cycle_safely(
                obj,
                s.features = s.genes,
                g2m.features = g2m.genes,
                ctrl = NULL,
                set.ident = FALSE
              )
              seuratObj(obj)
              nextPatchVersion <- metaPatchVersion() + 1L
              metaPatchVersion(nextPatchVersion)
              metaPatchRequest(list(
                cols = c("S.Score", "G2M.Score", "Phase"),
                version = nextPatchVersion
              ))
              showNotification(
                ui = "Successfully added cell-cycle metadata.",
                action = NULL,
                duration = 3,
                closeButton = TRUE,
                type = "default",
                session = session
              )
            },
            error = function(cond) {
              message("Cell-cycle scoring failed: ", conditionMessage(cond))
              showNotification(
                ui = paste(
                  "Cell-cycle scoring could not be completed.",
                  "Check that the active assay has normalized expression and",
                  "enough matching cell-cycle features."
                ),
                action = NULL,
                duration = 6,
                closeButton = TRUE,
                type = "warning",
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
) {
  startBin <- nbin
  obj <- NULL
  while (startBin >= 4) {
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
      error = function(cond) {
        message(cond)
        startBin <<- startBin - 1
        message("Decreasing nbin: ", startBin)
        return(NULL)
      },
      finally = {
        message("Done.")
      }
    )
    if (!is.null(obj)) {
      break
    }
  }
  return(obj)
}

## To be copied in the UI
# mod_CellCycling_ui("CellCyling_1")

## To be copied in the server
# mod_CellCycling_server("CellCyling_1")
