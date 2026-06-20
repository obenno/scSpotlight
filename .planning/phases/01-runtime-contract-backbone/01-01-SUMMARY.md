---
phase: 01-runtime-contract-backbone
plan: "01"
subsystem: backend
tags: [r, seurat, bpcells, arrow-ipc, testthat]

requires: []
provides:
  - Analysis Mode backend contract tests for Seurat/BPCells metadata, reductions, features, PCA stdev, and expression helpers.
  - Arrow IPC producer adapter coverage for Analysis metadata, reduction, PCA stdev, and path-based expression transfers.
  - Source guards proving Analysis transfer helpers do not reintroduce DuckDB calls or live Seurat objects in expression futures.
affects: [phase-02-arrow-transfer, phase-03-analysis-mode, backend-transfer-contracts]

tech-stack:
  added: []
  patterns:
    - testthat contract tests using small in-memory Seurat objects and BPCells-backed temp layers
    - Arrow IPC schema assertions for browser-facing Analysis payloads
    - source-level guard tests for path-based expression transfer futures

key-files:
  created:
    - tests/testthat/test-analysis-backend-contract.R
  modified: []

key-decisions:
  - "Kept Analysis Mode metadata and reduction transfers on data-frame adapters while expression uses BPCells path-based jobs."
  - "Added source guards rather than changing helper implementation because existing Seurat/BPCells helper paths already satisfied the contract tests."

patterns-established:
  - "Analysis backend seam tests should prove helper behavior through public namespace lookups, not mirrored DuckDB state."
  - "Expression transfer tests should assert future jobs contain paths and browser payload fields, not live Seurat/BPCells objects."

requirements-completed:
  - BACK-01

duration: 11 min
completed: 2026-06-20
---

# Phase 01 Plan 01: Analysis Backend Seam Contract Summary

**Seurat/BPCells Analysis Mode backend contract tests for metadata, reductions, PCA summaries, and path-based Arrow expression transfer**

## Performance

- **Duration:** 11 min
- **Started:** 2026-06-20T13:02:11Z
- **Completed:** 2026-06-20T13:13:26Z
- **Tasks:** 2 completed
- **Files modified:** 1

## Accomplishments

- Added `test-analysis-backend-contract.R` with a small Seurat object fixture covering metadata, features, UMAP/PCA reductions, PCA stdev, and expression vectors.
- Verified Analysis metadata, reduction, PCA stdev, and expression transfer adapters write the expected Arrow IPC browser schemas.
- Proved Analysis expression transfer jobs are BPCells path-based and exclude live object/data fields and DuckDB query plans.
- Added source guards that keep `R/fct_backend_transfer_adapter.R` and `R/mod_InputFeature.R` free of Analysis DuckDB calls and keep `prepare_backend_expression_transfer()` outside the promise body.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Analysis Mode backend seam contract tests** - `65d5be9` (test)
2. **Task 2: Harden Analysis Mode helper paths only where contract tests fail** - `bba5d85` (test)

**Plan metadata:** see final completion output for docs commit hash.

_Note: Helper source changes were not needed; the new contract tests passed against the existing Seurat/BPCells implementation._

## Files Created/Modified

- `tests/testthat/test-analysis-backend-contract.R` - Contract tests for Analysis helper seams, Arrow IPC adapter output, BPCells path-based expression transfer payloads, and source guards against Analysis DuckDB/live-object futures.

## Decisions Made

- Kept Analysis Mode metadata and reduction transfers on `backend = "data_frame"` producer jobs because they already read from Seurat helper outputs and satisfy the browser Arrow IPC contract.
- Kept Analysis expression transfer on `backend = "bpcells"` path jobs because tests confirm futures can write from `matrix_dir`, `feature`, and `output_file` without carrying a live Seurat object.
- Added explicit source guard coverage instead of changing R helper code because the existing implementation already met BACK-01 and the threat-model mitigations.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `state.add-decision` inserted the full SUMMARY content into `.planning/STATE.md`; STATE was repaired before final commit to keep only concise Phase 01 Plan 01 decisions and remain under the workflow size target.

## TDD Gate Compliance

- Task-level `tdd="true"` tests passed immediately against the existing helper implementation; no GREEN source-code commit was required.
- RED/GREEN feature commits are therefore not present for this execute-type plan. The resulting commits are both test commits because the plan's requested output was contract coverage plus narrow helper fixes only if tests failed.

## Known Stubs

None.

## Authentication Gates

None.

## Verification

- `pixi run Rscript -e "devtools::test(filter = 'analysis-backend-contract')"` — PASS (37 passing tests before Task 2 guard additions).
- `pixi run Rscript -e "devtools::test(filter = 'analysis-backend-contract|bpcells-expression-transfer')"` — PASS (47 passing tests after Task 2 guard additions).
- `pixi run Rscript -e "devtools::test(filter = 'explore-bundle|bpcells-expression-transfer|analysis-backend-contract')"` — PASS (100 passing tests).
- `bash -lc "! grep -nE 'DBI::dbConnect|duckdb::duckdb|query_duck' R/fct_backend_transfer_adapter.R R/mod_InputFeature.R"` — PASS.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for `01-02-PLAN.md` to add the browser payload manifest with paired R producer and JS consumer/cache tests.

## Self-Check: PASSED

- Found `tests/testthat/test-analysis-backend-contract.R`.
- Found `.planning/phases/01-runtime-contract-backbone/01-01-SUMMARY.md`.
- Found task commit `65d5be9`.
- Found task commit `bba5d85`.

---
*Phase: 01-runtime-contract-backbone*
*Completed: 2026-06-20*
