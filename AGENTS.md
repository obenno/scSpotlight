# AGENTS.md - scSpotlight Development Guide

## Project Overview

**scSpotlight** is an R/Shiny application for single-cell RNA-seq analysis and visualization,
built with the [golem](https://thinkr-open.github.io/golem/) framework.

**CRITICAL CONSTRAINT**: This application must efficiently handle **millions of cells**.
All code contributions must consider performance implications for large datasets (1M+ cells).

### Tech Stack
- **Backend**: R, Shiny, Seurat (v5), DuckDB (on-disk queries), qs2 (fast serialization)
- **Frontend**: JavaScript (ES6), deck.gl (WebGL), D3.js, webR
- **Build**: Use [packer](https://packer.john-coene.com/#/) package for JavaScript bundling

---

## Build / Lint / Test Commands

### R Package Commands
```r
devtools::document()            # Generate roxygen2 documentation
devtools::check()               # Run R CMD check
devtools::load_all()            # Load package for development
golem::document_and_reload()    # Quick reload during development (recommended)
```

### JavaScript Commands (packer - preferred)
```r
packer::bundle()                # Production bundle (minified)
packer::bundle_dev()            # Development bundle with source maps
```

### JavaScript Commands (npm - alternative)
```bash
npm run production              # webpack --config webpack.prod.js
npm run development             # webpack --config webpack.dev.js
npm run watch                   # Development with file watching
```

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
```bash
docker build -t scspotlight .
docker run -p 8081:8081 scspotlight \
  Rscript -e 'scSpotlight::run_app(options = list(port=8081, host="0.0.0.0", launch.browser=FALSE), runningMode="processing")'
```

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
- Use **DuckDB** for on-disk expression matrix queries (avoid loading full matrix)
- Use **qs2** package for fast binary serialization (`qs_save`)
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
- Document exported functions in `fct_duckdb.R` as reference

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
Use ES6 modules with packer/webpack bundling:
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
├── srcjs/                  # JavaScript source (bundled via packer)
│   ├── index.js            # Main entry point
│   ├── modules/            # JS modules
│   │   ├── deckScatter.js  # Main scatter plot (WebGL, deck.gl)
│   │   ├── scatter/         # deck.gl scatter support modules
│   │   ├── webr.js         # webR integration
│   │   └── ...
│   └── config/             # Webpack config JSON files
├── inst/app/www/           # Static assets & bundled JS output
├── dev/                    # Development scripts (golem)
├── man/                    # Generated documentation
└── vignettes/              # Package vignettes
```

---

## Key Patterns

### R ↔ JavaScript Data Transfer
1. **R saves data** using `qs2::qs_save()` to temp directory
2. **R notifies JS** via `session$sendCustomMessage()`
3. **JS fetches data** through webR reader utilities
4. Data converted to TypedArrays for efficiency

### Reactive Update Flow
Use indicator `reactiveVal()` counters to trigger cascading updates:
```r
metaUpdateIndicator <- reactiveVal(0)
# Trigger update:
metaUpdateIndicator(metaUpdateIndicator() + 1)
```

### DuckDB Table Naming
- Expression matrices: `{assay}__{layer}` (e.g., `RNA__counts`, `RNA__data`)
- Feature table: `{assay}__featureTbl`
- Cell table: `{assay}__cellTbl`
- Reductions: `Reductions__{name}` (e.g., `Reductions__umap`)
- Metadata: `metaData`

---

## Adding New Features

1. **New Shiny Module**: Use `golem::add_module(name = "ModuleName")`
2. **New JS Module**: Create in `srcjs/modules/`, import in `index.js`
3. **Rebuild JS**: Run `packer::bundle()` or `npm run production`
4. **Always test** with datasets of varying sizes (1K, 100K, 1M+ cells)
5. **Profile performance** for large datasets before merging
