---
status: testing
phase: 03-analysis-mode-processing-mutation-safety
source: [03-VERIFICATION.md]
started: 2026-06-25T18:28:02Z
updated: 2026-06-26T00:00:00Z
---

# Phase 03 UAT: Analysis Mode Processing and Mutation Safety

## Current Test

number: 1
name: End-to-end Analysis Mode mutation flow
expected: |
  Start Analysis Mode, load a representative processed BPCells-backed dataset,
  lasso cells, assign metadata, subset to the lasso selection, and restore the
  original object. The UI completes without stale selections, wrong selected
  cells, path leaks, or stuck transfer/loading state; metadata, reduction,
  feature, and plot state refresh after subset and restore.
awaiting: user response

## Tests

### 1. End-to-end Analysis Mode mutation flow

expected: |
  Start Analysis Mode, load a representative processed BPCells-backed dataset,
  lasso cells, assign metadata, subset to the lasso selection, and restore the
  original object. The UI completes without stale selections, wrong selected
  cells, path leaks, or stuck transfer/loading state; metadata, reduction,
  feature, and plot state refresh after subset and restore.
result: passed
evidence: |
  Assisted UAT was run in Analysis Mode at http://127.0.0.1:6830 using a
  synthetic processed Seurat RDS fixture generated at
  /tmp/opencode/scspotlight-uat-small.rds. The user completed the visible
  browser lasso/assign/subset/restore flow. Server log evidence showed the
  live session loaded the uploaded RDS, transferred metadata and reductions,
  selected real cell IDs (Cell5, Cell23, Cell32, Cell36, Cell48, Cell59),
  initialized a new metadata column, then refreshed metadata and reductions
  after subset and restore. No raw temp/session-path UI leak was reported.

### 2. Representative large-fixture safety check

expected: |
  Repeat load/process/mutate/subset/restore with a representative
  100K+/500K+/1M+ dataset when available. Memory remains bounded, no final dense
  scale.data is retained, and scoped metadata mutations do not force unnecessary
  full-dataset browser transfer.
result: pending

## Summary

total: 2
passed: 1
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps

No automated blocker gaps remain. These checks are human UAT items because they
require full Shiny/browser interaction and representative production-scale data.
