# Feature Landscape

**Domain:** R/Shiny single-cell RNA-seq analysis and visualization app  
**Project:** scSpotlight  
**Researched:** 2026-06-16  
**Overall confidence:** HIGH — grounded in repository planning docs and inspected implementation files; no external market survey was needed for this feature-focused pass.

## Product Frame

scSpotlight should be scoped as a two-mode single-cell application:

- **Analysis Mode** is the full workflow for loading Seurat/BPCells-compatible data, deriving or updating processed state, annotating cells, running marker analysis, converting artifacts, and exporting results.
- **Explore Mode** is the read-only workflow for opening preprocessed scSpotlight Explore Parquet bundles and interactively inspecting reductions, metadata, and feature expression without mutating the source artifact.

The most important feature constraint is not breadth; it is **large-dataset viability**. Any feature that forces eager full-matrix/full-metadata materialization, browser JSON table transfer, or non-WebGL rendering of million-cell scatter data should be treated as incompatible with the product direction.

## Table Stakes

Features users expect from a focused single-cell RNA-seq explorer. Missing these makes the product feel incomplete.

| Scope Category | Feature | Why Expected | Mode(s) | Complexity | Current Repo Grounding |
|---|---|---|---|---|---|
| Data input | Load Seurat `.Rds`, `.h5ad`, BPCells bundles, and compressed 10x matrix archives | Analysts arrive with Seurat/Scanpy/10x-style artifacts and need a path into the app | Analysis | High | `R/mod_dataInput.R` accepts these formats and routes through BPCells-backed import/validation |
| Data input | Load only `.explore-parquet.zip` artifacts in Explore Mode | Read-only exploration needs a portable, validated, processed artifact contract | Explore | Medium | `.planning/PROJECT.md` and `DEVELOPMENT.md` define Explore Parquet bundles; `R/mod_dataInput.R` enforces the extension and manifest |
| Data processing | Derive missing HVGs, PCA/neighbors/clusters/UMAP when Analysis Mode input is processable but incomplete | Analysis Mode should complete standard preprocessing instead of rejecting every partially processed object | Analysis | High | `validate_seuratRDS()` computes missing processed state in Analysis Mode |
| Data processing | Preserve BPCells-backed low-memory assay storage | Single-cell datasets can exceed RAM; BPCells is the app's canonical Analysis backend | Analysis | High | `AGENTS.md`, `.planning/PROJECT.md`, and `R/mod_dataInput.R` require/ensure BPCells backing |
| Main visualization | Render reductions as an interactive WebGL scatter plot | The central workflow is cell-level inspection on UMAP/tSNE/PCA-like embeddings | Both | High | `srcjs/modules/deckScatter.js` uses deck.gl and adaptive point settings |
| Main visualization | Switch reductions and cache/prefetch reduction payloads | Users compare UMAP/tSNE/PCA without reloading the whole dataset | Both | Medium | `R/mod_UpdateReduction.R` and `srcjs/index.js` implement reduction transfer/caching |
| Metadata visualization | Choose `group.by` and optional `split.by` categorical metadata | Standard single-cell inspection depends on coloring by clusters/cell types and faceting by sample/condition | Both | Medium | `R/mod_UpdateCategory.R`, `srcjs/modules/scatter/scatterModel.js` |
| Expression visualization | Query individual gene expression, cache it, show a mini distribution, and color the main scatter | Gene-level inspection is table stakes for scRNA-seq exploration | Both | High | `R/mod_InputFeature.R`, `srcjs/modules/featureSparkLine.js`, `srcjs/modules/scatter/scatterModel.js` |
| Multi-gene visualization | DotPlot and FeaturePlot for selected gene sets | Users need cluster-by-gene and multi-feature expression views beyond the main scatter | Both | Medium/High | Floating DotPlot/FeaturePlot panels in `R/app_ui.R` and `srcjs/index.js` |
| Distribution inspection | VlnPlot for numeric metadata and selected gene expression | Per-cluster expression/QC distributions are expected in Seurat-style workflows | Both | Medium | VlnPlot menu and rendering in `srcjs/index.js` |
| Selection | Lasso cell selection with persistent selected/total count | Interactive annotation and subsetting require reliable cell selection | Both for selection; Analysis for mutation | High | `srcjs/modules/deckScatter.js` and `srcjs/index.js` manage selection/highlights/count badge |
| Annotation | Assign selected cells to a new or existing metadata category | Analysts need to curate/rename clusters during manual annotation | Analysis | Medium | `R/mod_AssignCellCluster.R` plus client-side category/lasso selection in `srcjs/index.js` |
| Subsetting | Subset dataset to selected cells and restore original while switch is active | Common exploratory workflow after selecting a population | Analysis | Medium | `R/mod_SubsetCells.R` |
| Clustering/QC | Filter cells and update clustering by HVG method, dimensions, and resolution | Basic iterative single-cell analysis requires QC and reclustering controls | Analysis | High | `R/mod_FilterCell.R`, `R/mod_ClusterSetting.R` |
| Cell cycle | Add cell-cycle scores/phase as metadata patches | Common scRNA-seq QC/interpretation step | Analysis | Medium | `R/app_server.R` wires `mod_CellCycling_server()` to partial metadata patches |
| Marker analysis | Run FindAllMarkers-style DEG, view marker table, export CSV, and show heatmap | Marker discovery is a core analysis task after clustering/annotation | Analysis | High | `R/mod_DEG_Window.R`, `R/mod_FindMarkers.R`, `R/mod_DEG_Table.R` |
| Export | Download metadata, BPCells bundle, Explore Parquet bundle, Scanpy `.h5ad`, or standard `.Rds` with warnings | Users need portable outputs for downstream work and sharing | Analysis | High | `R/mod_Download.R`, `R/mod_DataConversion.R` |
| Progress/error UX | Visible progress, waiters, spinners, and recoverable plot-transfer errors | Large data transfers are slow enough that silent work feels broken | Both | Medium | `R/app_server.R`, `R/mod_UpdateMetaData.R`, `R/mod_UpdateReduction.R`, `srcjs/index.js` |

## Differentiators

Features that are not generic table stakes, but are valuable and should shape roadmap priorities.

| Feature | Value Proposition | Complexity | Keep / Build Because |
|---|---|---|---|
| Million-cell interactive scatter via deck.gl + TypedArrays | Makes scSpotlight credible for current large atlases, not only tutorial-sized datasets | High | This is the core product promise and is already the enforced rendering path |
| Seurat v5 + BPCells as canonical Analysis backend | Avoids duplicated Seurat/DuckDB runtime state while keeping assays on disk | High | Keeps the app aligned with common R workflows and large-data memory constraints |
| Explore Parquet bundle format | Enables lightweight, read-only dataset sharing without requiring Seurat object loading | High | This is the clean separation between authoring/analysis and broad exploration |
| Arrow IPC browser contracts | Faster, typed, versioned transfer of metadata/reductions/expression compared with JSON | High | Necessary for 1M+ cells and already embedded in the app architecture |
| Floating analysis panels with explicit-action rendering | Lets users inspect VlnPlot/DotPlot/FeaturePlot/DEG without expensive automatic redraws | Medium | Preserves responsiveness while keeping analysis context visible |
| Single-gene main expression, multi-gene floating plots | Avoids ambiguous main-plot color semantics while still supporting multi-gene analysis | Medium | This is a clear interaction rule documented in `DEVELOPMENT.md` |
| Client-side category selection for rename workflows | Avoids round trips for group/split filtering when metadata is already in the browser | Medium | Makes annotation feel instant without duplicating backend filtering logic |
| Portable conversion paths: BPCells, Explore Parquet, Scanpy h5ad | Reduces friction between R, Python, and read-only sharing workflows | High | Useful differentiator if kept low-memory and contract-driven |
| Optional summary-only AI assistant | Can help users interpret current app state without exposing raw data | Medium | Treat as a later visible differentiator; runtime exists but UI mounting is deferred |

## Anti-Features

Features to explicitly **not** build, especially for v1 roadmap scoping.

| Anti-Feature | Why Avoid | What to Do Instead |
|---|---|---|
| Arbitrary file loading in Explore Mode | Breaks the read-only processed-artifact contract and invites expensive processing in the wrong mode | Require `.explore-parquet.zip` bundles with valid manifests |
| A mirrored DuckDB assay/query store for Analysis Mode | Duplicates Seurat state, increases synchronization burden, and was already rejected | Use Seurat/BPCells directly for Analysis and DuckDB only for documented Explore Parquet queries |
| SVG/canvas main scatter for million-cell data | Cannot meet scale/performance expectations | Keep deck.gl/WebGL as the only main scatter path |
| Full metadata/reduction/expression JSON payloads | Browser/server memory and serialization costs become prohibitive | Use Arrow IPC, typed arrays, dictionary/categorical encodings, and chunked writers |
| Passing live Seurat/BPCells/Explore objects into background futures | Causes unsafe object transfer and memory spikes | Pass paths/query plans; keep Analysis expression extraction queued and in-process |
| Multi-gene composite coloring in the main scatter | Ambiguous semantics and conflicts with current rendering assumptions | Keep first selected gene for main expression; use DotPlot/FeaturePlot for multi-gene views |
| Auto-redrawing expensive floating plots on every selection change | Wastes webR/server work and makes selection unstable | Mark panels stale and require explicit plot actions or resize refresh after first render |
| Persisting dense `scale.data`, neighbor graphs, or huge graph state in portable bundles | Makes large bundles unusable and can OOM before assay layers are touched | Strip dense/graph state and recompute when needed |
| Provider credential entry through Shiny UI or raw-data LLM tools | High privacy/security risk for sensitive scRNA-seq data | Keep LLM disabled by default, server-side configured, summary-only, and without MCP for v1 |
| Broad omics platform expansion in v1: scATAC, spatial, multiome, trajectory, ligand-receptor, batch-integration workbenches | Expands scope beyond the app's core Seurat/BPCells visualization and annotation wedge | Defer until the core large-data scRNA-seq workflow is stable |
| Collaboration/audit/version-control features inside the app | Adds product surface unrelated to current architecture | Export portable artifacts and metadata; leave collaboration to external systems for now |

## Analysis Mode: Required User Capabilities

Analysis Mode should be scoped around an analyst who can modify and export the working object.

### 1. Load and normalize analysis inputs

Users must be able to:

1. Upload or select an input from `dataDir`.
2. Open processed Seurat `.Rds`, scSpotlight BPCells bundles, Scanpy/AnnData `.h5ad`, or compressed matrix directories.
3. Have the object converted or re-backed to BPCells where possible.
4. Have missing normalized layer / HVG / reduction state computed when the input is processable.
5. See clear progress and warning messages during load/validation.
6. Switch assays after load and trigger feature-list refresh.

### 2. Inspect the main embedding

Users must be able to:

1. Choose a reduction, preferably with UMAP/tSNE/PCA prioritized when present.
2. Group cells by a categorical metadata column.
3. Split cells by a categorical metadata column.
4. Pan/zoom/hover on the deck.gl scatter.
5. See cluster labels, legends, and a persistent total/selected cell count badge.
6. Recover from metadata/reduction transfer failures via visible in-plot errors.

### 3. Query and visualize features

Users must be able to:

1. Manually select genes from the active assay.
2. Upload gene-set lists as `.xlsx`, `.csv`, `.tsv`, or `.txt` and choose a gene set.
3. See feature extraction progress and a sparkline distribution for each loaded feature.
4. Toggle selected genes from the sparkline list.
5. Understand that the **first selected gene** drives the main scatter expression panel.
6. Use DotPlot/FeaturePlot for multi-gene views.
7. Clear loaded/selected features.
8. Optionally enable module-score coloring where supported, while keeping FeaturePlot unavailable during module-score mode.

### 4. Run standard analysis updates

Users must be able to:

1. Filter cells by feature-count and mitochondrial-percentage thresholds.
2. Re-run memory-conserving processing after filtering.
3. Update clustering by HVG method, PCA dimensions, and resolution.
4. Choose whether to update all processing, dimensions only, or resolution only.
5. Add cell-cycle metadata via partial metadata patching.

### 5. Annotate and subset cells

Users must be able to:

1. Select cells by lasso on the plot.
2. Select cells by current `group.by` and optional `split.by` categories from the rename panel.
3. See selected-cell counts persistently.
4. Assign selected cells to a metadata column/value.
5. Clear stale category selections when grouping context changes.
6. Optionally subset the working dataset to selected cells and restore the original while the subset switch is off.

### 6. Generate marker results

Users must be able to:

1. Open a floating DEG Analysis window.
2. Choose DEG method (`wilcox` or `MAST`) and thresholds (`min.pct`, logFC, adjusted p-value cutoff).
3. Run marker discovery explicitly.
4. View filtered marker rows in a table.
5. Export marker rows as CSV from the table.
6. View a heatmap of top significant markers grouped by the selected metadata column.

### 7. Export or convert results

Users must be able to:

1. Download metadata.
2. Download an Explore Parquet bundle for read-only sharing.
3. Download a BPCells bundle for portable low-memory reuse.
4. Download Scanpy-compatible `.h5ad`.
5. Download standard `.Rds`, but only after a warning for large/BPCells-backed objects.
6. Convert source `.Rds` or `.h5ad` files to Explore, BPCells, or h5ad outputs through the Data Conversion panel.

## Explore Mode: Required User Capabilities

Explore Mode should be scoped around a consumer who can inspect but not mutate a processed artifact.

### 1. Open a processed Explore artifact

Users must be able to:

1. Upload only a `.explore-parquet.zip` archive.
2. Receive a clear error if the archive lacks a valid scSpotlight Explore manifest.
3. Load metadata, reductions, PCA summaries when available, and expression blocks through the documented Parquet/DuckDB/Arrow path.

### 2. Inspect and compare views

Users must be able to:

1. Choose reductions.
2. Choose `group.by` and `split.by` from categorical metadata.
3. Query feature expression from the bundle.
4. Use the main scatter for category and first-selected-gene expression views.
5. Use VlnPlot, DotPlot, and FeaturePlot floating windows for read-only expression/metadata inspection.

### 3. Avoid accidental mutation

Explore Mode should **not** expose:

1. Cell filtering.
2. Clustering updates.
3. Cell-cycle scoring.
4. Rename-cluster / metadata assignment.
5. Subsetting that mutates a Seurat object.
6. DEG computation.
7. General source-file conversion.

Future read-only export from Explore Mode can be considered, but should be explicit and should not imply that the source bundle was changed.

## Established Interaction Patterns and Visible Workflows

These behaviors are already established and should be treated as requirements unless intentionally redesigned.

### Mode-dependent shell

- **Analysis left sidebar:** File Input, Data Conversion, Cell Filtering, Clustering Settings, Cell Cycling, Download Result.
- **Explore left sidebar:** File Input only.
- **Both right sidebars:** Reduction, Category, Feature Expression.
- **Analysis right sidebar additionally:** Rename Clusters.
- Collapsed sidebar rails provide icon access back into sidebar panels.

### Main scatter workflow

1. Dataset load triggers metadata/reduction/expression directories in the session temp path.
2. R writes Arrow IPC payloads and sends versioned custom messages.
3. JavaScript fetches/decode payloads and updates `reglScatterCanvas` state.
4. Plot readiness is signaled only after a real active reduction render.
5. Rendering replacement is atomic: if a new render fails, the previous plot remains available.
6. Multi-panel split layouts are first-class: lasso, highlighting, legends, panel titles, and labels must work across panels.

### Feature selection workflow

1. Manual selection or uploaded gene set starts expression extraction.
2. Sparkline rows show loading state, then expression distribution.
3. Clicking a sparkline toggles selected state.
4. The first selected gene label is bold.
5. The main plot uses only the first selected gene for expression coloring.
6. DotPlot and FeaturePlot use multi-gene selections but update only on explicit action or resize after initial render.

### Floating plot workflow

- Floating panels are opened from a rail, draggable, resizable, closable, and clamped to the main plot bounds.
- VlnPlot is menu-driven and redraws immediately when a menu item is selected.
- VlnPlot options include numeric metadata plus selected genes with loaded expression.
- DotPlot requires at least two selected genes and supports draggable custom cluster order.
- FeaturePlot requires at least two selected genes and exposes an `ncol` control.
- ElbowPlot is Analysis-only and auto-refreshes from PCA standard deviations when opened/resized/updated.
- DEG Analysis is Analysis-only and groups settings, marker table, and heatmap in one floating window.

### Annotation workflow

- Lasso selection and category-based selection share the selected-cell highlight path.
- Rename-cluster category selectors are client-side and context-scoped to the active `group.by`/`split.by` pair.
- Only the final assign action persists metadata server-side.
- Assign and deselect actions should clear category selections to prevent accidental carryover.

### Performance interaction rules

- Floating plots should not automatically rerender on every gene-selection change.
- Category metadata expansion and levels should be cached client-side.
- Reduction and expression IPC buffers should be versioned and cached with bounded limits.
- Partial metadata patches should be used for column-scoped changes instead of full metadata reloads.
- User-facing failures in metadata/reduction transfers should be visible in the plot area, not only in `console.error()`.

## V1 Scope Guardrails

For roadmap scoping, treat these as hard boundaries for v1 unless a separate phase explicitly changes the architecture.

| Boundary | Keep Out of v1 | Reason |
|---|---|---|
| Data scope | Arbitrary Explore inputs and unprocessed Explore files | Explore Mode is a read-only processed-artifact consumer |
| Analysis scope | Full Seurat/Scanpy workbench parity | scSpotlight's wedge is visualization, annotation, standard processing, marker analysis, and portable sharing |
| Visualization scope | Main-scatter multi-gene blend scores/colors | Current model deliberately uses the first selected gene; multi-gene views belong in floating panels |
| Scale scope | Dense full-matrix browser-side analytics | Breaks the million-cell constraint |
| AI scope | LLM-driven raw data analysis, credentials in UI, MCP tools | Privacy/security and summary-only guardrails are not yet mature enough |
| Persistence scope | Collaborative editing, audit history, user accounts | Not represented in current architecture and not needed for local Shiny package workflow |
| Export scope | Silent standard RDS materialization for large BPCells objects | Can be slow/memory-heavy; keep confirmation and prefer BPCells/Explore formats |
| Plot scope | Server-rendered main scatter or SVG/canvas million-cell path | deck.gl/WebGL is non-negotiable for scale |

## Feature Dependencies

```text
Valid input artifact → metadata transfer + reduction transfer → initial main scatter
Metadata transfer → categorical group.by/split.by choices → category legends + split panels
Reduction transfer → main scatter coordinates → lasso/hover/labels
Feature query → expression Arrow IPC → sparkline → selected feature list
Selected feature list → main scatter expression mode (first gene only)
Selected feature list + group.by → VlnPlot / DotPlot
Selected feature list + reduction data → FeaturePlot
PCA stdev transfer → ElbowPlot
group.by + loaded object → DEG run → marker table → DEG heatmap
Lasso/category selection → assign metadata → metadata patch/full update → plot refresh when active columns affected
Selected cells → subset workflow → gene/meta/reduction refresh
Processed Seurat/BPCells object → Explore/BPCells/h5ad/Rds export
Explore Parquet export → Explore Mode load → read-only visualization workflows
```

## MVP Recommendation for Future Requirements Scoping

Prioritize preserving and hardening the existing core before expanding scope:

1. **Load → render → inspect**: robust input validation, Arrow transfer, reduction/category/feature workflows, and visible error handling.
2. **Annotate → analyze → export** in Analysis Mode: rename/subset, clustering/QC updates, DEG window, and portable outputs.
3. **Share → explore**: Explore Parquet bundle creation plus read-only Explore Mode inspection at large scale.

Defer:

- Full AI assistant UI as a visible v1 feature: runtime guardrails exist, but UI mounting is explicitly deferred.
- Broader single-cell methods: trajectory, integration, ligand-receptor, automated cell-type annotation, scATAC/spatial/multiome.
- Collaboration and hosted multi-user workflows.

## Sources

- `.planning/PROJECT.md` — project value, active requirements, out-of-scope decisions, mode definitions.
- `AGENTS.md` — non-negotiable performance constraints, runtime modes, backend/frontend rules.
- `DEVELOPMENT.md` — established interaction rules for main scatter, floating plots, DEG, Explore bundles, and backend migration.
- `README.md` / `DESCRIPTION` — package purpose, run modes, dependency surface.
- `R/app_ui.R`, `R/app_server.R` — mode-specific UI shell and server orchestration.
- `R/mod_dataInput.R`, `R/mod_DataConversion.R`, `R/mod_Download.R` — input, conversion, and export workflows.
- `R/mod_UpdateReduction.R`, `R/mod_UpdateMetaData.R`, `R/mod_UpdateCategory.R`, `R/mod_InputFeature.R` — data transfer and user-facing plot controls.
- `R/mod_FilterCell.R`, `R/mod_ClusterSetting.R`, `R/mod_AssignCellCluster.R`, `R/mod_SubsetCells.R` — Analysis Mode mutation workflows.
- `R/mod_DEG_Window.R`, `R/mod_FindMarkers.R`, `R/mod_DEG_Table.R` — marker analysis workflow.
- `R/mod_LLMChat.R`, `R/fct_llm_context.R` — optional, disabled-by-default summary-only assistant behavior.
- `srcjs/index.js`, `srcjs/modules/featureSparkLine.js`, `srcjs/modules/deckScatter.js`, `srcjs/modules/scatter/scatterModel.js`, `srcjs/modules/floatingPlots.js` — browser interaction and rendering behavior.
