---
phase: 01-runtime-contract-backbone
plan: "02"
subsystem: browser-transfer-contracts
tags: [r, testthat, javascript, vitest, arrow-ipc, payload-contracts]

requires:
  - phase: 01-runtime-contract-backbone
    provides: Analysis Mode backend seam contract tests from 01-01.
provides:
  - Machine-readable browser payload manifest for metadata, metadata patches, reductions, batched reductions, PCA summaries, expression, and cached payload notifications.
  - R producer tests that assert browser payload fields, IPC columns, and no local path exposure against the manifest.
  - JS consumer/cache tests that assert all manifest message handlers and versioned cache behavior.
affects: [phase-02-arrow-transfer, main-scatter, browser-cache, metadata-patches, expression-transfer]

tech-stack:
  added: []
  patterns:
    - Shared JSON protocol manifest consumed by R and JS contract tests.
    - Versioned browser cache keys shaped with `::` for reduction and expression IPC buffers.
    - Browser payload path policy requiring resource basenames only.

key-files:
  created:
    - inst/protocol/browser-payload-contracts.json
    - tests/testthat/test-browser-payload-contracts.R
  modified:
    - srcjs/index.test.js

key-decisions:
  - "Kept production browser handlers unchanged because existing `srcjs/index.js` behavior already satisfied the manifest once covered by tests."
  - "Made `inst/protocol/browser-payload-contracts.json` the shared source of truth for R producer and JS consumer/cache contract assertions."

patterns-established:
  - "Payload field changes should update the manifest and paired R/JS tests in the same change."
  - "Browser messages should expose only resource basenames and never producer-local fields such as `filePath`, `output_file`, or `matrix_dir`."

requirements-completed:
  - XFER-05

duration: 13 min
completed: 2026-06-20
---

# Phase 01 Plan 02: Browser Payload Contract Manifest Summary

**Shared browser payload manifest with R producer and JS consumer/cache tests for metadata, reductions, PCA, expression, and metadata patches**

## Performance

- **Duration:** 13 min
- **Started:** 2026-06-20T13:21:22Z
- **Completed:** 2026-06-20T13:34:33Z
- **Tasks:** 2 completed
- **Files modified:** 3

## Accomplishments

- Added `inst/protocol/browser-payload-contracts.json` covering all eight XFER-05 browser message contracts: `meta_ready`, `meta_patch_ready`, `reduction_ready`, `reductions_ready`, `pca_ready`, `expr_ready`, `reduction_cached`, and `expr_cached`.
- Added manifest-driven R contract tests that create a small Seurat/BPCells-backed object, write Arrow IPC payloads, and assert required fields, IPC columns, basename-only file references, and no local producer path fields.
- Extended `srcjs/index.test.js` to register/assert all manifest message handlers and verify metadata, metadata patch, PCA, reduction cache, and expression cache behavior without network access.
- Confirmed existing production `srcjs/index.js` handler and cache behavior already satisfied the new manifest; no bundle rebuild was required because production JS did not change.

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Create browser payload manifest and R producer contract tests** - `c3ac5ee` (test)
2. **Task 1 GREEN: Add browser payload contract manifest** - `e57e4c9` (feat)
3. **Task 2 RED: Add JS consumer and cache-version contract tests** - `6615744` (test)
4. **Task 2 GREEN: Align JS payload mocks with production API** - `8c0fd60` (test)

**Plan metadata:** see final completion output for docs commit hash.

## Files Created/Modified

- `inst/protocol/browser-payload-contracts.json` - Canonical browser payload manifest with message fields, IPC columns, cache-version rules, cache miss inputs, and basename-only path policy.
- `tests/testthat/test-browser-payload-contracts.R` - Manifest-driven R producer tests for payload fields, Arrow IPC schemas, cached notification payloads, and local path exposure rejection.
- `srcjs/index.test.js` - JS consumer/cache tests for all manifest message handlers, resource URL shape, metadata patch notifications, PCA stdev handling, versioned cache keys, cache clearing, stale-version ignores, and cache miss signals.

## Decisions Made

- Kept production browser code unchanged because `srcjs/index.js` already registered the expected `Shiny.addCustomMessageHandler()` handlers and used the required cache key delimiter and version invalidation semantics.
- Used `inst/protocol/browser-payload-contracts.json` as the single source of truth for message names and field/cache contracts rather than duplicating the full protocol in tests.
- Treated test mock alignment as the GREEN step for Task 2 because production `reglScatterCanvas` already exposes the required methods; the failing tests exposed missing mock API, not missing production behavior.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Task 2 RED initially failed because the mocked `reglScatterCanvas` lacked production methods (`updateCellMetaData()`, `updateCellMetaDataPatch()`, `updateExpressionData()`, and `updatePcaStdev()`). The mock was updated to match production API, and targeted Vitest then passed.

## TDD Gate Compliance

- Task 1 produced RED (`c3ac5ee`) and GREEN (`e57e4c9`) commits.
- Task 2 produced RED (`6615744`) and GREEN (`8c0fd60`) commits.
- No refactor commits were needed.

## Known Stubs

None. Empty/null values found in `srcjs/index.test.js` are test fixture resets/defaults, not UI-facing stubs.

## Authentication Gates

None.

## Threat Flags

None. The new manifest and tests document and verify existing browser transfer trust boundaries; no new endpoint, auth path, file access pattern, or schema trust boundary was introduced.

## Verification

- `pixi run Rscript -e "devtools::test(filter = 'browser-payload-contracts|analysis-backend-contract')"` — PASS (120 passing tests).
- `pixi run npm test -- srcjs/index.test.js srcjs/modules/arrowReader.test.js srcjs/modules/scatter/scatterModel.test.js` — PASS (41 passing tests).
- `bash -lc 'if ! git diff --quiet -- srcjs/index.js; then pixi run build-js && git diff --name-only -- inst/app/www/index.js inst/app/www/index.js.map; fi'` — PASS/no-op because `srcjs/index.js` was unchanged.
- Acceptance checks confirmed all eight manifest message names, manifest-backed R tests, forbidden path field assertions, versioned reduction/expression cache keys, stale-version ignores, and cache-miss signal assertions.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for `01-03-PLAN.md` to document the runtime contract backbone and enforce documentation coverage for XFER-05/DOCS-01.

## Self-Check: PASSED

- Found `inst/protocol/browser-payload-contracts.json`.
- Found `tests/testthat/test-browser-payload-contracts.R`.
- Found `srcjs/index.test.js`.
- Found task commit `c3ac5ee`.
- Found task commit `e57e4c9`.
- Found task commit `6615744`.
- Found task commit `8c0fd60`.

---
*Phase: 01-runtime-contract-backbone*
*Completed: 2026-06-20*
