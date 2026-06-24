---
phase: 03-analysis-mode-processing-mutation-safety
verified: 2026-06-24T03:10:47Z
status: gaps_found
score: "1/5 must-haves verified"
overrides_applied: 0
gaps:
  - truth: "Analysis Mode user can load supported Seurat `.Rds`, `.h5ad`, BPCells bundle, and compressed 10x-style inputs with assay layers converted or preserved as BPCells-backed storage when possible."
    status: failed
    reason: "Compressed Analysis inputs are extracted with raw `untar()` / `zip::unzip()` and no path traversal or symlink validation, so supported archive loading is not safe for user uploads."
    artifacts:
      - path: "R/mod_dataInput.R"
        issue: "`decompress_matrix_input()` calls `untar(tarfile = filePath, exdir = tmpMatrixDir)` and `zip::unzip(zipfile = filePath, exdir = tmpMatrixDir)` directly at lines 920-936."
    missing:
      - "List archive entries before extraction and reject absolute paths, `..` path segments, Windows drive paths, and symlinks before extracting compressed Analysis inputs."
  - truth: "Analysis Mode user can filter cells, update clustering, and add cell-cycle metadata without preserving dense `scale.data` or triggering unnecessary full-dataset transfers."
    status: failed
    reason: "Cell-cycle and assignment metadata patches use `metaPatchVersion()` starting from 0 while full metadata transfers use `metaUpdateIndicator()` as `metaVersion`; the browser rejects any later patch with a lower version as stale. Successful server-side mutations can therefore be invisible in the browser."
    artifacts:
      - path: "R/app_server.R"
        issue: "Separate `metaPatchVersion <- reactiveVal(0)` and patch increments at lines 197-199 and 446-450 are independent of `metaUpdateIndicator()`."
      - path: "R/mod_CellCyling.R"
        issue: "Cell-cycle patch versions increment the same separate `metaPatchVersion()` at lines 129-134."
      - path: "srcjs/index.js"
        issue: "`startMetaRequest()` rejects patch versions lower than `activeMetaVersion` at lines 285-295."
    missing:
      - "Use one trusted monotonic metadata version for both full metadata transfers and column-scoped patches, or otherwise make patch versions comparable with full metadata versions."
  - truth: "Analysis Mode user can select cells by lasso or category context, assign metadata values, and see stale rename selections clear when grouping context changes."
    status: failed
    reason: "Server-side assignment validation falls back to the browser-submitted `metaVersion` as the trusted current version, and the assign button still sends duplicate assignment intents via both `pointerdown` and `click`. This leaves stale assignment protection bypassable and can duplicate mutations."
    artifacts:
      - path: "R/app_server.R"
        issue: "`current_context$metaVersion` falls back to `(assignmentIntent$context)$metaVersion` at lines 413-419."
      - path: "srcjs/index.js"
        issue: "`initRenameClusterClientSelection()` binds both `pointerdown` and `click` to `pushRenameAssignmentIntent` at lines 1566-1571."
    missing:
      - "Use only a server-trusted current metadata version for assignment validation and reject versioned intents when the server cannot verify current metadata state."
      - "Bind a single assignment activation event or add a short-lived in-flight guard to avoid duplicate intent submission."
  - truth: "Analysis Mode user can subset to selected cells and restore the original object while downstream metadata, reduction, feature, and plot state refresh correctly."
    status: failed
    reason: "The browser sends selected cell IDs to Shiny as `selectedPoints`, but the R assignment/subset module still coerces `selectedPoints()` to integer point indices. Lasso-selected barcodes become `NA`, so subset-to-selected-cells cannot reliably use the visible lasso selection."
    artifacts:
      - path: "srcjs/index.js"
        issue: "The lasso handler sends `Shiny.setInputValue('selectedPoints', selectedCells, ...)` at lines 2036-2041."
      - path: "R/mod_AssignCellCluster.R"
        issue: "`manuallySelectedCells()` does `as.integer(selectedPoints()) + 1L` and indexes `all_cells` at lines 94-103. A spot-check with `selectedPoints <- c('Cell1','Cell3')` produced no valid selected cells."
    missing:
      - "Make `manuallySelectedCells()` consume cell IDs directly, or change the browser/server contract back to numeric indices consistently. Prefer cell IDs and validate against current `colnames(seuratObj())`."
  - truth: "Analysis Mode user can subset to selected cells and restore the original object while downstream metadata, reduction, feature, and plot state refresh correctly."
    status: failed
    reason: "Subsetting BPCells-backed objects can write large backing directories outside the session cleanup root because `mod_SubsetCells_server()` does not pass `backend_root`; the safe subset helper then falls back to `tempfile('scspotlight_subset_layers_')`."
    artifacts:
      - path: "R/fct_bpcells_backend.R"
        issue: "`safe_subset_seurat_object()` uses `tempfile('scspotlight_subset_layers_')` when `backend_root` is NULL at lines 246-252."
      - path: "R/mod_SubsetCells.R"
        issue: "The module signature has no `backend_root` argument and calls `safe_subset_seurat_object(..., input_label = 'Selected cells')` without a session backend path at lines 25-33 and 93-98."
    missing:
      - "Thread `session$userData$backendDir` (or a child directory) into the subset module and require subset backing under the session cleanup root."
  - truth: "Analysis Mode user can subset to selected cells and restore the original object while downstream metadata, reduction, feature, and plot state refresh correctly."
    status: failed
    reason: "All sessions register Arrow IPC files under the same global `/data` Shiny resource prefix, while the browser hard-codes `/data/...` URLs. A later session can replace the resource mapping used by an earlier session, mixing or exposing metadata/reduction/expression IPC files across sessions."
    artifacts:
      - path: "R/app_server.R"
        issue: "Each session calls `addResourcePath('data', tempDir)` at line 163."
      - path: "srcjs/index.js"
        issue: "Browser fetches hard-code `/data/reduction/`, `/data/meta/`, and `/data/expr/` URLs at lines 787-789, 1633, 1694, and 1753."
    missing:
      - "Register a session-specific opaque resource prefix, remove it on session end, and include/use that prefix in metadata, reduction, expression, and patch payload fetch URLs."
---

# Phase 3: Analysis Mode Processing & Mutation Safety Verification Report

**Phase Goal:** As a single-cell analyst, I want to load, process, mutate, subset, and restore Analysis Mode Seurat/BPCells-backed data, so that large datasets remain usable without dense state, stale selections, or unnecessary full-dataset transfers.
**Roadmap Goal:** Analysis Mode users can load, process, mutate, annotate, subset, and restore Seurat/BPCells-backed data without unsafe dense state or unnecessary full-dataset transfers.
**Verified:** 2026-06-24T03:10:47Z
**Status:** gaps_found
**Re-verification:** No — initial verification. No prior `03-VERIFICATION.md` was found.

## User Flow Coverage

User story: "As a single-cell analyst, I want to load, process, mutate, subset, and restore Analysis Mode Seurat/BPCells-backed data, so that large datasets remain usable without dense state, stale selections, or unnecessary full-dataset transfers."

| Step | Expected | Evidence in codebase | Status |
|---|---|---|---|
| Load supported Analysis input | Seurat RDS, h5ad, BPCells bundles, and compressed 10x archives load into Analysis Mode with BPCells backing where possible | `load_analysis_input_file()` routes supported extensions and calls `ensure_bpcells_backing()` / `assert_no_dense_scale_data()`, but `decompress_matrix_input()` extracts archives without safe-entry validation | ✗ FAILED |
| Process missing state | Normalized data, HVGs, PCA, neighbors, clusters, and UMAP can be derived without final dense `scale.data` | `run_memory_conserving_processing()` calls NormalizeData, variable feature selection, PCA, neighbors/clusters/UMAP, then `drop_dense_scale_data()` and `assert_no_dense_scale_data()` | ✓ VERIFIED |
| Mutate Analysis state | Filtering, clustering, and cell-cycle metadata keep low-memory state and scoped transfers | Filter/cluster use no-dense-scale helpers, but cell-cycle patches use independent patch versions that can be rejected as stale by the browser | ✗ FAILED |
| Assign metadata from selection | Lasso/category assignment is bounded, current-context-safe, and visible through a scoped patch | Browser sends bounded intent, but server trusts browser version fallback and patch versioning can make successful assignment invisible; assign button can send duplicate intents | ✗ FAILED |
| Subset and restore | Current selected cells subset the object, restore returns original, and browser state refreshes | Subset/restore state machine exists, but lasso cell IDs are interpreted as integer indices in R; BPCells subset backing can be written outside session cleanup; IPC resource path is global | ✗ FAILED |
| Outcome | Large datasets remain usable without dense state, stale selections, or unnecessary full-dataset transfers | Dense-scale invariant is partly met, but stale patch/version, selection wiring, cross-session IPC, unsafe archive extraction, and backing cleanup blockers remain | ✗ FAILED |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Analysis Mode user can load supported Seurat `.Rds`, `.h5ad`, BPCells bundle, and compressed 10x-style inputs with assay layers converted or preserved as BPCells-backed storage when possible. | ✗ FAILED | Supported branches exist in `R/mod_dataInput.R:215-336`, but compressed archives are extracted directly by `untar()` / `zip::unzip()` at `R/mod_dataInput.R:920-936` with no path traversal validation. |
| 2 | Analysis Mode user can derive missing normalized, HVG, PCA, neighbors, clusters, and UMAP state through memory-conserving processing paths. | ✓ VERIFIED | `R/fct_bpcells_backend.R:1626-1670` derives NormalizeData, HVGs, PCA, neighbors, clusters, UMAP and then drops/asserts no dense `scale.data`; targeted tests passed for processing helpers. |
| 3 | Analysis Mode user can filter cells, update clustering, and add cell-cycle metadata without preserving dense `scale.data` or triggering unnecessary full-dataset transfers. | ✗ FAILED | Filter/cluster no-dense-scale code exists, but `metaPatchVersion()` is independent of full `metaUpdateIndicator()` (`R/app_server.R:197-199`, `R/mod_CellCyling.R:129-134`) and browser stale gates reject lower patch versions (`srcjs/index.js:285-295`). |
| 4 | Analysis Mode user can select cells by lasso or category context, assign metadata values, and see stale rename selections clear when grouping context changes. | ✗ FAILED | Bounded browser intent exists, but server stale protection falls back to browser-submitted version (`R/app_server.R:413-419`), patch versioning can drop visible results, and the assign button has duplicate event bindings (`srcjs/index.js:1566-1571`). |
| 5 | Analysis Mode user can subset to selected cells and restore the original object while downstream metadata, reduction, feature, and plot state refresh correctly. | ✗ FAILED | Subset/restore module exists, but JS sends cell IDs as `selectedPoints` (`srcjs/index.js:2036-2041`) while R treats them as integer indices (`R/mod_AssignCellCluster.R:94-103`); subset BPCells backing defaults outside session cleanup; `/data` IPC path is global. |

**Score:** 1/5 truths verified

## Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `R/fct_bpcells_backend.R` | BPCells backing, no-dense-scale, processing, safe subset helpers | ⚠️ PARTIAL | Helpers are substantive and wired, but `safe_subset_seurat_object()` falls back to `tempfile('scspotlight_subset_layers_')` outside session cleanup when callers omit `backend_root`. |
| `R/mod_dataInput.R` | Supported Analysis loading and initial processing handoff | ⚠️ PARTIAL | Loading/processing handoff exists; compressed archive extraction lacks safe-entry validation. |
| `R/mod_FilterCell.R` | Filter mutation path using safe subset and refresh indicators | ⚠️ PARTIAL | Uses `safe_subset_seurat_object()` and indicators, but expected filter edge cases (missing QC column / empty result) can still escape as observer errors. |
| `R/mod_ClusterSetting.R` | Cluster update mode semantics and no-dense-scale enforcement | ⚠️ PARTIAL | Update modes and no-dense-scale checks exist; requested dimensions are not clamped/validated against available PCA components. |
| `R/mod_CellCyling.R` | Cell-cycle fallback and scoped metadata patch | ⚠️ PARTIAL | Fallback and scoped columns exist; patch versioning can make browser-visible updates stale. |
| `R/app_server.R` | Assignment validation, metadata mutation, scoped patch request, resource wiring | ✗ FAILED | Assignment context can trust browser version; patch versions are independent; all sessions register global `/data`. |
| `R/mod_AssignCellCluster.R` | Selected-cell payload handling and subset module wiring | ✗ FAILED | `selectedPoints()` cell IDs are coerced to integer indices, breaking lasso-selected subset flow. |
| `R/mod_SubsetCells.R` | Subset/restore state machine and refresh indicators | ✗ FAILED | State machine exists, but selected-cell source is broken for lasso IDs and BPCells backing root is not threaded into the module. |
| `srcjs/index.js` | Bounded assignment intent, stale clearing, subset/restore browser cleanup | ⚠️ PARTIAL | Browser assignment/cleanup tests pass, but duplicate assign event binding remains and hard-coded `/data/...` fetch paths are not session-scoped. |
| Phase 03 test files | Executable coverage for loading, mutation, assignment, subset, docs guards | ✓ VERIFIED | Targeted R and JS tests exist and selected test commands passed; however tests missed the selected-cell ID/index contract and patch-version interplay. |

## Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `R/mod_dataInput.R` | `R/fct_bpcells_backend.R` | Loaded object validation, processing, re-backing, no-dense-scale checks | ⚠️ PARTIAL | Link exists; unsafe archive extraction occurs before safe loading for compressed inputs. |
| `R/fct_bpcells_backend.R` | Loading/processing tests | Processing and PCA no-dense-scale contract tests | ✓ WIRED | `test-analysis-loading-processing-safety.R` covers processing, PCA, supported input branches, and source guards. |
| `R/mod_FilterCell.R` | `R/fct_bpcells_backend.R` | Validated safe subset before reprocessing | ✓ WIRED | `safe_subset_seurat_object()` precedes `standard_process_seurat()` in `R/mod_FilterCell.R:149-162`. |
| `R/mod_ClusterSetting.R` | `R/fct_bpcells_backend.R` | Cluster update no-final-dense-scale helpers | ✓ WIRED | `apply_cluster_update_mode()` drops/asserts dense scale at `R/mod_ClusterSetting.R:144-145`. |
| `R/mod_CellCyling.R` | `R/mod_UpdateMetaData.R` | Scoped `metaPatchRequest` to `meta_patch_ready` producer | ⚠️ PARTIAL | Manual check verifies `cols = c('S.Score','G2M.Score','Phase')` and `mod_UpdateMetaData_server()` sends `meta_patch_ready`; versioning makes the link semantically unreliable. |
| `srcjs/index.js` | `R/app_server.R` | Bounded assignment intent consumed and resolved server-side | ⚠️ PARTIAL | Intent path exists, but server version fallback and duplicate event binding invalidate stale-safe assignment. |
| `srcjs/index.js` | `R/mod_AssignCellCluster.R` | Selected cell IDs for lasso/subset | ✗ NOT_WIRED | JS sends IDs; R expects numeric indices. Spot-check reproduced no valid cells from `c('Cell1','Cell3')`. |
| `R/mod_SubsetCells.R` | `R/fct_bpcells_backend.R` | Safe subset helper instead of raw subset | ⚠️ PARTIAL | Helper is called, but no `backend_root` is provided, causing unsafe temp backing for BPCells-backed subsets. |
| `R/app_server.R` | `srcjs/index.js` | Arrow IPC resource URLs | ✗ NOT_WIRED SAFELY | Server maps all sessions to global `/data`; client hard-codes `/data/...`, so session isolation is broken. |

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `load_analysis_input_file()` | `seuratObj` | Uploaded/local Analysis file, Seurat/BPCells helpers | Yes for fixtures; unsafe for compressed archive trust boundary | ⚠️ PARTIAL |
| `run_memory_conserving_processing()` | Processed Seurat state | Seurat/BPCells layers and helper calls | Yes; no final dense `scale.data` asserted | ✓ FLOWING |
| `mod_CellCycling_server()` | `S.Score`, `G2M.Score`, `Phase` metadata patch | `score_cell_cycle_safely()` then `metaPatchRequest` | Server data exists; browser may drop as stale | ⚠️ HOLLOW — patch version disconnected |
| Assignment observer in `app_server.R` | Assigned metadata column | `renameCluster-assignmentIntent` resolved against `object[[]]` | Server data exists; stale context bypass and stale patch possible | ⚠️ HOLLOW — stale gate not trusted |
| `mod_SubsetCells_server()` | Selected cells | `selectedCells()` from `mod_AssignCellCluster_server()` | No for browser lasso IDs; IDs are coerced as indices | ✗ DISCONNECTED |
| Browser metadata/reduction/expression fetches | Arrow IPC files | `/data/...` resource prefix | Real files, but resource prefix is app-global, not session-scoped | ✗ DISCONNECTED across sessions |

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| JS assignment/subset browser tests still pass | `pixi run npm test -- srcjs/index.test.js` | 36 tests passed | ✓ PASS |
| R assignment/subset targeted tests still pass | `pixi run Rscript -e "devtools::test(filter = 'assignment-metadata-safety|subset-cells')"` | `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 56 ]` | ✓ PASS |
| Lasso-selected cell IDs survive R selected-cell conversion | `Rscript -e 'selectedPoints <- c("Cell1", "Cell3"); all_cells <- paste0("Cell", 1:3); selected_idx <- as.integer(selectedPoints) + 1L; selected_idx <- selected_idx[selected_idx >= 1L & selected_idx <= length(all_cells)]; cells <- all_cells[selected_idx]; if (!length(stats::na.omit(cells))) stop("selected cell IDs became no valid cells")'` | Warning `NAs introduced by coercion`; error `selected cell IDs became no valid cells` | ✗ FAIL |

## Probe Execution

| Probe | Command | Result | Status |
|---|---|---|---|
| Conventional phase probes | `scripts/**/tests/probe-*.sh` discovery | No probe files or phase-declared probes found | SKIPPED |

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| ANAL-01 | `03-01-PLAN.md` | Load supported Seurat `.Rds`, `.h5ad`, BPCells bundle, and compressed 10x-style inputs with BPCells backing where possible | ✗ BLOCKED | Supported load code/tests exist, but compressed user archives are extracted without path traversal/symlink validation. |
| ANAL-02 | `03-01-PLAN.md`, `03-02-PLAN.md` | Derive missing normalized/HVG/PCA/neighbors/clusters/UMAP state through memory-conserving paths | ✓ SATISFIED | `run_memory_conserving_processing()` and helper tests verify derivation and no final dense `scale.data`. |
| ANAL-03 | `03-02-PLAN.md` | Filter, cluster, and add cell-cycle metadata without dense `scale.data` or unnecessary full-dataset transfers | ✗ BLOCKED | No-dense-scale is partly met, but scoped cell-cycle metadata patch can be dropped as stale because patch/full metadata versions are not monotonic together. |
| ANAL-04 | `03-03-PLAN.md` | Select by lasso/category and assign metadata with stale rename selections cleared | ✗ BLOCKED | Browser intent/stale clearing exists, but server uses browser version fallback, duplicate assign events remain, and metadata patch can be invisible. |
| ANAL-05 | `03-04-PLAN.md` | Subset selected cells and restore original object while downstream state refreshes | ✗ BLOCKED | Lasso IDs are not wired to R subset selection, BPCells subset backing can leak outside session cleanup, and global `/data` can mix downstream IPC refreshes across sessions. |

No orphaned Phase 03 requirements were found in `.planning/REQUIREMENTS.md`; Phase 03 maps exactly `ANAL-01` through `ANAL-05`.

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| `R/mod_dataInput.R` | 929, 936 | Raw archive extraction of user upload | 🛑 Blocker | Path traversal/symlink archive entries can write outside temp extraction root. |
| `R/app_server.R` | 163 | Global `addResourcePath('data', tempDir)` | 🛑 Blocker | Cross-session IPC files can be mixed/exposed through a shared `/data` prefix. |
| `R/app_server.R`, `R/mod_CellCyling.R`, `srcjs/index.js` | 197-199 / 129-134 / 285-295 | Independent metadata patch and full-transfer versions | 🛑 Blocker | Browser can drop successful metadata mutations as stale. |
| `R/app_server.R` | 416-418 | Browser-submitted version used as trusted current version fallback | 🛑 Blocker | Stale assignment context checks can be bypassed. |
| `R/mod_AssignCellCluster.R` | 94-103 | Cell IDs coerced to numeric indices | 🛑 Blocker | Lasso-selected cells cannot reliably drive subset/restore. |
| `R/fct_bpcells_backend.R`, `R/mod_SubsetCells.R` | 248 / 93-98 | BPCells subset backing outside session root | 🛑 Blocker | Large private BPCells layer directories can persist outside cleanup. |
| `srcjs/index.js` | 1569-1570 | Duplicate assignment event bindings | ⚠️ Warning | A normal assign click can submit two mutation intents. |
| `R/mod_FilterCell.R` | 136-154 | Missing pre-validation/tryCatch for QC columns and empty filter result | ⚠️ Warning | Expected filter edge cases can surface as Shiny observer errors. |
| `R/mod_ClusterSetting.R` | 101-116, 129-138 | No requested-dimension clamp against available PCs | ⚠️ Warning | Processed objects with fewer PCs than requested can error instead of showing recoverable validation. |

Debt marker scan found no unreferenced `TBD`, `FIXME`, or `XXX` markers in modified Phase 03 source/test files.

## Human Verification Required

Automated verification found blockers, so human UAT should wait until the gaps above are fixed. After fixes, manually verify:

1. Load a representative large BPCells-backed Analysis dataset, process missing state, then confirm memory remains bounded and no dense `scale.data` is retained.
2. In the Shiny UI, lasso cells, assign metadata, confirm the new column appears without a full metadata reload, subset to the lasso cells, and restore the original object.
3. Open two concurrent Shiny sessions with different datasets and confirm metadata/reduction/expression fetches remain session-isolated.

## Gaps Summary

The phase goal is **not achieved**. Although substantial no-dense-scale and test coverage was added, the codebase still contains blocker-class failures in the actual user/data flow: unsafe archive extraction, non-monotonic metadata patch versions, bypassable stale assignment validation, broken lasso-selected subset wiring, BPCells backing leakage outside session cleanup, and a global IPC resource path. These failures directly contradict the phase promise that large Analysis Mode datasets remain usable without stale selections, unsafe dense/backing state, or unnecessary transfers.

No gap is clearly deferred to a later roadmap phase. Phase 4 covers portable artifacts and Explore Mode, not these Phase 3 Analysis Mode safety regressions.

---

_Verified: 2026-06-24T03:10:47Z_
_Verifier: the agent (gsd-verifier)_
