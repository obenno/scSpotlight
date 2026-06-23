# Phase 03: Analysis Mode Processing & Mutation Safety - Patterns

**Mapped:** 2026-06-23
**Status:** Ready for planning
**Phase:** 03-analysis-mode-processing-mutation-safety

## Purpose

Map Phase 03 planned changes to existing implementation patterns so execution can make small, idiomatic changes without violating the app's low-memory Analysis Mode constraints.

## Global Patterns To Preserve

| Pattern | Existing location | How Phase 03 should use it |
|---|---|---|
| Indicator-driven updates | `R/app_server.R`, `R/mod_UpdateMetaData.R`, `R/mod_UpdateReduction.R`, `R/mod_InputFeature.R` | Mutating object-level state should increment `geneUpdateIndicator`, `metaUpdateIndicator`, and/or `reductionUpdateIndicator` only for downstream state that really changed. Column-scoped metadata should prefer `metaPatchRequest`. |
| Backend helper seam | `R/fct_bpcells_backend.R` | Add internal helpers here for safe processing/subsetting/backing checks. Keep Analysis Mode source of truth as Seurat/BPCells, not mirrored DuckDB. |
| Browser payload manifest | `inst/protocol/browser-payload-contracts.json`, `tests/testthat/test-browser-payload-contracts.R`, `srcjs/index.test.js` | Avoid new message contracts where existing `meta_ready`, `meta_patch_ready`, `expr_ready`, and reduction messages work. If payloads change, update manifest/tests/docs together. |
| Column-scoped metadata patches | `R/mod_UpdateMetaData.R`, `srcjs/index.js`, `srcjs/modules/scatter/scatterModel.js` | Cell-cycle metadata should continue to request only changed columns. Assignment should validate and transfer at most one changed metadata column where possible. |
| Client-side rename selection | `srcjs/index.js`, `R/mod_AssignCellCluster.R` | Keep category filtering in the browser using cached metadata. R receives only final selected cells/metadata assignment payloads. |
| BPCells-backed expression transfer | `R/mod_InputFeature.R`, `R/fct_backend_transfer_adapter.R`, `R/fct_bpcells_backend.R` | Do not disturb Phase 02 one-active expression queue or path-based writer contracts when subsetting/restoring changes gene versions. |
| Test-first safety hardening | Phase 02 plans and summaries | Add targeted failing tests before changes, then minimal implementation, then documentation and verification. |

## File Pattern Map

| Planned file | Role | Closest existing analogs | Concrete patterns to copy |
|---|---|---|---|
| `R/fct_bpcells_backend.R` | Internal backend helpers for BPCells backing, processing, dense-state stripping, and safe subsetting | Existing `ensure_bpcells_backing()`, `run_memory_conserving_processing()`, `run_memory_conserving_pca()`, `prepare_bundle_object()` | Keep helpers pure over `object` arguments; return the updated object; use `assay <- assay %||% DefaultAssay(object)`; call `assert_bpcells_available()` only where BPCells is mandatory; use `tryCatch()` for optional Seurat internals. |
| `R/mod_dataInput.R` | User input loading and initial processing | Existing direct branches for `.Rds`, `.h5ad`, compressed bundle, compressed matrix | Preserve branch structure and waiter copy. Add tests/source guards rather than a new loader stack. Keep Explore archives rejected in Analysis Mode. |
| `R/mod_FilterCell.R` | QC metadata and filtering mutation | `ensure_filter_cell_qc_metadata()`, `standard_process_seurat()` call site | Keep QC helper testable outside Shiny. Use safe subset helper before reprocessing. Increment gene/meta/reduction indicators after object replacement. |
| `R/mod_ClusterSetting.R` | Cluster and reduction recomputation | `run_memory_conserving_processing()` in Update All, existing graph check in Update Res Only | Preserve three modes. Update All and nDim change reductions; Res Only should not force reduction transfer if reductions did not change. |
| `R/mod_CellCyling.R` | Cell-cycle metadata mutation | Existing `CellCycleScoring_2()` fallback, `metaPatchRequest` pattern from current server | Use fallback wrapper instead of raw `CellCycleScoring()`. Request patch for exactly `S.Score`, `G2M.Score`, `Phase`. Do not increment full metadata transfer unless patch path fails. |
| `R/app_server.R` | Central mutation wiring | Existing `newMetaColData` observer and `metaPatchProcessed` observer | Validate assignment metadata before `AddMetaData()`. Trigger only needed plot refreshes and keep LLM context version tied to existing indicators. Preserve Analysis-only gates. |
| `R/mod_AssignCellCluster.R` | Assignment UI/server validation and subset module composition | Existing required-input notifications and selected payload selection order | Keep UI shape. Add validation for selected-cell payload and assignment names/labels. Do not move category filtering back to R. |
| `R/mod_UpdateCategory.R` | Sidebar category selection state | Existing `last_category_selection` and `scatterUpdateIndicator` guard | Preserve no-op behavior when effective group/split selection is unchanged. Extend tests for split/context resets. |
| `R/mod_SubsetCells.R` | Subset/restore object state machine | Existing switch observer and indicator increments | Replace raw subset with safe helper. Store original object only before first subset. Restore original and clear backup. Refresh gene/meta/reduction state. |
| `srcjs/index.js` | Browser rename/category and assignment state | Existing `syncRenameClusterSelectionUi()`, `addNewMeta`, `meta_patch_ready`, `clear_expr` handlers | Use `textContent` for user-derived labels. Preserve rename choice clearing on group/split context change. If subset/restore needs browser clearing, prefer existing `clear_expr`, selection reconciliation, and indicator-triggered transfers over a new broad protocol. |
| `DEVELOPMENT.md` | Behavior contract docs | Runtime Contract Backbone and BPCells processing notes | Add Phase 03 Analysis mutation safety notes plus docs guard tests. Keep unrelated existing sections intact. |

## Test Pattern Map

| Needed coverage | Existing analog | New or extended test target |
|---|---|---|
| BPCells backing accepts non-dgC sparse matrices | `tests/testthat/test-bpcells-matrix-coercion.R` | Extend or add `tests/testthat/test-analysis-processing-safety.R` for all Analysis app-state layers backed when possible. |
| BPCells HVG path equivalence | `tests/testthat/test-bpcells-hvg.R` | Add processing test that `run_memory_conserving_processing()` preserves HVGs/reductions without final `scale.data`. |
| Backend helper seam and no DuckDB | `tests/testthat/test-analysis-backend-contract.R` | Add source guard for processing/filter/subset futures and no mirrored DuckDB. |
| Metadata patch payloads | `tests/testthat/test-browser-payload-contracts.R`, `srcjs/index.test.js` | Add cell-cycle patch tests and assignment one-column metadata validation as needed. |
| Filter QC metadata | `tests/testthat/test-filter-cell-qc-metadata.R` | Extend with safe filter/subset helper coverage, including assay changes and invalid cells. |
| Category state clearing | `tests/testthat/test-update-category.R`, `srcjs/index.test.js` | Add split context, metadata patch, lasso precedence, and assignment completion regressions. |
| Subset/restore Shiny server behavior | No existing direct subset test | Add `tests/testthat/test-subset-cells.R` with `testServer()` and small Seurat fixtures. |
| Docs contract | `tests/testthat/test-development-contract-docs.R` | Extend to guard Phase 03 analysis processing/mutation safety documentation. |

## Implementation Rules For Executors

1. Keep changes small and localized. Prefer adding one or two helper functions over rewriting module flows.
2. Do not pass live Seurat/BPCells objects into new futures. Existing expression queue path is already constrained; do not widen it.
3. Do not introduce full metadata, reduction, or expression JSON payloads.
4. Do not add a mirrored Analysis Mode DuckDB store.
5. Do not preserve final dense `scale.data` in Analysis Mode app state after processing, filtering, clustering, subsetting, or restore.
6. Do not move rename/category selection filtering from browser to server.
7. If JavaScript source changes, run `pixi run build-js` and keep generated bundle artifacts.
8. If behavior contracts change, update `DEVELOPMENT.md` and docs guard tests.

## Known Landmines

| Landmine | Why it matters | Guard |
|---|---|---|
| `ScaleData(..., save = "scale.data")` | Can persist a dense feature-by-cell matrix in the Seurat object. | Tests assert no final `scale.data`; helper drops/avoids it. |
| Raw `subset(obj, cells = selectedCells())` | Invalid/stale selections can produce empty objects or wrong cell order. | Safe subset helper validates/intersects cells and errors clearly. |
| Raw `conditionMessage(error)` in browser-facing notifications | Can expose paths or internals. | Keep raw diagnostics server-side; browser messages use sanitized existing contracts. |
| Full `metaUpdateIndicator` after every small mutation | Forces full metadata IPC and browser decode. | Use `metaPatchRequest` for cell-cycle and one-column metadata changes where possible. |
| Reusing stale category choices after `group.by` or `split.by` changes | Can annotate wrong cells. | JS and R tests clear rename selections and selected cell state on context changes. |
| Replacing Seurat object without refreshing gene/reduction/meta state | Browser can show stale features, expression cache, reductions, or counts. | Subset/filter/restore tests assert all relevant indicators increment. |

## Suggested New Helpers

These names are suggestions for planning/execution, not hard API commitments:

- `drop_dense_scale_data(object, assays = NULL)`: remove any final `scale.data` layer after processing paths.
- `assert_no_dense_scale_data(object, assays = NULL)`: test/helper assertion for final app state.
- `safe_subset_seurat_object(object, cells, backend_root = NULL, input_label = "Selected cells")`: validate/intersect cells, subset, drop dense scale data, and restore BPCells backing.
- `validate_assignment_metadata(object, values, col_name)`: ensure browser-submitted metadata columns have the right length and safe name before `AddMetaData()`.

Keep helper names internal and covered by tests; avoid exporting unless execution finds a concrete external need.

## Plan Dependencies

- `03-01` should land first because all mutation paths depend on safe processing/backing helpers.
- `03-02` depends on `03-01` helpers for filter and cluster safety.
- `03-03` can run after `03-01`; it depends on Phase 02 browser state tests more than processing helpers.
- `03-04` should run after `03-01` and preferably after `03-03` because subset/restore must clear/reconcile selected-cell state.

---

_Pattern map source: direct codebase inspection after prior pattern-mapper subagent did not write an artifact._
