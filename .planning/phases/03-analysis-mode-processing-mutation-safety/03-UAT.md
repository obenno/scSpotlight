---
status: testing
phase: 03-analysis-mode-processing-mutation-safety
source: [03-VERIFICATION.md]
started: 2026-06-25T18:28:02Z
updated: 2026-06-25T18:28:02Z
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
result: pending

### 2. Representative large-fixture safety check

expected: |
  Repeat load/process/mutate/subset/restore with a representative
  100K+/500K+/1M+ dataset when available. Memory remains bounded, no final dense
  scale.data is retained, and scoped metadata mutations do not force unnecessary
  full-dataset browser transfer.
result: pending

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps

No automated blocker gaps remain. These checks are human UAT items because they
require full Shiny/browser interaction and representative production-scale data.
