#' LLMChat UI Function
#'
#' @noRd
mod_LLMChat_ui <- function(id) {
  ns <- NS(id)

  if (!requireNamespace("shinychat", quietly = TRUE)) {
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
    if (!requireNamespace("shinychat", quietly = TRUE)) {
      return(invisible(NULL))
    }

    chat_client <- reactiveVal(NULL)
    chat_context_version <- reactiveVal(NULL)
    chat_busy <- reactiveVal(FALSE)

    get_chat_client <- function(context_version) {
      client <- chat_client()
      if (!is.null(client) && identical(chat_context_version(), context_version)) {
        return(client)
      }

      client <- create_llm_chat(llmConfig)
      register_llm_tools(
        client,
        analysisContext = analysisContext,
        seuratObj = seuratObj,
        group.by = group.by,
        degMarkers = degMarkers,
        pAdjCutoff = pAdjCutoff
      )
      chat_client(client)
      chat_context_version(context_version)
      client
    }

    observeEvent(input$chat_user_input, {
      if (isTRUE(chat_busy())) {
        shinychat::chat_append(
          "chat",
          "I'm still generating a response. Please wait for it to finish before asking another question.",
          session = session
        )
        return()
      }

      context <- analysisContext()
      prompt <- build_llm_prompt(input$chat_user_input, context)
      context_version <- context$context_version %||% 0L

      client <- tryCatch(
        get_chat_client(context_version),
        error = function(error) {
          shinychat::chat_append(
            "chat",
            paste("The AI Assistant is not available:", conditionMessage(error)),
            session = session
          )
          NULL
        }
      )
      if (is.null(client)) {
        return()
      }

      chat_busy(TRUE)
      response <- llm_chat_response_async(client, prompt, llmConfig)
      response <- shinychat::chat_append("chat", response, session = session)
      invisible(promises::finally(
        response,
        function() {
          chat_busy(FALSE)
        }
      ))
      invisible(NULL)
    })

    invisible(NULL)
  })
}

llm_chat_response_async <- function(client, prompt, config) {
  provider <- normalize_llm_provider(config$provider %||% "ollama")

  if (identical(provider, "ollama")) {
    return(client$chat_async(prompt))
  }

  client$stream_async(prompt, stream = "content")
}

register_llm_tools <- function(client, analysisContext, seuratObj, group.by, degMarkers, pAdjCutoff) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    return(invisible(NULL))
  }

  client$register_tool(ellmer::tool(
    function() {
      analysisContext()
    },
    name = "get_current_app_state",
    description = paste(
      "Return the compact current scSpotlight app state. This tool returns",
      "summary metadata only and never returns raw cell-level data."
    )
  ))

  client$register_tool(ellmer::tool(
    function(column = NULL, top_n = 20L) {
      if (is.null(column) || !nzchar(column)) {
        column <- group.by()
      }
      llm_group_summary(seuratObj(), column = column, top_n = top_n)
    },
    name = "get_group_summary",
    description = paste(
      "Summarize counts for one metadata column. Use this when the user asks",
      "about cluster sizes, category sizes, group composition, or the current",
      "group.by distribution. Results are capped and aggregated."
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
    function(cluster = NULL, top_n = 10L, p_adj_max = NULL) {
      llm_deg_summary(
        degMarkers(),
        cluster = cluster,
        top_n = top_n,
        p_adj_max = p_adj_max %||% pAdjCutoff()
      )
    },
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
