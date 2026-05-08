# AGENTS.md - scSpotlight Development Guide

## Project Overview

**scSpotlight** is an R/Shiny application for single-cell RNA-seq analysis and visualization,
built with the [golem](https://thinkr-open.github.io/golem/) framework.

For recent frontend interaction decisions and UI behavior notes, see `DEVELOPMENT.md`.

**CRITICAL CONSTRAINT**: This application must efficiently handle **millions of cells**.
All code contributions must consider performance implications for large datasets (1M+ cells).

### Tech Stack
- **Backend**: R, Shiny, Seurat (v5), BPCells (on-disk assay storage), Arrow IPC (versioned binary transfer)
- **Frontend**: JavaScript (ES6), deck.gl (WebGL), D3.js, webR
- **Build**: [Vite](https://vitejs.dev/) for JavaScript bundling (native ES modules, fast HMR)

---

## Build / Lint / Test Commands

### Environment Management (Pixi)
```bash
pixi install                     # Create/update the locked project environment
pixi run setup                  # Install conda R deps, pak fallbacks, local package, and JS deps
pixi run setup-r                # Install R deps and local package without JS deps
pixi run run-app                # Start app in viewer mode
pixi run run-app-processing     # Start app in processing mode
```

Notes:
- Pixi is the source-checkout environment manager for development, CI, and Docker builds; normal users can install and run the app as an R package without Pixi.
- `DESCRIPTION` remains the source of truth for installed-package runtime dependencies.
- Pixi is the only repo environment manager; the repo does not use `renv`.
- `pixi run setup` is written to work in native Windows shells as well as Unix shells.
- `pixi run setup` currently uses Pixi-managed R packages where available and falls back to `pak` for packages that are not available on every supported platform.

### R Package Commands
```r
devtools::document()            # Generate roxygen2 documentation
devtools::check()               # Run R CMD check
devtools::load_all()            # Load package for development
golem::document_and_reload()    # Quick reload during development (recommended)
```

### JavaScript Commands (Vite)
```bash
pixi run build-js              # Production build (minified, optimized)
pixi run dev                   # Development server with HMR (hot module replacement)
pixi run npm run preview       # Preview production build locally
pixi run test-js               # Run tests (vitest, single run)
pixi run npm run test:watch    # Run tests in watch mode
pixi run npm run test:scatter-model  # Run specific test file
```

### webR VFS Library Rebuild (plotting stack)
Use this when webR package availability changes or when refreshing browser-side R libraries.

```bash
# Build package repo + VFS image in a clean toolchain container
mkdir -p /tmp/scspotlight-webrbuild
docker run --rm -v "/tmp/scspotlight-webrbuild:/output" -w /output ghcr.io/r-wasm/webr:main \
  Rscript -e "install.packages('pak', repos='https://cloud.r-project.org'); \
              pak::pak('r-wasm/rwasm'); \
              library(rwasm); \
              add_pkg(c('ggplot2','scales','scattermore','dplyr','patchwork','cowplot'), dependencies = NA); \
              make_vfs_library(compress = TRUE)"

# Deploy VFS files into app static assets
cp /tmp/scspotlight-webrbuild/vfs/library.data.gz inst/app/www/webr/vfs/library.data.gz
cp /tmp/scspotlight-webrbuild/vfs/library.js.metadata inst/app/www/webr/vfs/library.js.metadata

# Rebuild JS bundle after VFS update
pixi run build-js
```

Notes:
- `dependencies = NA` is the recommended `add_pkg()` setting for hard dependencies.
- If `compress = TRUE`, mount `www/webr/vfs/library.data.gz` and ensure `library.js.metadata` contains `"gzip": true`.
- If compression causes issues, fall back to `make_vfs_library(compress = FALSE)` and mount `www/webr/vfs/library.data`.

### Running the Application
```r
# Viewer mode (read-only, for exploring processed data)
scSpotlight::run_app()

# Processing mode (full analysis capabilities)
scSpotlight::run_app(runningMode = "processing")

# Development mode (from dev/run_dev.R)
golem::document_and_reload()
run_app()
```

### Docker
The Dockerfile uses the [pixi](https://pixi.sh/) base image in the build stage, installs locked `default` and `prod` environments, builds JavaScript assets in `default`, installs the R package into `prod`, and copies only the activated `prod` environment into the runtime image. The final container runs `Rscript` directly and does not require Pixi at runtime.

```bash
docker build -t scspotlight .
docker run -p 8081:8081 scspotlight
```

The container's default `CMD` already starts the app in processing mode on port 8081.

---

## Git Workflow Policy (Solo Dev: `dev` -> `main`)

### Branch Roles
- `main` is the production branch and must always remain deployable.
- `dev` is the integration/staging branch for ongoing feature work.
- `feature/*` branches are short-lived and should be created from `dev`.

### PR Flow
1. Create `feature/*` from `dev`.
2. Open PR from `feature/*` -> `dev`.
3. Address review feedback in the same branch, push new commits, and keep the PR updated.
4. Merge to `dev` only after checks pass.
5. Promote tested changes via PR from `dev` -> `main`.

### PR Summary Expectations
- PR summaries should be detailed enough to preserve implementation context for future review.
- Include, when relevant: overall goal, server-side changes, client-side changes, performance impact, correctness/safety improvements, caching or state-management changes, and validation performed.
- Prefer repository file references and concrete behavior changes over vague summaries like "refactor" or "cleanup".
- When a PR changes interaction contracts or architectural patterns, also update `DEVELOPMENT.md` with the rationale and behavior rules.

### Review Feedback Handling
- Reply to each review thread with one of: fixed, partially fixed, or not changed.
- When fixed, reference commit SHA or file path.
- When not changed, provide a short rationale (scope, risk, compatibility, or performance).
- Resolve review threads only after posting a clear reply.

### Merge and Rollback Rules
- Prefer squash merge for feature PRs unless preserving commit history is important.
- Delete merged `feature/*` branches.
- If a change in `dev` is problematic, revert it in `dev` before promoting.
- If a change reaches `main` and must be undone, revert the merge commit on `main`.

### Sync Rules
- Keep `dev` synchronized with `main` after each release merge to avoid drift.
- Keep active feature branches rebased/merged with `dev` regularly to reduce conflicts.

---

## Performance Requirements (CRITICAL)

**This app MUST handle 1M+ cells efficiently. Always consider performance impact.**

### Rendering Thresholds (deck.gl)
Adjust rendering parameters based on cell count (see `srcjs/modules/deckScatter.js:1041-1067`):

| Cell Count   | Point Size | Opacity | Pickable |
|--------------|------------|---------|----------|
| < 15,000     | 4          | 0.8     | true     |
| 15K - 50K    | 3          | 0.7     | true     |
| 50K - 500K   | 2          | 0.6     | true     |
| 500K - 1M    | 1          | 0.5     | true     |
| 1M - 2M      | 0.5        | 0.4     | true     |
| > 2M         | 0.2        | 0.2     | false    |

### Performance Best Practices

**JavaScript:**
- Use `deck.gl` for WebGL-accelerated main scatter plots (NOT canvas/SVG)
- Use **TypedArrays** (`Float32Array`, `Int32Array`, `Int16Array`) for large numeric data
- Store categorical data as **index arrays** with level lookup, not string arrays
- **Debounce** resize handlers (250ms) to prevent excessive redraws
- Purge webR `shelter` after each operation to free memory
- Avoid DOM manipulation in tight loops

**R:**
- Use **BPCells** for on-disk assay storage and direct Seurat layer access (avoid loading full matrices into memory)
- Use **Arrow IPC** for versioned binary transfer between R and the browser
- Use **ExtendedTask** + `future_promise` for non-blocking async operations
- Use `scattermore::geom_scattermost()` for R-generated plots when cells > 30K
- Consider **BPCells** for very large sparse matrices

---

## R Code Style Guidelines

### File Naming Conventions
- `mod_*.R` - Shiny modules (paired UI + Server functions)
- `fct_*.R` - Feature/business logic functions
- `utils_*.R` - Utility/helper functions
- `app_*.R` - App-level files (ui, server, config, global)

### Shiny Module Pattern
```r
#' ModuleName UI Function
#' @noRd
#' @importFrom shiny NS tagList
mod_ModuleName_ui <- function(id) {
    ns <- NS(id)
    tagList(
        # Use ns() for all input/output IDs
    )
}

#' ModuleName Server Functions
#' @noRd
mod_ModuleName_server <- function(id, reactive_args) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns
        # Module logic
    })
}
```

### Documentation
- Use roxygen2 with `@noRd` for internal functions
- Use `@importFrom` for specific imports, `@import` sparingly
- Document exported functions in the current backend helpers as reference

### Naming Conventions
- Functions: `snake_case` (e.g., `query_duck_expr`)
- Shiny inputs/outputs: `camelCase` (e.g., `selectedAssay`)
- Reactive values: `camelCase` (e.g., `seuratObj`, `metaProcessed`)

### Error Handling
- Use `req()` for input validation in observers
- Use `validate(need(...))` for user-facing validation
- Use `tryCatch()` for operations that may fail
- Use `isTruthy()` to check for valid values

---

## JavaScript Code Style Guidelines

### Module System
Use ES6 modules with Vite bundling:
```javascript
// Imports at top
import { functionName } from "./modules/moduleName.js";

// Exports
export const myFunction = () => { ... };
export class MyClass { ... }
```

### Naming Conventions
- Variables/functions: `camelCase`
- Classes: `PascalCase` (e.g., `ScatterDeckController`)
- Constants: `camelCase` or `UPPER_SNAKE_CASE` for true constants
- DOM element IDs: `camelCase`

### Shiny Integration
```javascript
// R → JS: Custom message handlers
Shiny.addCustomMessageHandler("message_type", (msg) => {
    // Handle message from R
});

// JS → R: Set input values
Shiny.setInputValue("inputName", value, { priority: "event" });
```

### Async Operations (webR)
```javascript
// Always use async/await with webR
const result = await shelter.evalR(`R code here`);
// Always purge shelter after use
await shelter.purge();
```

---

## File Organization

```
scSpotlight/
├── R/                      # R source files
│   ├── app_*.R             # App-level (ui, server, config, global)
│   ├── mod_*.R             # Shiny modules
│   ├── fct_*.R             # Feature functions
│   └── utils_*.R           # Utilities
├── srcjs/                  # JavaScript source (bundled via Vite)
│   ├── index.js            # Main entry point
│   └── modules/            # JS modules
│       ├── deckScatter.js  # Main scatter plot (WebGL, deck.gl)
│       ├── scatter/        # deck.gl scatter support modules
│       ├── webr.js         # webR integration
│       └── ...
├── vite.config.js          # Vite configuration
├── vitest.config.js        # Vitest configuration
├── inst/app/www/           # Static assets & bundled JS output
├── dev/                    # Development scripts (golem)
├── man/                    # Generated documentation
└── vignettes/              # Package vignettes
```

---

## Key Patterns

### R ↔ JavaScript Data Transfer
1. **R saves data** as versioned Arrow IPC files in the session temp directory
2. **R notifies JS** via `session$sendCustomMessage()`
3. **JS fetches data** through Arrow IPC helpers and may keep cold IPC buffers in a versioned client cache
4. Data is decoded to TypedArrays / compact metadata structures only when needed for rendering or analysis

### Reactive Update Flow
Use indicator `reactiveVal()` counters to trigger cascading updates:
```r
metaUpdateIndicator <- reactiveVal(0)
# Trigger update:
metaUpdateIndicator(metaUpdateIndicator() + 1)
```

### Backend Data Access
- Assay layers are read directly from the Seurat object, preferably through BPCells-backed on-disk matrices.
- Metadata is read from `object[[]]`.
- Reductions are read from `Embeddings(object[[reduction]])`.
- Expression payloads should use the selected Seurat assay layer instead of a mirrored query store.

---

## Adding New Features

1. **New Shiny Module**: Use `golem::add_module(name = "ModuleName")`
2. **New JS Module**: Create in `srcjs/modules/`, import in `index.js`
3. **Rebuild JS**: Run `pixi run build-js` for production or `pixi run dev` for development
4. **Always test** with datasets of varying sizes (1K, 100K, 1M+ cells)
5. **Profile performance** for large datasets before merging

---

## Development Workflow

### Local Development
```bash
# Terminal 1: Start Vite dev server with HMR
pixi run dev

# Terminal 2: Start R development
# In R console:
golem::document_and_reload()
run_app()
```

### Production Build
```bash
# Build optimized bundle
pixi run build-js

# Verify bundle
pixi run npm run preview
```

### Testing
```bash
# Run all tests
pixi run test-js

# Watch mode for development
pixi run npm run test:watch

# Run specific test
pixi run npm run test:scatter-model
```

---

## Vite Configuration Details

**vite.config.js** handles:
- Entry point: `srcjs/index.js`
- Output: `inst/app/www/index.js` (UMD format)
- Externals: Shiny, jQuery, waiter (R-provided globals)
- Source maps: Enabled for debugging
- Minification: Terser for production

**vitest.config.js** handles:
- Test environment: jsdom (browser-like)
- Global test utilities: describe, it, expect
- Module resolution: Same as Vite config
