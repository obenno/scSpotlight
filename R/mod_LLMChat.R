#' LLMChat UI Function
#'
#' @noRd
mod_LLMChat_ui <- function(id) {
  ns <- NS(id)

  if (!llm_chat_ui_available()) {
    return(div(
      class = "alert alert-warning mb-0",
      "The optional package 'shinychat' is required to use the AI Assistant."
    ))
  }

  div(
    class = "scspotlight-llm-chat html-fill-container",
    style = "height: min(68vh, 720px); min-height: 420px;",
    shinychat::chat_ui(
      id = ns("chat"),
      messages = llm_welcome_message(),
      placeholder = "Ask about the current scSpotlight view...",
      width = "100%",
      height = "100%",
      fill = TRUE,
      icon_assistant = bsicons::bs_icon("robot")
    )
  )
}

llm_welcome_message <- function() {
  paste(
    "**scSpotlight Assistant**",
    "",
    "I can summarize the current dataset, view state, group sizes, and DEG results that have already been computed.",
    "I do not receive full cell-level metadata, expression matrices, or local file paths.",
    "",
    "Suggested prompts:",
    "",
    "1. <span class=\"suggestion submit\">Summarize the current view.</span>",
    "2. <span class=\"suggestion\">What groups are visible in the current category?</span>",
    "3. <span class=\"suggestion\">Summarize the available DEG results.</span>",
    sep = "\n"
  )
}

#' LLMChat Server Functions
#'
#' @noRd
mod_LLMChat_server <- function(
  id,
  analysisContext,
  seuratObj,
  group.by,
  degMarkers,
  pAdjCutoff,
  llmConfig
) {
  moduleServer(id, function(input, output, session) {
    if (!llm_chat_ui_available()) {
      return(invisible(NULL))
    }

    chat_client <- reactiveVal(NULL)
    chat_client_generation <- reactiveVal(NULL)
    chat_busy <- reactiveVal(FALSE)
    chat_tool_state <- new.env(parent = emptyenv())
    chat_tool_state$snapshot <- NULL
    chat_tool_state$generation <- NULL

    request_state <- reactive({
      list(
        snapshot = llm_request_snapshot(
          analysis_context = analysisContext(),
          object = seuratObj(),
          group_by = group.by(),
          deg_markers = degMarkers(),
          p_adj_cutoff = pAdjCutoff()
        ),
        generation = new.env(parent = emptyenv())
      )
    })

    observeEvent(request_state()$generation, {
      current_generation <- request_state()$generation
      if (!identical(chat_client_generation(), current_generation)) {
        chat_client(NULL)
        chat_client_generation(NULL)
      }
      if (
        !is.null(chat_tool_state$generation) &&
          !identical(chat_tool_state$generation, current_generation)
      ) {
        # Do not retain a replaced dataset while a provider call is still pending.
        chat_tool_state$snapshot <- NULL
        chat_tool_state$generation <- NULL
      }
    }, ignoreInit = TRUE)

    get_chat_client <- function(generation) {
      client <- chat_client()
      if (!is.null(client) && identical(chat_client_generation(), generation)) {
        return(client)
      }

      client <- create_llm_chat(llmConfig)
      register_llm_tools(
        client,
        requestSnapshot = function() chat_tool_state$snapshot
      )
      chat_client(client)
      chat_client_generation(generation)
      client
    }

    observeEvent(input$chat_user_input, {
      if (isTRUE(chat_busy())) {
        llm_chat_append(
          "I'm still generating a response. Please wait for it to finish before asking another question.",
          session = session
        )
        return()
      }

      state <- request_state()
      snapshot <- state$snapshot
      request_generation <- state$generation
      context <- snapshot$analysis_context
      prompt <- build_llm_prompt(input$chat_user_input, context)
      chat_tool_state$snapshot <- snapshot
      chat_tool_state$generation <- request_generation

      client <- tryCatch(
        get_chat_client(request_generation),
        error = function(error) {
          llm_chat_report_error(
            error = error,
            user_message = llm_chat_unavailable_message(),
            log_context = "AI Assistant initialization failed",
            session = session
          )
          NULL
        }
      )
      if (is.null(client)) {
        chat_tool_state$snapshot <- NULL
        chat_tool_state$generation <- NULL
        return()
      }

      chat_busy(TRUE)
      response <- tryCatch(
        llm_chat_response_async(client, prompt, llmConfig),
        error = function(error) {
          llm_chat_report_error(
            error = error,
            user_message = llm_chat_request_failed_message(),
            log_context = "AI Assistant request failed",
            session = session
          )
          NULL
        }
      )
      if (is.null(response)) {
        chat_busy(FALSE)
        chat_tool_state$snapshot <- NULL
        chat_tool_state$generation <- NULL
        return()
      }

      # The tool-state environment owns the request snapshot. Do not let promise
      # callbacks retain a Seurat object or Explore bundle after invalidation.
      state <- NULL
      snapshot <- NULL
      context <- NULL

      response <- promises::then(
        response,
        onFulfilled = function(value) {
          current_generation <- shiny::isolate(request_state()$generation)
          llm_append_response_if_current(
            response = value,
            request_generation = request_generation,
            current_generation = current_generation,
            append = function(current_response) {
              llm_chat_append(
                current_response,
                session = session
              )
            },
            on_stale = function() {
              chat_client(NULL)
              chat_client_generation(NULL)
              llm_chat_append(
                llm_stale_response_message(),
                session = session
              )
            }
          )
        },
        onRejected = function(error) {
          current_generation <- shiny::isolate(request_state()$generation)
          chat_client(NULL)
          chat_client_generation(NULL)
          if (!identical(request_generation, current_generation)) {
            return(llm_chat_append(
              llm_stale_response_message(),
              session = session
            ))
          }

          llm_chat_report_error(
            error = error,
            user_message = llm_chat_request_failed_message(),
            log_context = "AI Assistant request failed",
            session = session
          )
        }
      )
      invisible(promises::finally(
        response,
        function() {
          if (identical(chat_tool_state$generation, request_generation)) {
            chat_tool_state$snapshot <- NULL
            chat_tool_state$generation <- NULL
          }
          chat_busy(FALSE)
        }
      ))
      invisible(NULL)
    })

    invisible(NULL)
  })
}

llm_chat_ui_available <- function() {
  requireNamespace("shinychat", quietly = TRUE)
}

llm_chat_append <- function(response, session) {
  shinychat::chat_append(
    "chat",
    llm_text_only_chat_response(response),
    session = session
  )
}

llm_chat_unavailable_message <- function() {
  "The AI Assistant is unavailable. Please try again later."
}

llm_chat_request_failed_message <- function() {
  "The AI Assistant request failed. Please try again."
}

llm_chat_report_error <- function(error, user_message, log_context, session) {
  message(log_context, ": ", conditionMessage(error))
  llm_chat_append(user_message, session = session)
  invisible(NULL)
}

llm_chat_response_async <- function(client, prompt, config) {
  provider <- normalize_llm_provider(config$provider %||% "ollama")

  if (identical(provider, "ollama")) {
    return(client$chat_async(prompt))
  }

  client$stream_async(prompt, stream = "content")
}

llm_request_snapshot <- function(
  analysis_context,
  object,
  group_by,
  deg_markers,
  p_adj_cutoff
) {
  analysis_context <- analysis_context %||% list()
  allowed_metadata_columns <- llm_authorized_metadata_columns(
    object,
    group_by = group_by,
    split_by = analysis_context$current_view$split_by
  )
  list(
    analysis_context = analysis_context,
    object = object,
    group_by = llm_safe_context_scalar(
      group_by,
      allowed = allowed_metadata_columns,
      default = "None"
    ),
    allowed_metadata_columns = allowed_metadata_columns,
    deg_markers = deg_markers,
    p_adj_cutoff = p_adj_cutoff
  )
}

llm_request_tool_handlers <- function(request_snapshot) {
  get_snapshot <- if (is.function(request_snapshot)) {
    request_snapshot
  } else {
    function() request_snapshot
  }
  current_snapshot <- function() {
    snapshot <- get_snapshot()
    if (!is.list(snapshot)) {
      stop("The LLM request context is no longer available.", call. = FALSE)
    }
    snapshot
  }
  safely_run_tool <- function(operation, error_message) {
    tryCatch(
      operation(),
      error = function(...) list(error = error_message)
    )
  }

  list(
    get_current_app_state = function() {
      safely_run_tool(
        function() current_snapshot()$analysis_context,
        "Current app state is unavailable."
      )
    },
    get_group_summary = function(column = NULL, top_n = 20L) {
      safely_run_tool(
        function() {
          snapshot <- current_snapshot()
          requested_column <- llm_clean_scalar(column, default = snapshot$group_by)
          if (!isTruthy(requested_column)) {
            requested_column <- snapshot$group_by
          }
          if (!requested_column %in% snapshot$allowed_metadata_columns) {
            return(list(
              error = paste(
                "Only metadata columns selected in the current view are available",
                "to the assistant."
              )
            ))
          }
          llm_group_summary(
            snapshot$object,
            column = requested_column,
            top_n = top_n
          )
        },
        "Metadata summary is unavailable."
      )
    },
    get_deg_summary = function(cluster = NULL, top_n = 10L, p_adj_max = NULL) {
      safely_run_tool(
        function() {
          snapshot <- current_snapshot()
          llm_deg_summary(
            snapshot$deg_markers,
            cluster = cluster,
            top_n = top_n,
            p_adj_max = p_adj_max %||% snapshot$p_adj_cutoff
          )
        },
        "DEG summary is unavailable."
      )
    }
  )
}

llm_stale_response_message <- function() {
  paste(
    "The scSpotlight context changed before this request finished, so its",
    "response was discarded. Ask again to use the current dataset and view."
  )
}

llm_append_response_if_current <- function(
  response,
  request_generation,
  current_generation,
  append,
  on_stale = function() NULL
) {
  if (!identical(request_generation, current_generation)) {
    return(on_stale())
  }
  append(response)
}

register_llm_tools <- function(client, requestSnapshot) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    return(invisible(NULL))
  }
  handlers <- llm_request_tool_handlers(requestSnapshot)

  client$register_tool(ellmer::tool(
    handlers$get_current_app_state,
    name = "get_current_app_state",
    description = paste(
      "Return the compact current scSpotlight app state. This tool returns",
      "summary metadata only and never returns raw cell-level data."
    )
  ))

  client$register_tool(ellmer::tool(
    handlers$get_group_summary,
    name = "get_group_summary",
    description = paste(
      "Summarize counts for one metadata column. Use this when the user asks",
      "about cluster sizes, category sizes, group composition, or the current",
      "group.by distribution. Results are capped and aggregated. Category labels",
      "are omitted when they exceed the app's cardinality or value safety limits."
    ),
    arguments = list(
      column = ellmer::type_string(
        "Metadata column to summarize. Leave empty to use the current group.by selection.",
        required = FALSE
      ),
      top_n = ellmer::type_integer(
        "Maximum number of groups to return. The app caps this value for safety.",
        required = FALSE
      )
    )
  ))

  client$register_tool(ellmer::tool(
    handlers$get_deg_summary,
    name = "get_deg_summary",
    description = paste(
      "Return a compact top-marker summary from already-computed DEG results.",
      "Use this only after DEG results are available; it does not run a new DEG analysis."
    ),
    arguments = list(
      cluster = ellmer::type_string(
        "Optional cluster/group label to filter DEG results.",
        required = FALSE
      ),
      top_n = ellmer::type_integer(
        "Maximum number of marker rows to return. The app caps this value for safety.",
        required = FALSE
      ),
      p_adj_max = ellmer::type_number(
        "Optional adjusted p-value threshold. Defaults to the app's DEG cutoff.",
        required = FALSE
      )
    )
  ))

  invisible(client)
}
