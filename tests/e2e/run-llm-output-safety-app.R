port <- suppressWarnings(as.integer(Sys.getenv("SCSPOTLIGHT_LLM_E2E_PORT", "8901")))
if (is.na(port) || port < 1L || port > 65535L) {
  stop("SCSPOTLIGHT_LLM_E2E_PORT must be a valid port number.", call. = FALSE)
}

if (!requireNamespace("shinychat", quietly = TRUE)) {
  stop("The LLM output-safety browser test requires shinychat.", call. = FALSE)
}

devtools::load_all(".", quiet = TRUE, export_all = FALSE)

escape_response <- getFromNamespace("llm_escape_chat_response", "scSpotlight")
malicious_response <- paste0(
  "<shinychat-raw-html><img src=\"/missing-image\" ",
  "onerror=\"window.__scspotlightXss=true\"></shinychat-raw-html>",
  "\n\n![shinychat-markdown-image](https://example.invalid/llm-tracker.png)"
)

ui <- shiny::fluidPage(
  shinychat::chat_ui(
    id = "chat",
    messages = "LLM output-safety regression fixture."
  )
)

server <- function(input, output, session) {
  session$onFlushed(function() {
    llm_text_only_chat_response <- getFromNamespace(
      "llm_text_only_chat_response",
      "scSpotlight"
    )
    shinychat::chat_append("chat", llm_text_only_chat_response(malicious_response), session = session)
  }, once = TRUE)
}

shiny::runApp(
  shiny::shinyApp(ui, server),
  host = "127.0.0.1",
  port = port,
  launch.browser = FALSE
)
