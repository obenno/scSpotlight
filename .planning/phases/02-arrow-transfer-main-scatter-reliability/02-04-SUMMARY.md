---
phase: 02-arrow-transfer-main-scatter-reliability
plan: 04
subsystem: frontend-scatter
tags: [deck-gl, scatter, lasso, selection, vitest]

requires:
  - phase: 02-arrow-transfer-main-scatter-reliability
    provides: Wave 1-3 transfer, expression, cache, and browser-state reliability foundations
provides:
  - Adaptive deck.gl scatter threshold and binary-layer regression coverage
  - Multi-panel split/lasso/count synchronization coverage and fixes
  - Main scatter renderer and selection documentation
affects: [main-scatter, browser-rendering, lasso-selection, split-panels]

tech-stack:
  added: []
  patterns: [deck.gl binary attributes, panel-local lasso hit-testing, visible-cell selection reconciliation]

key-files:
  created:
    - .planning/phases/02-arrow-transfer-main-scatter-reliability/02-04-SUMMARY.md
  modified:
    - srcjs/modules/deckScatter.js
    - srcjs/modules/deckScatter.test.js
    - srcjs/modules/lasso.test.js
    - srcjs/modules/scatter/scatterLayout.test.js
    - srcjs/modules/scatter/scatterModel.test.js
    - inst/app/www/index.js
    - inst/app/www/index.js.map
    - DEVELOPMENT.md

key-decisions:
  - "Base deck.gl picking remains disabled for panels with at least 2M points, even when zoomed, while lasso selection remains available."
  - "Selection reconciliation is performed during panel highlight matching to avoid materializing all visible cell IDs into an extra flat array."
  - "Null, empty, and literal undefined metadata levels are treated as missing for category/split levels."

patterns-established:
  - "Synthetic large-scale tests pass point-count thresholds directly instead of allocating million-row fixtures."
  - "Scatter selection state is reconciled by currently visible cell IDs before badge/highlight updates."

requirements-completed:
  - SCAT-01
  - SCAT-02
  - SCAT-03

duration: 55 min
completed: 2026-06-22
---

# Phase 02 Plan 04: Scatter Rendering And Lasso Reliability Summary

**deck.gl binary scatter thresholds, split-panel geometry, and lasso/count synchronization are now covered and hardened for large datasets.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-06-22T00:55:00Z
- **Completed:** 2026-06-22T01:50:00Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments

- Locked AGENTS.md adaptive point thresholds, including strict non-pickable base scatter layers at 2M+ cells.
- Added regression coverage proving deck.gl `ScatterplotLayer` uses typed binary attributes, not per-point object arrays.
- Added split-panel title/geometry/missing-level coverage for category, expression, exactly-two-split, and multi-split modes.
- Added lasso and selected-count coverage for non-origin/high-cardinality panels and short gestures clearing selection.
- Reconciled requested selected cell IDs against current panel cell IDs before highlight and badge updates.
- Documented the main scatter binary renderer, adaptive thresholds, lasso, missing-level, split geometry, and selection reconciliation contracts.

## Task Commits

1. **Task 1: Add scatter rendering, split, and lasso regression tests** - `4488258` (feat, includes tests and implementation)
2. **Task 2: Implement adaptive deck scatter and multi-panel selection reliability** - `4488258` (feat)
3. **Task 3: Document scatter reliability and run final Phase 02 checks** - `4488258` (feat, docs and bundle)

**Plan metadata:** committed separately after this summary.

## Files Created/Modified

- `srcjs/modules/deckScatter.js` - Enforces 2M+ non-pickable base layers, filters missing metadata levels, and reconciles selection during highlight matching.
- `srcjs/modules/deckScatter.test.js` - Adds threshold, binary attribute, missing-level, selection reconciliation, and count badge tests.
- `srcjs/modules/lasso.test.js` - Adds high-cardinality non-origin viewport lasso and short-gesture clear tests.
- `srcjs/modules/scatter/scatterLayout.test.js` - Locks adaptive minimum panel size boundaries and scrollable high-cardinality layouts.
- `srcjs/modules/scatter/scatterModel.test.js` - Covers missing split/category levels, title rules, expression panels, and first-selected-gene behavior.
- `inst/app/www/index.js` - Rebuilt production JS bundle.
- `inst/app/www/index.js.map` - Rebuilt production sourcemap.
- `DEVELOPMENT.md` - Documents Wave 4 scatter reliability contracts.

## Decisions Made

- Disabled base hover/picking at `nPoints >= 2000000` regardless of zoom because the Phase 02 UI spec and AGENTS.md table make that threshold normative.
- Reconciled selection while walking panel cell arrays to avoid an extra `flat()`/`Set` over every visible cell in large split layouts.
- Treated `null`, empty string, and literal string `undefined` metadata values as missing levels so they do not appear in legends, split titles, or selectable IDs.

## Deviations from Plan

None - plan executed as written. The implementation kept changes focused to the scatter modules, tests, docs, and rebuilt bundle.

## Issues Encountered

- No local representative 100K or 1M+ fixtures were available for manual browser validation.
- Searched locations/patterns: repo-wide `**/*100k*`, `**/*100K*`, `**/*1m*`, `**/*1M*`, `**/*.explore-parquet.zip`, `**/*.rds`, `**/*.Rds`, `**/*.h5ad`, `**/data/**`, `**/extdata/**`, `**/fixtures/**`, `**/fixture/**`, `**/testdata/**`, `**/example*/**`, and `**/sample*/**`.
- Fallback evidence used synthetic threshold, binary-layer, split-geometry, lasso, selection, and transfer contract tests. Real 100K/1M+ manual validation was not performed because fixtures were unavailable.

## Validation

- `pixi run npm test -- srcjs/modules/deckScatter.test.js srcjs/modules/scatter/scatterModel.test.js srcjs/modules/scatter/scatterLayout.test.js srcjs/modules/lasso.test.js srcjs/modules/scatter/scatterCoordinates.test.js srcjs/modules/scatter/scatterRelayout.test.js` - PASS, 56 tests.
- `pixi run npm test -- srcjs/modules/deckScatter.test.js srcjs/modules/scatter/scatterModel.test.js srcjs/modules/scatter/scatterLayout.test.js srcjs/modules/lasso.test.js srcjs/modules/scatter/scatterCoordinates.test.js srcjs/modules/scatter/scatterRelayout.test.js srcjs/index.test.js srcjs/modules/featureSparkLine.test.js` - PASS, 86 tests.
- `pixi run Rscript -e "devtools::test(filter = 'development-contract-docs|browser-payload-contracts|bpcells-expression-transfer|explore-bundle|analysis-backend-contract')"` - PASS, 272 tests.
- `pixi run build-js` - PASS.
- `git diff --cached --check` - PASS before implementation commit.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 02 Wave 4 is complete. Phase 02 is ready for full phase-level verification, state/roadmap updates, and then stop because execution was launched with `--no-transition`.

---
*Phase: 02-arrow-transfer-main-scatter-reliability*
*Completed: 2026-06-22*
