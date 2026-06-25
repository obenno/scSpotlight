#' UpdateReduction UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_UpdateReduction_ui <- function(id) {
  ns <- NS(id)
  tagList(
    selectizeInput(
      ns("reduction"),
      "Choose reduction",
      choices = "None",
      selected = "None",
      multiple = FALSE,
      options = list(dropdownParent = "body"),
      width = NULL
    )
  )
}

#' UpdateReduction Server Functions
#'
#' @noRd
#'
#' @importFrom cli hash_md5
#' @importFrom arrow arrow_table write_ipc_stream float32 Array
#' @importFrom promises future_promise %...>% %...!% finally
mod_UpdateReduction_server <- function(
  id,
  seuratObj,
  reductionUpdateIndicator,
  reductionProcessed
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    prefetchingReductionVersion <- reactiveVal(NULL)
    prefetchingReductionNames <- reactiveVal(character(0))

    observeEvent(
      reductionUpdateIndicator(),
      {
        req(isTruthy(seuratObj()))
        k <- get_backend_reduction_names(seuratObj())
        idx <- na.omit(match(c("umap", "tsne", "pca"), k))
        ordered_reduction <- k[c(idx, setdiff(seq_along(k), idx))]
        selected_reduction <- if (
          isTruthy(input$reduction) && input$reduction %in% ordered_reduction
        ) {
          input$reduction
        } else if (length(ordered_reduction)) {
          ordered_reduction[[1]]
        } else {
          character(0)
        }
        ## update input list
        updateSelectizeInput(
          session = session,
          inputId = "reduction",
          label = "Choose reduction",
          choices = ordered_reduction,
          selected = selected_reduction
        )

        reductionVersion <- reductionUpdateIndicator()
        pca_result <- tryCatch(
          capture_warnings(
            write_backend_pca_stdev_transfer(
              seuratObj(),
              dir_path = file.path(session$userData$tempDir, "reduction"),
              reduction_version = reductionVersion,
              resource_prefix = session$userData$dataResourcePrefix
            )
          ),
          error = function(error) {
            message("PCA stdev export failed during IPC write.")
            session$sendCustomMessage(
              type = "transfer_error",
              message = make_transfer_error_payload(
                "pca",
                "write_failed",
                reductionVersion,
                resource_prefix = session$userData$dataResourcePrefix
              )
            )
            showNotification(
              ui = "PCA summary export failed. The main scatter can still load.",
              action = NULL,
              duration = 6,
              closeButton = TRUE,
              type = "error",
              session = session
            )
            NULL
          }
        )
        if (!is.null(pca_result)) {
          show_captured_warnings(
            pca_result$warnings,
            title = "PCA stdev export completed with warnings",
            session = session
          )
          session$sendCustomMessage(
            type = "pca_ready",
            message = pca_result$value
          )
        }

        prefetch_limit <- if (get_backend_cell_count(seuratObj()) >= 250000L) {
          1L
        } else {
          5L
        }
        prefetched_reductions <- if (prefetch_limit == 1L) {
          selected_reduction
        } else {
          utils::head(ordered_reduction, prefetch_limit)
        }
        prefetched_reductions <- intersect(
          unique(prefetched_reductions),
          ordered_reduction
        )
        if (length(prefetched_reductions) > 0) {
          invoke_all_reduction_transfer(
            prefetched_reductions,
            selected_reduction
          )
        }
      },
      priority = -200
    )

    ##observeEvent(input$reduction, {
    ##   reductionUpdateIndicator(reductionUpdateIndicator()+1)
    ##}, ignoreNULL = TRUE)

    invoke_reduction_transfer <- function(reduction_name) {
      showNotification(
        ui = div(
          div(
            class = c("spinner-border", "spinner-border-sm", "text-primary"),
            role = "status",
            span(class = "sr-only", "Loading...")
          ),
          "Updating reduction data..."
        ),
        action = NULL,
        duration = NULL,
        closeButton = FALSE,
        type = "default",
        id = "update_reduction_notification",
        session = session
      )
      message("Transferring reductionData...")
      reductionProcessed(FALSE)
      dirPath <- file.path(session$userData$tempDir, "reduction")
      reductionVersion <- reductionUpdateIndicator()
      transfer <- prepare_backend_reduction_transfer(
        seuratObj(),
        reduction_name = reduction_name,
        dir_path = dirPath,
        reduction_version = reductionVersion,
        resource_prefix = session$userData$dataResourcePrefix
      )
      reduction_promise <- future_promise({
        capture_warnings(write_backend_reduction_transfer(transfer))
      }) %...>%
        (function(result) {
          show_captured_warnings(
            result$warnings,
            title = "Reduction export completed with warnings",
            session = session
          )
          session$sendCustomMessage(
            type = "reduction_ready",
            message = result$value
          )
          result$value
        }) %...!%
        (function(error) {
          message("Reduction export failed during IPC write.")
          session$sendCustomMessage(
            type = "transfer_error",
            message = make_transfer_error_payload(
              "reduction",
              "write_failed",
              reductionVersion,
              list(reductionName = reduction_name),
              resource_prefix = session$userData$dataResourcePrefix
            )
          )
          showNotification(
            ui = "Reduction export failed. Try switching reductions or retry transfer.",
            action = NULL,
            duration = 6,
            closeButton = TRUE,
            type = "error",
            session = session
          )
        })

      promises::finally(
        reduction_promise,
        function() {
          removeNotification(
            id = "update_reduction_notification",
            session = session
          )
        }
      )
    }

    invoke_all_reduction_transfer <- function(
      reduction_names,
      active_reduction_name
    ) {
      req(length(reduction_names) > 0)
      showNotification(
        ui = div(
          div(
            class = c("spinner-border", "spinner-border-sm", "text-primary"),
            role = "status",
            span(class = "sr-only", "Loading...")
          ),
          "Preparing all reduction data..."
        ),
        action = NULL,
        duration = NULL,
        closeButton = FALSE,
        type = "default",
        id = "update_reduction_notification",
        session = session
      )
      message("Transferring all reductionData...")
      reductionProcessed(FALSE)
      dirPath <- file.path(session$userData$tempDir, "reduction")
      reductionVersion <- reductionUpdateIndicator()
      prefetchingReductionVersion(reductionVersion)
      prefetchingReductionNames(reduction_names)
      reduction_transfers <- lapply(reduction_names, function(reduction_name) {
        prepare_backend_reduction_transfer(
          seuratObj(),
          reduction_name = reduction_name,
          dir_path = dirPath,
          reduction_version = reductionVersion,
          resource_prefix = session$userData$dataResourcePrefix
        )
      })
      names(reduction_transfers) <- reduction_names

      reductions_promise <- future_promise({
        results <- lapply(reduction_transfers, function(transfer) {
          capture_warnings(write_backend_reduction_transfer(transfer))
        })
        list(
          value = unname(lapply(results, `[[`, "value")),
          warnings = unique(unlist(lapply(results, `[[`, "warnings")))
        )
      }) %...>%
        (function(result) {
          show_captured_warnings(
            result$warnings,
            title = "Reduction prefetch completed with warnings",
            session = session
          )
          session$sendCustomMessage(
            type = "reductions_ready",
            message = list(
              reductions = result$value,
              activeReduction = active_reduction_name,
              reductionVersion = reductionVersion,
              resourcePrefix = session$userData$dataResourcePrefix
            )
          )
          result$value
        }) %...!%
        (function(error) {
          message("Reduction prefetch failed during IPC write.")
          session$sendCustomMessage(
            type = "transfer_error",
            message = make_transfer_error_payload(
              "reductions",
              "write_failed",
              reductionVersion,
              list(activeReduction = active_reduction_name),
              resource_prefix = session$userData$dataResourcePrefix
            )
          )
          showNotification(
            ui = "Reduction prefetch failed. Try switching reductions or retry transfer.",
            action = NULL,
            duration = 6,
            closeButton = TRUE,
            type = "error",
            session = session
          )
        })

      promises::finally(
        reductions_promise,
        function() {
          prefetchingReductionVersion(NULL)
          prefetchingReductionNames(character(0))
          removeNotification(
            id = "update_reduction_notification",
            session = session
          )
        }
      )
    }

    observeEvent(
      input$reduction,
      {
        req(isTruthy(seuratObj()))
        req(input$reduction != "None")

        reductionVersion <- reductionUpdateIndicator()
        cacheKey <- paste0(reductionVersion, cache_key_delim, input$reduction)

        if (
          isTruthy(input$cachedReductionKeys) &&
            cacheKey %in% input$cachedReductionKeys
        ) {
          reductionProcessed(FALSE)
          session$sendCustomMessage(
            type = "reduction_cached",
            message = list(
              reductionName = input$reduction,
              reductionVersion = reductionVersion
            )
          )
          return()
        }

        if (
          identical(prefetchingReductionVersion(), reductionVersion) &&
            input$reduction %in% prefetchingReductionNames()
        ) {
          reductionProcessed(FALSE)
          return()
        }

        invoke_reduction_transfer(input$reduction)
      },
      priority = -500
    )

    observeEvent(
      input$cacheMissReduction,
      {
        req(isTruthy(seuratObj()))
        req(
          isTruthy(input$cacheMissReduction),
          input$cacheMissReduction != "None"
        )
        invoke_reduction_transfer(input$cacheMissReduction)
      },
      priority = -500
    )

    selectedReduction <- reactive({
      input$reduction
    })

    list(
      reduction = selectedReduction
    )
  })
}

## To be copied in the UI
# mod_UpdateReduction_ui("UpdateReduction_1")

## To be copied in the server
# mod_UpdateReduction_server("UpdateReduction_1")
