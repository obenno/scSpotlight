# LLM Chatbox Integration Plan

## Goal

Add an optional in-app LLM assistant to scSpotlight using Posit's `shinychat`
for the Shiny chat UI and `ellmer` for LLM provider access. The assistant should
help interpret the current app state and already-computed summaries without
materializing or sending large single-cell data payloads to an LLM.

MCP is explicitly reserved as a future integration layer and is not implemented
in this branch.

## Current Implementation Status

- Branch: `feature/llm-chatbox`
- Status: backend/context implementation complete; app UI insertion deferred to
  keep `R/app_ui.R` identical to `dev`
- Provider key handling: server-side only through environment variables or
  provider-managed credentials detected by `ellmer`
- Default availability: disabled unless `run_app(enableLLM = TRUE, ...)` is used
- MCP status: deferred
- Validation so far: targeted LLM context tests, run-app mode tests, full R test
  suite, and package load checks pass in the Pixi environment

## Best-Practice Design

Current Posit guidance for Shiny LLM apps favors:

- `shinychat::chat_ui()` for the chat UI.
- `ellmer::stream_async()` for non-blocking streaming responses.
- `stream = "content"` when tools are registered so `shinychat` can show rich
  tool call/result cards.
- `ellmer` tool/function calling for controlled, caller-executed access to app
  data.
- A stable system prompt for assistant behavior and a compact per-message app
  context snapshot for current state.

For scSpotlight, the assistant must not receive full Seurat objects, full
metadata tables, expression matrices, or reductions. The app should provide
compact summaries and read-only internal tools that return bounded, validated
JSON-serializable outputs.

## Provider And Credential Handling

Provider selection is app configuration, but credentials are not app
configuration.

`run_app()` exposes only non-secret LLM options:

- `enableLLM`
- `llmProvider`
- `llmModel`
- `llmBaseUrl`

Provider credentials are resolved only by the provider implementation in
`ellmer`, for example from environment variables such as `OPENAI_API_KEY`,
`ANTHROPIC_API_KEY`, or from cloud/OAuth credentials supported by `ellmer`.
For local Ollama usage, no key is required by default.

Credential rules:

- Do not add API key fields to Shiny UI.
- Do not add API key arguments to `run_app()`.
- Do not send credentials through `session$sendCustomMessage()`.
- Do not log credentials.
- Do not write credentials to temp files, `DEVELOPMENT.md`, or chat transcripts.
- Prefer local Ollama for private exploratory use.

## Architecture

### UI Layer

The chat UI module exists as `mod_LLMChat_ui("llmChat")`, but it is not inserted
into `R/app_ui.R` in this pass. This keeps the current app UI identical to
`dev`. A future UI integration should decide where to mount the module without
reintroducing the discarded UI branch changes.

### Runtime Layer

`mod_LLMChat_server()` creates one `ellmer` chat object per Shiny session.
The module observes `input$chat_user_input`, builds a prompt from the current
compact analysis context, and appends the answer to the chat UI with
non-blocking `ellmer` APIs.

For the initial Ollama provider, the module uses `chat_async()` so tool calling
can remain available despite Ollama's current streaming/tool limitations. Future
providers that support tool streaming can use `stream_async(..., stream =
"content")` so `shinychat` can render rich tool call/result cards.

Concurrency rules:

- Keep one mutable `ellmer` chat object per Shiny session.
- Do not start concurrent streams on the same chat object.
- Use a session-local busy flag to reject a new prompt while one is streaming.
- Rebuild/reset the chat object when a new dataset context version is loaded.

### Context Layer

The app builds a small context snapshot per user message. The snapshot contains
only state needed to orient the LLM, such as:

- running mode
- whether a dataset is loaded
- cell count
- feature count
- assays and default/selected assay
- reductions and active reduction
- active `group.by` and `split.by`
- selected feature names
- available metadata columns, capped
- whether DEG results exist

Detailed results are exposed through read-only tools rather than prompt dumps.

### Tool Layer

Internal tool functions are plain R helpers first, then wrapped as `ellmer`
tools by the chat module. This keeps the implementation testable and leaves a
future MCP wrapper path open.

Initial tools:

- `get_current_app_state()`
- `get_group_summary(column, top_n)`
- `get_deg_summary(cluster, top_n, p_adj_max)`

Tool constraints:

- Validate all LLM-provided arguments.
- Return compact JSON-serializable outputs.
- Apply hard caps to rows/categories/characters.
- Never return raw per-cell payloads.
- Never mutate app state.

## Data Safety Rules

Do not send to the LLM:

- Full Seurat objects
- Full BPCells matrices
- Full metadata tables
- Full reductions or UMAP coordinates
- Full expression vectors for all cells
- Full DEG tables
- Local file paths or temp paths

Allowed payloads:

- Counts and names
- Small selected UI state
- Top-N category summaries
- Top-N marker summaries
- Explicit missing-result messages

## MVP Scope

Implemented in this branch:

- Optional `enableLLM` app option, default `FALSE`
- Provider factory with Ollama first
- Server-side credential handling via `ellmer`
- `shinychat` chat module, not yet mounted in `R/app_ui.R`
- Compact app context snapshots
- Read-only summary tools
- Context/tool tests that do not call a real LLM
- `DEVELOPMENT.md` architecture notes
- Unit tests for context truncation, unloaded dataset context, group summaries,
  DEG summaries, and LLM app-option normalization

Not implemented in this branch:

- MCP server
- RAG/vector search
- Persistent chat history
- Browser-side API keys
- Automatic biological labeling from raw data
- Raw cell-level data export to LLM

## Optional Future MCP Design

If external agents should query scSpotlight later, expose the same internal
read-only helpers through MCP tools:

- `get_dataset_summary`
- `get_current_plot_state`
- `get_group_summary`
- `get_deg_summary`
- `get_feature_expression_summary`

MCP should remain a wrapper layer around already-tested internal helpers, not a
separate data-access implementation.

## Validation Notes

Validated with:

- `pixi run Rscript -e "devtools::test(filter = 'llm-context')"`
- `pixi run Rscript -e "devtools::test(filter = 'run-app-modes')"`
- `pixi run Rscript -e "devtools::test()"`
- `pixi run Rscript -e "devtools::load_all(); cat('loaded\\n')"`
- direct parse checks for modified R files

`devtools::check()` currently fails during `R CMD build` before package checks
because the local Pixi checkout contains environment files with broken debug
symlink targets under `.pixi`. The failure happens before code checks and is
not caused by the LLM implementation.
