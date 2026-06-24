# Roadmap: scSpotlight

## Overview

This MVP roadmap hardens scSpotlight around its core wedge: large single-cell datasets remain interactively inspectable through a Seurat/BPCells Analysis Mode, a read-only Explore artifact mode, Arrow IPC browser contracts, and a deck.gl scatter runtime. Phases follow the natural dependency chain from backend/protocol guardrails, to main data transfer and scatter reliability, to mutable Analysis workflows, portable sharing/Explore loading, floating analysis panels, and finally optional assistant/documentation safety.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Runtime Contract Backbone** - Lock Analysis backend seams and browser protocol change rules before higher-level workflows depend on them. (completed 2026-06-20)
- [x] **Phase 2: Arrow Transfer & Main Scatter Reliability** - Make metadata, reductions, expression, patches, and the main deck.gl scatter dependable at large scale. (completed 2026-06-22)
- [ ] **Phase 3: Analysis Mode Processing & Mutation Safety** - Preserve low-memory Analysis Mode loading, processing, mutation, annotation, subsetting, and restore behavior.
- [ ] **Phase 4: Portable Artifacts & Explore Mode End-to-end** - Deliver portable exports and validated read-only Explore artifact inspection without mode leakage.
- [ ] **Phase 5: Floating Analysis Panels & DEG Workflows** - Stabilize explicit-action floating visualizations and bounded DEG/marker inspection.
- [ ] **Phase 6: Optional Assistant Safety & Release Documentation** - Keep optional dependencies, assistant helpers, and public contributor docs aligned and safe.

## Phase Details

### Phase 1: Runtime Contract Backbone

**Goal:** Developers can rely on stable Analysis Mode backend seams and explicit browser-contract rules before user-facing workflows build on them.
**Mode:** mvp
**Depends on:** Nothing (first phase)
**Requirements:** BACK-01, XFER-05, DOCS-01
**Success Criteria** (what must be TRUE):

  1. Developer can access Analysis Mode metadata, reductions, features, PCA summaries, and expression through Seurat/BPCells helpers without reintroducing a mirrored DuckDB runtime.
  2. Developer can change metadata, reduction, expression, PCA, or patch payloads only with paired R producer tests, JS consumer tests, cache-version behavior, and documented protocol notes.
  3. `DEVELOPMENT.md` reflects any behavior contracts, validation rules, or major architecture decisions changed by this phase.

**Plans:** 3/3 plans complete
**Wave 1**

- [x] 01-01-PLAN.md — Lock Analysis Mode Seurat/BPCells backend helper seams with contract tests.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — Add browser payload manifest with paired R producer and JS consumer/cache tests.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-03-PLAN.md — Document runtime contract backbone and enforce docs coverage.

**UI hint**: no

### Phase 2: Arrow Transfer & Main Scatter Reliability

**Goal:** Users can load large datasets, receive versioned Arrow IPC payloads, and interact with the main deck.gl scatter without silent failures or stale render state.
**Mode:** mvp
**Depends on:** Phase 1
**Requirements:** XFER-01, XFER-02, XFER-03, XFER-04, SCAT-01, SCAT-02, SCAT-03, SCAT-04, SCAT-05
**Success Criteria** (what must be TRUE):

  1. User can load metadata and reductions through versioned Arrow IPC payloads and see visible in-plot errors if fetch, decode, or write steps fail.
  2. User can switch reductions and query first-selected-gene expression through queued, chunked, versioned Arrow IPC payloads without overlapping large BPCells/DuckDB memory peaks.
  3. User can render, group, and split 1M+ cell reductions in the main deck.gl scatter with correct adaptive point settings, legends, labels, titles, and split-panel geometry.
  4. User can lasso cells across every scatter panel and see synchronized highlights plus persistent total and selected cell counts.
  5. User can receive column-scoped metadata patches without forcing full metadata reloads for every mutation.

**Plans:** 4/4 plans complete

**Wave 1**

- [x] 02-01-PLAN.md — Make metadata and active-reduction Arrow transfers visible, current, and recoverable.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-02-PLAN.md — Harden queued BPCells and DuckDB/Explore expression transfer contracts.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 02-03-PLAN.md — Harden browser expression state, column-scoped metadata patches, and first-gene sparkline behavior.

**Wave 4** *(blocked on Waves 1–3 completion)*

- [x] 02-04-PLAN.md — Lock deck.gl scatter rendering, split-panel geometry, lasso, highlights, and counts.

**UI hint**: yes

### Phase 3: Analysis Mode Processing & Mutation Safety

**Goal:** Analysis Mode users can load, process, mutate, annotate, subset, and restore Seurat/BPCells-backed data without unsafe dense state or unnecessary full-dataset transfers.
**Mode:** mvp
**Depends on:** Phase 2
**Requirements:** ANAL-01, ANAL-02, ANAL-03, ANAL-04, ANAL-05
**Success Criteria** (what must be TRUE):

  1. Analysis Mode user can load supported Seurat `.Rds`, `.h5ad`, BPCells bundle, and compressed 10x-style inputs with assay layers converted or preserved as BPCells-backed storage when possible.
  2. Analysis Mode user can derive missing normalized, HVG, PCA, neighbors, clusters, and UMAP state through memory-conserving processing paths.
  3. Analysis Mode user can filter cells, update clustering, and add cell-cycle metadata without preserving dense `scale.data` or triggering unnecessary full-dataset transfers.
  4. Analysis Mode user can select cells by lasso or category context, assign metadata values, and see stale rename selections clear when grouping context changes.
  5. Analysis Mode user can subset to selected cells and restore the original object while downstream metadata, reduction, feature, and plot state refresh correctly.

**Plans:** 2/4 plans executed

**Wave 1**

- [x] 03-01-PLAN.md — Lock Analysis Mode loading and processing safety.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 03-02-PLAN.md — Harden filter, cluster, and cell-cycle mutation safety.

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 03-03-PLAN.md — Make assignment and category selection bounded and stale-safe.

**Wave 4** *(blocked on Waves 1–3 completion)*

- [ ] 03-04-PLAN.md — Stabilize subset and restore refresh semantics.

**UI hint**: yes

### Phase 4: Portable Artifacts & Explore Mode End-to-end

**Goal:** Users can export portable artifacts from Analysis Mode and inspect validated Explore Parquet bundles in a read-only workflow with strict mode gates.
**Mode:** mvp
**Depends on:** Phase 3
**Requirements:** BACK-02, BACK-03, BUND-01, BUND-02, BUND-03, BUND-04, BUND-05
**Success Criteria** (what must be TRUE):

  1. Analysis Mode user can export self-identifying BPCells bundles and schema-versioned Explore Parquet bundles with portable paths and without unnecessary dense scale, graph, or neighbor state.
  2. Explore Mode user can open only validated `.explore-parquet.zip` artifacts and receives clear validation errors for unsupported or malformed inputs.
  3. Explore Mode user can inspect metadata, reductions, PCA summaries, feature expression, and read-only floating plots through validated bundle paths/query plans without mutating the source bundle.
  4. Analysis Mode user can export Scanpy-compatible `.h5ad` and standard `.Rds` outputs with safeguards against source overwrite, unrelated HDF5 handle closure, and unconfirmed large RDS materialization.
  5. Developer can rely on mode gates that keep Analysis-only mutation workflows unavailable in Explore Mode.

**Plans:** TBD
**UI hint**: yes

### Phase 5: Floating Analysis Panels & DEG Workflows

**Goal:** Users can run floating VlnPlot, DotPlot, FeaturePlot, and DEG workflows through explicit, resize-aware interactions that do not destabilize the main scatter.
**Mode:** mvp
**Depends on:** Phase 4
**Requirements:** PLOT-01, PLOT-02, PLOT-03, PLOT-04, PLOT-05
**Success Criteria** (what must be TRUE):

  1. User can open, drag, resize, close, and refocus floating plot panels without action buttons accidentally starting panel dragging.
  2. User can inspect numeric metadata or selected gene expression in VlnPlot through a menu-driven floating panel that redraws immediately on menu selection.
  3. User can render DotPlot for at least two selected genes and multi-gene FeaturePlot only through explicit action or resize-after-render, with cluster ordering and module-score availability rules preserved.
  4. Analysis Mode user can run DEG analysis explicitly in the floating DEG window and inspect bounded marker table and heatmap outputs without blocking unrelated workflows indefinitely.
  5. Floating plot workflows remain stable across feature-selection changes and resize events without expensive automatic redraw loops.

**Plans:** TBD
**UI hint**: yes

### Phase 6: Optional Assistant Safety & Release Documentation

**Goal:** Users and developers can trust that optional assistant functionality, optional packages, and release-facing docs never compromise core startup, privacy, or architecture accuracy.
**Mode:** mvp
**Depends on:** Phase 5
**Requirements:** BACK-04, DOCS-02, AI-01, AI-02, AI-03
**Success Criteria** (what must be TRUE):

  1. User can start the app without LLM dependencies, optional acceleration packages, or provider configuration unless optional functionality is explicitly requested.
  2. If enabled, assistant helpers expose only capped, aggregated, read-only summaries of app state, group counts, and top DEG rows.
  3. If enabled, assistant code never accepts provider credentials through Shiny inputs or `run_app()` arguments and never sends raw metadata, expression matrices, reductions, local paths, or secrets to a provider.
  4. Developer can verify README, package docs, Pixi tasks, Docker guidance, and dependency metadata match the current BPCells/Arrow/deck.gl/Explore architecture.

**Plans:** TBD
**UI hint**: no

## Requirement Coverage

| Requirement | Phase |
|-------------|-------|
| BACK-01 | Phase 1 |
| XFER-05 | Phase 1 |
| DOCS-01 | Phase 1 |
| XFER-01 | Phase 2 |
| XFER-02 | Phase 2 |
| XFER-03 | Phase 2 |
| XFER-04 | Phase 2 |
| SCAT-01 | Phase 2 |
| SCAT-02 | Phase 2 |
| SCAT-03 | Phase 2 |
| SCAT-04 | Phase 2 |
| SCAT-05 | Phase 2 |
| ANAL-01 | Phase 3 |
| ANAL-02 | Phase 3 |
| ANAL-03 | Phase 3 |
| ANAL-04 | Phase 3 |
| ANAL-05 | Phase 3 |
| BACK-02 | Phase 4 |
| BACK-03 | Phase 4 |
| BUND-01 | Phase 4 |
| BUND-02 | Phase 4 |
| BUND-03 | Phase 4 |
| BUND-04 | Phase 4 |
| BUND-05 | Phase 4 |
| PLOT-01 | Phase 5 |
| PLOT-02 | Phase 5 |
| PLOT-03 | Phase 5 |
| PLOT-04 | Phase 5 |
| PLOT-05 | Phase 5 |
| BACK-04 | Phase 6 |
| DOCS-02 | Phase 6 |
| AI-01 | Phase 6 |
| AI-02 | Phase 6 |
| AI-03 | Phase 6 |

**Coverage:** 34/34 v1 requirements mapped exactly once.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Runtime Contract Backbone | 3/3 | Complete    | 2026-06-20 |
| 2. Arrow Transfer & Main Scatter Reliability | 4/4 | Complete    | 2026-06-22 |
| 3. Analysis Mode Processing & Mutation Safety | 2/4 | In Progress | - |
| 4. Portable Artifacts & Explore Mode End-to-end | 0/TBD | Not started | - |
| 5. Floating Analysis Panels & DEG Workflows | 0/TBD | Not started | - |
| 6. Optional Assistant Safety & Release Documentation | 0/TBD | Not started | - |

---
*Roadmap created: 2026-06-16*
