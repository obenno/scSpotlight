---
phase: 03-analysis-mode-processing-mutation-safety
plan: 05
subsystem: testing
tags: [r, testthat, vitest, shiny, browser-contracts, red-harness]

requires:
  - phase: 03-analysis-mode-processing-mutation-safety
    provides: Phase 03 Plans 01-04 Analysis Mode loading, mutation, assignment, subset, and restore seams
provides:
  - Failing R regression coverage for unsafe archive extraction, metadata versioning, assignment trust, selected-cell IDs, and subset backend roots
  - Failing browser contract coverage for session-scoped IPC resource prefixes and single assignment activation
  - DEVELOPMENT.md guard needles for Phase 03 gap-closure documentation
affects: [phase-03-gap-closure, analysis-mode, browser-payload-contracts, assignment, subset]

tech-stack:
  added: []
  patterns: [testthat source assertions, tiny synthetic Shiny fixtures, Vitest browser contract regressions]

key-files:
  created:
    - .planning/phases/03-analysis-mode-processing-mutation-safety/03-05-SUMMARY.md
  modified:
    - tests/testthat/test-analysis-loading-processing-safety.R
    - tests/testthat/test-analysis-mutation-safety.R
    - tests/testthat/test-assignment-metadata-safety.R
    - tests/testthat/test-subset-cells.R
    - tests/testthat/test-browser-payload-contracts.R
    - tests/testthat/test-development-contract-docs.R
    - srcjs/index.test.js

key-decisions:
  - "Plan 03-05 is intentionally RED: it adds failing regression coverage only, with no production code changes."
  - "Browser IPC tests now require session-scoped resourcePrefix URLs instead of the current global /data fetch base."
  - "Assignment activation tests now assert one renameCluster-assignmentIntent per normal click path."

patterns-established:
  - "Regression harness first: source assertions and tiny fixtures pin Phase 03 blocker seams before implementation repairs."
  - "Browser payload contract changes must be reflected in R manifest tests, JS consumer tests, and DEVELOPMENT.md guard needles."

requirements-completed: [ANAL-01, ANAL-03, ANAL-04, ANAL-05]

duration: 10min
completed: 2026-06-24
---

# Phase 03 Plan 05: Failing Regression Harness Summary

**RED regression harness for Phase 03 blocker gaps across Analysis archive safety, metadata mutation ordering, assignment trust, subset backing, browser IPC resource prefixes, and documentation guards.**

## Performance

- **Duration:** 10 min active continuation time
- **Started:** 2026-06-24T15:44:28Z
- **Completed:** 2026-06-24T15:53:34Z
- **Tasks:** 2/2
- **Files modified:** 7 test files plus this summary

## Accomplishments

- Added failing R regressions for unsafe compressed Analysis archive handling, single monotonic metadata-version sequencing, browser assignment trust fallback, selected-cell ID handling, and BPCells-safe subset backend-root threading.
- Added failing JS and R contract coverage for duplicate assignment activation and session-scoped `resourcePrefix` IPC fetch URLs.
- Added a DEVELOPMENT.md docs guard requiring the later gap-closure documentation to name all Phase 03 invariants explicitly.
- Preserved the plan’s core constraint: no production code was changed; all additions are test/docs-guard harness coverage.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add failing R regressions for archive, metadata version, assignment trust, and subset flow** — `7973547` (test)
2. **Task 2: Add failing JS, manifest, and docs contract regressions** — `f281773` (test)

## Files Created/Modified

- `tests/testthat/test-analysis-loading-processing-safety.R` — Added archive-entry source assertions requiring unsafe tar/zip entries to be validated before extraction.
- `tests/testthat/test-analysis-mutation-safety.R` — Added metadata patch/full-refresh monotonic version source assertions.
- `tests/testthat/test-assignment-metadata-safety.R` — Added assignment validation coverage rejecting browser-trusted current-version fallback.
- `tests/testthat/test-subset-cells.R` — Added selected-cell ID and backend-root subset wiring regressions.
- `tests/testthat/test-browser-payload-contracts.R` — Added manifest/source guards requiring file-backed payloads to include `resourcePrefix` and avoid hard-coded global `/data` roots.
- `tests/testthat/test-development-contract-docs.R` — Added DEVELOPMENT.md guard needles for the Phase 03 gap-closure invariants.
- `srcjs/index.test.js` — Added Vitest regressions for one assignment intent per activation and `resourcePrefix`-based metadata fetch URLs.

## Verification

This plan intentionally creates failing tests. Verification passed by confirming the current codebase enters the expected RED state:

- `pixi run Rscript -e "testthat::set_max_fails(Inf); devtools::test(filter = 'analysis-loading-processing-safety|analysis-mutation-safety|assignment-metadata-safety|subset-cells')"` — Expected RED, observed `FAIL 20 | WARN 41 | SKIP 0 | PASS 137`.
- `pixi run Rscript -e "devtools::test(filter = 'browser-payload-contracts|development-contract-docs')"` — Expected RED, observed missing `resourcePrefix` manifest/source/docs guard failures.
- `pixi run npm test -- srcjs/index.test.js` — Expected RED, observed 2 failing tests and 36 passing tests: duplicate assignment intent emission and hard-coded `/data/meta/...` fetch URL.
- Final combined R RED check: `pixi run Rscript -e "devtools::test(filter = 'analysis-loading-processing-safety|analysis-mutation-safety|assignment-metadata-safety|subset-cells|browser-payload-contracts|development-contract-docs')"` — Expected RED; output truncated after intended blocker failures with full log captured by the runtime.

## Decisions Made

- Kept all work test-only so later plans must repair production implementation rather than this harness hiding the gaps.
- Used source assertions where the blocker is architectural wiring that is easier to pin by contract needles than by heavy runtime fixtures.
- Kept fixtures synthetic and small to honor the project’s large-data constraints while still protecting 1M+ cell data paths from unsafe eager behavior.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed an R regex escape in the new archive safety test**
- **Found during:** Task 1 verification
- **Issue:** The first archive-entry source assertion used an invalid R string escape for a literal dot pattern.
- **Fix:** Corrected the escaped regex so the harness parses and reaches the intended RED failures.
- **Files modified:** `tests/testthat/test-analysis-loading-processing-safety.R`
- **Verification:** Re-ran the targeted R RED suite and reached intended blocker failures.
- **Committed in:** `7973547`

**2. [Rule 1 - Bug] Prevented the new resourcePrefix JS RED test from polluting later metadata patch tests**
- **Found during:** Task 2 verification
- **Issue:** The new `meta_ready` resource-prefix test used a high metadata version, causing existing later `meta_patch_ready` tests to be treated as stale and fail for the wrong reason.
- **Fix:** Lowered the test metadata version to align with surrounding fixture state while preserving the intended URL assertion failure.
- **Files modified:** `srcjs/index.test.js`
- **Verification:** Re-ran `pixi run npm test -- srcjs/index.test.js`; only the intended duplicate-intent and resourcePrefix URL tests failed.
- **Committed in:** `f281773`

---

**Total deviations:** 2 auto-fixed (Rule 1 test-harness bugs)
**Impact on plan:** No scope expansion and no production changes; both fixes kept the RED harness precise.

## Issues Encountered

- Verification commands fail by design because Plan 03-05 is a failing regression harness. Later Phase 03 plans are expected to turn these tests green by changing production code and documentation.
- `.planning/STATE.md` had pre-existing orchestrator modifications and future PLAN files `03-05-PLAN.md` through `03-08-PLAN.md` were untracked before close-out. They were intentionally left unstaged per resume instructions.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None. Stub-pattern scan only found normal test fixture initializers such as empty arrays, empty strings for invalid-input assertions, and null reset state in JS tests.

## Threat Flags

None. This plan adds tests for existing trust boundaries but introduces no new production endpoints, auth paths, file access paths, or schema changes.

## Next Phase Readiness

- Later Phase 03 implementation plans can now run the RED harness directly and make the new failures pass without rewriting the assertions.
- Priority repair targets are archive entry validation before extraction, one server-owned metadata version sequence, server-owned assignment current-version context, selected-cell ID handling, subset backend-root threading, session-scoped IPC resource prefixes, and DEVELOPMENT.md gap-closure documentation.

## Self-Check: PASSED

- Summary file existence: FOUND
- Task commit `7973547`: FOUND
- Task commit `f281773`: FOUND

---
*Phase: 03-analysis-mode-processing-mutation-safety*
*Completed: 2026-06-24*
