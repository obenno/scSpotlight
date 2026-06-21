---
phase: 02-arrow-transfer-main-scatter-reliability
plan: "03"
subsystem: browser-state
tags: [arrow-ipc, metadata-patch, expression-cache, sparkline, main-scatter]

# Dependency graph
requires:
  - phase: 02-arrow-transfer-main-scatter-reliability
    provides: Plan 02 expression backend transfer payloads and transfer_error contract
provides:
  - Browser-side stale expression guards after async fetch/decode
  - Column-scoped metadata patch validation and refresh decisions
  - Scoped expression and metadata patch failure copy
  - First-selected-gene scatter/sparkline state coverage
affects: [phase-02, browser-payload-contracts, main-scatter, feature-sparkline]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Version/assay/gene expression cache identity checks before cache writes and scatter mutation
    - Column-scoped metadata patch merge through ScatterModel validation
    - Sparkline checked state separated from first-gene primary emphasis

key-files:
  created:
    - .planning/phases/02-arrow-transfer-main-scatter-reliability/02-03-SUMMARY.md
    - srcjs/modules/featureSparkLine.test.js
  modified:
    - srcjs/index.js
    - srcjs/index.test.js
    - srcjs/modules/featureSparkLine.js
    - srcjs/modules/scatter/scatterModel.test.js
    - tests/testthat/test-development-contract-docs.R
    - DEVELOPMENT.md
    - inst/app/www/index.js
    - inst/app/www/index.js.map

key-decisions:
  - "Expression payloads are current only when `exprVersion`, `assay`, and `geneName` still match the active browser expression identity."
  - "Metadata patch payloads apply only requested `cols`; decoded extra columns are ignored."
  - "Sparkline checked state remains independent from primary state; only `selectedFeatures[0]` receives semibold/aria-current emphasis."

requirements-completed: [XFER-03, XFER-04, SCAT-04]

# Metrics
duration: 24min
completed: 2026-06-22
---

# Phase 02 Plan 03: Browser Expression And Metadata Patch State Summary

**Stale-safe expression payloads, scoped metadata patch application, and first-selected-gene sparkline/main-scatter synchronization**

## Accomplishments

- Added post-await stale guards for `expr_ready` and `expr_cached` so stale version/assay/gene results cannot write the expression cache or mutate scatter state.
- Added scoped expression failure copy using `Expression could not load` while preserving existing category scatter context.
- Tightened `meta_patch_ready` to require `cols`, apply only scoped decoded columns, rely on `ScatterModel` validation before merge, and show `Metadata update could not apply` on malformed/failing patches.
- Preserved targeted cache-miss behavior through `inputFeatures-cacheMissFeature` without adding full metadata or dataset reload paths.
- Added first-selected-gene sparkline tests and implementation refinements: checked genes remain checked, only the first selected gene is primary, and removing the first selected gene promotes the next checked gene.
- Documented the implemented Phase 02 browser-state rules in `DEVELOPMENT.md` and guarded them with `test-development-contract-docs.R`.
- Rebuilt frontend assets in `inst/app/www/index.js` and `inst/app/www/index.js.map`.

## Files Created/Modified

- `srcjs/index.js` - expression identity gates, metadata patch scope/validation, and scoped failure copy.
- `srcjs/index.test.js` - stale expression/patch, patch validation, failure copy, and targeted cache-miss coverage.
- `srcjs/modules/featureSparkLine.js` - testable checked/primary state, safe text labels, keyboard toggle support, and primary `aria-current` state.
- `srcjs/modules/featureSparkLine.test.js` - focused sparkline first-selected-gene regression coverage.
- `srcjs/modules/scatter/scatterModel.test.js` - first-selected-feature panel title/z-data assertions.
- `DEVELOPMENT.md` - browser-state contract documentation.
- `tests/testthat/test-development-contract-docs.R` - docs guard for expression/patch/sparkline rules.
- `inst/app/www/index.js`, `inst/app/www/index.js.map` - rebuilt frontend bundle artifacts.

## Verification

- `pixi run npm test -- srcjs/index.test.js srcjs/modules/featureSparkLine.test.js srcjs/modules/scatter/scatterModel.test.js srcjs/modules/arrowReader.test.js` (pass, 56 JS tests)
- `pixi run Rscript -e "devtools::test(filter = 'development-contract-docs|browser-payload-contracts|bpcells-expression-transfer|explore-bundle|analysis-backend-contract')"` (pass, 272 R tests)
- `pixi run build-js` (pass)
- `pixi run npm test -- srcjs/index.test.js srcjs/modules/featureSparkLine.test.js srcjs/modules/scatter/scatterModel.test.js srcjs/modules/arrowReader.test.js` after bundle rebuild (pass, 56 JS tests)

## Deviations from Plan

- No R producer code changes were needed in `R/mod_UpdateMetaData.R`; the metadata patch transfer-error path already used the sanitized `metadata_patch` contract with `cols` and `version`.

## Issues Encountered

- `DEVELOPMENT.md` still contains unrelated pre-existing LLM/runtime-mode hunks in the dirty worktree. Only the Phase 02 transfer reliability hunk is plan-scoped.
- Vitest prints expected console output/errors from existing failure-path tests; all targeted tests pass.

## Threat Flags

None. Expression and patch failure copy is path-free and rendered through `textContent`; expression payloads remain Arrow/TypedArray oriented and metadata patches remain column-scoped.

## User Setup Required

None.

## Next Phase Readiness

- Plan 04 can build on stable browser expression and metadata patch state for adaptive deck.gl rendering, split-panel geometry, legend/title behavior, and lasso synchronization.

## Self-Check: PASSED

- Verified all modified Plan 03 source/test/docs/build files exist on disk.
- Verified targeted R tests, JS tests, and frontend build pass after implementation.

---
*Phase: 02-arrow-transfer-main-scatter-reliability*
*Completed: 2026-06-22*
