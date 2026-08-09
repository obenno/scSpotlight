# Development Notes

This file records recent frontend behavior changes for the main scatter plot, sparkline gene selection, and floating plot windows. The goal is to preserve implementation intent and make later regressions easier to trace.

## Scope

The recent work touched these areas:

- optional LLM assistant design in `LLM_CHATBOX_PLAN.md`
- optional LLM assistant module/server code in `R/mod_LLMChat.R`
- LLM context and summary helpers in `R/fct_llm_context.R`
- floating plot UI in `R/app_ui.R`
- DEG analysis UI in `R/mod_DEG_Window.R`, `R/mod_FindMarkers.R`, and `R/mod_DEG_Table.R`
- reduction transfer in `R/mod_UpdateReduction.R`
- processed input validation in `R/mod_dataInput.R`
- h5ad conversion/export helpers in `R/fct_bpcells_backend.R`
- Analysis Version selection and subset flow in `R/fct_analysis_transition.R`, `R/mod_AssignCellCluster.R`, `R/mod_SubsetCells.R`, and `R/mod_mainClusterPlot.R`
- floating plot state and rendering flow in `srcjs/index.js`
- sparkline gene selection behavior in `srcjs/modules/featureSparkLine.js`
- main scatter plot mode selection in `srcjs/modules/scatter/scatterModel.js`
- main expression legend handling in `srcjs/modules/deckScatter.js`
- floating panel drag behavior in `srcjs/modules/floatingPlots.js`

## Key Decisions

### 1. Main panel uses only the first selected gene for expression mode

Decision:

- The main scatter plot supports a single expression layer at a time.
- If multiple genes are selected in the feature sparkline list, the main panel uses only the first selected gene.

Why:

- This matches current visualization constraints in the main panel.
- It avoids ambiguous multi-gene coloring behavior.

Implementation notes:

- `srcjs/modules/scatter/scatterModel.js` treats any non-empty `selectedFeatures` array as expression mode.
- `srcjs/modules/scatter/scatterModel.js` uses `selectedFeatures[0]` when building expression-backed plot data.
- `srcjs/modules/deckScatter.js` also uses `selectedFeatures[0]` for the expression legend to avoid client errors when multiple genes are selected.

### 2. The first selected gene is visually emphasized in the sparkline list

Decision:

- The first selected gene label is shown in bold in the feature sparkline list.

Why:

- It makes the main-panel expression source visible to the user when multiple genes are selected.

Implementation notes:

- `srcjs/modules/featureSparkLine.js` adds `.feature-gene-symbol` to gene labels.
- The helper `syncSelectedFeatureLabelStyles()` sets the first selected gene to bold and resets others to normal weight.

### 3. Floating plots are decoupled from automatic redraw on gene-selection changes

Decision:

- Selecting or deselecting genes in the sparkline list does not automatically redraw DotPlot or FeaturePlot.
- Those floating plots update only when their own plot action is taken, or when their already-rendered panel is resized.

Why:

- This keeps floating plots stable while users are adjusting selections.
- It avoids unnecessary webR work and reduces accidental expensive rerenders.

Implementation notes:

- `srcjs/modules/featureSparkLine.js` emits `scspotlight:featurePlotSelectionChanged` after selection updates.
- `srcjs/index.js` uses this event to refresh VlnPlot menu contents/status only, not to redraw DotPlot or FeaturePlot.

### 4. VlnPlot uses menu-driven selection and updates immediately on menu click

Decision:

- VlnPlot has no dedicated plot/refresh icon.
- Choosing an item from the VlnPlot popout menu updates the VlnPlot immediately.

Why:

- VlnPlot now behaves as a direct inspection panel for one chosen term at a time.
- This keeps the interaction lightweight compared with DotPlot and FeaturePlot.

Implementation notes:

- `R/app_ui.R` removes the VlnPlot action button and keeps inline status text.
- `srcjs/index.js` updates `reglElementData.plotMetaData.selectedMeta` from the dropdown item, refreshes menu state, and immediately calls `updateVlnPlot()` when the canvas is visible.
- Opening the floating VlnPlot window renders the current selection.

### 5. VlnPlot menu contains numeric metadata columns and selected genes

Decision:

- The VlnPlot popout menu includes:
  - all numeric metadata columns
  - all currently selected genes that have loaded expression data

Why:

- Users need to inspect either object metadata or selected-gene expression in the same VlnPlot UI.

Implementation notes:

- `srcjs/index.js` builds menu options via `getVlnPlotTermOptions()`.
- Option ids are typed as `meta:<name>` or `feature:<name>`.
- The selected item is highlighted in the dropdown.

### 6. DotPlot is explicit-action and order-aware

Decision:

- DotPlot redraws only when the DotPlot action button is clicked, or when an already-rendered DotPlot panel is resized.
- DotPlot supports a custom draggable cluster order in the floating panel.

Why:

- DotPlot is comparatively expensive and should not rerun on every selection tweak.
- Custom cluster ordering is part of the floating panel workflow and should persist independently of immediate redraws.

Implementation notes:

- `R/app_ui.R` adds a DotPlot toolbar with status text, draggable order list, and reset button.
- `srcjs/index.js` stores custom order in panel dataset fields and resolves it before plotting.
- Group order for UI sync is derived from category keys, not fully expanded per-cell metadata, to avoid unnecessary large allocations.

### 7. FeaturePlot is explicit-action and resize-aware

Decision:

- FeaturePlot redraws only when the FeaturePlot action button is clicked, or when an already-rendered FeaturePlot panel is resized.
- FeaturePlot is not auto-opened or auto-rendered by multi-gene selection in the main panel.

Why:

- FeaturePlot can be expensive for multiple features.
- The floating panel is the intended place for this multi-gene view.

Implementation notes:

- `R/app_ui.R` adds a dedicated floating FeaturePlot panel and a rail button.
- `srcjs/index.js` tracks `featurePlotRendered` and `featurePlotStale` in the panel dataset.
- The panel also exposes an `ncol` input to control layout.

### 8. Floating panel action buttons should not start panel dragging

Decision:

- Clicking a floating panel action button should activate the button only, not drag the panel.

Why:

- The action button sits inside the panel header, which also acts as the drag handle.
- Without a guard, slight pointer movement during click could move the panel unintentionally.

Implementation notes:

- `srcjs/modules/floatingPlots.js` excludes `.plot-floating-action` from drag start handling.

### 9. ElbowPlot is rendered client-side from transferred PCA standard deviations

Decision:

- The floating ElbowPlot window renders on the client from PCA standard deviation data sent from R.
- ElbowPlot refreshes automatically when the window opens, when the window is resized, and when PCA is updated after analysis.

Why:

- The elbow plot depends on PCA summary data, not the current main-plot reduction state.
- Client-side rendering avoids relying on Shiny plot output sizing inside the floating panel.

Implementation notes:

- `R/mod_UpdateReduction.R` transfers PCA standard deviations to the client via `pca_ready` whenever reductions are updated.
- `srcjs/modules/scatter/scatterModel.js` stores `pcaStdev` alongside other client-side data.
- `srcjs/index.js` renders the elbow plot on `elbowPlotCanvas` and refreshes it on floating-panel open, resize, and PCA updates.

### 10. DEG analysis lives in the floating DEG window

Decision:

- DEG settings, run action, marker table, and heatmap are grouped inside the floating DEG window.
- The old left-sidebar "Find Markers" panel is removed.

Why:

- DEG analysis is a result workflow rather than a persistent sidebar setting.
- Keeping settings, results, and heatmap together reduces context switching.

Implementation notes:

- `R/mod_DEG_Window.R` composes DEG settings, marker table, and heatmap into one floating workflow.
- `R/mod_FindMarkers.R` owns the async DEG run and returns marker results reactively.
- The DEG rail button now opens the full DEG analysis window rather than a table-only panel.

### 11. LLM assistant is optional, server-side, and summary-only

Decision:

- The AI Assistant runtime is disabled by default and is enabled only when `run_app(enableLLM = TRUE, ...)` is used.
- No chat panel is currently inserted into `R/app_ui.R`; the visible UI remains identical to `dev` until a later explicit UI mounting decision.
- The UI uses Posit's `shinychat` package, and model access uses `ellmer`.
- The first supported provider is local Ollama via `ellmer::chat_ollama()`.
- Provider credentials are never accepted through Shiny inputs or `run_app()` arguments.
- Credentials are resolved only server-side by `ellmer`, for example through environment variables or provider-managed credentials.
- MCP is explicitly deferred and is not implemented in this branch.

Why:

- LLM features require optional packages and provider setup, so normal app startup should not depend on them.
- Single-cell analysis data can be large and sensitive; the LLM must not receive full metadata, reductions, expression matrices, or local file paths.
- Internal read-only summary helpers are easier to test and can later be wrapped by MCP without changing the data-access logic.

Implementation notes:

- `run_app()` accepts non-secret options: `enableLLM`, `llmProvider`, `llmModel`, and `llmBaseUrl`.
- `DESCRIPTION` lists `ellmer` and `shinychat` under `Suggests` so the feature remains optional.
- `R/app_ui.R` is intentionally left matching `dev`; UI mounting for `mod_LLMChat_ui()` is deferred.
- `R/app_server.R` builds a compact reactive analysis context and passes it to `mod_LLMChat_server()`.
- `R/mod_LLMChat.R` creates one session-local `ellmer` chat object, uses non-blocking `ellmer` calls, and registers read-only tools. Ollama uses `chat_async()` to preserve tool calling despite current Ollama streaming/tool limitations; future providers that support tool streaming can use `stream_async(..., stream = "content")` for rich `shinychat` tool displays.
- `R/fct_llm_context.R` owns the system prompt, context builder, provider factory, context truncation, group summaries, and DEG summaries.
- `LLM_CHATBOX_PLAN.md` records the implementation plan, credential handling rules, and reserved future MCP design.

## Runtime Contract Backbone

This section is the developer-facing contract for the Analysis Mode backend seams and browser payload protocols. If metadata, reductions, expression, PCA summaries, metadata patches, or cached payload notifications change, update this section together with the manifest and paired tests.

### Analysis Mode backend seams

Analysis Mode uses the in-memory Seurat object plus BPCells-backed assay layers as its source of truth. Metadata, feature names, reduction names, reduction coordinates, expression vectors, and PCA summaries must flow through the backend helper seam instead of a duplicated query store:

- `get_backend_metadata` reads Seurat metadata from `object[[]]` for Analysis Mode and bundle metadata for Explore Mode.
- `get_backend_features` reads feature names from the selected Seurat assay layer or Explore bundle feature table.
- `get_backend_reduction_names` and `get_backend_reduction` read dimensional reductions from Seurat `Reductions()` / `Embeddings()` or Explore bundle reduction files.
- `get_backend_expr` reads the selected Analysis assay layer through Seurat/BPCells helpers or the Explore bundle expression query path.
- `get_backend_pca_stdev` reads PCA standard deviations from the Seurat PCA reduction or the Explore bundle PCA summary.
- `prepare_backend_metadata_transfer`, `prepare_backend_reduction_transfer`, `write_backend_pca_stdev_transfer`, and `prepare_backend_expression_transfer` prepare the browser-facing Arrow IPC transfer jobs.

For Analysis Mode, do not reintroduce a mirrored DuckDB runtime for Analysis Mode. DuckDB remains appropriate for immutable Explore Parquet bundle scans, but Analysis metadata, reductions, features, PCA summaries, and expression must not be mirrored into a second DuckDB runtime source of truth.

### Phase 03 Analysis Mode processing and mutation safety

Analysis loading now routes supported Analysis Mode inputs through one validation,
BPCells-backing, and no-dense-scale safety seam before the Seurat object becomes
app state. The supported Analysis Mode inputs are Seurat `.Rds`, `.h5ad`,
BPCells bundle archive, and compressed 10x-style matrix archive files. Explore Parquet bundles remain rejected in Analysis Mode; open those read-only artifacts
only with `run_app(runningMode = "explore")`.

Loaded and processed Analysis objects must preserve or convert assay storage to
BPCells-backed assay layers whenever BPCells is available. The loading and
validation paths derive missing normalized data, HVGs, PCA, neighbors, clusters,
and UMAP through the memory-conserving helpers in `R/fct_bpcells_backend.R`.
This is the required memory-conserving derivation of normalized, HVG, PCA, neighbors, clusters, and UMAP state for Analysis Mode startup and reprocessing.

No Analysis load, validation, PCA, processing, or portable bundle-save path may
finish with a no final dense `scale.data` violation: final app state must have
no final dense `scale.data` layers. Temporary Seurat fallback scaling is allowed
only inside a helper call and must be followed by `drop_dense_scale_data()` plus
`assert_no_dense_scale_data()` before returning. `counts`, normalized `data`,
metadata, reductions, graphs, and BPCells layer paths remain intact.

Phase 02 browser transfer contracts remain unchanged while this backend safety
work lands. Continue using Arrow IPC messages `meta_ready`, `reduction_ready`,
`reductions_ready`, `expr_ready`, `meta_patch_ready`, `pca_ready`, cache messages,
and `transfer_error`; do not add JSON cell-level payloads, local file paths,
mirrored Analysis DuckDB stores, or live Seurat/BPCells objects in background
futures to work around loading or processing issues.

The same section owns filter, cluster, and cell-cycle mutation safety. Filtering
must route browser/reactive selections through validated selected-cell sets via
`safe_subset_seurat_object`, preserve source-object cell order, reject stale selections before mutating app state, preserve BPCells backing where available,
and finish with `drop_dense_scale_data()` / `assert_no_dense_scale_data()`.
filtering and clustering must drop final dense `scale.data` before replacing the
server-side Seurat object.

Cluster update modes have intentionally different scopes and transfer indicators.
Update All refreshes metadata and reductions after rerunning the full
memory-conserving processing path. Update nDim Only refreshes metadata and reductions because neighbors, clusters, and UMAP can change when dimensions
change. Update Res Only reuses an existing graph and refreshes metadata without a reduction transfer when only resolution-driven cluster metadata changes.

Cell-cycle scoring first tries Seurat::CellCycleScoring() and falls back to CellCycleScoring_2() for small-gene/bin failures. It must reuse the existing `meta_patch_ready` path for the new `S.Score`, `G2M.Score`, and `Phase` columns,
and do not trigger a full metadata reload for cell-cycle scoring. browser-visible mutation errors must be path-free and must not expose raw condition text,
local paths, or stack traces.

The assignment and category-selection consistency contract keeps browser-owned rename filtering for responsive previews while moving persistence to a bounded server-validated intent. lasso selections take precedence over category selections. The browser sends bounded browser assignment intent through `renameCluster-assignmentIntent`: manual/lasso assignment carries selected cell IDs, and category assignment carries the current group/split levels and plot context. The server resolves assigned cells from canonical Seurat metadata, assignment mutates exactly one metadata column, and the browser receives a one-column scoped `meta_patch_ready` patch. Assignment must use no full JSON cell-level metadata transfer. Rename UI state must clear stale rename selections on group.by or split.by changes, metadata patch invalidation, explicit deselect, and clear stale rename selections after assignment completion.

Subset requests are intentionally limited to a manual/lasso Cell-ID selection.
The browser publishes `renameCluster-selectedCellsPayload` with canonical Cell
IDs plus the observed metadata version, Analysis Version, and Analysis lineage
ID. `R/mod_AssignCellCluster.R` validates payload structure and the metadata
epoch, then forwards the captured Analysis Version/lineage to the Analysis
Transition seam. The Analysis Transition validates every Cell ID against the
active Seurat object and canonicalizes source `colnames()` order once before
subsetting.
Category controls remain available for metadata assignment previews, but category
selection cannot substitute for a missing manual/lasso subset intent. The lasso
lifecycle, successful metadata patch, and any object replacement clear a
previously published manual selection payload.

The subset and restore refresh semantics are part of the same Analysis Mode mutation safety seam. A subset uses safe_subset_seurat_object with a complete validated selected-cell set, preserves source-object cell order, and leaves app state untouched when the requested Cell-ID set is not completely valid. The original object is stored once by the Analysis Transition controller before the first active subset, and restore clears that controller-owned backup after replacing app state with the original object. invalid or repeated subset toggles do not mutate app state: empty, duplicate, mixed-validity, stale, or already-subsetted requests reset or no-op without incrementing refresh indicators. successful subset and restore increment geneUpdateIndicator, metaUpdateIndicator, and reductionUpdateIndicator so existing metadata, reduction, feature, expression, and plot refresh chains run.

Every full or patch metadata IPC stream carries ordered canonical Cell IDs in its
`cells` column. The browser decodes this as an identity vector rather than a
category map, so Cell IDs are never expanded into one category bucket per cell.
Before a positional `meta_patch_ready` merge, the browser requires the patch
Cell-ID sequence to exactly match the current sequence; a mismatched or
reordered Cell-ID sequence is rejected without mutating metadata. A full
metadata refresh is an object replacement only when that ordered Cell-ID
population changes. Metadata-only refreshes retain same-version expression
availability.

The rule is: browser selected-cell, rename, assignment, expression cache, and feature state clear or reconcile after object replacement. The server sends `clear_expr`
with the replaced `geneUpdateIndicator` expression epoch before incrementing
the indicator. The client rejects expression payloads at or below that
invalidated epoch and also uses a per-request generation token, so a delayed
fetch/decode completion cannot apply after a Subset, Restore, or Analysis
dataset replacement. The implementation must reuse existing Phase 02 contracts
(`meta_ready`, `reduction_ready`/`reductions_ready`, `expr_ready`,
`meta_patch_ready`, `transfer_error`, and `clear_expr`) rather than adding a
subset-specific browser message. There must be no final dense `scale.data` after subset or restore.

### Phase 03 gap-closure invariants

The final Phase 03 gap-closure repairs are now part of the Analysis Mode processing and mutation safety contract. Preserve these rules with source changes, browser payload changes, and documentation updates:

- **Safe archive extraction:** compressed Analysis archives must validate unsafe entries before extraction. Tar and zip inputs are listed before unpacking, and absolute paths, Windows drive roots, parent-directory traversal, and symlink entries are rejected with generic path-free errors.
- **Session-scoped IPC resource prefixes:** IPC payload URLs use a session-scoped resourcePrefix plus basename instead of global /data paths. R registers an opaque per-session Shiny resource prefix, sends `resourcePrefix` with metadata, reduction, PCA, expression, metadata patch, and transfer-error payloads, and removes that prefix when the session ends.
- **Monotonic metadata versioning:** metadata refreshes and metadata patches share one server-owned monotonic version sequence. Full `meta_ready` transfers and column-scoped `meta_patch_ready` transfers must allocate comparable metadata versions from the same server-owned counter so valid patches cannot be rejected as stale after a full refresh.
- **Server-trusted assignment validation:** assignment validation must not trust browser-submitted current metadata versions. Versioned assignment intents are accepted only when the server can compare them with the server-trusted current metadata version for the active group/split context.
- **Single assignment activation:** normal assignment activation emits a single renameCluster-assignmentIntent. Browser handlers must avoid pointerdown/click double submission so one user action produces one bounded assignment intent and one scoped metadata mutation.
- **Cell-ID lasso and subset flow:** browser `renameCluster-selectedCellsPayload` carries canonical Cell IDs plus metadata, Analysis Version, and lineage tokens captured from the rendered plot. The Analysis Transition rejects lasso/manual selections unless every Cell ID exists in `colnames(seuratObj())`, then re-orders the complete selection once by the current Seurat object before subsetting. Successful metadata patches clear the visible lasso and its transport so a stale metadata epoch cannot remain selectable. Empty, duplicate, mixed-validity, metadata-stale, version-stale, and lineage-stale requests publish no Analysis Version.
- **Session-root BPCells subset backing:** subset backing must use the session backend root for BPCells-safe output. Session callers pass `session$userData$backendDir` (or a child directory) into `safe_subset_seurat_object()` so temporary BPCells subset layers are cleaned up with the Shiny session.

### Browser payload contracts

The machine-readable payload contract is `inst/protocol/browser-payload-contracts.json`. The paired R producer test is `tests/testthat/test-browser-payload-contracts.R`, and the paired JS consumer test is `srcjs/index.test.js`.

The manifest currently defines these browser message contracts:

- `meta_ready`: full metadata Arrow IPC notification with `metaFile`, `metaVersion`, and an ordered canonical `cells` Cell-ID column.
- `meta_patch_ready`: column-scoped metadata patch notification with `metaFile`, `metaVersion`, `cols`, and the same ordered canonical `cells` Cell-ID column.
- `reduction_ready`: single-reduction Arrow IPC notification with `reductionFile`, `reductionName`, and `reductionVersion`.
- `reductions_ready`: batched reduction prefetch notification with active reduction selection and versioned entries.
- `pca_ready`: PCA standard deviation Arrow IPC notification with `stdevFile` and `reductionVersion`.
- `expr_ready`: feature-expression Arrow IPC notification with `exprFile`, `geneName`, `assay`, and `exprVersion`.
- `reduction_cached`: request to rehydrate an already-cached reduction payload for the current `reductionVersion`.
- `expr_cached`: request to rehydrate an already-cached expression payload for the current `exprVersion`.
- `transfer_error`: sanitized transfer failure notification with `payloadType`, `reasonCode`, `version`, and scoped context fields such as `reductionName`, `activeReduction`, `geneName`, `assay`, or `cols`.

Browser payload file fields are resource basenames, not local paths. Resource-backed payloads include the session-scoped `resourcePrefix`, and the browser fetches files by combining that prefix with the metadata, reduction, or expression basename. Payloads must not use global `/data` paths or expose producer-local `filePath`, `output_file`, or `matrix_dir` fields.

### Phase 02 transfer reliability

The metadata, reduction, batched reduction, and PCA transfer path now uses the
manifest-backed `transfer_error` contract for visible transfer failures. R
producer failures call `make_transfer_error_payload()` before crossing the
Shiny/browser boundary, and browser handlers in `srcjs/index.js` format those
payloads into path-free user copy with `textContent`, `role="alert"`, and
`aria-live="assertive"`.

User-facing failure copy is intentionally stable:

- `Metadata could not load` for full metadata transfer failures.
- `Metadata update could not apply` for column-scoped metadata patch failures.
- `Reduction could not load` for a selected single-reduction transfer failure.
- `Scatter could not initialize` when no current active batched reduction renders.
- `Expression could not load` for expression transfer failures; the category scatter remains available.
- `PCA summary unavailable` for PCA standard deviation transfer failures; this updates only the ElbowPlot status and does not block the main scatter.

The client treats stale payloads as no-ops. Metadata and reduction handlers record
the active version/request before asynchronous Arrow fetch/decode work and check it
again immediately before mutating scatter state. Stale successes and stale
`transfer_error` messages must not clear the current plot, overwrite current typed
arrays, or show stale warnings.

The active-reduction readiness rule is: `initialPlotReady` is reported only after
one current active reduction renders successfully, or after the current transfer
visibly fails and settles the waiter. Batched `reductions_ready` must prefer the
server-provided `activeReduction` over a stale DOM selection.

Expression transfers are scoped backend jobs. `R/mod_InputFeature.R` keeps
queued one-active expression jobs per session and uses duplicate scoped key suppression
for `{exprVersion, assay, geneName}` so BPCells and DuckDB reads do not overlap
for the same requested expression payload. Analysis Mode uses
path-based BPCells expression transfers prepared outside the promise body, and
Explore Mode uses DuckDB/Explore query-plan expression transfers with only the
selected `block_path`, `feature_idx`, `cell_count`, and output file path carried
into the writer. Both branches write Arrow IPC numeric `expr` vectors and expose
only basename-only expression payloads: `exprFile`, `geneName`, `assay`, and
`exprVersion`.

Browser-side stale expression application is guarded after every asynchronous
step: `expr_ready` and `expr_cached` re-check `exprVersion`, `assay`, and the
requested `geneName` before writing the expression cache, decoding/applying the
typed `expr` vector, or updating sparkline state. Expression cache keys remain
`{exprVersion}::{assay}::{geneName}`. Cache misses send only the targeted
`inputFeatures-cacheMissFeature` request for the missing gene, not a full
metadata or dataset reload.

Metadata patches remain column-scoped. `meta_patch_ready` must include `cols`
and ordered canonical Cell IDs. The browser applies only those decoded columns,
and `ScatterModel` validates patch shape, length, and type before merge. The
browser validates the Cell-ID sequence before that positional merge, so a
mismatched or reordered Cell-ID sequence, malformed patch, or stale patch does
not mutate existing metadata. Valid patches refresh the main scatter only when
patched columns affect active metadata-backed plot state such as `group.by`,
`split.by`, or selected VlnPlot metadata.

Main scatter expression rendering remains first-selected-gene only. The main
scatter model, expression legend, panel title, and sparkline primary state all
read `selectedFeatures[0]`; additional selected genes stay available to floating
plots but never create multi-gene main-scatter coloring. The sparkline list keeps
checked state separate from primary state: checked non-first genes remain checked,
only the first selected gene receives semibold/`aria-current` primary emphasis,
and removing the first gene promotes the next checked gene.

Do not widen expression payloads to JSON arrays, dense matrices, local paths,
DBI connections, live Seurat/BPCells objects, or live Explore bundle objects.

For payload behavior changes, update these files together: the manifest
(`inst/protocol/browser-payload-contracts.json`), R producer tests
(`tests/testthat/test-browser-payload-contracts.R`), JS consumer/cache tests
(`srcjs/index.test.js`), producer/consumer code, generated bundle artifacts, and
this `DEVELOPMENT.md` section.

### Payload change checklist

Any payload contract change must be committed with all of the following updates:

1. Update `inst/protocol/browser-payload-contracts.json` with the message fields, IPC columns, cache family, and browser path policy.
2. Update the paired R producer test in `tests/testthat/test-browser-payload-contracts.R` so R payloads and Arrow IPC columns satisfy the manifest.
3. Update the paired JS consumer test in `srcjs/index.test.js` so every handler, resource URL shape, cache miss signal, and stale-version behavior remains covered.
4. Preserve cache-version behavior for `reduction_cached`, `expr_cached`, `updateReduction-cachedReductionKeys`, and `inputFeatures-cachedExprKeys`; current cache keys use the `::` delimiter and clear older-family entries on newer versions.
5. Update `DEVELOPMENT.md` when behavior contracts, validation rules, or architecture decisions change.
6. Run the targeted verification commands before merging:
   - `pixi run Rscript -e "devtools::test(filter = 'analysis-backend-contract')"`
   - `pixi run Rscript -e "devtools::test(filter = 'browser-payload-contracts|analysis-backend-contract')"`
   - `pixi run Rscript -e "devtools::test(filter = 'development-contract-docs|browser-payload-contracts|analysis-backend-contract')"`
   - `pixi run npm test -- srcjs/index.test.js srcjs/modules/arrowReader.test.js srcjs/modules/scatter/scatterModel.test.js`

### Runtime source-of-truth boundaries

- Analysis Mode source of truth: Seurat v5 object state and BPCells-backed assay layers. Analysis futures should use path-based BPCells work where needed and must not receive live Seurat/BPCells objects for large expression extraction.
- Explore Mode source of truth: validated, read-only Explore Parquet bundle files with DuckDB query plans and Arrow IPC writers. Explore Mode stays immutable during app runtime.
- Browser source of truth: versioned Arrow IPC payloads and compact decoded TypedArrays/category encodings. The browser may keep cold IPC buffers for reduction/expression caches, but should not receive raw matrices, full datasets, local filesystem paths, or secrets.
- LLM/assistant boundary: only capped summary data may leave the server; raw metadata, reductions, expression matrices, local paths, credentials, and arbitrary file contents stay out of assistant payloads.

## Important Behavior Rules

These rules should be preserved unless intentionally changed.

### Main panel

- Main panel expression mode uses only the first selected gene.
- Multiple selected genes do not create multi-gene expression rendering in the main scatter plot.

### Sparkline list

- Multiple genes may be selected.
- The first selected gene label is bold.

### VlnPlot

- VlnPlot menu must contain all numeric metadata columns.
- VlnPlot menu must contain all selected genes with available expression data.
- Selecting a VlnPlot menu item redraws VlnPlot immediately.

### DotPlot

- DotPlot requires at least two selected genes.
- DotPlot does not redraw on gene-selection change alone.
- DotPlot redraws on explicit action button click or on resize after first render.

### FeaturePlot

- FeaturePlot requires more than one selected gene and is unavailable for module-score mode.
- FeaturePlot does not redraw on gene-selection change alone.
- FeaturePlot redraws on explicit action button click or on resize after first render.

### ElbowPlot

- ElbowPlot shows PCA standard deviations when PCA data exists.
- ElbowPlot refreshes automatically on panel open.
- ElbowPlot refreshes automatically on panel resize.
- ElbowPlot refreshes automatically when client-side PCA summary data is updated.

### DEG analysis

- DEG settings are configured inside the floating DEG window.
- DEG results run only when the user clicks the DEG run button.
- DEG marker table and DEG heatmap live in the same floating DEG window.
- DEG marker table and DEG heatmap are rendered server-side in the floating DEG window.

## Performance Considerations

These changes were implemented with the repo's large-dataset constraints in mind.

- Avoid expanding full category metadata arrays for DotPlot panel state when only group labels are needed.
- Avoid auto-redrawing floating panels on every selection change.
- Keep main-panel expression handling single-gene to match current rendering assumptions.
- Decode Arrow dictionary-encoded metadata from index buffers directly in `srcjs/modules/arrowReader.js` instead of calling `col.get(j)` for every row. This preserves the Arrow IPC migration's performance benefit for 1M+ cells by avoiding slow per-element Arrow accessor calls on categorical metadata columns.
- Keep plot refresh signaling separate from transfer completion state. `R/app_server.R` now increments a dedicated `plotRefreshIndicator` when full metadata/reduction transfers finish, while view-driven redraws continue to use `scatterUpdateIndicator`. This prevents `mod_mainClusterPlot_server()` from directly depending on `metaProcessed()` and `reductionProcessed()` as redraw triggers.
- Prefer partial metadata transfers for column-scoped changes. `R/mod_UpdateMetaData.R` supports Arrow IPC patches via `meta_patch_ready`, and `srcjs/index.js` merges them into the existing client metadata object instead of replacing the entire metadata payload. `Cell Cycling` uses this path for `S.Score`, `G2M.Score`, and `Phase`.
- Version all Arrow IPC payload filenames by data epoch so the client can safely distinguish stale files from current files. Reduction, expression, metadata, metadata patches, and PCA standard deviations now include versioned hash inputs on the R side.
- Keep a cold client-side IPC cache only for reduction and expression payloads. `srcjs/index.js` stores fetched Arrow IPC `ArrayBuffer`s keyed by `{version, reduction}` and `{version, assay, gene}` and rehydrates typed arrays on demand. This avoids repeated server fetches for reduction switching and cleared/reloaded expression panels while conserving memory by not keeping extra decoded hot copies.
- Cache expanded categorical metadata and unique sorted levels per column object on the client. `srcjs/modules/deckScatter.js` now memoizes both expanded arrays and level lists so plot-mode derivation, legends, category selection, and rename-cluster filtering do not rebuild the same metadata repeatedly.
- Keep rename-cluster category filtering on the client. `srcjs/index.js` now computes rename selections directly from cached metadata and only sends the final selected cells to R on assign.
- Use adaptive split-panel grids for very high-cardinality `split.by` layouts. `srcjs/modules/scatter/scatterLayout.js` now balances columns/rows and shrinks minimum panel sizes as panel counts rise so the deck surface does not become excessively large.
- Keep main scatter rendering deck.gl-only with typed binary attributes. `srcjs/modules/deckScatter.js` builds `ScatterplotLayer` inputs from `Float32Array` positions and `Uint8Array` colors, applies the AGENTS.md point-size/opacity/pickability thresholds, and keeps base hover picking disabled at 2M+ points while lasso selection remains available through client-side geometry.

## Validation Performed

Recent validation included:

- `pixi run Rscript -e "devtools::test(filter = 'llm-context')"`
- `pixi run Rscript -e "devtools::test(filter = 'run-app-modes')"`
- `pixi run Rscript -e "devtools::test()"`
- `pixi run Rscript -e "devtools::load_all(); cat('loaded\\n')"`
- parse validation for `R/fct_llm_context.R`, `R/mod_LLMChat.R`, `R/app_server.R`, and `R/app_ui.R`
- `pixi run test-js`
- `pixi run R -e 'devtools::document()'`
- `pixi run build-js`
- parse validation for `R/app_ui.R`

At the time of writing, the R test suite passed with 173 tests. The JS test
suite previously passed with 69 tests. `devtools::check()` failed during local
`R CMD build` before package checks because the checkout's `.pixi` environment
contains debug symlink targets that cannot be copied into the temporary build
directory; this is a local build-copy issue rather than an LLM implementation
test failure.

## Backend Migration Notes

These notes capture the recent backend reconstruction from a DuckDB-centered runtime to a Seurat v5 + BPCells runtime.

### 12. BPCells is now the primary assay backend

Decision:

- Analysis Mode and Explore Mode now treat Seurat objects as the single source of truth.
- DuckDB-backed assay/query storage has been removed from the active app runtime.
- BPCells is a required part of the runtime rather than an optional acceleration path.
- Counts and normalized data layers are stored as BPCells-backed on-disk matrices whenever possible.

Why:

- The app already keeps metadata, reductions, clustering state, and other analysis state inside the Seurat object.
- Maintaining both Seurat and DuckDB introduced duplicated storage, conversion work, and synchronization overhead.
- BPCells keeps large assay layers memory-efficient while preserving Seurat workflows.
- The app's large-dataset guarantees depend on BPCells-backed storage being available in every supported environment.

Implementation notes:

- `R/fct_bpcells_backend.R` now owns BPCells detection, conversion, querying, bundle save/load helpers, and memory-conserving PCA helpers.
- `R/mod_dataInput.R` converts loaded Seurat objects to BPCells-backed assay layers through `ensure_bpcells_backing()`.
- Metadata, reduction, and expression transfers now read directly from the Seurat object rather than querying DuckDB.

### 13. Client data exports should remain low-memory

Decision:

- Metadata and reduction IPC generation can use `future_promise()` for Arrow file writing and browser notification.
- Analysis Mode expression IPC generation should remain in-process, queued one feature at a time per session, and should not use `multisession` workers.
- BPCells-backed Seurat reads should remain on the Shiny main thread.

Why:

- BPCells-backed assay data is not a good fit for inter-process transfer or forked worker access.
- Large Analysis Mode sessions already hold substantial Seurat/BPCells state in the main R process. Spawning R worker processes for expression queries can exceed low-memory Docker limits even when each feature vector is chunked.
- Expression extraction is already chunked through BPCells and Arrow IPC writers, so queuing avoids overlapping memory peaks without materializing full assay data.

Implementation notes:

- `R/mod_UpdateMetaData.R` and `R/mod_UpdateReduction.R` fetch Seurat/BPCells data in-process, then wrap Arrow IPC writing in background promises before notifying the browser on completion.
- `R/mod_InputFeature.R` queues expression transfers and writes each selected feature through the BPCells/Explore chunked IPC writer in the main R process before notifying the browser.

### 14. Metadata and reductions are exported directly from Seurat

Decision:

- Metadata Arrow IPC payloads come from `object[[]]`.
- Reduction Arrow IPC payloads come from `Embeddings(object[[reduction]])`.

Why:

- These structures are already in memory in Seurat and are faster to access directly than round-tripping through an external query engine.

Implementation notes:

- `R/mod_UpdateMetaData.R` now builds full and partial metadata payloads from `get_backend_metadata()`.
- `R/mod_UpdateReduction.R` now builds reduction payloads from `get_backend_reduction()` and sends PCA standard deviations directly from the Seurat object.

### 15. Expression queries now use Seurat/BPCells layer access

Decision:

- Feature expression extraction for the main scatter plot now reads from the selected Seurat assay layer directly.

Why:

- The backend is no longer split between Seurat state and DuckDB tables.
- This keeps expression serving consistent with the BPCells-backed assay storage model.

Implementation notes:

- `R/mod_InputFeature.R` uses `get_backend_expr()` for expression payload generation.
- `R/fct_bpcells_backend.R` chooses the preferred layer via `preferred_expr_layer()` and extracts feature vectors from the active BPCells or in-memory layer.
- Analysis Mode feature expression transfers use `prepare_backend_expression_transfer()` plus `extract_bpcells_expr_to_ipc()` so only one feature vector chunk is in memory at a time.

### 16. Processing mode should prefer BPCells-compatible code paths

Decision:

- Processing mode should assume Seurat calls may densify unexpectedly and should prefer BPCells-native or BPCells-compatible code paths.
- Full dense `scale.data` should not be preserved in portable BPCells bundles.

Why:

- Large datasets cannot tolerate accidental dense layer persistence.
- `ScaleData()` and related workflows can create expensive dense intermediates if left unchecked.

Implementation notes:

- `R/fct_bpcells_backend.R` provides `run_memory_conserving_processing()` and `run_memory_conserving_pca()`.
- BPCells-backed PCA uses BPCells matrix stats and truncated SVD when available.
- BPCells bundle export removes `scale.data` before saving to avoid shipping large dense matrices in portable archives.

### 16a. Seurat `ScaleData()` on BPCells supports scaling but not regression

Decision:

- Do not rely on `ScaleData(..., vars.to.regress = ...)` for BPCells-backed assay layers.
- BPCells-backed processing should use explicit BPCells-native scaling/PCA paths instead of Seurat regression-driven scaling.

Why:

- Seurat 5 provides an `IterableMatrix` method for `ScaleData()`, but that method only implements feature centering/scaling.
- The BPCells `IterableMatrix` path does not use `vars.to.regress`, `latent.data`, `split.by`, or regression models.
- This matches the behavior discussed in Seurat issue `#9676`, where users observed that regression requests on BPCells-backed data had no effect.

Implementation notes:

- Seurat's documented `ScaleData.IterableMatrix` signature omits `vars.to.regress`.
- The current Seurat implementation uses `BPCells::matrix_stats()` and row-wise transforms for scaling, but does not run regression in the `IterableMatrix` method.
- `R/fct_bpcells_backend.R` avoids this gap in the main processing route by using `run_bpcells_pca()` / `run_memory_conserving_pca()` instead of relying on `ScaleData()` for BPCells-backed objects.

### 17. BPCells layer types are optimized for storage

Decision:

- BPCells counts layers should be written as integer-like storage.
- BPCells normalized data layers should be written as float storage rather than raw doubles.

Why:

- BPCells warns that compression performs poorly for non-integer matrices.
- Counts compress better as `uint32_t`, while normalized data is more efficient as `float` than as double.

Implementation notes:

- `R/fct_bpcells_backend.R` uses `optimize_bpcells_matrix_type()` before `write_matrix_dir()`.
- `R/mod_dataInput.R` applies the same optimization in `BPCells_Read10X()`.

### 17a. Portable bundles should not preserve Seurat graph state

Decision:

- scSpotlight BPCells bundles drop Seurat `graphs` and `neighbors` before saving the portable RDS.

Why:

- Neighbor and SNN graphs can be hundreds of MB for 500K+ cells and are not needed for initial visualization.
- Clusters are already represented in metadata, and graph state can be recomputed from PCA when clustering settings are updated.
- Keeping graph state in the serialized RDS can make a BPCells-backed bundle OOM before the assay layers are ever touched.

Implementation notes:

- `R/fct_bpcells_backend.R` removes graphs and neighbors through SeuratObject accessors in `prepare_bundle_object()` after BPCells layer paths are made portable.
- Large reduction prefetch is limited to the selected reduction to avoid copying several 500K+ cell coordinate payloads during initial load.

### 18. Portable BPCells downloads use a scSpotlight bundle contract

Decision:

- The BPCells download format is a self-identifying zip bundle, not just a generic compressed folder.
- The download menu also keeps a standard `.Rds` export for compatibility with tooling that expects a plain serialized Seurat object.

Why:

- A plain `.zip` does not indicate whether it contains a valid scSpotlight BPCells-backed Seurat bundle.
- Portable reuse requires a stable contract for locating the entrypoint RDS and the supporting BPCells layer directories.
- Some downstream workflows still expect a conventional `.Rds`, even though that path may need to materialize BPCells-backed layers first.

Implementation notes:

- `R/mod_Download.R` now defaults to `BPCells` format in Analysis Mode.
- `R/mod_Download.R` now uses a single confirm modal before standard `Rds` export for large or BPCells-backed objects.
- `R/mod_Download.R` uses `progressr::withProgressShiny()` for BPCells bundle export and for coarse-grained standard `Rds` export progress.
- `R/fct_bpcells_backend.R` writes bundles containing:
  - `manifest.json`
  - the Seurat `.Rds`
  - `supporting/<assay>/<layer>/...` BPCells directories
  - `load_bundle.R`
  - `README.txt`
- `manifest.json` includes `bundle_type = "scspotlight_bpcells_seurat_bundle"` and `rds_file` so the app can identify valid bundles.

### 19. Bundled BPCells Seurat objects must be loaded from the bundle directory context

Decision:

- Reusable BPCells zip bundles should be loaded through the app import path or the bundle loader helper, not by calling `LoadSeuratRds()` on the RDS from an arbitrary working directory.

Why:

- `SeuratObject::LoadSeuratRds()` rehydrates on-disk layers from the cached paths stored in the object.
- For relative paths like `supporting/RNA/counts`, path resolution depends on loading from the bundle directory context.

Implementation notes:

- `R/fct_bpcells_backend.R` provides `load_scspotlight_bundle()` to set the bundle directory context before calling `LoadSeuratRds()`.
- `R/mod_dataInput.R` uses the bundle-aware loader for direct `.Rds` input and for decompressed BPCells bundles.
- The saved bundle RDS now exposes the tool cache under `SaveSeuratRds`, matching what `LoadSeuratRds()` expects.

### 20. `.h5ad` bundle conversion should stream matrices through BPCells

Decision:

- `.h5ad` to BPCells bundle conversion should use `BPCells::open_matrix_anndata_hdf5()` for the matrix payload instead of first materializing a full Seurat object through `anndataR`.

Why:

- Large AnnData inputs can exceed memory limits if `X` is loaded fully into RAM before BPCells conversion.
- BPCells can read AnnData matrices lazily from HDF5, which keeps the conversion path aligned with the app's large-dataset constraints.

Implementation notes:

- `R/fct_bpcells_backend.R` now prefers native BPCells `.h5ad` import and falls back to reconstructing CSR/CSC matrices plus AnnData dataframe encodings via `rhdf5` when BPCells cannot open the matrix layout directly.
- `R/mod_dataInput.R` now accepts direct `.h5ad` uploads and routes them through the same BPCells-backed import path used by bundle conversion.
- `R/fct_bpcells_backend.R` also provides Scanpy-compatible `.h5ad` export. It writes `X` and sparse matrix layers with BPCells, then fills the AnnData structure (`obs`, `var`, `raw`, `obsm`, `varm`, `uns`) with `rhdf5`.

## Explore Parquet Bundle Format

The Explore Parquet bundle is the read-optimized Explore Mode distribution format. It is produced by `convert_to_explore_bundle()` and loaded by `R/mod_dataInput.R` through `read_scspotlight_explore_bundle()`.

### Format goals

- Keep Explore Mode startup independent of Seurat/BPCells object loading.
- Keep the canonical stored data portable across R, Python, Arrow, DuckDB, and other Parquet readers.
- Keep expression lookup fast enough for interactive single-gene queries at 1M+ cells.
- Keep all cross-table joins on zero-based integer ids, not barcodes or gene names.

### Archive and discovery contract

- The converter writes a `.zip` archive containing one bundle root directory.
- The bundle root is identified by `manifest.json` with `bundle_type = "scspotlight_explore_parquet_bundle"`.
- Explore Mode accepts only `.explore-parquet.zip` archives as user input. Direct extracted bundle directories and direct `manifest.json` paths remain internal discovery helpers, but they are not exposed as supported Explore Mode inputs.
- The bundle is immutable/read-only at app runtime. User-created metadata during an Explore session is client/session state unless a future explicit export path is added.

### Required file layout

```text
<bundle>/
  manifest.json
  cells.parquet
  metadata.parquet
  features.parquet
  reductions/
    <reduction>.parquet
    pca_stdev.parquet        # optional, present when PCA stdev exists
  expression/
    block_00000.parquet
    block_00001.parquet
    ...
```

### `manifest.json`

Required fields for schema version 1:

- `bundle_type`: must be `scspotlight_explore_parquet_bundle`.
- `schema_version`: currently `1`.
- `created_at`: creation timestamp.
- `scspotlight_version`: package version that wrote the bundle.
- `assay`: exported assay name.
- `layer`: exported assay layer, usually `data`.
- `assays`: list of exported assays and layers.
- `default_assay`: default assay exposed to the app.
- `cell_count`: total number of cells.
- `feature_count`: total number of exported features.
- `block_size`: number of features per expression block.
- `expression_compression`: Parquet compression codec.
- `reductions`: dimensional reductions available under `reductions/`.

If any field changes incompatibly, bump `schema_version` and add a loader migration or a clear unsupported-version error.

### `cells.parquet`

Schema:

- `cell_idx`: zero-based integer cell id.
- `cell_id`: original cell barcode/name.

`cell_idx` is the dense, unique zero-based join key across bundle tables, with
values from `0` to `cell_count - 1`. `cell_id` is the canonical
Cell ID exposed to Analysis and browser code, and `cells.parquet` is the sole
canonical source of those IDs. The loader validates that Cell IDs are non-empty
and unique and that the cells table matches `manifest.json` `cell_count`.

### `metadata.parquet`

Schema:

- one column per metadata field.
- `.scspotlight_cell_idx`: required zero-based join key into `cells.parquet`.
- row names and the client-facing `cells` column are not stored.

The loader and direct metadata transfer path validate that metadata contains one
valid, unique `.scspotlight_cell_idx` for every row in `cells.parquet`; they do
not trust Parquet row position. Metadata is joined to `cells.parquet` and
transferred to the browser as Arrow IPC with the client-facing ordered `cells`
Cell-ID column. Do not add `cells` to canonical `metadata.parquet` unless the
schema is intentionally changed. Factors and logical columns are stored as
character-like values; numeric columns must replace `NaN` and infinite values
with missing values before writing. Explore Mode metadata transfers must stream
the DuckDB join through Arrow IPC chunks instead of materializing the full
metadata frame in R.

### `features.parquet`

Schema:

- `feature_idx`: zero-based integer feature id.
- `feature`: feature/gene name.
- `assay`: exported assay name.
- `layer`: exported layer name.
- `block`: integer expression block id.

`feature_idx` must be dense and ordered from `0` to `feature_count - 1`. The current block assignment is `feature_idx %/% block_size`.

### `reductions/<reduction>.parquet`

Schema:

- `cell_idx`: zero-based integer cell id.
- one column per reduction component, preserving the source embedding column names.

The app currently uses the first two component columns for the main scatter and renames them to `X` and `Y` in the IPC payload. Additional dimensions may be stored for external readers or future UI work.

### `reductions/pca_stdev.parquet`

Schema:

- `stdev`: PCA standard deviation values.

This file is optional. It is used for the client-side ElbowPlot when present.

### `expression/block_*.parquet`

Schema:

- `feature_idx`: zero-based integer feature id.
- `cell_idx`: zero-based integer cell id.
- `value`: non-zero normalized expression value.

Each block file contains sparse long-format expression rows for the features assigned to that block. Rows should be sorted by `feature_idx, cell_idx` when written. Missing `(feature_idx, cell_idx)` pairs represent zero expression.

Expression queries must use DuckDB. The app selects the correct block from `features.parquet`, runs `read_parquet(<block>) WHERE feature_idx = <id> ORDER BY cell_idx`, and writes a dense Arrow IPC `expr` vector only for the requested feature. Explore Mode expression transfers should fetch sparse rows and write dense Float32 IPC chunks incrementally so R never holds both the full sparse query result and dense vector at once. Do not reintroduce a full-block Arrow fallback for expression queries; it is substantially slower and higher-memory for common genes.

### Conversion path

- `convert_to_explore_bundle()` converts processed Seurat `.Rds` or `.h5ad` files into this format.
- `R/mod_DataConversion.R` exposes the same converter in the Analysis Mode Data Conversion panel as `Explore Bundle`.
- `R/mod_Download.R` exposes the same format for the current in-memory object as `Explore Parquet`.
- The converter requires metadata, normalized expression, and at least one reduction. Analysis Mode may compute missing processed state before conversion only through separate analysis workflows; the Explore bundle writer itself should not silently invent reductions.

### Runtime transfer path

- Parquet is the canonical stored format.
- Arrow IPC remains the R-to-browser transport format for metadata, reductions, PCA stdev, and expression vectors.
- `R/fct_explore_bundle.R` owns bundle loading and Parquet/DuckDB queries.
- `R/fct_bpcells_backend.R` exposes backend-agnostic helpers so app modules can work with either Seurat/BPCells objects or Explore bundles.
- Explore Mode transfer futures should receive paths/query plans only, not live bundle objects or eager data frames. Metadata, reductions, and expression all stream DuckDB fetch batches into Arrow IPC writers to keep server-side peak memory bounded by chunk size.
- Before an Explore metadata transfer, validate the dense unique `cells.parquet` index and Cell IDs plus the complete unique metadata index join. The IPC writer then joins on `.scspotlight_cell_idx` and emits canonical Cell IDs in `cells`.

## Scatter Interaction Notes

These notes capture recent fixes and interaction decisions for the main scatter plot, category sidebar, and rename-cluster workflow.

### 21. Multi-panel scatter interaction must treat every panel as a first-class viewport

Decision:

- Lasso hit-testing, highlight propagation, and legends must work across all scatter panels, not just the first panel.
- Repeated cell views, such as paired cluster/expression panels, should keep selection state synchronized across every panel that contains the same cells.
- Large `split.by` layouts should use adaptive grid geometry instead of a fixed two-column layout.

Why:

- The main scatter now operates in several true multi-panel modes, and panel-local assumptions caused hit-testing, highlight, and placement bugs.
- Fixed two-column layouts produced very tall deck surfaces for large split counts, which made viewport placement unstable.

Implementation notes:

- `srcjs/modules/lasso.js` now tests lasso polygons against canvas-relative projected coordinates so non-origin panels can be selected correctly.
- `srcjs/modules/deckScatter.js` now centralizes selection through `setSelectedCells()`, reconciles requested selections to the currently visible cell IDs, and mirrors repeated selected cells across every panel.
- `srcjs/modules/scatter/scatterLayout.js` now computes balanced panel grids and adaptive minimum panel sizes for high-cardinality split layouts: 400px for 1-11 panels, 320px for 12-23, 280px for 24-47, 240px for 48-71, 200px for 72-95, and 180px for 96+.
- `srcjs/modules/scatter/scatterRelayout.js` now measures panel rectangles relative to the deck container instead of relying only on offsets.
- `srcjs/modules/deckScatter.js` treats null, empty, and literal `undefined` metadata levels as missing so they do not appear as category legends, split panel titles, or selectable category IDs.

### 21a. Main scatter uses adaptive deck.gl binary layers

Decision:

- The main scatter remains a deck.gl `ScatterplotLayer` renderer with binary TypedArray attributes.
- Point size, opacity, and base pickability follow the AGENTS.md thresholds exactly, including disabled base picking at 2M+ cells.
- Lasso selection remains available for 2M+ cells even when hover/picking is disabled.

Why:

- The app must remain responsive for 1M+ cell reductions without canvas/SVG fallback paths or per-point object arrays.
- Hover picking is expensive at extreme scale, but explicit lasso hit-testing can still run from panel-local geometry after the user completes a gesture.

Implementation notes:

- `srcjs/modules/deckScatter.js` builds panel buffers as `Float32Array` positions and `Uint8Array` RGBA colors before creating deck.gl layers.
- `getPointOptions()` encodes the AGENTS.md thresholds: `<15K` uses size 4/opacity 0.8/pickable, `15K-50K` size 3/opacity 0.7/pickable, `50K-500K` size 2/opacity 0.6/pickable, `500K-1M` size 1/opacity 0.5/pickable, `1M-2M` size 0.5/opacity 0.4/pickable, and `2M+` size 0.2/opacity 0.2/non-pickable.
- `shouldEnablePicking()` does not re-enable base picking for `nPoints >= 2000000`, even when zoomed.
- `srcjs/modules/scatter/scatterModel.js` keeps main scatter expression mode first-selected-gene only. Category + expression with exactly two split levels creates paired `{split} : {group_by}` and `{split} : {gene}` panels; expression multi-split uses one expression panel per non-missing split level.

### 22. Category sidebar stays hybrid, but metadata expansion is cached on the client

Decision:

- The browser remains the source of truth for expanded metadata arrays and level discovery.
- The category sidebar still uses Shiny inputs, but those inputs are synchronized from one batched client snapshot.
- Client metadata expansion and unique-level derivation should be cached aggressively.

Why:

- The client already holds Arrow-decoded metadata, so repeated `expandMeta()` work is wasted CPU and allocation churn.
- Keeping `group.by` and `split.by` as Shiny inputs preserves existing module contracts while still removing expensive client recomputation.

Implementation notes:

- `srcjs/modules/deckScatter.js` now exposes cache-backed `expandMeta()`, `getMetaLevels()`, and `invalidateMetaCache()` helpers.
- `srcjs/modules/scatter/scatterModel.js` now derives group/split levels from cached level lists instead of rebuilding `Set(expandMeta(...))` repeatedly.
- `srcjs/index.js` now sends a single `metaSidebarState` payload containing available categorical columns plus current group/split levels.
- `R/app_server.R` and `R/mod_UpdateCategory.R` now consume that single snapshot and preserve the currently selected `group.by` / `split.by` values when choices are rebuilt.
- `R/mod_UpdateCategory.R` only increments `scatterUpdateIndicator` when the effective `(group.by, split.by)` pair actually changes.

### 23. Rename Clusters selection UX is client-side; assignment persistence remains server-side

Decision:

- The `Rename Clusters` section should perform group/split-level filtering and selected-cell preview entirely in the browser.
- Only the final assign action should round-trip to R for metadata persistence.
- Rename selectors should use stable native multi-select widgets.

Why:

- The browser already has the metadata needed to compute rename selections instantly.
- Server-side filtering introduced unnecessary latency and duplicated logic already present in the scatter client.
- Native multi-selects avoid selectize option/item desynchronization during dynamic choice refresh.

Implementation notes:

- `srcjs/index.js` now owns rename-cluster selector choice population, selector visibility, category-based cell filtering, and selected-cell count text updates.
- `srcjs/index.js` sends bounded `renameCluster-assignmentIntent` payloads immediately before assign so the server receives either validated lasso cell IDs or the current category context, never a full metadata column.
- `R/mod_AssignCellCluster.R` keeps assign-time input validation/notifications while `R/app_server.R` validates the assignment intent, resolves category cells from canonical Seurat metadata, mutates one metadata column, and requests the existing `meta_patch_ready` path.
- `R/mod_AssignCellCluster.R` now uses `selectize = FALSE` for `chosenGroup` and `chosenSplit`.
- `R/app_server.R` no longer passes obsolete rename-cluster category-filtering reactives into `mod_AssignCellCluster_server()`.

### 24. Main scatter overlays expose persistent total/selected cell counts

Decision:

- The main plot should show total and selected cell counts in a persistent top-right badge instead of relying on transient selection notifications.

Why:

- Selection is an ongoing interaction state, not a one-time event.
- A persistent badge is easier to scan and avoids toast noise during repeated selection workflows.

Implementation notes:

- `srcjs/modules/scatter/scatterUI.js` now creates and updates a `Total | Selected` badge.
- `srcjs/modules/deckScatter.js` updates that badge whenever lasso or category selection changes, with counts formatted by `Intl.NumberFormat`.
- `setSelectedCells()` reconciles selected IDs against current panel cell IDs so valid redraws preserve visible selections and ambiguous context changes immediately clear stale IDs to `Selected 0`.

### 25. Category legends and rename selectors must ignore null / missing category levels

Decision:

- Client UI should never synthesize a visible `undefined` category entry when metadata contains nulls or missing values.

Why:

- Null category values are a data condition, not a valid selectable level.
- Rendering `undefined` as a visible level confuses both legends and rename-cluster dropdowns.

Implementation notes:

- `srcjs/modules/deckScatter.js` now filters null category titles before building legends.
- `srcjs/index.js` now normalizes rename selector choices to distinct non-empty strings and ignores nullish values.

### 26. Rename selectors should only persist within one grouping context

Decision:

- Rename-cluster category selections should persist only while the same `group.by` / `split.by` context remains active.
- Explicit clear actions, including assign completion and manual deselect, must leave the rename selectors empty.

Why:

- Reused labels across different metadata columns can silently target the wrong cells if old rename selections carry into a new grouping context.
- Users expect `Assign` and manual deselect to fully clear the rename selection rather than immediately restoring the previous category-based selection.

Implementation notes:

- `srcjs/index.js` now tracks the last active `group.by` / `split.by` pair and only preserves rename selector values when that pair has not changed.
- `srcjs/index.js` now clears rename selector UI state after assign-time deselect and manual lasso deselect before resyncing category selection.
- `srcjs/index.test.js` covers both regressions: grouping changes clear stale rename selections, and assign leaves the rename selectors cleared.

### 27. Initial plot readiness depends on a real active reduction render

Decision:

- Batched reduction prefetch must render exactly one active reduction before reporting reduction transfer completion.
- The server-provided `activeReduction` takes precedence over any stale DOM select value from the previous dataset.
- If neither the server-provided active reduction nor the DOM value exists in the incoming payload, the client renders the first prefetched reduction rather than leaving the plot uninitialized.

Why:

- Dataset changes can temporarily leave the reduction select DOM with a value from the previous object.
- If the client prefetches reductions but renders none, `reductionProcessed` never reaches Shiny and the initial waiter can remain visible.
- Rendering a deterministic fallback is safer than waiting for another reduction change event that may never arrive.

Implementation notes:

- `srcjs/index.js` resolves active reductions through `resolveActiveReduction()`.
- `reductions_ready` fetches and plots the resolved active reduction before warming the cache with inactive reductions.
- `srcjs/index.test.js` covers stale DOM reduction values and missing active-reduction fallback behavior.

### 28. Scatter render replacement must be atomic

Decision:

- The previous deck/gl scatter instance must not be destroyed until the replacement plot has completed setup.
- If replacement setup fails, the previous DOM nodes and plot instance are restored.

Why:

- Rendering now swaps plot DOM atomically to avoid partial redraw artifacts.
- Destroying the old instance too early makes rollback unsafe if late setup steps, such as selection handlers, throw.

Implementation notes:

- `srcjs/index.js` defers `previousReglElementData.destroy()` until after replacement setup succeeds.
- The catch path removes replacement nodes, restores previous plot/legend nodes, destroys only the replacement instance, and settles initial readiness if needed.
- `srcjs/index.test.js` covers both early render-generation failures and late setup failures.

### 29. Plot data transfer failures must be visible to users

Decision:

- Reduction and metadata transfer failures should show a visible in-plot error message, not only `console.error()`.
- Initial plot waiters should still settle on transfer failures so users are not trapped behind a loading overlay.

Why:

- Silent async failures make the plot area appear blank or indefinitely loading.
- A visible error gives users a recoverable next action, such as switching reductions or reloading the dataset.

Implementation notes:

- `srcjs/index.js` uses `handlePlotTransferError()` for `reduction_ready`, `reductions_ready`, `reduction_cached`, and `meta_ready` failures.
- Successful reduction or metadata transfer clears the visible transfer error.

### 30. Analysis Mode can derive missing processed state

Decision:

- Explore Mode should continue requiring processed inputs with metadata, normalized data, and reductions.
- Analysis Mode may accept an object missing reductions and compute the missing HVG/PCA/neighbors/clusters/UMAP state.

Why:

- Analysis Mode is intended to complete analysis workflows from partially processed inputs.
- Requiring reductions in all modes regresses the existing RDS import path for processable datasets.

Implementation notes:

- `R/mod_dataInput.R` keeps `ensure_normalized_layer()` before validation.
- In Analysis Mode, `validate_seuratRDS()` computes missing HVGs and reductions before calling `assert_processed_input_requirements()`.
- When `backend_root` is available, the processed object is re-backed through BPCells after derived state is created.

### 31. h5ad export must not close unrelated HDF5 handles or overwrite source files

Decision:

- `write_h5ad_scanpy()` must not call `rhdf5::h5closeAll()`.
- h5ad-to-h5ad conversion with no explicit output path writes `<input>-scanpy.h5ad`.
- Explicit `output_file` paths that resolve to the input file are rejected.

Why:

- Shiny sessions share one R process, so global HDF5 handle closure can disrupt unrelated HDF5-backed workflows.
- In-place h5ad conversion risks destroying the source before conversion succeeds.

Implementation notes:

- `R/fct_bpcells_backend.R` now relies on local HDF5 handle close calls in helper functions.
- `convert_to_scanpy_h5ad()` normalizes input/output paths and rejects same-path conversion.

### 32. BPCells matrix coercion should fail clearly

Decision:

- Unsupported matrix-like inputs should fail before `BPCells::convert_matrix_type()` is called.

Why:

- Returning unsupported objects unchanged pushes failures downstream and produces less actionable BPCells errors.

Implementation notes:

- `R/fct_bpcells_backend.R` now reports the unsupported class from `coerce_bpcells_source_matrix()`.
- `tests/testthat/test-bpcells-matrix-coercion.R` covers the unsupported-input error.

## Files to Check for Future Changes

If behavior changes again, review these files together:

- `R/app_ui.R`
- `srcjs/index.js`
- `srcjs/modules/arrowReader.js`
- `srcjs/modules/featureSparkLine.js`
- `srcjs/modules/scatter/scatterModel.js`
- `srcjs/modules/deckScatter.js`
- `R/mod_UpdateMetaData.R`
- `R/fct_bpcells_backend.R`
- `R/fct_explore_bundle.R`
- `R/mod_dataInput.R`
- `R/mod_Download.R`
- `R/mod_InputFeature.R`
- `R/mod_UpdateReduction.R`
- `R/mod_mainClusterPlot.R`
- `R/app_server.R`
- `srcjs/modules/floatingPlots.js`

## Suggested Follow-up Discipline

When changing plot behavior in the future:

1. Update this file with the new rule and rationale.
2. Keep the interaction contract explicit for each floating panel.
3. Re-run `pixi run test-js`.
4. Rebuild the frontend bundle with `pixi run build-js` before manual browser verification.

## Engineering Workflow Configuration

### Scope

The repository now includes the per-repo configuration used by the engineering skills for issue tracking, triage, and domain-document discovery.

### Key Decisions

- GitHub Issues are the issue tracker, operated through the `gh` CLI.
- The canonical triage labels remain `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`.
- The repository uses the single-context domain documentation layout with root `CONTEXT.md` and `docs/adr/`.
- The existing broad `docs` ignore rule was narrowed so `docs/agents/` configuration remains versioned while other generated documentation remains ignored.

### Validation Performed

- Confirmed the GitHub remote and existing agent instructions.
- Confirmed the repository has no monorepo signals or prior Matt Pocock skill configuration.
- Ran `git diff --check` after writing the configuration.

## Architecture Research

### 33. Million-cell architecture alternatives research

- Added `docs/architecture-research-2026-08.md` as a primary-source research note comparing retention, hybridization, and replacement of the R/Shiny architecture.
- The note records options and evidence only; it does not change the application source-of-truth boundaries or select an implementation plan.

### 34. Versioned Subset/Restore Analysis Transition slice

Decision:

- The long-term architecture is hybrid: R/Seurat/BPCells remains the Analysis kernel, while a future language-neutral query interface and Python query process may be added later.
- The first migration slice stays inside the existing R/Shiny runtime and does not introduce Python, TileDB-SOMA, durable Analysis Artifacts, a TypeScript migration, or a browser protocol migration.
- Analysis state uses a server-owned monotonic logical Analysis Version per Session/Analysis lineage during Phase 1.
- Each Analysis load receives a server-owned lineage ID in addition to its logical version counter, so a version-zero intent captured before a Dataset Artifact reset cannot mutate the replacement Analysis.
- Filter changes View state only. Subset and Restore are Analysis Mutations.
- Restore creates a new forward Analysis Version that reuses an earlier scientific state; it never rewinds the version counter.
- Analysis Mutations are serialized and atomic. Stale, empty, invalid, cancelled, or failed requests publish no version and leave the active Analysis unchanged.
- The Analysis Transition seam is the sole writer for Subset and Restore. Its Change-set remains server-internal and existing metadata, reduction, expression, cache, and transfer-error contracts remain the browser seam.
- The controller is constructed only for Analysis Mode. Explore Mode continues to load its read-only artifact directly without invoking the Seurat-only transition reset path.

Why:

- This establishes a testable scientific-state model without paying the risk of a language or storage rewrite.
- Monotonic versions prevent stale asynchronous work and browser caches from being mistaken for current Analysis state.
- Reusing existing payload contracts keeps the first vertical slice small while preserving the low-memory and BPCells rules.

Implementation and tracking:

- The full specification is GitHub issue `#21`.
- Child tickets `#22` through `#27` are linked under `#21` with native blocking relationships.
- The domain vocabulary is recorded in the root `CONTEXT.md`.
- `R/fct_analysis_transition.R` owns the deterministic transition evaluator and the Session-scoped controller. The controller owns the original Analysis backup, logical version state, last server-internal Change-set, reset operation, and re-entrant mutation guard.
- `R/app_server.R` constructs one controller per Shiny Session. `R/mod_dataInput.R`, `R/mod_AssignCellCluster.R`, and `R/mod_SubsetCells.R` pass requests through that controller instead of writing Subset/Restore state directly.
- A successful Analysis dataset reset also clears the nested Subset switch through an Analysis-only UI callback, keeping the visible control aligned with the new lineage.
- `tests/testthat/test-subset-cells.R` verifies successful Subset/Restore lineage, Change-set publication, strict and cancelled intents, failed transitions, reset behavior, and re-entrant mutation rejection with deterministic Seurat fixtures.
- Targeted validation passed with `pixi run Rscript -e "devtools::test(filter = 'subset-cells')"` and adjacent mutation/document/runtime tests passed with `pixi run Rscript -e "devtools::test(filter = 'analysis-mutation-safety|development-contract-docs|run-app-modes')"`.
- This checkout has no checked-in deterministic Playwright/end-to-end harness or representative 1M+ benchmark fixture. Issue #27 live-browser and large-dataset evidence therefore remains separate work and must not be inferred from unit or module-level integration tests.

### 35. Canonical Cell-ID and expression-epoch hardening

Decision:

- Arrow metadata `cells` is an ordered canonical Cell-ID vector in both
  Analysis and Explore Mode, not a zero-based numeric row index and not a
  categorical metadata column.
- A metadata patch is position-safe only when its Cell-ID vector exactly
  matches the active vector.
- Analysis object replacement invalidates the preceding expression epoch even
  if no prior expression payload has reached the browser cache.
- `cells.parquet` is the authoritative Cell-ID table for Explore bundles;
  metadata references it only through `.scspotlight_cell_idx`.

Why:

- Stable Cell IDs keep lasso, category Subset, Restore reconciliation, and
  partial metadata patches independent of browser array positions.
- Treating unique Cell IDs as categories would allocate one category bucket per
  cell and is not viable for million-cell metadata.
- Cache-only invalidation could allow a queued old expression job to apply when
  a replacement occurred before that job populated the cache.
- Trusting metadata row order in an Explore bundle could silently attach
  annotations to the wrong cells.

Implementation notes:

- `R/mod_UpdateMetaData.R` fails closed when metadata lacks explicit canonical
  row names, and `R/fct_explore_bundle.R` joins validated Explore metadata to
  `cells.parquet` before emitting IPC.
- `srcjs/modules/arrowReader.js` decodes `cells` as `cell_id`; text metadata
  remains category encoded. `expandMeta()` returns the ordered Cell-ID vector
  directly, including the cluster-only scatter path.
- `srcjs/index.js` rejects a mismatched or reordered Cell-ID sequence in
  `meta_patch_ready`. A full `meta_ready` only clears expression state when the
  Cell-ID population/order changes.
- `R/mod_SubsetCells.R` and `R/mod_dataInput.R` send the previous numeric
  `geneUpdateIndicator` through `clear_expr`. `srcjs/index.js` blocks
  expression payloads at or below that invalidated expression epoch and checks
  the current request generation after every asynchronous phase.
- `R/mod_AssignCellCluster.R` validates browser category context against the
  server-owned group, split, and metadata version before the Subset module
  builds the transition intent.
- Explore reduction transfers validate dense, unique `cell_idx` coverage before
  emitting position-based coordinates. Requested Explore expression rows are
  validated for unique in-range Cell indexes and finite values before streaming
  their dense Arrow IPC vector.

Validation performed for this hardening slice:

- `pixi run Rscript -e "devtools::test(filter = 'explore-bundle|subset-cells|development-contract-docs|browser-payload-contracts|analysis-backend-contract|metadata-cleaning')"` passed 423 tests.
- `pixi run Rscript -e "devtools::test()"` passed 684 tests with 40 existing small-fixture/underlying-library warnings.
- `pixi run npm test` passed 15 test files and 135 tests.
- `pixi run npm run build` completed successfully and regenerated
  `inst/app/www/index.js` plus `inst/app/www/index.js.map`.
- `git diff --check` passed.
