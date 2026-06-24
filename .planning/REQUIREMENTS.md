# Requirements: scSpotlight

**Defined:** 2026-06-16
**Core Value:** Users can load or create large processed single-cell artifacts and inspect metadata, reductions, expression, and marker signals interactively without materializing whole datasets in memory.

## v1 Requirements

Requirements for the current roadmap. Each requirement maps to exactly one roadmap phase.

### Backend Runtime

- [x] **BACK-01**: Developer can access Analysis Mode metadata, reductions, features, PCA summaries, and expression through Seurat/BPCells backend helpers without reintroducing a mirrored DuckDB runtime.
- [ ] **BACK-02**: Developer can access Explore Mode metadata, reductions, PCA summaries, and expression through validated Explore Parquet bundle paths/query plans without passing live bundle objects to futures.
- [ ] **BACK-03**: Developer can rely on mode gates that keep Analysis-only mutation workflows unavailable in Explore Mode.
- [ ] **BACK-04**: Developer can verify that optional packages such as `presto`, `ellmer`, and `shinychat` remain guarded and do not break core app startup when absent.

### Data Transfer Contracts

- [x] **XFER-01**: User can load a dataset and receive metadata as a versioned Arrow IPC payload with visible error handling on fetch/decode/write failure.
- [x] **XFER-02**: User can load or switch reductions through versioned Arrow IPC payloads and the app renders one real active reduction before reporting readiness.
- [x] **XFER-03**: User can query individual feature expression through queued, chunked, versioned Arrow IPC payloads without overlapping large BPCells/DuckDB memory peaks.
- [x] **XFER-04**: User can receive column-scoped metadata updates through `meta_patch_ready` without forcing full metadata reloads for every mutation.
- [x] **XFER-05**: Developer can change metadata, reduction, expression, PCA, or patch message payloads only with paired R producer tests, JS consumer tests, cache-version behavior, and `DEVELOPMENT.md` documentation.

### Main Scatter Interaction

- [x] **SCAT-01**: User can render reductions in the main deck.gl scatter with adaptive point size, opacity, and picking behavior suitable for 1M+ cells.
- [x] **SCAT-02**: User can group and split cells by categorical metadata while legends, labels, panel titles, and adaptive split-panel geometry remain correct.
- [x] **SCAT-03**: User can lasso cells across every panel in a multi-panel scatter layout and see synchronized highlights plus persistent total/selected cell counts.
- [x] **SCAT-04**: User can inspect expression in the main scatter using the first selected gene only, with the selected gene reflected in legend and sparkline state.
- [x] **SCAT-05**: User can recover from failed metadata or reduction transfers through visible in-plot errors rather than a silent blank plot or stuck waiter.

### Analysis Workflows

- [x] **ANAL-01**: Analysis Mode user can load supported Seurat `.Rds`, `.h5ad`, BPCells bundle, and compressed 10x-style inputs and have assay layers converted or preserved as BPCells-backed storage when possible.
- [x] **ANAL-02**: Analysis Mode user can derive missing normalized/HVG/PCA/neighbors/clusters/UMAP state for processable inputs through memory-conserving processing paths.
- [x] **ANAL-03**: Analysis Mode user can filter cells, update clustering, and add cell-cycle metadata without preserving dense `scale.data` or triggering unnecessary full-dataset transfers.
- [ ] **ANAL-04**: Analysis Mode user can select cells by lasso or category context and assign them to metadata values with stale rename selections cleared when grouping context changes.
- [ ] **ANAL-05**: Analysis Mode user can subset to selected cells and restore the original object while downstream metadata, reduction, feature, and plot state refresh correctly.

### Portable Artifacts and Explore Mode

- [ ] **BUND-01**: Analysis Mode user can export a self-identifying BPCells bundle with portable relative layer paths and without unnecessary dense scale, graph, or neighbor state.
- [ ] **BUND-02**: Analysis Mode user can export a schema-versioned Explore Parquet bundle containing manifest, cells, metadata, features, reductions, optional PCA summaries, and sparse expression blocks.
- [ ] **BUND-03**: Explore Mode user can open only validated `.explore-parquet.zip` artifacts and receives clear validation errors for unsupported or malformed inputs.
- [ ] **BUND-04**: Explore Mode user can inspect metadata, reductions, feature expression, and read-only floating plots from Parquet/DuckDB/Arrow paths without mutating the source bundle.
- [ ] **BUND-05**: Analysis Mode user can export Scanpy-compatible `.h5ad` and standard `.Rds` outputs with safeguards against source overwrite, unrelated HDF5 handle closure, and unconfirmed large RDS materialization.

### Floating Analysis Panels

- [ ] **PLOT-01**: User can open, drag, resize, close, and refocus floating plot panels without action buttons accidentally starting panel dragging.
- [ ] **PLOT-02**: User can inspect numeric metadata or selected gene expression in VlnPlot through a menu-driven floating panel that redraws immediately on menu selection.
- [ ] **PLOT-03**: User can render DotPlot for at least two selected genes only through explicit action or resize-after-render, with custom cluster order preserved.
- [ ] **PLOT-04**: User can render multi-gene FeaturePlot only through explicit action or resize-after-render, and FeaturePlot remains unavailable during module-score mode.
- [ ] **PLOT-05**: Analysis Mode user can run DEG analysis explicitly in the floating DEG window and inspect bounded marker table and heatmap outputs without blocking unrelated workflows indefinitely.

### Optional Assistant and Documentation

- [x] **DOCS-01**: Developer can update `DEVELOPMENT.md` whenever behavior contracts, packaging workflows, validations, or major architectural decisions change.
- [ ] **DOCS-02**: Developer can keep README, package docs, Pixi tasks, Docker guidance, and dependency metadata aligned with the current BPCells/Arrow/deck.gl/Explore architecture.
- [ ] **AI-01**: User can start the app without LLM dependencies or provider configuration unless `enableLLM = TRUE` is explicitly requested.
- [ ] **AI-02**: If enabled, assistant helpers expose only capped, aggregated, read-only summaries of app state, group counts, and top DEG rows.
- [ ] **AI-03**: If enabled, assistant code never accepts provider credentials through Shiny inputs or `run_app()` arguments and never sends raw metadata, expression matrices, reductions, local paths, or secrets to a provider.

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Analysis Breadth

- **BREAD-01**: User can run broader single-cell workflows such as trajectory inference, ligand-receptor analysis, automated cell-type annotation, or batch integration.
- **BREAD-02**: User can analyze scATAC, spatial, multiome, or non-scRNA-seq modalities through dedicated mode-aware data contracts.

### Collaboration

- **COLL-01**: User can collaborate through accounts, hosted multi-user sessions, shared audit history, or in-app artifact versioning.

### Assistant Expansion

- **AIV2-01**: User can interact with visible assistant UI after privacy/security review and explicit UI mounting decision.
- **AIV2-02**: Developer can integrate MCP-backed tools after summary-only helper contracts are proven safe.

### Explore Exports

- **EXPV2-01**: Explore Mode user can export read-only derived session state through an explicit non-mutating export contract.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Analysis Mode mirrored DuckDB assay/query store | Reintroduces duplicated source-of-truth state, memory overhead, and synchronization bugs. |
| SVG or canvas main scatter for million-cell datasets | Cannot satisfy the required 1M+ cell interaction path. |
| Full metadata, reduction, or expression JSON payloads | Too memory-intensive for large server-to-browser transfers. |
| Passing live Seurat, BPCells, or Explore bundle objects into futures | Risks object serialization, HDF5/BPCells handle problems, and worker memory spikes. |
| Arbitrary user files in Explore Mode | Explore Mode is a read-only processed-artifact consumer, not a processing runtime. |
| Multi-gene composite coloring in the main scatter | Current interaction contract uses the first selected gene; multi-gene views live in floating panels. |
| Auto-redrawing DotPlot or FeaturePlot on every feature-selection change | Causes expensive webR/server rerenders and unstable selection workflows. |
| Persisting dense `scale.data`, graphs, or neighbors in portable BPCells bundles | Can make large bundles unusable or trigger OOM before assay layers are touched. |
| LLM access to raw data, local paths, credentials, arbitrary files, or arbitrary R execution | Violates summary-only privacy and security constraints. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BACK-01 | Phase 1 | Complete |
| BACK-02 | Phase 4 | Pending |
| BACK-03 | Phase 4 | Pending |
| BACK-04 | Phase 6 | Pending |
| XFER-01 | Phase 2 | Complete |
| XFER-02 | Phase 2 | Complete |
| XFER-03 | Phase 2 | Complete |
| XFER-04 | Phase 2 | Complete |
| XFER-05 | Phase 1 | Complete |
| SCAT-01 | Phase 2 | Complete |
| SCAT-02 | Phase 2 | Complete |
| SCAT-03 | Phase 2 | Complete |
| SCAT-04 | Phase 2 | Complete |
| SCAT-05 | Phase 2 | Complete |
| ANAL-01 | Phase 3 | Complete |
| ANAL-02 | Phase 3 | Complete |
| ANAL-03 | Phase 3 | Complete |
| ANAL-04 | Phase 3 | Pending |
| ANAL-05 | Phase 3 | Pending |
| BUND-01 | Phase 4 | Pending |
| BUND-02 | Phase 4 | Pending |
| BUND-03 | Phase 4 | Pending |
| BUND-04 | Phase 4 | Pending |
| BUND-05 | Phase 4 | Pending |
| PLOT-01 | Phase 5 | Pending |
| PLOT-02 | Phase 5 | Pending |
| PLOT-03 | Phase 5 | Pending |
| PLOT-04 | Phase 5 | Pending |
| PLOT-05 | Phase 5 | Pending |
| DOCS-01 | Phase 1 | Complete |
| DOCS-02 | Phase 6 | Pending |
| AI-01 | Phase 6 | Pending |
| AI-02 | Phase 6 | Pending |
| AI-03 | Phase 6 | Pending |

**Coverage:**

- v1 requirements: 34 total
- Mapped to phases: 34
- Unmapped: 0

---
*Requirements defined: 2026-06-16*
*Last updated: 2026-06-22 after Phase 02 verification*
