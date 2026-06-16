# Technology Stack

**Project:** scSpotlight  
**Domain:** single-cell RNA-seq analysis and visualization at million-cell scale  
**Researched:** 2026-06-16  
**Overall confidence:** HIGH

Use the repo's Pixi-locked R/Shiny + Seurat v5 + BPCells backend, Arrow IPC for browser transport, deck.gl for the main scatter, and DuckDB only for read-only Explore bundles. The stack is already mostly decided by the codebase; the main job is to keep the large-data contract from drifting.

## Recommended / Actual Stack

### R / backend

| Layer | Actual in repo | Recommended standard | Why it fits large data | Confidence / risk |
|---|---|---|---|---|
| Runtime R | DESCRIPTION says R >= 4.1.0; Pixi locks `r-base >=4.4,<4.6` | Standardize on R 4.4–4.5 for dev, CI, and runtime | matches the real build floor and modern Arrow/BPCells toolchains | HIGH; risk: DESCRIPTION minimum lags the true runtime floor |
| App framework | Shiny >= 1.8.1 + golem >= 0.4.1 | Keep Shiny + golem | module boundaries, server-side state, stable reactivity | HIGH |
| Analysis object model | Seurat v5 / SeuratObject v5 | Keep Seurat as the source of truth | metadata, reductions, and assay layers stay together; no duplicate state | HIGH |
| On-disk assay storage | BPCells >= 0.3.1 | Keep BPCells as required backend | counts/data layers stay on disk and avoid full-matrix RAM blowups | HIGH; risk: HDF5/C++ toolchain portability |
| Async work | `future` + `promises` + `progressr`; Shiny `ExtendedTask` pattern | Use `future_promise()` for non-blocking writes and keep BPCells expression work queued in-process | keeps UI responsive without shipping live BPCells objects into worker processes | HIGH |
| Binary transport | Arrow R + Arrow IPC payload files | Use Arrow IPC, not JSON tables | typed binary transport, compact categorical encoding, browser decodes to typed arrays | HIGH |
| Read-only Explore mode | DuckDB + Parquet bundles | Use DuckDB only to scan immutable Explore bundles | pushdown reads, versioned schema, no mirrored assay store | HIGH |

### Frontend / browser

| Layer | Actual in repo | Recommended standard | Why it fits large data | Confidence / risk |
|---|---|---|---|---|
| JS module system | ES modules bundled by Vite | Keep ES modules + Vite library mode | fast dev loop, stable bundle output to `inst/app/www/index.js` | HIGH |
| Main scatter renderer | `@deck.gl/core` + `@deck.gl/layers` 9.x | Keep deck.gl as the only main scatter path | WebGL survives 1M+ points; canvas/SVG do not | HIGH |
| Browser data encoding | `apache-arrow` JS + TypedArrays | Decode Arrow to typed arrays and dictionary-coded categories | avoids repeated strings and keeps payloads compact | HIGH |
| Supporting viz/UI libs | D3 7.x, `bootstrap-icons`, `jquery-sparkline`, `html2canvas` | Use these only for secondary UI/plot widgets | good for helpers, not the primary high-volume render path | HIGH |
| Browser R | `webr` 0.5.8, optional | Keep webR isolated and non-critical | useful for small client-side helpers only; browser RAM/API churn is the risk | MEDIUM |

### Build / test

| Layer | Actual in repo | Recommended standard | Why it fits large data | Confidence / risk |
|---|---|---|---|---|
| Package/environment manager | Pixi | Keep Pixi as the only source-checkout environment manager | one lockfile across R, Node, CI, and Docker | HIGH |
| Node toolchain | Node 20.19–22 | Keep the current Node floor | matches Vite 8 and modern JS tooling without legacy transpilation | HIGH |
| Bundler | Vite 8.x in library mode | Keep Vite library mode with externalized Shiny/jQuery/waiter | predictable UMD bundle, fast rebuilds, simpler deploy artifact | HIGH |
| Test runner | Vitest 4.x + jsdom 24.x | Keep jsdom-based unit tests for JS modules | fast regression coverage for scatter state, layout, and IPC code | HIGH |

### Deployment / runtime

| Layer | Actual in repo | Recommended standard | Why it fits large data | Confidence / risk |
|---|---|---|---|---|
| Container build | Pixi builder stage | Build in Pixi, ship a slim runtime image | repeatable builds and smaller production image | HIGH |
| Runtime image | Ubuntu 24.04 + activated `prod` env | Run `Rscript` directly in the final container | no Pixi required at runtime; simpler ops surface | HIGH |
| Runtime port | 8081 | Keep the current app port | matches existing container entrypoint and docs | HIGH |
| System deps | HDF5, `pkg-config`, C++ compiler, `zlib`, `xz` | Keep these available in build/dev images | BPCells, rhdf5, and Arrow need modern native toolchains | HIGH; risk: platform-specific binary availability |

## What Not to Use

| Anti-stack choice | Why to avoid | Use instead |
|---|---|---|
| `renv` | repo has standardized on Pixi; a second environment manager adds drift | Pixi lockfiles + tasks |
| SVG/canvas for the main scatter | will not hold up for 1M+ cells | deck.gl WebGL scatter |
| Mirrored DuckDB assay/query store in Analysis Mode | duplicates Seurat state and burns memory/sync time | Seurat + BPCells only |
| Passing live Seurat/BPCells objects into futures | serialization and peak-memory risk | path/query-plan tasks + `future_promise()` |
| JSON tables for cell-level payloads | too large and string-heavy | Arrow IPC + typed arrays |
| `regl-scatterplot` as the primary render stack | the README wording is stale; the active JS path is deck.gl-based | keep the deck.gl renderer |

## Confidence / Risk Notes

- **Core backend:** HIGH. Repo docs and active code all agree on Seurat v5 + BPCells + Arrow IPC.
- **Frontend/build:** HIGH. `package.json`, `vite.config.js`, and the JS source all point to deck.gl + Vite + Vitest.
- **Explore Mode:** HIGH. `DEVELOPMENT.md` and the bundle contract make Parquet + DuckDB the read-only path.
- **Optional browser compute:** MEDIUM. webR is useful, but keep it optional because browser RAM and API churn are real constraints.
- **Main risks:** DESCRIPTION minimums lag the real Pixi runtime floor; HDF5/C++ availability varies by platform; Arrow IPC and Explore bundle schemas must stay versioned.

## Sources

### Repo grounding

- `.planning/PROJECT.md`
- `AGENTS.md`
- `DEVELOPMENT.md`
- `DESCRIPTION`
- `pixi.toml`
- `package.json`
- `Dockerfile`
- `vite.config.js`
- `vitest.config.js`
- `R/fct_bpcells_backend.R`
- `R/mod_dataInput.R`
- `R/mod_UpdateMetaData.R`
- `R/mod_UpdateReduction.R`
- `R/mod_InputFeature.R`
- `R/mod_Download.R`
- `R/app_server.R`
- `srcjs/index.js`
- `srcjs/modules/deckScatter.js`
- `srcjs/modules/scatter/scatterModel.js`
- `srcjs/modules/floatingPlots.js`

### Supporting official docs

- Shiny non-blocking operations / ExtendedTask
- Seurat BPCells vignette
- BPCells docs
- Apache Arrow R + JavaScript docs
- DuckDB Parquet docs
- deck.gl ScatterplotLayer docs
- Vite library mode docs
- Pixi docs
- webR docs
- SeuratObject `SaveSeuratRds()` docs

External docs are corroborative only; repo files are the authoritative source of truth for this app's actual stack.
