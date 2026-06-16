# Project Research Summary

**Project:** scSpotlight  
**Domain:** R/Shiny single-cell RNA-seq analysis, visualization, and read-only exploration at million-cell scale  
**Researched:** 2026-06-16  
**Confidence:** HIGH

## Executive Summary

scSpotlight is a brownfield R/Shiny/golem application whose winning constraint is large-dataset viability, not broad single-cell method parity. It should remain a two-mode product: **Analysis Mode** for mutable Seurat v5/BPCells workflows and **Explore Mode** for read-only inspection of processed `.explore-parquet.zip` artifacts. The core user value is loading or creating large single-cell artifacts, then inspecting metadata, reductions, expression, annotations, and marker signals without materializing full datasets in memory.

The recommended direction is to harden the architecture already present in the repo. R owns persistent analysis state; JavaScript owns interactive rendering state; versioned Arrow IPC files are the large-payload boundary. Analysis Mode should read metadata, reductions, and expression directly from Seurat/BPCells through backend seam helpers. Explore Mode should stream validated Parquet bundle data through DuckDB query plans into Arrow IPC writers. The main scatter must stay deck.gl/WebGL-backed with TypedArrays, adaptive render settings, compact categorical encodings, and stable cache/message contracts.

The biggest risks are accidental full-dataset materialization, unsafe async object transfer, protocol drift between R and JS, Explore/Analysis mode leakage, and privacy-sensitive LLM expansion. The roadmap should therefore prioritize contract hardening, transfer/scatter reliability, low-memory mutation/export paths, and realistic large-dataset profiling before optional AI UI, broader omics methods, collaboration, or hosted multi-user features.

## Stack

Use the repo's existing stack; do not introduce parallel runtimes or environment managers.

- **R 4.4-4.5 via Pixi, Shiny, golem:** keep the current app/package structure and reproducible Pixi-managed development, CI, JS, and Docker workflow. `DESCRIPTION` still advertises R >= 4.1.0, but Pixi and modern native deps imply the real development floor is R 4.4+.
- **Seurat v5 + SeuratObject v5:** the canonical Analysis Mode object model for metadata, reductions, assays, clustering, and marker workflows.
- **BPCells:** required primary assay backend for large Analysis Mode objects; avoids dense full-matrix RAM blowups and supports low-memory processing/export paths.
- **Arrow IPC:** non-negotiable browser transport for metadata, reductions, expression vectors, PCA summaries, and metadata patches. Avoid JSON for cell-level payloads.
- **DuckDB + Parquet:** use only for immutable Explore Parquet bundle queries, not as a mirrored Analysis Mode assay/query store.
- **deck.gl + TypedArrays:** the only credible main scatter rendering path for 1M+ cells; keep adaptive point size, opacity, and picking thresholds.
- **Vite + Vitest:** keep ES module source, Vite library bundle output to `inst/app/www/index.js`, and jsdom-based JS tests for scatter/IPC state.
- **webR:** useful for browser-side floating plot helpers, but optional and memory-sensitive; purge shelters after every operation and keep expensive renders explicit-action.
- **Optional LLM packages (`ellmer`, `shinychat`):** remain `Suggests`, disabled by default, server-side, summary-only, and outside the core runtime.

Avoid `renv`, SVG/canvas main scatter, JSON cell tables, live Seurat/BPCells objects in futures, Analysis-mode DuckDB mirrors, mandatory LLM dependencies, and broad new omics stacks in v1.

## Table Stakes

These capabilities are expected for scSpotlight to feel complete and should be treated as requirements unless deliberately descoped.

### Analysis Mode

- Load processed Seurat `.Rds`, `.h5ad`, BPCells bundles, and compressed 10x-style matrix inputs.
- Convert or preserve low-memory BPCells-backed assay storage.
- Derive missing normalized/HVG/PCA/neighbors/clusters/UMAP state when processable inputs are incomplete.
- Render reductions in the deck.gl main scatter, with `group.by`, optional `split.by`, labels, legends, hover, pan/zoom, lasso, and persistent selected/total counts.
- Query individual gene expression, cache expression vectors, show sparkline distributions, and color the main scatter by the first selected gene.
- Support multi-gene VlnPlot/DotPlot/FeaturePlot workflows through floating panels, with explicit refresh semantics for expensive plots.
- Filter cells, update clustering, add cell-cycle metadata, rename/assign selected cells to metadata categories, and subset/restore selected populations.
- Run explicit DEG/marker analysis in the floating DEG workflow, with method/threshold controls, marker table export, and bounded heatmap rendering.
- Export metadata, BPCells bundles, Explore Parquet bundles, Scanpy-compatible `.h5ad`, and standard `.Rds` with large-object warnings.

### Explore Mode

- Accept only validated `.explore-parquet.zip` artifacts with a scSpotlight manifest.
- Load metadata, reductions, PCA summaries, and expression blocks through Parquet/DuckDB/Arrow paths.
- Provide the same read-only scatter, category, feature expression, and floating VlnPlot/DotPlot/FeaturePlot inspection workflows where the data contract supports them.
- Exclude mutation workflows: filtering, clustering, cell-cycle scoring, metadata assignment, subsetting that mutates Seurat state, DEG computation, and general conversion.

### Cross-mode UX

- Keep progress, waiter/spinner, and visible in-plot transfer errors for slow or failed large operations.
- Keep mode-specific sidebars: Analysis gets input/conversion/filtering/clustering/cell-cycle/download plus rename; Explore gets file input only, with shared reduction/category/feature controls.
- Preserve the established interaction rule that the main expression scatter uses the **first selected gene only**; multi-gene views live in floating panels.

## Differentiators

- **Million-cell interactive scatter:** deck.gl + TypedArrays makes the app credible for large atlases rather than tutorial-sized datasets.
- **Seurat/BPCells Analysis backend:** keeps the app aligned with common R workflows while avoiding duplicated mutable state.
- **Explore Parquet bundles:** cleanly separates authoring/analysis from portable read-only sharing.
- **Versioned Arrow IPC contracts:** compact, typed browser transport for large metadata, reduction, and expression payloads.
- **Floating analysis panels with explicit-action rendering:** allows rich VlnPlot/DotPlot/FeaturePlot/DEG workflows without destabilizing main scatter responsiveness.
- **Portable conversion/export paths:** BPCells, Explore Parquet, `.h5ad`, metadata, and guarded `.Rds` exports reduce friction across R, Python, and sharing workflows.
- **Client-side category selection for annotation:** fast rename/selection UX without unnecessary backend round trips when categorical metadata is already decoded.
- **Optional summary-only assistant:** potential later differentiator for interpreting app state, but only after privacy/security and summary contracts are proven.

Defer v2+ work: broad Seurat/Scanpy workbench parity, scATAC/spatial/multiome, trajectory, ligand-receptor, automated cell-type annotation, collaboration/audit/version-control inside the app, hosted multi-user workflows, raw-data LLM tools, and MCP-backed assistants.

## Watch Out For

Top pitfalls that should shape every phase plan:

1. **Accidental full-dataset materialization** — avoid `as.matrix()`, broad `FetchData()`, full `collect()`, dense `scale.data`, and full JSON payloads. Use BPCells reads, DuckDB query plans, chunked Arrow IPC writers, and memory-conserving processing.
2. **Passing live objects into futures** — do not capture `seuratObj()`, BPCells matrices, HDF5 handles, or live Explore descriptors in background workers. Pass paths/query plans for Explore and keep Analysis expression extraction queued in-process.
3. **Mirrored DuckDB in Analysis Mode** — do not copy Seurat/BPCells metadata, reductions, or expression into DuckDB tables for mutable workflows. That reintroduces two sources of truth and synchronization bugs.
4. **R/JS message contract drift** — treat `meta_ready`, `meta_patch_ready`, `reduction_ready`, `reductions_ready`, `reduction_cached`, `pca_ready`, `expr_ready`, `expr_cached`, and plot refresh payloads as protocols. Version payloads/cache keys and test stale-cache behavior.
5. **Explore Mode becoming Analysis Mode** — keep Explore inputs constrained to `.explore-parquet.zip`, keep it read-only, and do not compute missing state during bundle load.
6. **Scatter performance regressions** — no per-cell DOM/SVG/canvas path, repeated metadata expansion in render loops, unbounded split panels, or disabled cache eviction.
7. **Expression workflow ambiguity** — preserve one-at-a-time expression extraction, the first-selected-gene main scatter rule, and explicit DotPlot/FeaturePlot rerender actions.
8. **LLM data leakage or hidden dependencies** — no raw metadata/expression/reductions, paths, credentials, arbitrary tools, or required startup packages. Keep `enableLLM = FALSE` and helper outputs aggregated/capped.
9. **Bundle/export fragility** — keep manifests, schema versions, relative-path-safe BPCells bundles, guarded `.h5ad` output paths, and warnings for standard RDS materialization.
10. **Documentation drift** — update `DEVELOPMENT.md` when behavior contracts, validations, packaging workflows, or architecture decisions change; sync README terminology away from stale renderer/runtime assumptions.

## Architecture Implications

The architecture should remain a single Shiny runtime with two explicit backend modes and one shared browser visualization runtime.

- **R owns source-of-truth state.** `app_server.R` orchestrates session temp dirs, resource paths, reactive indicators, and mode gates. Analysis state is Seurat/BPCells; Explore state is a validated bundle descriptor plus paths/query plans.
- **Backend seam first.** Server modules should call backend helpers for features, metadata, reductions, expression, PCA stdev, bundles, and exports instead of branching deeply on Seurat vs Explore internals.
- **Arrow IPC is the large-payload boundary.** R writes versioned files under session temp dirs; Shiny sends only file/version metadata; JS fetches, decodes, caches, and acknowledges readiness.
- **JavaScript owns interactive render state.** `srcjs/index.js`, `ScatterModel`, `deckScatter.js`, `scatterLayout.js`, `featureSparkLine.js`, and `floatingPlots.js` should keep compact client state, TypedArrays, dictionary/categorical structures, and bounded IPC caches.
- **Reactive counters are dependency edges.** Use monotonic indicators for metadata, reductions, genes, scatter settings, and plot refresh rather than direct dependencies on heavy objects.
- **Floating panels have separate refresh contracts.** VlnPlot may redraw on menu selection; DotPlot and FeaturePlot should mark stale on upstream changes and redraw only on explicit action or resize after first render; ElbowPlot uses PCA stdev; DEG remains server-side and Analysis-only.
- **Mode gates are architecture, not UI polish.** Analysis-only mutation modules must not appear or activate in Explore Mode. Explore should never mutate source bundles unless a future export contract explicitly defines that behavior.
- **Optional LLM stays outside the data plane.** Build compact summaries from current app state and capped aggregates only; never expose raw files, full cell-level data, secrets, or arbitrary R/file tools.

## Requirements Implications

Future requirements should be framed as preserving and hardening the current product wedge rather than expanding method breadth.

- **Non-negotiable acceptance criterion:** every large-data path must be low-memory by design and should describe how it avoids eager materialization for 1M+ cell workflows.
- **Mode-specific requirements:** each feature must state whether it is Analysis-only, Explore-only, or shared, and why. Explore additions must preserve read-only processed-artifact semantics.
- **Protocol requirements:** any change to metadata/reduction/expression/PCA/patch/plot messages must include R producer updates, JS consumer updates, cache-version behavior, failure UX, tests, and `DEVELOPMENT.md` documentation.
- **Performance requirements:** scatter features must be validated with realistic split panels, lasso/highlight behavior, adaptive rendering thresholds, browser memory stability, and cache eviction.
- **Mutation requirements:** annotation, cell-cycle, clustering, filtering, and subsetting should use metadata patches or targeted refreshes where possible and must clear stale selections when context changes.
- **Export requirements:** portable formats must be self-identifying, schema-versioned, cross-machine loadable, and low-memory. Standard RDS should remain a warned/explicit path for large BPCells-backed objects.
- **Optional dependency requirements:** optional acceleration or assistant packages must be guarded by `requireNamespace()` or equivalent checks and must not break core startup.
- **Documentation requirements:** changes that alter behavior contracts, packaging, validation, or architecture must update `DEVELOPMENT.md`; release-facing terminology should be kept aligned with deck.gl/BPCells/Arrow/Explore realities.

## Roadmap Implications

Suggested phase structure for future roadmap creation:

### Phase 1: Contract Hardening and Regression Harness

**Rationale:** Stabilize the protocols every other feature depends on before adding breadth.  
**Delivers:** documented backend seam expectations, versioned Arrow IPC payload tests, message/cache contract tests, visible transfer-error coverage, mode-gate checks, and DEVELOPMENT.md protocol notes.  
**Addresses:** low-memory backend access, metadata/reduction/expression transfer, plot readiness, Explore input validation.  
**Avoids:** R/JS contract drift, stale caches, hidden full-dataset JSON, and Analysis/Explore leakage.  
**Research flag:** needs phase-specific test-design research for R + JS protocol fixtures and large Arrow IPC regression coverage.

### Phase 2: Large-data Transfer and Main Scatter Reliability

**Rationale:** The main scatter is the product's credibility test; it must remain responsive before deeper workflows matter.  
**Delivers:** hardened metadata/reduction/expression chunking, metadata patch behavior, bounded IPC caches, reduction prefetch policy, deck.gl multi-panel/lasso/highlight correctness, high-cardinality split safeguards, and browser memory profiling.  
**Addresses:** render reductions, group/split categories, feature expression coloring, lasso, selected counts, progress/error UX.  
**Avoids:** main scatter regressions, unbounded client memory, full metadata reloads for column patches, and stuck waiters.  
**Research flag:** needs profiling with synthetic/realistic 100K, 500K, and 1M+ cell datasets and browser memory measurements.

### Phase 3: Analysis Mode Mutation and Processing Safety

**Rationale:** Mutable workflows must be safe after transfer/rendering contracts are stable, because annotation/export correctness depends on object state.  
**Delivers:** robust filtering, clustering updates, cell-cycle metadata patches, rename/assignment, subsetting/restore, memory-conserving PCA/scaling paths, and stale-selection clearing.  
**Addresses:** Analysis Mode processing, annotation, subsetting, clustering/QC, cell-cycle scoring.  
**Avoids:** dense `scale.data`, unsafe regression-heavy Seurat processing, wrong-cell annotation, full metadata reloads, and stale category carryover.  
**Research flag:** needs Seurat/BPCells method validation for PCA/scaling/regression choices and realistic metadata patch tests.

### Phase 4: Portable Export and Explore Bundle End-to-end

**Rationale:** Sharing only works once the runtime contracts and mutable object state are stable.  
**Delivers:** schema-versioned Explore Parquet bundles, portable BPCells bundles, guarded `.h5ad` conversion, bundle-aware loading, RDS warning/confirmation behavior, and cross-machine validation.  
**Addresses:** Explore artifact creation/loading, read-only Explore inspection, BPCells/h5ad/RDS export, data conversion panel.  
**Avoids:** broken bundle paths, schema drift, `.h5ad` overwrite/global HDF5 handle issues, Explore accepting arbitrary inputs, and heavy standard RDS materialization.  
**Research flag:** needs schema migration policy and interoperability testing across machines, OSes, and representative AnnData layouts.

### Phase 5: Floating Analysis Workflows and DEG Polish

**Rationale:** Secondary analysis panels should refine the experience after core data and scatter state are dependable.  
**Delivers:** stable VlnPlot/DotPlot/FeaturePlot explicit refresh behavior, webR shelter cleanup, resize debouncing, DEG method thresholds, bounded marker tables/heatmaps, and optional acceleration fallbacks.  
**Addresses:** multi-gene visualization, distribution inspection, DEG/marker analysis, floating panel UX.  
**Avoids:** auto-render loops, webR browser memory leaks, blocking marker analysis, giant heatmaps/tables, and optional package startup failures.  
**Research flag:** needs browser/webR memory profiling and DEG method benchmarking on realistic datasets.

### Phase 6: Optional Assistant and Interpretation Helpers

**Rationale:** AI is a potential differentiator but is optional, privacy-sensitive, and should not shape the core architecture.  
**Delivers:** if pursued, visible assistant mounting, provider configuration outside Shiny UI, capped read-only helper tools, privacy tests, dependency guards, and explicit no-MCP/no-raw-data boundaries.  
**Addresses:** optional summary-only interpretation of app state, group counts, and top DEG rows.  
**Avoids:** raw data exfiltration, credentials in UI, local path disclosure, mandatory `ellmer`/`shinychat`, and premature MCP tooling.  
**Research flag:** requires privacy/security review before any visible UI or provider expansion.

### Phase Ordering Rationale

- Stabilize backend seams and browser protocols first because all user-facing workflows depend on correct metadata/reduction/expression transport.
- Harden transfer/scatter reliability before mutation and exports because users experience plot failure immediately and because export correctness depends on trusted state.
- Address Analysis mutation before portable sharing so exported artifacts reflect correct, low-memory state changes.
- Complete Explore/export work before optional differentiators so the two-mode product promise is real.
- Polish floating plots/DEG after expression/grouping contracts are settled.
- Leave AI last because it has the highest privacy risk and the lowest dependency value for the core large-data workflow.

### Research Flags

Needs deeper `/gsd-plan-phase --research-phase <N>` style research:

- **Phase 1:** contract-test architecture across R modules, Shiny messages, Arrow IPC schemas, and JS decoders.
- **Phase 2:** performance profiling methodology and datasets for 1M+ cell scatter, cache, lasso, and split-panel behavior.
- **Phase 3:** Seurat/BPCells processing compatibility, especially scaling/regression/PCA/clustering choices under memory constraints.
- **Phase 4:** Explore schema migration, BPCells bundle portability, and h5ad interoperability.
- **Phase 5:** webR memory profiling and DEG benchmarking.
- **Phase 6:** privacy/security threat modeling for any assistant UI.

Standard patterns likely do **not** need broad external research:

- Shiny/golem module wiring when it follows existing repo patterns.
- Vite/Vitest maintenance when dependency versions are not changing.
- UI gating for Analysis vs Explore controls when it follows current `app_ui.R` / `app_server.R` mode checks.
- Documentation sync to `DEVELOPMENT.md`, README, and package docs.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Repo files and research agree on R/Shiny/golem, Seurat v5, BPCells, Arrow IPC, deck.gl, Vite/Vitest, Pixi, Docker, and Explore Parquet/DuckDB. |
| Features | HIGH | Feature landscape maps directly to current modules, `PROJECT.md` active requirements, and documented Analysis/Explore mode behavior. |
| Architecture | HIGH | The Seurat/BPCells vs Explore Parquet split, Arrow IPC boundary, deck.gl frontend, floating plot rules, and LLM constraints are explicit in repo docs and research. |
| Pitfalls | HIGH | Critical risks are repo-specific, repeatedly reinforced across `AGENTS.md`, `PROJECT.md`, `DEVELOPMENT.md`, and implementation-oriented research. |

**Overall confidence:** HIGH

### Gaps to Address

- Large-dataset performance still needs active profiling with 100K, 500K, and 1M+ cell datasets; architecture review alone cannot prove memory ceilings.
- Explore bundle portability and schema migration should be tested across machines, operating systems, and future bundle versions.
- `.h5ad` import/export needs continued validation against diverse AnnData layouts (`X`, layers, raw, `obs`/`var`, `obsm`, `uns`).
- Seurat/BPCells processing choices need phase-level validation for scaling, PCA, regression limitations, clustering, and dense state stripping.
- Optional LLM assistant work needs a dedicated privacy/security gate before visible UI, provider expansion, or any tool beyond capped summaries.
- Public docs should be checked for stale renderer/runtime wording and synced with the current deck.gl/BPCells/Arrow/Explore architecture.

## Sources

### Primary repo sources

- `.planning/PROJECT.md`
- `.planning/research/STACK.md`
- `.planning/research/FEATURES.md`
- `.planning/research/ARCHITECTURE.md`
- `.planning/research/PITFALLS.md`
- `AGENTS.md`
- `DEVELOPMENT.md`
- `DESCRIPTION`
- `package.json`
- `pixi.toml`
- `Dockerfile`
- `vite.config.js`
- `vitest.config.js`

### Implementation areas referenced by research

- `R/app_ui.R`, `R/app_server.R`
- `R/fct_bpcells_backend.R`, `R/fct_explore_bundle.R`, `R/fct_backend_transfer_adapter.R`
- `R/mod_dataInput.R`, `R/mod_UpdateMetaData.R`, `R/mod_UpdateReduction.R`, `R/mod_UpdateCategory.R`, `R/mod_InputFeature.R`
- `R/mod_FilterCell.R`, `R/mod_ClusterSetting.R`, `R/mod_AssignCellCluster.R`, `R/mod_SubsetCells.R`
- `R/mod_DEG_Window.R`, `R/mod_FindMarkers.R`, `R/mod_DEG_Table.R`
- `R/mod_Download.R`, `R/mod_DataConversion.R`
- `R/mod_LLMChat.R`, `R/fct_llm_context.R`
- `srcjs/index.js`, `srcjs/modules/deckScatter.js`, `srcjs/modules/scatter/scatterModel.js`, `srcjs/modules/scatter/scatterLayout.js`, `srcjs/modules/floatingPlots.js`, `srcjs/modules/featureSparkLine.js`

---
*Research completed: 2026-06-16*  
*Ready for roadmap: yes*
