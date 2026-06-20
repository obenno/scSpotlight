---
phase: 01-runtime-contract-backbone
verified: 2026-06-20T14:14:19Z
status: passed
score: 9/9 must-haves verified
overrides_applied: 0
---

# Phase 01: Runtime Contract Backbone Verification Report

**Phase Goal:** Developers can rely on stable Analysis Mode backend seams and explicit browser-contract rules before user-facing workflows build on them.
**Verified:** 2026-06-20T14:14:19Z
**Status:** passed
**Re-verification:** No — initial verification; no prior `*-VERIFICATION.md` existed in the phase directory.

## User Flow Coverage

Phase 1 is marked `Mode: mvp` in `ROADMAP.md`. The ROADMAP goal is written as developer-facing shorthand; the phase plans restate it as the user story: **As a developer, I want to rely on stable Analysis Mode backend seams and explicit browser-contract rules, so that user-facing workflows can build on them safely.** Verification uses that outcome clause and checks that the backing contracts actually exist, are wired, and pass targeted tests.

| Step | Expected | Evidence in Codebase | Status |
|---|---|---|---|
| Inspect Analysis backend seams | Developer can find/use helper functions for metadata, features, reductions, PCA stdev, and expression | `R/fct_bpcells_backend.R:1039-1255` implements `get_backend_metadata`, `get_backend_features`, `get_backend_reduction_names`, `get_backend_reduction`, `get_backend_expr`, and `get_backend_pca_stdev`; `tests/testthat/test-analysis-backend-contract.R:53-95` exercises them on a Seurat object | ✓ VERIFIED |
| Inspect Analysis transfer producers | Developer can use Arrow IPC producer adapters without a mirrored Analysis DuckDB runtime | `R/fct_backend_transfer_adapter.R:5-242` implements metadata, reduction, PCA, and expression transfers; `tests/testthat/test-analysis-backend-contract.R:97-230` verifies IPC schemas and BPCells path-based expression jobs | ✓ VERIFIED |
| Inspect browser payload contracts | Developer can inspect one manifest and paired R/JS tests before changing payloads | `inst/protocol/browser-payload-contracts.json:1-100` enumerates all eight messages, fields, IPC columns, cache-version rules, and path policy; `tests/testthat/test-browser-payload-contracts.R:137-319` and `srcjs/index.test.js:616-868` verify producer/consumer behavior | ✓ VERIFIED |
| Inspect protocol docs | Developer can find backend seam rules, payload checklist, and source boundaries in docs | `DEVELOPMENT.md:226-280` contains `## Runtime Contract Backbone`; `tests/testthat/test-development-contract-docs.R:30-56` guards headings, manifest/test links, message names, and required phrases | ✓ VERIFIED |
| Outcome | User-facing workflows can build on stable backend and browser-contract rules safely | Targeted R tests passed 123 tests; targeted JS tests passed 33 tests; contracts prohibit local path exposure and mirrored Analysis DuckDB runtime | ✓ VERIFIED |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Developer can access Analysis Mode metadata through `get_backend_metadata()` and Arrow metadata transfer helpers without Analysis DuckDB. | ✓ VERIFIED | `get_backend_metadata()` reads Seurat `object[[]]` for Analysis Mode (`R/fct_bpcells_backend.R:1051-1061`). Metadata transfer uses `backend = "data_frame"` with `clean_meta_frame(get_backend_metadata(...))` and no DuckDB call in Analysis branch (`R/fct_backend_transfer_adapter.R:5-47`). Contract test verifies metadata rows/values and zero-based `cells` IPC (`tests/testthat/test-analysis-backend-contract.R:74-77`, `151-163`). |
| 2 | Developer can access Analysis Mode reductions and PCA summaries through `get_backend_reduction*()` / `get_backend_pca_stdev()` and Arrow reduction/PCA producers. | ✓ VERIFIED | `get_backend_reduction_names()` uses Seurat reductions and `get_backend_reduction()` uses `Seurat::Embeddings()` (`R/fct_bpcells_backend.R:1163-1189`); `get_backend_pca_stdev()` reads Seurat PCA stdev (`R/fct_bpcells_backend.R:1245-1255`). Tests verify UMAP X/Y, PCA stdev IPC, and null stdev when PCA absent (`tests/testthat/test-analysis-backend-contract.R:83-90`, `165-198`). |
| 3 | Developer can access Analysis Mode features and expression through Seurat/BPCells helper paths and queued path-based expression transfer jobs. | ✓ VERIFIED | `get_backend_features()` and `get_backend_expr()` use Seurat layer access (`R/fct_bpcells_backend.R:1039-1048`, `1192-1215`). `prepare_backend_expression_transfer()` returns a BPCells `matrix_dir` job plus basename-only browser payload, and `write_backend_expression_transfer()` writes from the path (`R/fct_backend_transfer_adapter.R:149-242`). `mod_InputFeature.R:232-233` writes `job$transfer` inside `future_promise`, while `mod_InputFeature.R:297-305` prepares the transfer before queueing. Tests assert no `object`, `seuratObj`, `data`, `query_plan`, or `duckdb` fields in the Analysis expression job (`tests/testthat/test-analysis-backend-contract.R:200-229`). |
| 4 | Developer can inspect one explicit manifest for metadata, reduction, expression, PCA, and patch browser message payloads. | ✓ VERIFIED | `inst/protocol/browser-payload-contracts.json:4-55` defines `meta_ready`, `meta_patch_ready`, `reduction_ready`, `reductions_ready`, `pca_ready`, `expr_ready`, `reduction_cached`, and `expr_cached`; test verifies manifest keys and all eight message names (`tests/testthat/test-browser-payload-contracts.R:137-165`). |
| 5 | Developer can verify R producers satisfy the manifest through testthat before changing payload fields or IPC columns. | ✓ VERIFIED | `tests/testthat/test-browser-payload-contracts.R:20-24` reads the manifest with `jsonlite`; `tests/testthat/test-browser-payload-contracts.R:167-319` creates producer payloads, reads IPC streams, verifies required columns, cache notifications, and no forbidden local path fields. |
| 6 | Developer can verify JS consumers and cache-version behavior satisfy the same message contracts through Vitest. | ✓ VERIFIED | `srcjs/index.test.js:6` imports the manifest; `srcjs/index.test.js:616-868` verifies handler registration, metadata/patch/PCA processing, reduction/expression cache key shapes, newer-version cache clearing, stale-version ignores, and cache-miss signals. Production handlers are present in `srcjs/index.js:574-1219`. |
| 7 | Developer can find the Analysis Mode backend seam rules in `DEVELOPMENT.md`. | ✓ VERIFIED | `DEVELOPMENT.md:230-241` names the helper seams and states Analysis Mode must not reintroduce a mirrored DuckDB runtime. Docs guard verifies the section and phrase (`tests/testthat/test-development-contract-docs.R:34-55`). |
| 8 | Developer can find the browser payload change checklist in `DEVELOPMENT.md`. | ✓ VERIFIED | `DEVELOPMENT.md:243-273` links the manifest, R producer test, JS consumer test, all message names, cache-version behavior, and targeted commands. |
| 9 | Developer can verify documentation stays aligned with payload manifest and tests. | ✓ VERIFIED | `tests/testthat/test-development-contract-docs.R:15-20` reads manifest message names and `tests/testthat/test-development-contract-docs.R:30-56` verifies `DEVELOPMENT.md` contains required headings, files, messages, and phrases. |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `tests/testthat/test-analysis-backend-contract.R` | Analysis Mode backend contract tests for metadata, reductions, features, PCA summaries, expression, transfer adapters, and source guards | ✓ VERIFIED | Exists and substantive (275 lines). Covers helper access, Arrow IPC schemas, BPCells path-based expression transfer, and source guards (`lines 53-275`). |
| `R/fct_bpcells_backend.R` | Seurat/BPCells helper seam implementation | ✓ VERIFIED | Contains Analysis helpers for metadata, features, reductions, expression, and PCA stdev (`lines 1039-1255`). |
| `R/fct_backend_transfer_adapter.R` | Arrow IPC producer adapter for metadata, reductions, PCA summaries, and expression | ✓ VERIFIED | Contains producer functions and path-based expression branch (`lines 5-242`); no DuckDB connection/query calls in this file. |
| `R/mod_InputFeature.R` | Queued expression transfer wiring | ✓ VERIFIED | Prepares expression transfer outside promise (`lines 297-305`) and writes only `job$transfer` inside promise (`lines 232-233`). |
| `inst/protocol/browser-payload-contracts.json` | Machine-readable browser payload contract manifest | ✓ VERIFIED | Exists and valid JSON; defines all eight messages, IPC columns, cache versions, and basename-only path policy (`lines 1-100`). |
| `tests/testthat/test-browser-payload-contracts.R` | R producer contract tests tied to manifest | ✓ VERIFIED | Exists and substantive (319 lines); manifest-driven tests verify payload fields, IPC schemas, cache notifications, and no local path exposure. |
| `srcjs/index.test.js` | JS consumer/cache contract tests tied to manifest | ✓ VERIFIED | Imports manifest and covers all eight handlers plus versioned cache behavior (`lines 6`, `616-868`). |
| `srcjs/index.js` | Production JS custom message handlers and cache logic | ✓ VERIFIED | Registers all manifest message handlers and uses versioned reduction/expression cache keys (`lines 574-1219`, `145-219`). |
| `tests/testthat/test-development-contract-docs.R` | Documentation guard test | ✓ VERIFIED | Reads manifest and verifies `DEVELOPMENT.md` headings, file links, message names, and required phrases (`lines 15-56`). |
| `DEVELOPMENT.md` | Runtime Contract Backbone documentation | ✓ VERIFIED | Contains `## Runtime Contract Backbone`, backend seam rules, browser payload contracts, checklist, and source-of-truth boundaries (`lines 226-280`). |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `R/mod_UpdateMetaData.R` | `R/fct_backend_transfer_adapter.R` | `prepare_backend_metadata_transfer()` / `write_backend_metadata_transfer()` | ✓ WIRED | Full metadata path prepares transfer then writes in future and sends `meta_ready` (`lines 76-93`); patch path sends `meta_patch_ready` (`lines 152-170`). |
| `R/mod_UpdateReduction.R` | `R/fct_backend_transfer_adapter.R` | `write_backend_pca_stdev_transfer()`, `prepare_backend_reduction_transfer()`, `write_backend_reduction_transfer()` | ✓ WIRED | PCA sends `pca_ready` (`lines 68-84`); single reductions send `reduction_ready` (`lines 133-153`); batched reductions send `reductions_ready` (`lines 201-237`); cached reductions send `reduction_cached` (`lines 270-284`). |
| `R/mod_InputFeature.R` | `R/fct_backend_transfer_adapter.R` | `prepare_backend_expression_transfer()` before queued future; `write_backend_expression_transfer()` inside future | ✓ WIRED | Transfer is prepared from current object once (`lines 297-305`), queued by key (`lines 329-334`), and the promise writes only the transfer job (`lines 232-233`). |
| `tests/testthat/test-browser-payload-contracts.R` | `inst/protocol/browser-payload-contracts.json` | `jsonlite::fromJSON()` | ✓ WIRED | Test reads the manifest from the real path rather than duplicating it inline (`lines 1-24`). |
| `srcjs/index.test.js` | `inst/protocol/browser-payload-contracts.json` | JSON import and handler assertions | ✓ WIRED | Test imports the manifest (`line 6`) and asserts handler registration for all manifest messages (`lines 616-620`). |
| `srcjs/index.js` | browser payload manifest intent | `Shiny.addCustomMessageHandler()` handlers and cache keys | ✓ WIRED | Production handlers for all eight manifest messages exist (`lines 574-1219`) and use `::` cache keys (`lines 145-219`). |
| `DEVELOPMENT.md` | manifest + paired tests | documented links and payload checklist | ✓ WIRED | Docs name the manifest and paired test files (`line 245`) and require updates across manifest/R/JS/docs/tests (`lines 260-273`). |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| Metadata transfer | `meta_ready` / `metaFile` / `metaVersion` | `get_backend_metadata(object)` → `clean_meta_frame()` → `write_ipc_stream(as_arrow_table(...))` | Yes — test reads IPC and verifies cleaned metadata plus zero-based `cells` (`test-analysis-backend-contract.R:151-163`) | ✓ FLOWING |
| Metadata patch transfer | `meta_patch_ready` / `cols` | `prepare_backend_metadata_transfer(..., cols = patch_cols)` in `mod_UpdateMetaData.R` | Yes — patch IPC contains `cells` plus only changed columns (`test-browser-payload-contracts.R:234-246`) | ✓ FLOWING |
| Reduction transfer | `reduction_ready` / `reductionFile` / `reductionName` | `get_backend_reduction()` from Seurat embeddings → Arrow `X`/`Y` | Yes — test reads IPC with exactly `X` and `Y` (`test-analysis-backend-contract.R:165-177`) | ✓ FLOWING |
| PCA summary transfer | `pca_ready` / `stdevFile` | `get_backend_pca_stdev()` from Seurat PCA reduction → Arrow `stdev` | Yes — test reads IPC `stdev` and null missing-PCA payload (`test-analysis-backend-contract.R:179-198`) | ✓ FLOWING |
| Expression transfer | `expr_ready` / `exprFile` / `geneName` | BPCells `matrix_dir` path → `extract_bpcells_expr_to_ipc()` → Arrow `expr` | Yes — job is path-based and test reads requested feature expression (`test-analysis-backend-contract.R:200-229`) | ✓ FLOWING |
| JS consumer/cache | decoded typed arrays and scatter model updates | `/data/{meta,reduction,expr}/<basename>` fetch → Arrow decode → `update*` methods | Yes — Vitest verifies metadata, patches, PCA Float32Array, reduction cache, expression cache, stale-version ignores, and cache misses (`srcjs/index.test.js:623-868`) | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| R contract tests for BACK-01, XFER-05, DOCS-01 | `pixi run Rscript -e "devtools::test(filter = 'analysis-backend-contract|browser-payload-contracts|development-contract-docs')"` | PASS: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 123 ]` | ✓ PASS |
| JS consumer/cache tests requested by verification context | `pixi run npm test -- --run srcjs/index.test.js srcjs/modules/scatter/scatterModel.test.js` | PASS: 2 files passed, 33 tests passed | ✓ PASS |
| Manifest parse + key artifact existence | `pixi run Rscript -e "jsonlite::fromJSON('inst/protocol/browser-payload-contracts.json'); stopifnot(file.exists(...)); cat('ok\n')"` | PASS: manifest parsed and printed `ok` | ✓ PASS |

### Probe Execution

| Probe | Command | Result | Status |
|---|---|---|---|
| Not applicable | No probe scripts or probe declarations found in Phase 01 plans/summaries | Phase is contract tests/docs, not probe-based migration/tooling | SKIPPED |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| BACK-01 | `01-01-PLAN.md` | Developer can access Analysis Mode metadata, reductions, features, PCA summaries, and expression through Seurat/BPCells backend helpers without reintroducing mirrored DuckDB runtime. | ✓ SATISFIED | Helper implementations in `R/fct_bpcells_backend.R`; transfer adapters in `R/fct_backend_transfer_adapter.R`; source guard tests; targeted R tests passed 123-test combined run. |
| XFER-05 | `01-02-PLAN.md`, `01-03-PLAN.md` | Developer can change metadata, reduction, expression, PCA, or patch payloads only with paired R producer tests, JS consumer tests, cache-version behavior, and docs. | ✓ SATISFIED | Manifest exists; R producer tests read it; JS tests import it and verify all eight handlers/cache behavior; docs checklist names required paired updates. |
| DOCS-01 | `01-03-PLAN.md` | Developer can update `DEVELOPMENT.md` whenever behavior contracts, validations, or architecture decisions change. | ✓ SATISFIED | `DEVELOPMENT.md:226-280` documents runtime contracts; `test-development-contract-docs.R` guards documentation and passed in targeted R run. |

No Phase 1 requirement IDs are orphaned: `.planning/REQUIREMENTS.md` maps BACK-01, XFER-05, and DOCS-01 to Phase 1, and all three appear in Phase 01 plan frontmatter.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| Phase contract artifacts | — | `TBD` / `FIXME` / `XXX` debt markers | — | None found in Phase 01 created/verified contract artifacts. |
| `srcjs/index.test.js` | 54, 71 | `return []` | ℹ️ Info | Test/mock helper defaults, not runtime stubs and not user-visible output. |
| `srcjs/index.js` | 602, 1076, 1111, 1147, 1194 | `console.log` diagnostics | ℹ️ Info | Diagnostic logs inside substantive existing handlers; not console-log-only implementations and not blockers for the contract goal. |

### Performance and Security Regression Check

| Constraint | Evidence | Status |
|---|---|---|
| No mirrored DuckDB runtime for Analysis Mode | `R/fct_backend_transfer_adapter.R` contains no `DBI::dbConnect`, `duckdb::duckdb`, or `query_duck`; tests assert adapter/module source guards (`test-analysis-backend-contract.R:232-275`). DuckDB use remains in Explore/LLM-specific files, outside this Analysis transfer adapter seam. | ✓ VERIFIED |
| Analysis Mode source of truth remains Seurat/BPCells | Helper implementations read Seurat metadata/reductions/layers and BPCells matrix paths (`R/fct_bpcells_backend.R:1039-1294`). | ✓ VERIFIED |
| No local path exposure in browser payloads | Manifest forbids absolute paths and `filePath`/`output_file`/`matrix_dir` fields (`browser-payload-contracts.json:94-99`); R test rejects path-like browser payloads (`test-browser-payload-contracts.R:87-135`, `308-318`). | ✓ VERIFIED |
| Arrow IPC / TypedArray-oriented contracts | Manifest IPC columns define `cells`, `X`/`Y`, `stdev`, and `expr`; JS handlers decode Arrow and use `Float32Array` for PCA/reduction/expression (`srcjs/index.js:280-291`, `728-741`, `1131-1146`). | ✓ VERIFIED |
| No eager large expression materialization in queued futures | Expression future writes from `job$transfer` only; job is `matrix_dir` path-based and excludes live Seurat/BPCells object fields (`mod_InputFeature.R:232-233`, `297-305`; `test-analysis-backend-contract.R:200-229`). | ✓ VERIFIED |

### Human Verification Required

None. This phase delivers developer-facing runtime contracts, tests, and documentation; no visual flow, external service integration, or subjective UX behavior was introduced.

### Gaps Summary

No blocking gaps found. Phase 01 achieves its Runtime Contract Backbone goal: Analysis backend seams are implemented and contract-tested, browser payload changes are guarded by a manifest plus paired R/JS tests, and `DEVELOPMENT.md` documents the contract with a docs guard test. User-facing large-scale load/render behavior remains later roadmap scope (Phase 2) and is not a Phase 1 blocker.

---

_Verified: 2026-06-20T14:14:19Z_
_Verifier: the agent (gsd-verifier)_
