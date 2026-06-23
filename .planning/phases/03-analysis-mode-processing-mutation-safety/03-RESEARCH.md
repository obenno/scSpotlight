# Phase 03: Analysis Mode Processing & Mutation Safety - Research

**Researched:** 2026-06-23
**Status:** Ready for planning
**Phase:** 03-analysis-mode-processing-mutation-safety

## Research Question

What do we need to know to plan Phase 03 well, given the project constraint that Analysis Mode must load, process, mutate, annotate, subset, and restore Seurat/BPCells-backed data without unsafe dense state or unnecessary full-dataset transfers?

## Phase Boundary

Phase 03 covers mutable Analysis Mode workflows after Phase 02 locked the Arrow IPC and main scatter reliability contracts.

In scope:

- Loading supported Analysis Mode inputs: Seurat `.Rds`, `.h5ad`, BPCells bundle archives, and compressed 10x-style matrix archives.
- Deriving missing normalized, HVG, PCA, neighbor, cluster, and UMAP state through memory-conserving paths.
- Filtering cells, updating clusters, and adding cell-cycle metadata without preserving dense `scale.data` or forcing full metadata reloads for column-scoped mutations.
- Selecting cells by lasso or category context, assigning metadata values, and clearing stale rename/category selections when grouping context changes.
- Subsetting to selected cells and restoring the original object while downstream metadata, reductions, feature choices, and plot state refresh correctly.

Out of scope:

- Portable export and Explore Mode end-to-end behavior. That is Phase 04.
- Floating DotPlot/FeaturePlot/VlnPlot/DEG workflow polish beyond keeping refresh contracts intact. That is Phase 05.
- Any broad new single-cell methods such as integration, trajectory, ligand-receptor, or cell type prediction.

## Current Implementation Evidence

| Area | Current files | Evidence | Planning implication |
|---|---|---|---|
| Analysis input loading | `R/mod_dataInput.R`, `R/fct_bpcells_backend.R` | Direct `.Rds`, `.h5ad`, compressed 10x, and compressed BPCells bundle paths all route through Seurat/BPCells helpers. `.Rds` and `.h5ad` paths call `ensure_bpcells_backing()` and `validate_seuratRDS()`. | Plan should harden existing paths with tests and invariants rather than rewrite loading. |
| BPCells conversion | `R/fct_bpcells_backend.R` | `ensure_bpcells_backing()` converts layers to BPCells dirs; `optimize_bpcells_matrix_type()` writes counts as integer-like storage and normalized data as float. | Tests should assert all Analysis app state uses BPCells-backed layers when possible. |
| Processing | `R/fct_bpcells_backend.R`, `R/mod_ClusterSetting.R`, `R/mod_dataInput.R` | `run_memory_conserving_processing()` runs NormalizeData, HVG, PCA, neighbors, clusters, and UMAP. `run_memory_conserving_pca()` uses BPCells PCA when the object is BPCells-backed, but the non-BPCells fallback calls `ScaleData(..., save = "scale.data")`. | Phase 03 must guard against persisted dense `scale.data`, especially after fallback paths, filtering, and cluster updates. |
| Filtering | `R/mod_FilterCell.R` | Filtering computes QC metadata, `subset()`s selected cells, reruns `standard_process_seurat()`, then increments gene/meta/reduction indicators. | Plan should validate selected cells, keep subsetted layers BPCells-backed, drop dense scale data, and preserve downstream refresh indicators. |
| Cluster updates | `R/mod_ClusterSetting.R` | `Update All` uses `run_memory_conserving_processing()`. `Update nDim Only` reruns UMAP/neighbors/clusters. `Update Res Only` uses existing graph when present. | Plan should lock processing mode semantics and ensure Update Res Only avoids unnecessary reduction refresh while Update All/nDim refresh reductions. |
| Cell cycle | `R/mod_CellCyling.R`, `R/mod_UpdateMetaData.R` | Cell cycling uses `CellCycleScoring()` and requests `meta_patch_ready` for `S.Score`, `G2M.Score`, and `Phase`. A fallback `CellCycleScoring_2()` exists but is not used. | Plan should use the robust fallback, keep the mutation column-scoped, and test metadata patch requests. |
| Metadata assignment | `R/mod_AssignCellCluster.R`, `R/app_server.R`, `srcjs/index.js` | Browser computes rename/category selected cells and sends final selected-cell payload to R. R validates required inputs and sends `addNewMeta`; browser updates metadata and sends `newMetaColData` to R. | Plan should preserve client-side selection speed while adding validation for payload length/cell identity and stale selection clearing. |
| Category state | `R/mod_UpdateCategory.R`, `srcjs/index.js` | Category sidebar consumes batched `metaSidebarState`; JS clears rename choices when `group.by` or `split.by` changes, and tests already cover basic clearing. | Plan should extend regression coverage to split changes, missing levels, patch-driven group changes, and assignment completion. |
| Subset/restore | `R/mod_SubsetCells.R` | Subset switch stores original object in `seuratObj_orig`, applies `subset(obj, cells = selectedCells())`, restores original on switch off, and increments all three indicators. | Plan should introduce guard helpers/tests so invalid selections cannot subset, original state is stored once, BPCells backing is preserved, and refresh indicators are complete. |
| Transfer refresh | `R/app_server.R`, `R/mod_UpdateMetaData.R`, `R/mod_UpdateReduction.R`, `R/mod_InputFeature.R` | Phase 02 created versioned metadata/reduction/expression/patch IPC and separate `plotRefreshIndicator`; Phase 03 can reuse these contracts. | Do not create new browser payload protocols unless unavoidable. Prefer existing full transfer indicators and `meta_patch_ready`. |

## Technical Findings

### 1. Loading is mostly implemented but needs contract coverage

The current app already supports the four Phase 03 Analysis Mode input classes. The risky parts are not missing branches; they are drift and edge cases:

- Direct `.Rds` loading must use the bundle-aware loader so relative BPCells paths resolve from the bundle directory context.
- Plain Seurat objects need conversion to `Assay5` plus BPCells-backed layers before app state updates.
- Native `.h5ad` import prefers `BPCells::open_matrix_anndata_hdf5()` and falls back to sparse `rhdf5` reads when BPCells cannot open the layout directly.
- Compressed 10x-style matrix archives are imported through BPCells matrix market import and then processed.
- Explore bundles must remain rejected in Analysis Mode and accepted only by Explore Mode.

Plan implication: add focused tests/source guards around these existing paths rather than adding another import abstraction.

### 2. Dense `scale.data` persistence is the central Phase 03 memory risk

The app already documents that processing mode should prefer BPCells-compatible paths and avoid dense `scale.data`. The implementation partially satisfies this through `run_bpcells_pca()`, which uses BPCells matrix stats and truncated SVD. The remaining risk is the fallback branch in `run_memory_conserving_pca()`:

```r
object <- Seurat::ScaleData(
  object,
  assay = assay,
  layer = layer,
  features = VariableFeatures(object),
  save = "scale.data"
)
```

Plan implication: execution should either avoid this branch for Analysis Mode objects by ensuring BPCells backing first, or confine any Seurat fallback scaling to a temporary object and explicitly drop persisted `scale.data` before app state changes. Tests should assert no final Analysis object keeps a `scale.data` layer after processing, filtering, or cluster updates.

### 3. Filtering and subset both need a shared safe-cell operation

`R/mod_FilterCell.R` and `R/mod_SubsetCells.R` both call `subset(obj, cells = ...)`. That is appropriate for Seurat state, but needs common guards:

- Coerce selected cells to character cell IDs.
- Intersect selected cells with `colnames(object)` and fail clearly when none remain.
- Preserve cell order from the source object when appropriate.
- Preserve or restore BPCells backing after subsetting.
- Drop dense `scale.data` and avoid carrying stale graphs/neighbors when reductions/clusters will be recomputed.

Plan implication: create a small internal helper, likely in `R/fct_bpcells_backend.R`, that both filter and subset modules can call. Keep it focused and test it directly.

### 4. Column-scoped metadata patches are already the correct mutation transport

Phase 02 established `meta_patch_ready` and stale-safe browser patch handling. Cell cycle and assignment workflows should reuse that path where a small number of metadata columns changes.

Plan implication:

- Cell-cycle scoring should request a patch for `S.Score`, `G2M.Score`, and `Phase` only.
- Assignment currently updates browser metadata first and then sends the full column to R through `newMetaColData`. That can remain because it is one metadata column, but R should validate shape before committing to the Seurat object.
- Full `metaUpdateIndicator` should be reserved for structural full metadata changes or object replacement, not every metadata column mutation.

### 5. Rename/category selection is already client-side and should stay there

The browser owns expanded metadata arrays and computes category-selected cells locally. This avoids server-side filtering over 1M+ metadata rows on each selection interaction. Existing tests cover clearing selected group choices when grouping changes and after metadata assignment.

Plan implication: extend tests for split context changes, patch-driven choices, lasso precedence, and selected-cell payload behavior. Do not move category filtering back to R.

### 6. Subset/restore is a state machine, not only a Seurat operation

Subsetting and restoring must refresh four downstream views of the object:

- Metadata transfer via `metaUpdateIndicator`.
- Reductions and PCA summaries via `reductionUpdateIndicator`.
- Feature choices and expression cache version via `geneUpdateIndicator`.
- Main scatter redraw through the existing Phase 02 `metaProcessed`, `reductionProcessed`, and `plotRefreshIndicator` chain.

Plan implication: tests should verify indicator increments and selected-cell clearing on subset/restore, not just object dimensions.

## Recommended Plan Slices

### Plan 03-01: Loading and processing safety

Cover `ANAL-01` and the base of `ANAL-02`.

Focus:

- Analysis input acceptance/rejection contracts.
- BPCells backing after load/import/conversion.
- Memory-conserving processing and PCA with no final dense `scale.data`.
- Documentation of Analysis Mode processing invariants.

### Plan 03-02: Filter, cluster, and cell-cycle mutation safety

Cover `ANAL-03` and remaining processing pieces of `ANAL-02`.

Focus:

- Safe filtering with validated cell sets and BPCells backing.
- Cluster update paths with correct meta/reduction indicator semantics.
- Cell-cycle scoring fallback plus column-scoped metadata patches.

### Plan 03-03: Assignment and category-selection consistency

Cover `ANAL-04`.

Focus:

- Lasso/category selected-cell precedence.
- Assignment payload validation in browser and R.
- Stale rename choices clear on group/split changes and assignment completion.
- Metadata mutation remains one-column scoped where possible.

### Plan 03-04: Subset and restore refresh semantics

Cover `ANAL-05`.

Focus:

- Safe subset helper reuse.
- Original-object storage and restore lifecycle.
- Refresh indicators and browser state clearing/reconciliation.
- Regression tests for invalid selections and repeated toggle behavior.

## Validation Strategy

Automated checks should be favored because representative 1M+ fixtures may be unavailable locally.

Required targeted verification by slice:

- R tests for BPCells backing, processing, safe subsetting, filter/cluster/cell-cycle modules, and assignment metadata validation.
- JS tests for rename/category stale clearing, assignment payload, metadata patch behavior, and selection clearing.
- Existing Phase 02 transfer/scatter contract tests where Phase 03 changes touch payload or browser state.
- `pixi run build-js` only when `srcjs` changes.
- `DEVELOPMENT.md` docs guard tests when behavior contracts are added.

Large-data manual validation should be recorded but not claimed if fixtures are unavailable. Fallback evidence should include source guards and synthetic tests that assert no dense `scale.data` persistence, no live-object futures for large expression transfer, and no full metadata reload for column-scoped mutations.

## Risks And Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Seurat calls silently create dense `scale.data` | OOM risk for large Analysis Mode workflows | Add explicit no-final-`scale.data` tests and drop/avoid scale data after processing. |
| Filtering/subsetting invalid or stale cells | Wrong-cell annotation or empty object failure | Centralize safe cell validation and test invalid/stale selections. |
| CellCycleScoring fails on small gene/bin combinations | User cannot add cell-cycle metadata | Use existing `CellCycleScoring_2()` fallback and test patch request output. |
| Assignment payload length mismatch | Corrupts Seurat metadata | Validate new metadata column length/cell alignment before `AddMetaData()`. |
| Full metadata transfer after every metadata mutation | Unnecessary browser/server payload for 1M+ cells | Preserve `meta_patch_ready` and one-column assignment semantics. |
| Subset/restore leaves stale feature/expression/cache state | Browser shows stale genes, reductions, or selected cells | Increment all relevant indicators and clear/reconcile browser selection/expression state. |

## Canonical References

- `.planning/ROADMAP.md` Phase 03 success criteria.
- `.planning/REQUIREMENTS.md` `ANAL-01` through `ANAL-05`.
- `.planning/STATE.md` Phase 02 transfer/scatter decisions.
- `AGENTS.md` low-memory and BPCells constraints.
- `DEVELOPMENT.md` runtime contract backbone, Phase 02 transfer reliability, BPCells processing notes, and scatter interaction notes.
- `R/mod_dataInput.R`
- `R/fct_bpcells_backend.R`
- `R/mod_FilterCell.R`
- `R/mod_ClusterSetting.R`
- `R/mod_CellCyling.R`
- `R/mod_AssignCellCluster.R`
- `R/mod_SubsetCells.R`
- `R/mod_UpdateCategory.R`
- `R/app_server.R`
- `srcjs/index.js`
- Existing tests under `tests/testthat/` and `srcjs/**/*.test.js` referenced in `03-PATTERNS.md`.

---

_Research source: direct codebase inspection after prior researcher subagent failed to write an artifact._
