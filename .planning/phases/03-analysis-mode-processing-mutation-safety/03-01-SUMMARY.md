---
phase: 03-analysis-mode-processing-mutation-safety
plan: "01"
subsystem: analysis-backend
tags: [r, shiny, seurat-v5, bpcells, analysis-mode, testthat]

requires:
  - phase: 02-arrow-transfer-main-scatter-reliability
    provides: Versioned Arrow IPC browser transfer contracts and stale-payload guards preserved by this plan.
provides:
  - Analysis Mode loading helper for Seurat RDS, h5ad, BPCells bundle archives, and compressed 10x-style inputs.
  - No-final-dense-scale invariant helpers around Analysis load, PCA, processing, validation, and bundle save paths.
  - Fixture-backed tests for Analysis loading, BPCells backing, processing derivation, and Explore bundle rejection.
affects: [phase-03-mutation-slices, phase-04-portable-artifacts, analysis-mode-loading, bpcells-processing]

tech-stack:
  added: []
  patterns:
    - Centralized Analysis input routing through `load_analysis_input_file()`.
    - `drop_dense_scale_data()` plus `assert_no_dense_scale_data()` before app-state handoff.
    - Small-fixture-only BPCells VST sparse fallback guarded by matrix size.

key-files:
  created:
    - tests/testthat/test-analysis-loading-processing-safety.R
  modified:
    - R/fct_bpcells_backend.R
    - R/mod_dataInput.R
    - tests/testthat/test-bpcells-matrix-coercion.R
    - tests/testthat/test-bpcells-hvg.R
    - tests/testthat/test-development-contract-docs.R
    - DEVELOPMENT.md

key-decisions:
  - "Analysis Mode loading now uses a central helper so every supported input class reaches validation, BPCells backing, and no-dense-scale checks before app-state update."
  - "Final Analysis app state must not retain dense `scale.data`; temporary fallback scaling is allowed only inside helpers and is followed by drop/assert enforcement."
  - "Large-data safety in this slice is proven by automated invariants and synthetic fixtures; no representative 1M+ fixture was manually loaded."

patterns-established:
  - "No-dense-scale invariant: call `drop_dense_scale_data()` and `assert_no_dense_scale_data()` before returning processed Analysis state."
  - "Mode-gated loading: `.explore-parquet.zip` remains rejected in Analysis Mode and accepted only by Explore Mode paths."
  - "Fixture executable coverage: supported load branches should be exercised with small synthetic files when dependencies are available."

requirements-completed: [ANAL-01, ANAL-02]

duration: 50 min
completed: 2026-06-23
---

# Phase 03 Plan 01: Analysis Mode Loading and Processing Safety Summary

**Analysis Mode loading now routes supported Seurat/BPCells inputs through validation, BPCells backing, and no-final-dense-scale processing guards.**

## Performance

- **Duration:** 50 min
- **Started:** 2026-06-23T11:25:29Z
- **Completed:** 2026-06-23T12:15:08Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- Added failing-then-passing test coverage for Analysis Mode loading safety, processing derivation, BPCells backing, Explore bundle rejection, and no final dense `scale.data` state.
- Added `drop_dense_scale_data()` / `assert_no_dense_scale_data()` helper enforcement around PCA, full processing, validation, app-state handoff, and bundle-save preparation.
- Introduced `load_analysis_input_file()` so Seurat `.Rds`, `.h5ad`, BPCells bundle archives, and compressed 10x-style inputs follow the same Analysis validation and BPCells backing seam.
- Updated `DEVELOPMENT.md` and its docs guard to preserve the Phase 03 loading/processing invariants and unchanged Phase 02 Arrow IPC browser contracts.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add loading and processing safety coverage** - `c2dd068` (test)
2. **Task 2: Implement no-dense-scale processing and input safety guards** - `9abf5a6` (feat)
3. **Task 3: Document Analysis loading/processing invariants and verify slice** - `b94c199` (docs)

**Plan metadata:** committed separately after this summary.

_Note: Tasks 1 and 2 followed the TDD red/green sequence: the RED tests failed before implementation, then the implementation commit made the targeted tests pass._

## Files Created/Modified

- `tests/testthat/test-analysis-loading-processing-safety.R` - New fixture tests for processing/PCA no-dense-scale invariants, supported Analysis input loading branches, Explore archive rejection, and source drift guards.
- `tests/testthat/test-bpcells-matrix-coercion.R` - Extended BPCells app-state layer backing coverage.
- `tests/testthat/test-bpcells-hvg.R` - Extended HVG/processing coverage to assert no final dense `scale.data`.
- `tests/testthat/test-development-contract-docs.R` - Added Phase 03 documentation guard needles.
- `R/fct_bpcells_backend.R` - Added dense-scale detection/drop/assert helpers and enforcement in PCA, processing, backend assertions, and bundle preparation.
- `R/mod_dataInput.R` - Added centralized Analysis loader, non-reactive-safe waiter wrapper, and no-dense-scale validation before app-state updates.
- `DEVELOPMENT.md` - Documented supported Analysis inputs, Explore rejection, BPCells backing, memory-conserving processing, no final dense `scale.data`, and unchanged transfer contracts.

## Decisions Made

- Centralized supported Analysis input loading in `load_analysis_input_file()` instead of maintaining separate duplicated server branches.
- Enforced no final dense `scale.data` as a backend invariant, including portable bundle preparation, because dense scale layers are a direct large-dataset memory risk.
- Kept the tiny BPCells VST fallback bounded to small matrices only so synthetic fixtures remain executable without creating a large-dataset materialization path.
- Did not claim real 1M+ manual validation; this plan uses small executable fixtures plus invariant tests to guard large-data safety properties.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added non-reactive-safe waiter updates**
- **Found during:** Task 2 (Implement no-dense-scale processing and input safety guards)
- **Issue:** `validate_seuratRDS()` and `standard_process_seurat()` call `waiter_update()`, which can fail outside a live Shiny reactive context when helper-level tests exercise the loading/processing seam.
- **Fix:** Added `analysis_waiter_update()` to preserve UI status updates in the app while making helper tests safe in non-reactive test contexts.
- **Files modified:** `R/mod_dataInput.R`
- **Verification:** `pixi run Rscript -e "devtools::test(filter = 'analysis-loading-processing-safety|bpcells-matrix-coercion|bpcells-hvg')"`
- **Committed in:** `9abf5a6`

**2. [Rule 3 - Blocking] Added small-fixture BPCells VST fallback**
- **Found during:** Task 2 (Implement no-dense-scale processing and input safety guards)
- **Issue:** Seurat's BPCells/IterableMatrix VST path can hit loess edge cases on very small synthetic fixtures, blocking executable load-path coverage.
- **Fix:** Added a sparse temporary fallback only for tiny matrices (`prod(dim) <= 1e6`), leaving large BPCells paths non-materializing.
- **Files modified:** `R/fct_bpcells_backend.R`
- **Verification:** `pixi run Rscript -e "devtools::test(filter = 'analysis-loading-processing-safety|bpcells-matrix-coercion|bpcells-hvg')"`
- **Committed in:** `9abf5a6`

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes were required to make the planned helper-level tests executable and did not add new user-facing scope.

## Issues Encountered

- Targeted tests emit expected warnings from tiny synthetic fixtures, including Seurat VST loess singularity warnings and a BPCells non-integer compression warning. The warnings do not indicate test failures and are constrained to small fixture execution.
- No external authentication gates or package installs were required.

## Validation Performed

- RED gate: `pixi run Rscript -e "devtools::test(filter = 'analysis-loading-processing-safety|bpcells-matrix-coercion|bpcells-hvg|development-contract-docs')"` failed before implementation as expected due missing helpers and documentation.
- Task 2 GREEN: `pixi run Rscript -e "devtools::test(filter = 'analysis-loading-processing-safety|bpcells-matrix-coercion|bpcells-hvg')"` passed with `[ FAIL 0 | WARN 40 | SKIP 0 | PASS 51 ]`.
- Final plan verification: `pixi run Rscript -e "devtools::test(filter = 'development-contract-docs|analysis-loading-processing-safety|bpcells-matrix-coercion|bpcells-hvg')"` passed with `[ FAIL 0 | WARN 40 | SKIP 0 | PASS 56 ]`.

## Known Stubs

None. Stub-pattern scan found only pre-existing or intentional Shiny input initializers such as empty select choices; no new goal-blocking stubs were introduced in this plan's created or modified files.

## Auth Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 03 mutation slices can reuse `assert_no_dense_scale_data()` to guard filter, clustering, cell-cycle, assignment, subset, and restore flows.
- Later portable artifact work can rely on bundle preparation dropping dense `scale.data` before save.
- Phase 02 browser message contracts remain unchanged, so downstream scatter and transfer code should not need browser protocol migration for this slice.

## Self-Check: PASSED

- Found created/modified files: `tests/testthat/test-analysis-loading-processing-safety.R`, `R/fct_bpcells_backend.R`, `R/mod_dataInput.R`, `DEVELOPMENT.md`, and this summary file.
- Found task commits: `c2dd068`, `9abf5a6`, and `b94c199`.

---
*Phase: 03-analysis-mode-processing-mutation-safety*
*Completed: 2026-06-23*
