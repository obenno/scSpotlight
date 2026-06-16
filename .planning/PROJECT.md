# scSpotlight

## What This Is

scSpotlight is an R/Shiny application for single-cell RNA-seq analysis, visualization, and read-only exploration of processed datasets. It serves analysts working with Seurat v5 objects, BPCells-backed assay layers, and portable Explore artifacts, with a main browser-based scatter workflow and floating analysis panels for expression, marker, and metadata inspection.

The project is already a substantial brownfield R package. This planning setup exists to guide future work without violating the app's central constraint: interactive workflows must remain viable for very large single-cell datasets, including 1M+ cells.

## Core Value

Users can load or create large processed single-cell artifacts and inspect metadata, reductions, expression, and marker signals interactively without materializing whole datasets in memory.

## Requirements

### Validated

- ✓ R/Shiny package structure built with golem and launched through `scSpotlight::run_app()`.
- ✓ Analysis Mode exists for full analysis workflows through `scSpotlight::run_app()`.
- ✓ Explore Mode exists for read-only workflows through `scSpotlight::run_app(runningMode = "explore")`.
- ✓ The package uses Seurat v5 as the primary analysis object model.
- ✓ BPCells is the required primary assay backend for low-memory assay storage.
- ✓ Browser-facing large data transfers use Arrow IPC payloads rather than JSON tables.
- ✓ The main scatter visualization uses a WebGL/deck.gl path with adaptive rendering thresholds.
- ✓ JavaScript source is bundled with Vite and tested with Vitest.
- ✓ Source-checkout development, CI, and Docker builds are managed through Pixi.
- ✓ Explore Parquet bundle format is documented as the read-optimized Explore Mode distribution format.

### Active

- [ ] Preserve the Seurat/BPCells runtime as the canonical backend for Analysis Mode metadata, reductions, and expression access.
- [ ] Preserve low-memory Explore Mode by accepting only processed Explore artifacts and streaming Parquet/DuckDB reads into Arrow IPC writers.
- [ ] Preserve stable browser-facing message contracts for metadata, reductions, expression, PCA summaries, metadata patches, and plot refresh events.
- [ ] Keep the main scatter plot responsive and correct across large datasets, expression mode, grouping, splitting, lasso selection, and multi-panel layouts.
- [ ] Keep floating plot workflows explicit-action, resize-aware, and stable across feature-selection changes.
- [ ] Keep DEG analysis grouped inside the floating DEG workflow with server-side marker table and heatmap rendering.
- [ ] Keep portable BPCells and Explore bundle import/export paths low-memory, self-identifying, and compatible with documented bundle contracts.
- [ ] Keep optional LLM assistant functionality disabled by default, server-side only, summary-only, and free of Shiny-provided credentials or full dataset/file-path disclosure.
- [ ] Keep package, Docker, Pixi, R, JavaScript, and documentation workflows reproducible enough for contributors and release checks.

### Out of Scope

- Reintroducing DuckDB as a mirrored assay/query store for Analysis Mode — duplicated Seurat and DuckDB state created synchronization and memory overhead.
- Main scatter rendering through SVG or canvas for million-cell datasets — WebGL/deck.gl is required for the large-data path.
- Passing full Seurat, BPCells, or Explore bundle objects into background futures — path/query-plan based work is the low-memory contract.
- Sending full metadata, reductions, expression matrices, local file paths, or secrets to an LLM provider — the assistant is summary-only and server-side.
- Accepting arbitrary user files in Explore Mode — user-facing Explore inputs remain constrained to processed Explore artifacts.
- Preserving full dense `scale.data` in portable BPCells bundles — dense layers can make large bundles unusable.
- MCP-backed LLM tools — explicitly deferred until summary-only helpers and runtime guardrails are stable.

## Context

The repository is an existing R package and Shiny app. `AGENTS.md` defines the operating manual for future code changes, including low-memory execution, stable browser contracts, Pixi as the only source-checkout environment manager, and mandatory documentation updates in `DEVELOPMENT.md` for major behavior changes.

`DEVELOPMENT.md` records recent architecture and behavior decisions. The largest backend change is the migration from a DuckDB-centered runtime to a Seurat v5 + BPCells runtime. Metadata and reductions now come directly from the Seurat object, expression queries use Seurat/BPCells layer access, and Explore Mode reads from a documented Parquet bundle format through DuckDB and Arrow IPC transfer paths.

The frontend has an explicit interaction model for large data. The main panel supports one expression layer at a time using the first selected gene, floating DotPlot and FeaturePlot panels redraw only on explicit action or resize, VlnPlot is menu-driven, ElbowPlot renders client-side from PCA standard deviations, and scatter/lasso/category interactions must work across multi-panel layouts.

An optional LLM assistant design exists in the repo. It is disabled by default, relies on optional `ellmer` and `shinychat` packages, uses local Ollama first, and must only expose compact summaries through read-only helpers rather than raw datasets or paths.

## Constraints

- **Scale**: The app must handle millions of cells, especially 1M+ cell workflows, without eager full-dataset materialization.
- **Memory**: Large transfers must stream or chunk data; avoid full dense matrices, full metadata copies, and overlapping expression extraction memory peaks.
- **Backend**: Analysis Mode data access uses Seurat/BPCells as the source of truth; Explore Mode uses processed Explore bundle paths and query plans.
- **Transport**: Arrow IPC remains the browser transport for metadata, reductions, expression vectors, PCA summaries, and metadata patches.
- **Frontend**: Main scatter rendering must stay WebGL/deck.gl-backed and use TypedArrays and compact categorical encodings for large payloads.
- **Runtime Modes**: Analysis Mode and Explore Mode are distinct user-facing modes; Explore Mode input must stay constrained to processed Explore artifacts.
- **Security/Privacy**: LLM functionality must not accept credentials through Shiny inputs or expose full datasets, expression matrices, local paths, or secrets.
- **Packaging**: Pixi remains the repo environment manager for source-checkout development, CI, JavaScript builds, and Docker builds.
- **Documentation**: `DEVELOPMENT.md` must be updated when features, behavior contracts, packaging workflows, validations, or architectural decisions change.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use Seurat v5 + BPCells as the primary runtime backend | Avoid duplicated Seurat/DuckDB state and keep large assays on disk | ✓ Good |
| Use Arrow IPC for R-to-browser large data transfer | Preserve typed binary transport and avoid large JSON payloads | ✓ Good |
| Use Explore Parquet bundles for read-only Explore Mode | Keep canonical stored data portable and streamable through DuckDB/Arrow | — Pending |
| Keep expression transfers queued in-process for Analysis Mode | Avoid worker-process memory spikes and unsafe BPCells object transfer | ✓ Good |
| Keep floating DotPlot/FeaturePlot explicit-action | Prevent expensive automatic webR/server rerenders during selection changes | ✓ Good |
| Keep main panel expression mode single-gene | Avoid ambiguous multi-gene color semantics and preserve current rendering assumptions | ✓ Good |
| Keep optional LLM assistant disabled-by-default and summary-only | Protect sensitive large analysis state and avoid mandatory provider setup | — Pending |
| Use Pixi instead of renv for source-checkout development | Keep one environment path for R, JS, CI, and Docker workflows | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-16 after initialization*
