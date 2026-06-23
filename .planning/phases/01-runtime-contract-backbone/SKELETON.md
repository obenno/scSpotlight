# Walking Skeleton — scSpotlight Runtime Contract Backbone

**Phase:** 1
**Generated:** 2026-06-16

## Capability Proven End-to-End

A developer can run contract tests that exercise an Analysis Mode Seurat/BPCells helper path through R Arrow IPC producers, browser message consumers, cache-version behavior, and documented protocol rules.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Framework | R/Shiny golem package with Vite-bundled ES modules | Existing brownfield stack; phase hardens contracts without changing app framework. |
| Analysis data layer | Seurat v5 object as source of truth with BPCells-backed assay layers | Satisfies 1M+ cell low-memory constraints and avoids duplicated runtime state. |
| Explore data layer | DuckDB/Parquet only for validated Explore bundles | Keeps DuckDB out of Analysis Mode while preserving read-only Explore query plans. |
| Browser transport | Versioned Arrow IPC files plus `session$sendCustomMessage()` notifications | Maintains compact typed-array transfer for metadata, reductions, expression, PCA summaries, and patches. |
| Auth | No auth seam in this local Shiny analysis runtime | This phase changes developer/runtime contracts, not user authentication. |
| Deployment/run target | Pixi local commands and existing Docker port 8081 | Existing repo run commands remain the full-stack exercise path. |
| Directory layout | `R/fct_*.R` helpers, `R/mod_*.R` Shiny modules, `srcjs/modules/`, `tests/testthat/`, and `srcjs/**/*.test.js` | Matches current package organization and keeps R producer / JS consumer tests near their code. |
| Contract source | `inst/protocol/browser-payload-contracts.json` plus `DEVELOPMENT.md` | Machine-readable contract guardrails are paired with human-readable protocol notes. |

## Stack Touched in Phase 1

- [ ] R backend helper seams for Analysis Mode metadata, reductions, features, PCA summaries, and expression.
- [ ] R Arrow IPC producer tests for metadata, metadata patches, reductions, PCA summaries, and expression.
- [ ] JavaScript consumer/cache tests for `meta_ready`, `meta_patch_ready`, `reduction_ready`, `reductions_ready`, `pca_ready`, `expr_ready`, `reduction_cached`, and `expr_cached`.
- [ ] Documentation contract in `DEVELOPMENT.md` explaining how payload changes are made safely.
- [ ] Local full-stack run remains `pixi run run-app`; targeted verification uses `pixi run Rscript -e "devtools::test(...)"` and `pixi run npm test -- ...`.

## Out of Scope (Deferred to Later Slices)

- New user-facing scatter behavior, lasso behavior, floating-panel behavior, and visual redesign.
- Reintroducing a mirrored DuckDB assay/query runtime for Analysis Mode.
- Explore Mode export/import expansion beyond documenting the boundary between Analysis and Explore helpers.
- Optional assistant UI mounting, provider expansion, MCP tooling, or credential workflows.
- Large-dataset profiling runs for 100K, 500K, and 1M+ cells; this phase creates contract guardrails that later slices use during profiling.

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this runtime-contract skeleton without renegotiating these decisions:

- Phase 2: Arrow transfer and main deck.gl scatter reliability.
- Phase 3: Analysis Mode processing and mutation safety.
- Phase 4: Portable artifacts and read-only Explore Mode end-to-end loading.
- Phase 5: Floating analysis panels and DEG workflows.
- Phase 6: Optional assistant safety and release documentation alignment.
