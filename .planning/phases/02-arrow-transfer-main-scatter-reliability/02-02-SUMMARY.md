---
phase: 02-arrow-transfer-main-scatter-reliability
plan: "02"
subsystem: data-transfer
tags: [arrow-ipc, bpcells, duckdb, explore-mode, expression-transfer]

# Dependency graph
requires:
  - phase: 02-arrow-transfer-main-scatter-reliability
    provides: Plan 01 `transfer_error` contract, stale metadata/reduction guards, and Phase 02 transfer docs section
provides:
  - Queued one-active expression transfer contract coverage
  - BPCells path-based chunked Arrow `expr` IPC source guards
  - Explore DuckDB/query-plan expression transfer coverage
  - Sanitized expression `transfer_error` producer path
  - DEVELOPMENT.md expression transfer contract documentation
affects: [phase-02, expression-transfer, bpcells, explore-mode, browser-payload-contracts]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - One-active expression transfer queue shared by BPCells and Explore backends
    - Path/query-plan-only expression jobs with basename-only browser payloads
    - Chunked Arrow IPC `expr` writers for single-feature expression vectors

key-files:
  created:
    - .planning/phases/02-arrow-transfer-main-scatter-reliability/02-02-SUMMARY.md
  modified:
    - R/mod_InputFeature.R
    - tests/testthat/test-bpcells-expression-transfer.R
    - tests/testthat/test-explore-bundle.R
    - tests/testthat/test-browser-payload-contracts.R
    - tests/testthat/test-development-contract-docs.R
    - DEVELOPMENT.md

key-decisions:
  - "Reuse Plan 01's sanitized `transfer_error` path for expression IPC write failures."
  - "Keep expression jobs path/query-plan based and single-feature; browser payloads expose only basename/version/scoped feature fields."
  - "Leave browser stale-expression application and first-selected-gene rendering behavior to dependent Plan 03."

patterns-established:
  - "Expression queue source guards assert `future_promise()` bodies call only `write_backend_expression_transfer(job$transfer)`."
  - "Explore expression transfer jobs carry `block_path`, `feature_idx`, `cell_count`, `output_file`, and payload only."
  - "Docs guards pin queued BPCells and DuckDB/Explore expression transfer constraints."

requirements-completed: [XFER-03]

# Metrics
duration: 17min
completed: 2026-06-22
---

# Phase 02 Plan 02: Expression Backend Transfer Contracts Summary

**Queued BPCells and DuckDB/Explore expression transfers with Arrow `expr` IPC and basename-only browser payloads**

## Performance

- **Duration:** 17 min
- **Started:** 2026-06-22T00:00:00Z
- **Completed:** 2026-06-22T00:17:00Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- Added source and producer tests proving expression transfers remain one-active, duplicate-key suppressed, and prepared outside the promise body.
- Strengthened BPCells and Explore expression IPC coverage so both backends write single-feature Arrow `expr` vectors without dense/browser JSON payloads.
- Added expression IPC write failures to the sanitized `transfer_error` producer path.
- Documented the Phase 02 expression backend transfer contract in `DEVELOPMENT.md` and guarded it with docs tests.

## Task Commits

Plan changes were committed together for this slice so the committed state remains test-passing:

1. **Task 1: Add queued expression and Explore transfer contract tests** - included in Wave 2 implementation commit.
2. **Task 2: Implement queued BPCells and DuckDB/Explore expression contracts** - included in Wave 2 implementation commit.
3. **Task 3: Document expression backend transfer contracts** - included in Wave 2 implementation commit.

## Files Created/Modified

- `R/mod_InputFeature.R` - Sends sanitized expression `transfer_error` payloads when queued IPC writes fail.
- `tests/testthat/test-bpcells-expression-transfer.R` - Guards BPCells path-based chunked Float32 Arrow `expr` IPC and queue source semantics.
- `tests/testthat/test-explore-bundle.R` - Guards Explore expression query-plan shape, DuckDB resource cleanup, and single-feature Arrow IPC output.
- `tests/testthat/test-browser-payload-contracts.R` - Covers expression transfer errors and basename-only `expr_ready` payloads.
- `tests/testthat/test-development-contract-docs.R` - Guards Phase 02 expression transfer documentation.
- `DEVELOPMENT.md` - Documents queued/path-based BPCells and DuckDB/Explore expression transfer rules.

## Decisions Made

- Kept the existing backend transfer implementation because it already used BPCells paths and Explore query plans; added missing guards and failure notification instead of rewriting working code.
- Scoped expression failure payloads to `payloadType = "expression"`, `geneName`, `assay`, and `version = exprVersion` to avoid path or exception leakage.
- Deferred browser stale-expression application and first-selected-gene UI behavior to Plan 03 as specified.

## Deviations from Plan

None - plan executed as written. The target suite already passed before edits, so this slice focused on strengthening missing contract guards and documentation.

## Issues Encountered

- `DEVELOPMENT.md` had unrelated pre-existing LLM hunks in the dirty worktree. Only the expression transfer hunk is plan-scoped and should be staged for this plan.
- The docs guard initially failed on line-wrapped fixed strings; documentation wording was adjusted without changing the contract.

## Verification

- `pixi run Rscript -e "devtools::test(filter = 'development-contract-docs|bpcells-expression-transfer|explore-bundle|browser-payload-contracts|analysis-backend-contract')"` (baseline before edits; pass, 228 R tests)
- `pixi run Rscript -e "devtools::test(filter = 'development-contract-docs|bpcells-expression-transfer|explore-bundle|browser-payload-contracts|analysis-backend-contract')"` (after edits; pass, 272 R tests)

## Known Stubs

None.

## Threat Flags

None. Expression transfer failure payloads reuse the sanitized browser contract and tests reject local paths, dense vectors, live objects, DBI connections, and all-block transfer state.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 03 can consume the stable expression backend contract for browser stale-expression handling, first-selected-gene emphasis, sparkline synchronization, and metadata patch state safety.
- No JS bundle rebuild was required in this slice because the browser-side expression consumer is intentionally handled in the dependent plan.

## Self-Check: PASSED

- Verified all modified Plan 02 source/test/docs files exist on disk.
- Verified targeted Wave 2 R tests pass after implementation.

---
*Phase: 02-arrow-transfer-main-scatter-reliability*
*Completed: 2026-06-22*
