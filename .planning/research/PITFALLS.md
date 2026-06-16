# Domain Pitfalls

**Domain:** R/Shiny single-cell RNA-seq analysis and visualization app  
**Project:** scSpotlight  
**Researched:** 2026-06-16  
**Overall confidence:** HIGH — primarily grounded in repository constraints, implementation notes, and current planning research. External ecosystem findings were used only as support.

## Critical Pitfalls

Mistakes that can cause rewrites, major performance regressions, privacy failures, or unusable large-dataset workflows.

### Pitfall 1: Accidental full-dataset materialization

**What goes wrong:** A helper converts BPCells-backed layers, Explore Parquet metadata, sparse expression blocks, reductions, or marker matrices into full in-memory R data frames/matrices before writing transfer/export output.

**Why it happens:** Convenience functions (`as.matrix()`, broad `FetchData()`, full `collect()`, eager DuckDB queries, full block Arrow fallbacks, dense `scale.data`) work on tutorial-sized objects and fail only at atlas scale.

**Consequences:** Sessions OOM in Docker/local R, Shiny becomes unresponsive, exports fail midway, and users lose trust that the app handles 1M+ cells.

**Prevention:**

- Treat low-memory execution as the default design constraint.
- Use BPCells-backed layer reads in Analysis Mode and DuckDB query plans over Parquet in Explore Mode.
- Write Arrow IPC in chunks for metadata, reductions, and expression.
- Strip dense `scale.data`, graphs, and neighbor state from portable BPCells bundles unless a future phase explicitly adds a bounded contract.
- Use `run_memory_conserving_processing()` / BPCells-native PCA paths rather than regression-heavy dense Seurat processing for large objects.

**Detection / warning signs:**

- New code calls `as.matrix()`, `as.data.frame()`, `collect()` without `LIMIT`/chunking, or reads whole expression blocks.
- Peak RSS grows roughly with `cells × features` instead of chunk size.
- Tests pass on small fixtures but fail on 100K+ cells.
- Bundle exports include huge `scale.data`, `graphs`, or `neighbors` entries.

**Likely phase:** Backend contract, import/export, processing, DEG, Explore bundle, or any feature that touches assay-scale data.

### Pitfall 2: Passing live Seurat/BPCells/Explore objects into futures

**What goes wrong:** A background future receives `seuratObj()`, BPCells matrices, HDF5 handles, or an Explore bundle descriptor with live object state instead of a path/query-plan payload.

**Why it happens:** Shiny async patterns make it tempting to wrap expensive work in `future_promise()` without considering object serialization, process boundaries, and on-disk matrix handles.

**Consequences:** Large objects are copied into worker processes, BPCells/HDF5 assumptions break, memory doubles or triples, and background errors are hard to reproduce.

**Prevention:**

- For Explore Mode, pass only paths, manifest metadata, query parameters, and output IPC paths.
- For Analysis Mode expression extraction, keep the per-session in-process queue and chunked writer.
- Use futures only where the payload is already compact or where R has already prepared the data safely.
- Keep async completion tied to visible transfer-error handling.

**Detection / warning signs:**

- `future_promise({ ... seuratObj() ... })` or closures capture large reactives.
- Worker logs show serialization/HDF5/BPCells path errors.
- Memory spikes only when async work starts, even for one gene.
- Multiple expression transfers run simultaneously in a single session.

**Likely phase:** Transfer hardening, expression query work, metadata/reduction async work, conversion/export, any “make it non-blocking” refactor.

### Pitfall 3: Reintroducing mirrored DuckDB storage for Analysis Mode

**What goes wrong:** A new feature copies Seurat/BPCells assay, metadata, or reduction state into DuckDB tables for normal Analysis Mode queries.

**Why it happens:** DuckDB is valuable for Explore Parquet, so it may look like a universal query solution. But Analysis Mode already has canonical mutable state in Seurat.

**Consequences:** Two sources of truth drift apart, memory/storage use grows, update ordering becomes fragile, and prior backend-migration complexity returns.

**Prevention:**

- Keep Analysis Mode data access through backend seam helpers over Seurat/BPCells.
- Reserve DuckDB for Explore Parquet bundles and file/query-plan based transfers.
- If a feature needs query-like behavior in Analysis Mode, build a backend-seam helper that reads directly from Seurat/BPCells or compact metadata.

**Detection / warning signs:**

- New Analysis Mode code writes `metadata`, `expression`, or `reductions` tables to DuckDB.
- Data update code has to sync both Seurat and DuckDB after filtering, clustering, or annotation.
- Bugs appear where plot state differs from exported object state.

**Likely phase:** Backend refactors, query/filter features, marker workflows, Explore/Analysis unification attempts.

### Pitfall 4: Breaking Arrow IPC and browser message contracts

**What goes wrong:** A phase changes `meta_ready`, `meta_patch_ready`, `reduction_ready`, `reductions_ready`, `reduction_cached`, `pca_ready`, `expr_ready`, or plot refresh payload shape without updating both R producers and JS consumers.

**Why it happens:** Message handlers are distributed across R modules and `srcjs/index.js`; a local change can look harmless while invalidating cache keys, readiness signals, or decoder assumptions.

**Consequences:** Blank plots, stale reductions/expression, invisible transfer failures, stuck waiters, or wrong data rendered under an old cache key.

**Prevention:**

- Version every large transfer file and cache key by data epoch / assay / reduction / gene as applicable.
- Treat message payloads as protocols; document intentional migrations in `DEVELOPMENT.md`.
- Add R and JS tests for new payload shapes and stale-cache behavior.
- Keep visible plot-transfer errors for decode/fetch failures.

**Detection / warning signs:**

- Browser `console.error()` mentions Arrow decode, missing `url`, stale version, or unknown reduction/gene.
- Initial plot waiter never settles.
- Switching reductions/genes shows data from the previous dataset.
- Metadata patches apply to columns with mismatched lengths or types.

**Likely phase:** Transfer path changes, cache changes, metadata patch work, reduction prefetch, expression cache, Explore schema migration.

### Pitfall 5: Treating Explore Mode like Analysis Mode

**What goes wrong:** Explore Mode accepts arbitrary `.Rds`, `.h5ad`, extracted directories, or mutable workflows; or it silently computes missing reductions/metadata/expression state.

**Why it happens:** Both modes share UI and backend seams, so features can accidentally bypass mode gates.

**Consequences:** Explore Mode loses its read-only processed-artifact guarantee, starts doing heavy analysis in the wrong runtime, and can no longer be trusted for lightweight sharing.

**Prevention:**

- User-facing Explore input remains only `.explore-parquet.zip` with valid `manifest.json`.
- Keep filtering, clustering, cell-cycle scoring, metadata assignment, DEG, and conversion out of Explore Mode unless a future phase adds explicit read-only/export contracts.
- Keep Explore transfers path/query-plan based through `R/fct_explore_bundle.R`.

**Detection / warning signs:**

- Explore UI shows Analysis-only controls.
- Explore loader accepts Seurat/h5ad/10x files directly.
- Explore code mutates bundle files or session Seurat objects.
- Explore conversion code computes reductions “helpfully” during bundle load.

**Likely phase:** Mode-specific UI, input validation, conversion/export, feature parity requests.

### Pitfall 6: Main scatter performance regression

**What goes wrong:** Main scatter rendering becomes DOM/SVG/canvas-heavy, expands categorical metadata repeatedly, enables expensive picking at extreme scale, or creates unbounded split panels.

**Why it happens:** Visualization tweaks are often tested on small datasets where inefficient per-cell DOM work, repeated metadata expansion, or high-cardinality panels still feel acceptable.

**Consequences:** Million-cell interaction becomes sluggish, lasso/hover breaks, resize thrashes, and WebGL memory grows unnecessarily.

**Prevention:**

- Keep deck.gl as the only main scatter path.
- Keep coordinates/colors in TypedArrays.
- Use dictionary/categorical encodings and cached metadata expansions/levels.
- Preserve adaptive point size/opacity/pickable thresholds.
- Verify multi-panel split layout, lasso, highlight mirroring, and label placement across large split counts.

**Detection / warning signs:**

- Per-cell DOM nodes appear in scatter code.
- Repeated calls to expand full metadata arrays inside render loops.
- `split.by` with many levels produces huge scroll surfaces or misaligned lasso.
- Browser memory climbs on every redraw without cache eviction.

**Likely phase:** Scatter UX, multi-panel layout, category sidebar, lasso/selection, visual polish.

### Pitfall 7: Expression workflow ambiguity or overlapping extraction

**What goes wrong:** Main scatter starts blending multiple selected genes, expression transfer launches concurrently for many genes, or FeaturePlot/DotPlot auto-redraws on every selection change.

**Why it happens:** Users can select multiple genes, but the main panel currently has a clear first-selected-gene rule while floating panels handle multi-gene views.

**Consequences:** Users misinterpret expression colors, BPCells reads overlap and spike memory, webR repeatedly rerenders, and browser state becomes stale or inconsistent.

**Prevention:**

- Preserve “first selected gene controls main scatter expression.”
- Keep first selected gene visually emphasized in the sparkline list.
- Keep expression transfers queued one feature at a time per session.
- Keep DotPlot/FeaturePlot explicit-action and resize-aware, not auto-run on selection changes.

**Detection / warning signs:**

- Main scatter legend names a list or composite score not explicitly created.
- `selectedFeatures` changes trigger immediate DotPlot/FeaturePlot renders.
- Multiple `expr_ready` writes for the same session run concurrently.
- FeaturePlot becomes available during module-score mode without a new contract.

**Likely phase:** Feature expression, module scores, floating plot UX, gene-set upload, webR performance.

### Pitfall 8: LLM assistant leaks sensitive data or becomes a hidden dependency

**What goes wrong:** LLM code sends raw metadata, expression matrices, reductions, file paths, API keys, or open-ended tools to a provider; or `ellmer`/`shinychat` become required for normal startup.

**Why it happens:** Assistant features are valuable, and it is easy to expose “helpful” context without enforcing summary-only boundaries.

**Consequences:** Privacy/security breach, cloud data exfiltration, package installation failures, and loss of user trust for sensitive single-cell datasets.

**Prevention:**

- Keep `enableLLM = FALSE` by default.
- Keep `ellmer` and `shinychat` in `Suggests`.
- Never accept provider credentials through Shiny UI or `run_app()` arguments.
- Only expose capped, aggregated read-only summaries: app state, group counts, top DEG rows.
- Defer MCP tools until summary-only helper contracts are stable.

**Detection / warning signs:**

- Prompts include file paths, full cell IDs, full metadata columns, matrix values, or credentials.
- Chat UI mounts by default.
- Package startup fails when optional LLM packages are absent.
- Assistant tools can query arbitrary R expressions or files.

**Likely phase:** AI assistant UI, provider integration, MCP/tooling, interpretation features.

## Moderate Pitfalls

### Pitfall 1: Portable bundle contracts drift

**What goes wrong:** BPCells or Explore bundles are written without stable manifests, wrong relative paths, missing schema fields, or files that cannot be loaded outside the original session.

**Prevention:** Keep self-identifying `manifest.json` files, bundle-aware loaders, schema-version checks, and explicit unsupported-version errors. Load BPCells bundles through the bundle helper so relative `supporting/...` paths resolve correctly.

**Detection:** Bundle works immediately after export but fails after moving directories, uploading to another machine, or loading via Explore Mode.

**Likely phase:** Download/export, data conversion, bundle schema migration.

### Pitfall 2: h5ad conversion damages source files or global HDF5 state

**What goes wrong:** `.h5ad` conversion writes over its input or closes unrelated HDF5 handles in a shared Shiny R process.

**Prevention:** Reject same-path output, default no-output conversions to `<input>-scanpy.h5ad`, and avoid `rhdf5::h5closeAll()` in app code.

**Detection:** Unrelated HDF5-backed operations fail after export; source `.h5ad` becomes corrupt or partially overwritten.

**Likely phase:** AnnData import/export, Scanpy interoperability.

### Pitfall 3: DEG analysis blocks or over-materializes

**What goes wrong:** Marker analysis runs automatically, uses dense expression matrices, or renders huge tables/heatmaps without filtering.

**Prevention:** Keep DEG inside the explicit floating DEG workflow, require user action, cap/stream display output, prefer memory-aware methods, and treat `presto` as optional acceleration.

**Detection:** Clicking unrelated controls starts marker work; app freezes during DEG; exported tables are far larger than displayed; heatmap tries to render thousands of genes.

**Likely phase:** Marker analysis, DEG UX, optional method support.

### Pitfall 4: Metadata patch misuse causes wrong annotations

**What goes wrong:** Column-scoped updates replace full metadata unnecessarily, patch columns with wrong length/type, or stale category selections assign the wrong cells.

**Prevention:** Use `meta_patch_ready` for column-scoped changes, validate patch length/type, clear rename selections after assign/deselect, and reset selections when `group.by`/`split.by` context changes.

**Detection:** Cell-cycle scores force a full metadata reload; legends show old labels; rename dropdowns retain values after grouping changes; assignment count differs from highlighted cells.

**Likely phase:** Annotation, cell cycling, category sidebar, metadata transfer.

### Pitfall 5: Missing values become visible fake categories

**What goes wrong:** Null, NA, empty, or undefined category values become selectable levels or legend entries.

**Prevention:** Normalize metadata values before transfer and filter nullish/non-empty category labels in browser legend and rename selector code.

**Detection:** UI shows `undefined`, `null`, or blank cluster labels; assigning by category selects unexpected cells.

**Likely phase:** Metadata import, category sidebar, rename-cluster UX, Explore bundle loading.

### Pitfall 6: webR floating plots leak browser memory

**What goes wrong:** webR shelters are not purged, plot canvases accumulate, or resizing triggers repeated unbounded renders.

**Prevention:** Use `async`/`await`, purge shelters after every operation, clear previous plot output before replacing it, and preserve explicit-action semantics for expensive panels.

**Detection:** Browser memory increases after repeated VlnPlot/DotPlot/FeaturePlot use; performance degrades after opening/closing floating windows; resize causes rapid render loops.

**Likely phase:** Floating plots, webR upgrades, visual polish.

### Pitfall 7: Source-checkout environment drift

**What goes wrong:** Contributors add `renv`, install packages outside Pixi, update JS deps without lock alignment, or forget platform-specific package availability.

**Prevention:** Keep Pixi as the source-checkout manager, `DESCRIPTION` as runtime dependency source of truth, and README/DEVELOPMENT docs updated with workflow changes.

**Detection:** Works on one developer machine but fails in CI/Docker/Windows; `.libPaths()` points outside Pixi; `.pixi/` gets committed.

**Likely phase:** Dependency upgrades, CI/Docker, packaging, release prep.

## Minor Pitfalls

### Pitfall 1: README and implementation terminology drift

**What goes wrong:** Public docs mention older renderer/runtime assumptions while current code uses deck.gl, BPCells, Arrow IPC, and Explore Parquet contracts.

**Prevention:** Update README/README.Rmd and `DEVELOPMENT.md` when major behavior changes ship.

**Detection:** New contributors follow README guidance that conflicts with `AGENTS.md` or current code.

**Likely phase:** Documentation, release prep.

### Pitfall 2: Unclear progress/error UX for large operations

**What goes wrong:** Users see a spinner or blank plot with no actionable error when transfer/conversion/export fails.

**Prevention:** Keep visible in-plot transfer errors, progressr/waiter messages, and user-facing validation for unsupported inputs.

**Detection:** Errors appear only in browser console or R logs; initial waiters never dismiss.

**Likely phase:** Input validation, transfers, export/conversion, scatter refresh.

### Pitfall 3: Optional acceleration becomes mandatory behavior

**What goes wrong:** Code assumes `presto`, `ellmer`, `shinychat`, or provider-specific tools exist.

**Prevention:** Guard optional package use with `requireNamespace()` and clear fallback messages.

**Detection:** App startup or core workflows fail in minimal install even though optional package is only in `Suggests`.

**Likely phase:** DEG performance, LLM assistant, optional feature integration.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|----------------|------------|
| Backend contract/schema | Mirrored DuckDB runtime; materialization | Define backend seam first; verify Seurat/BPCells and Explore paths separately. |
| Large data transfer | Broken IPC contracts; stale cache | Add versioned payload tests and visible transfer-error tests before UI polish. |
| Explore bundle | Unprocessed inputs; schema drift | Accept only `.explore-parquet.zip`; enforce manifest/schema validation and migration policy. |
| Analysis processing | Dense `scale.data`; unsupported BPCells regression | Use BPCells-compatible PCA/scaling paths and document unsupported regression behavior. |
| Feature expression | Overlapping expression reads; multi-gene ambiguity | Preserve queue and first-selected-gene rule; keep multi-gene views in floating panels. |
| Annotation/cell cycling | Full metadata reload; stale category selection | Use metadata patches and clear context-scoped selections after assign/deselect. |
| DEG | Blocking huge analysis; oversized outputs | Run only on explicit action, cap table/heatmap display, use memory-aware methods. |
| Export/conversion | Standard RDS materialization; broken bundle paths | Default to BPCells/Explore bundles; warn for RDS; load from bundle context. |
| Frontend scatter | DOM/canvas performance regression | Keep deck.gl + TypedArrays + adaptive thresholds; test high-cardinality splits. |
| Floating plots | Auto-render loops; webR leaks | Explicit action for expensive plots, purge shelters, debounce resize. |
| LLM assistant | Raw-data/privacy leak; optional deps required | Summary-only tools, server-side credentials, disabled by default, optional packages guarded. |
| Packaging/CI | Pixi/DESCRIPTION drift | Update Pixi, lockfile, DESCRIPTION, README, and DEVELOPMENT together. |

## Sources

- `.planning/PROJECT.md`
- `AGENTS.md`
- `DEVELOPMENT.md`
- `README.md`
- `DESCRIPTION`
- `.planning/research/ARCHITECTURE.md`
- `.planning/research/FEATURES.md`
- `R/fct_bpcells_backend.R`
- `R/fct_explore_bundle.R`
- `R/fct_backend_transfer_adapter.R`
- `R/mod_dataInput.R`
- `R/mod_UpdateMetaData.R`
- `R/mod_UpdateReduction.R`
- `R/mod_InputFeature.R`
- `R/mod_Download.R`
- `R/mod_FindMarkers.R`
- `R/mod_LLMChat.R`
- `R/fct_llm_context.R`
- `srcjs/index.js`
- `srcjs/modules/deckScatter.js`
- `srcjs/modules/scatter/scatterModel.js`
- `srcjs/modules/scatter/scatterLayout.js`
- `srcjs/modules/floatingPlots.js`
- `srcjs/modules/featureSparkLine.js`
