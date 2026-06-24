---
phase: 03-analysis-mode-processing-mutation-safety
plan: 04
subsystem: analysis-mode-mutation-safety
tags: [r, shiny, seurat, bpcells, arrow-ipc, deckgl, vite, tdd]

# Dependency graph
requires:
  - phase: 03-analysis-mode-processing-mutation-safety
    provides: Analysis loading, filtering, clustering, cell-cycle, and assignment mutation safety from plans 03-01 through 03-03.
  - phase: 02-arrow-transfer-main-scatter-reliability
    provides: Existing browser transfer contracts and stale-gated metadata, reduction, expression, patch, and transfer-error handlers.
provides:
  - Guarded subset/restore lifecycle for Analysis Mode Seurat objects.
  - Browser object-replacement cleanup for selected cells, rename state, assignment payloads, expression cache, and selected features.
  - DEVELOPMENT documentation guard for ANAL-05 subset/restore semantics.
affects: [analysis-mode, subset-restore, browser-state, metadata-transfer, expression-cache, phase-04-explore]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - safe_subset_seurat_object-backed subset state machine
    - full object replacement state cleanup through existing Phase 02 browser contracts
    - no-final-dense-scale invariant on subset and restore

key-files:
  created:
    - tests/testthat/test-subset-cells.R
  modified:
    - R/mod_SubsetCells.R
    - srcjs/index.js
    - srcjs/index.test.js
    - inst/app/www/index.js
    - inst/app/www/index.js.map
    - tests/testthat/test-development-contract-docs.R
    - DEVELOPMENT.md

key-decisions:
  - "Subset/restore reuses safe_subset_seurat_object() and existing Phase 02 browser contracts instead of introducing a subset-specific transfer message."
  - "Browser object replacement purges expression cache/state and reconciles lasso-selected cells only against visible metadata cell IDs."
  - "Large-data subset/restore evidence is automated invariant and synthetic-state coverage only; no representative 100K/1M+ fixture was manually loaded."

patterns-established:
  - "Subset mutation: validate selected cells before mutation, store original once, drop/assert dense scale.data, and increment gene/meta/reduction indicators only after success."
  - "Object replacement cleanup: clear stale rename/assignment transport state, expression cache, selected features, and invalid selected cells after full metadata refresh."

requirements-completed: [ANAL-05]

# Metrics
duration: 17min
completed: 2026-06-24
---

# Phase 03 Plan 04: Subset/Restore Refresh Semantics Summary

**Analysis Mode subset/restore now uses safe Seurat/BPCells mutation guards with browser state reconciliation through existing Arrow IPC contracts.**

## Performance

- **Duration:** 17 min
- **Started:** 2026-06-24T02:14:15Z
- **Completed:** 2026-06-24T02:31:37Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments

- Added RED/GREEN coverage for subset/restore lifecycle, invalid selections, original-object backup lifecycle, no-final-dense-scale checks, and complete refresh indicator increments.
- Reworked `mod_SubsetCells_server()` to validate current cells, use `safe_subset_seurat_object()`, store the original once, restore once, clear backup state, and avoid indicator increments on invalid or repeated toggles.
- Added browser object replacement cleanup that clears/reconciles selected cells, rename selections, assignment payloads, expression cache, and selected feature state without adding a new browser message contract.
- Documented the subset/restore contract in `DEVELOPMENT.md` and kept a docs guard in `test-development-contract-docs.R`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add subset/restore lifecycle and browser refresh coverage** - `dc56b69` (test)
2. **Task 2: Implement safe subset/restore and browser state reconciliation** - `08e4644` (feat)
3. **Task 3: Document subset/restore semantics and run final Phase 03 verification** - `dfdf169` (docs)

**Plan metadata:** captured in the final closeout docs commit for this plan.

_Note: This plan used TDD-style RED/GREEN commits for the feature slice._

## Files Created/Modified

- `tests/testthat/test-subset-cells.R` - New Shiny `testServer()` coverage for subset invalid paths, valid subset, restore, indicators, original backup, and no-dense-scale behavior.
- `tests/testthat/test-development-contract-docs.R` - Added fixed-string docs guard for subset/restore safety rules.
- `srcjs/index.test.js` - Added browser tests for full object replacement cleanup, selected-cell reconciliation, stale gate preservation, and no new subset-specific message contract.
- `R/mod_SubsetCells.R` - Replaced raw `subset()` path with guarded validation plus `safe_subset_seurat_object()` and restore cleanup.
- `srcjs/index.js` - Added expression-state clearing and selection reconciliation after full metadata replacement using existing handlers.
- `inst/app/www/index.js` - Rebuilt bundled JavaScript output.
- `inst/app/www/index.js.map` - Rebuilt bundled JavaScript sourcemap.
- `DEVELOPMENT.md` - Documented subset/restore refresh semantics and contract reuse.

## Decisions Made

- Subset/restore reuses `safe_subset_seurat_object()` to keep cell selection validation, source-object cell order, BPCells/no-dense-scale behavior, and filter path semantics aligned.
- Full object replacement uses existing `meta_ready`, reduction/expression handlers, `clear_expr`, stale gates, and `transfer_error`; no `subset_restore_ready` message was introduced.
- Browser expression cache is purged on full metadata replacement because subset/restore changes the canonical cell universe and old expression vectors may be wrong length or stale.
- Large-fixture status: no representative 100K/1M+ dataset was manually loaded; large-data behavior is covered by automated no-dense-scale, source-guard, indicator, safe helper, and synthetic browser-state tests only.

## Verification

- `pixi run Rscript -e "devtools::test(filter = 'subset-cells|development-contract-docs')"` — RED observed expected failures before implementation.
- `pixi run npm test -- srcjs/index.test.js` — RED observed expected browser cleanup/reconciliation failures before implementation.
- `pixi run Rscript -e "devtools::test(filter = 'subset-cells|analysis-mutation-safety|analysis-loading-processing-safety')"` — PASS after implementation, with pre-existing fixture warnings from Seurat/BPCells small test data.
- `pixi run npm test -- srcjs/index.test.js` — PASS after implementation and final verification.
- `pixi run build-js` — PASS after implementation and final verification.
- `pixi run Rscript -e "devtools::test(filter = 'development-contract-docs|browser-payload-contracts|analysis-loading-processing-safety|analysis-mutation-safety|assignment-metadata-safety|subset-cells|filter-cell-qc-metadata|update-category|bpcells-matrix-coercion|bpcells-hvg')"` — PASS final targeted Phase 03 verification, with known small-fixture warnings only.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

- Documentation guard initially failed because the DEVELOPMENT text did not exactly match the fixed-string needles. Resolved by adjusting the documented phrases to match the guard.
- The targeted R suite emits existing Seurat/BPCells small-fixture warnings such as loess span and dense conversion warnings; these did not fail tests and were not changed.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Threat Flags

None. The plan touched an existing browser-selected-cells to server subset trust boundary and existing browser cache state, both covered by the plan threat model.

## Self-Check: PASSED

- FOUND: `R/mod_SubsetCells.R`
- FOUND: `srcjs/index.js`
- FOUND: `tests/testthat/test-subset-cells.R`
- FOUND: `tests/testthat/test-development-contract-docs.R`
- FOUND: `DEVELOPMENT.md`
- FOUND: `inst/app/www/index.js`
- FOUND: `inst/app/www/index.js.map`
- FOUND commit: `dc56b69`
- FOUND commit: `08e4644`
- FOUND commit: `dfdf169`

## Next Phase Readiness

- Phase 03 mutation safety chain is complete for ANAL-05 subset/restore behavior.
- Phase 04 can rely on stable Phase 02 browser transfer contracts and Phase 03 Analysis Mode mutation invariants.
- Remaining project-level concern: representative 100K/1M+ fixture validation is still needed before claiming manual large-dataset subset/restore validation.

---
*Phase: 03-analysis-mode-processing-mutation-safety*
*Completed: 2026-06-24*
