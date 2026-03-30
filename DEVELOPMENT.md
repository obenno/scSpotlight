# Development Notes

This file records recent frontend behavior changes for the main scatter plot, sparkline gene selection, and floating plot windows. The goal is to preserve implementation intent and make later regressions easier to trace.

## Scope

The recent work touched these areas:

- floating plot UI in `R/app_ui.R`
- DEG analysis UI in `R/mod_DEG_Window.R`, `R/mod_FindMarkers.R`, and `R/mod_DEG_Table.R`
- reduction transfer in `R/mod_UpdateReduction.R`
- floating plot state and rendering flow in `srcjs/index.js`
- sparkline gene selection behavior in `srcjs/modules/featureSparkLine.js`
- main scatter plot mode selection in `srcjs/modules/scatter/scatterModel.js`
- main expression legend handling in `srcjs/modules/deckScatter.js`
- floating panel drag behavior in `srcjs/modules/floatingPlots.js`

## Key Decisions

### 1. Main panel uses only the first selected gene for expression mode

Decision:

- The main scatter plot supports a single expression layer at a time.
- If multiple genes are selected in the feature sparkline list, the main panel uses only the first selected gene.

Why:

- This matches current visualization constraints in the main panel.
- It avoids ambiguous multi-gene coloring behavior.

Implementation notes:

- `srcjs/modules/scatter/scatterModel.js` treats any non-empty `selectedFeatures` array as expression mode.
- `srcjs/modules/scatter/scatterModel.js` uses `selectedFeatures[0]` when building expression-backed plot data.
- `srcjs/modules/deckScatter.js` also uses `selectedFeatures[0]` for the expression legend to avoid client errors when multiple genes are selected.

### 2. The first selected gene is visually emphasized in the sparkline list

Decision:

- The first selected gene label is shown in bold in the feature sparkline list.

Why:

- It makes the main-panel expression source visible to the user when multiple genes are selected.

Implementation notes:

- `srcjs/modules/featureSparkLine.js` adds `.feature-gene-symbol` to gene labels.
- The helper `syncSelectedFeatureLabelStyles()` sets the first selected gene to bold and resets others to normal weight.

### 3. Floating plots are decoupled from automatic redraw on gene-selection changes

Decision:

- Selecting or deselecting genes in the sparkline list does not automatically redraw DotPlot or FeaturePlot.
- Those floating plots update only when their own plot action is taken, or when their already-rendered panel is resized.

Why:

- This keeps floating plots stable while users are adjusting selections.
- It avoids unnecessary webR work and reduces accidental expensive rerenders.

Implementation notes:

- `srcjs/modules/featureSparkLine.js` emits `scspotlight:featurePlotSelectionChanged` after selection updates.
- `srcjs/index.js` uses this event to refresh VlnPlot menu contents/status only, not to redraw DotPlot or FeaturePlot.

### 4. VlnPlot uses menu-driven selection and updates immediately on menu click

Decision:

- VlnPlot has no dedicated plot/refresh icon.
- Choosing an item from the VlnPlot popout menu updates the VlnPlot immediately.

Why:

- VlnPlot now behaves as a direct inspection panel for one chosen term at a time.
- This keeps the interaction lightweight compared with DotPlot and FeaturePlot.

Implementation notes:

- `R/app_ui.R` removes the VlnPlot action button and keeps inline status text.
- `srcjs/index.js` updates `reglElementData.plotMetaData.selectedMeta` from the dropdown item, refreshes menu state, and immediately calls `updateVlnPlot()` when the canvas is visible.
- Opening the floating VlnPlot window renders the current selection.

### 5. VlnPlot menu contains numeric metadata columns and selected genes

Decision:

- The VlnPlot popout menu includes:
  - all numeric metadata columns
  - all currently selected genes that have loaded expression data

Why:

- Users need to inspect either object metadata or selected-gene expression in the same VlnPlot UI.

Implementation notes:

- `srcjs/index.js` builds menu options via `getVlnPlotTermOptions()`.
- Option ids are typed as `meta:<name>` or `feature:<name>`.
- The selected item is highlighted in the dropdown.

### 6. DotPlot is explicit-action and order-aware

Decision:

- DotPlot redraws only when the DotPlot action button is clicked, or when an already-rendered DotPlot panel is resized.
- DotPlot supports a custom draggable cluster order in the floating panel.

Why:

- DotPlot is comparatively expensive and should not rerun on every selection tweak.
- Custom cluster ordering is part of the floating panel workflow and should persist independently of immediate redraws.

Implementation notes:

- `R/app_ui.R` adds a DotPlot toolbar with status text, draggable order list, and reset button.
- `srcjs/index.js` stores custom order in panel dataset fields and resolves it before plotting.
- Group order for UI sync is derived from category keys, not fully expanded per-cell metadata, to avoid unnecessary large allocations.

### 7. FeaturePlot is explicit-action and resize-aware

Decision:

- FeaturePlot redraws only when the FeaturePlot action button is clicked, or when an already-rendered FeaturePlot panel is resized.
- FeaturePlot is not auto-opened or auto-rendered by multi-gene selection in the main panel.

Why:

- FeaturePlot can be expensive for multiple features.
- The floating panel is the intended place for this multi-gene view.

Implementation notes:

- `R/app_ui.R` adds a dedicated floating FeaturePlot panel and a rail button.
- `srcjs/index.js` tracks `featurePlotRendered` and `featurePlotStale` in the panel dataset.
- The panel also exposes an `ncol` input to control layout.

### 8. Floating panel action buttons should not start panel dragging

Decision:

- Clicking a floating panel action button should activate the button only, not drag the panel.

Why:

- The action button sits inside the panel header, which also acts as the drag handle.
- Without a guard, slight pointer movement during click could move the panel unintentionally.

Implementation notes:

- `srcjs/modules/floatingPlots.js` excludes `.plot-floating-action` from drag start handling.

### 9. ElbowPlot is rendered client-side from transferred PCA standard deviations

Decision:

- The floating ElbowPlot window renders on the client from PCA standard deviation data sent from R.
- ElbowPlot refreshes automatically when the window opens, when the window is resized, and when PCA is updated after analysis.

Why:

- The elbow plot depends on PCA summary data, not the current main-plot reduction state.
- Client-side rendering avoids relying on Shiny plot output sizing inside the floating panel.

Implementation notes:

- `R/mod_UpdateReduction.R` transfers PCA standard deviations to the client via `pca_ready` whenever reductions are updated.
- `srcjs/modules/scatter/scatterModel.js` stores `pcaStdev` alongside other client-side data.
- `srcjs/index.js` renders the elbow plot on `elbowPlotCanvas` and refreshes it on floating-panel open, resize, and PCA updates.

### 10. DEG analysis lives in the floating DEG window

Decision:

- DEG settings, run action, marker table, and heatmap are grouped inside the floating DEG window.
- The old left-sidebar "Find Markers" panel is removed.

Why:

- DEG analysis is a result workflow rather than a persistent sidebar setting.
- Keeping settings, results, and heatmap together reduces context switching.

Implementation notes:

- `R/mod_DEG_Window.R` composes DEG settings, marker table, and heatmap into one floating workflow.
- `R/mod_FindMarkers.R` owns the async DEG run and returns marker results reactively.
- The DEG rail button now opens the full DEG analysis window rather than a table-only panel.

## Important Behavior Rules

These rules should be preserved unless intentionally changed.

### Main panel

- Main panel expression mode uses only the first selected gene.
- Multiple selected genes do not create multi-gene expression rendering in the main scatter plot.

### Sparkline list

- Multiple genes may be selected.
- The first selected gene label is bold.

### VlnPlot

- VlnPlot menu must contain all numeric metadata columns.
- VlnPlot menu must contain all selected genes with available expression data.
- Selecting a VlnPlot menu item redraws VlnPlot immediately.

### DotPlot

- DotPlot requires at least two selected genes.
- DotPlot does not redraw on gene-selection change alone.
- DotPlot redraws on explicit action button click or on resize after first render.

### FeaturePlot

- FeaturePlot requires more than one selected gene and is unavailable for module-score mode.
- FeaturePlot does not redraw on gene-selection change alone.
- FeaturePlot redraws on explicit action button click or on resize after first render.

### ElbowPlot

- ElbowPlot shows PCA standard deviations when PCA data exists.
- ElbowPlot refreshes automatically on panel open.
- ElbowPlot refreshes automatically on panel resize.
- ElbowPlot refreshes automatically when client-side PCA summary data is updated.

### DEG analysis

- DEG settings are configured inside the floating DEG window.
- DEG results run only when the user clicks the DEG run button.
- DEG marker table and DEG heatmap live in the same floating DEG window.
- DEG marker table and DEG heatmap are rendered server-side in the floating DEG window.

## Performance Considerations

These changes were implemented with the repo's large-dataset constraints in mind.

- Avoid expanding full category metadata arrays for DotPlot panel state when only group labels are needed.
- Avoid auto-redrawing floating panels on every selection change.
- Keep main-panel expression handling single-gene to match current rendering assumptions.
- Decode Arrow dictionary-encoded metadata from index buffers directly in `srcjs/modules/arrowReader.js` instead of calling `col.get(j)` for every row. This preserves the Arrow IPC migration's performance benefit for 1M+ cells by avoiding slow per-element Arrow accessor calls on categorical metadata columns.
- Keep plot refresh signaling separate from transfer completion state. `R/app_server.R` now increments a dedicated `plotRefreshIndicator` when full metadata/reduction transfers finish, while view-driven redraws continue to use `scatterUpdateIndicator`. This prevents `mod_mainClusterPlot_server()` from directly depending on `metaProcessed()` and `reductionProcessed()` as redraw triggers.
- Prefer partial metadata transfers for column-scoped changes. `R/mod_UpdateMetaData.R` supports Arrow IPC patches via `meta_patch_ready`, and `srcjs/index.js` merges them into the existing client metadata object instead of replacing the entire metadata payload. `Cell Cycling` uses this path for `S.Score`, `G2M.Score`, and `Phase`.
- Version all Arrow IPC payload filenames by data epoch so the client can safely distinguish stale files from current files. Reduction, expression, metadata, metadata patches, and PCA standard deviations now include versioned hash inputs on the R side.
- Keep a cold client-side IPC cache only for reduction and expression payloads. `srcjs/index.js` stores fetched Arrow IPC `ArrayBuffer`s keyed by `{version, reduction}` and `{version, assay, gene}` and rehydrates typed arrays on demand. This avoids repeated server fetches for reduction switching and cleared/reloaded expression panels while conserving memory by not keeping extra decoded hot copies.

## Validation Performed

Recent validation included:

- `pixi run test-js`
- `pixi run R -e 'devtools::document()'`
- `pixi run build-js`
- parse validation for `R/app_ui.R`

At the time of writing, the JS test suite passed with 55 tests.

## Backend Migration Notes

These notes capture the recent backend reconstruction from a DuckDB-centered runtime to a Seurat v5 + BPCells runtime.

### 11. BPCells is now the primary assay backend

Decision:

- Processing mode and viewer mode now treat Seurat objects as the single source of truth.
- DuckDB-backed assay/query storage has been removed from the active app runtime.
- BPCells is a required part of the runtime rather than an optional acceleration path.
- Counts and normalized data layers are stored as BPCells-backed on-disk matrices whenever possible.

Why:

- The app already keeps metadata, reductions, clustering state, and other analysis state inside the Seurat object.
- Maintaining both Seurat and DuckDB introduced duplicated storage, conversion work, and synchronization overhead.
- BPCells keeps large assay layers memory-efficient while preserving Seurat workflows.
- The app's large-dataset guarantees depend on BPCells-backed storage being available in every supported environment.

Implementation notes:

- `R/fct_bpcells_backend.R` now owns BPCells detection, conversion, querying, bundle save/load helpers, and memory-conserving PCA helpers.
- `R/mod_dataInput.R` converts loaded Seurat objects to BPCells-backed assay layers through `ensure_bpcells_backing()`.
- Metadata, reduction, and expression transfers now read directly from the Seurat object rather than querying DuckDB.

### 12. Client data exports should remain asynchronous

Decision:

- Metadata, reduction, and expression IPC generation should still use `future_promise()` for Arrow file writing and browser notification.
- BPCells-backed Seurat reads should remain on the Shiny main thread before the async boundary.

Why:

- BPCells-backed assay data is not a good fit for inter-process transfer or forked worker access.
- Arrow serialization can still be moved off the reactive loop after the in-process data extraction step.

Implementation notes:

- `R/mod_UpdateMetaData.R`, `R/mod_UpdateReduction.R`, and `R/mod_InputFeature.R` fetch Seurat/BPCells data in-process, then wrap Arrow IPC writing in background promises before notifying the browser on completion.

### 13. Metadata and reductions are exported directly from Seurat

Decision:

- Metadata Arrow IPC payloads come from `object[[]]`.
- Reduction Arrow IPC payloads come from `Embeddings(object[[reduction]])`.

Why:

- These structures are already in memory in Seurat and are faster to access directly than round-tripping through an external query engine.

Implementation notes:

- `R/mod_UpdateMetaData.R` now builds full and partial metadata payloads from `get_backend_metadata()`.
- `R/mod_UpdateReduction.R` now builds reduction payloads from `get_backend_reduction()` and sends PCA standard deviations directly from the Seurat object.

### 14. Expression queries now use Seurat/BPCells layer access

Decision:

- Feature expression extraction for the main scatter plot now reads from the selected Seurat assay layer directly.

Why:

- The backend is no longer split between Seurat state and DuckDB tables.
- This keeps expression serving consistent with the BPCells-backed assay storage model.

Implementation notes:

- `R/mod_InputFeature.R` uses `get_backend_expr()` for expression payload generation.
- `R/fct_bpcells_backend.R` chooses the preferred layer via `preferred_expr_layer()` and extracts feature vectors from the active BPCells or in-memory layer.

### 15. Processing mode should prefer BPCells-compatible code paths

Decision:

- Processing mode should assume Seurat calls may densify unexpectedly and should prefer BPCells-native or BPCells-compatible code paths.
- Full dense `scale.data` should not be preserved in portable BPCells bundles.

Why:

- Large datasets cannot tolerate accidental dense layer persistence.
- `ScaleData()` and related workflows can create expensive dense intermediates if left unchecked.

Implementation notes:

- `R/fct_bpcells_backend.R` provides `run_memory_conserving_processing()` and `run_memory_conserving_pca()`.
- BPCells-backed PCA uses BPCells matrix stats and truncated SVD when available.
- BPCells bundle export removes `scale.data` before saving to avoid shipping large dense matrices in portable archives.

### 15a. Seurat `ScaleData()` on BPCells supports scaling but not regression

Decision:

- Do not rely on `ScaleData(..., vars.to.regress = ...)` for BPCells-backed assay layers.
- BPCells-backed processing should use explicit BPCells-native scaling/PCA paths instead of Seurat regression-driven scaling.

Why:

- Seurat 5 provides an `IterableMatrix` method for `ScaleData()`, but that method only implements feature centering/scaling.
- The BPCells `IterableMatrix` path does not use `vars.to.regress`, `latent.data`, `split.by`, or regression models.
- This matches the behavior discussed in Seurat issue `#9676`, where users observed that regression requests on BPCells-backed data had no effect.

Implementation notes:

- Seurat's documented `ScaleData.IterableMatrix` signature omits `vars.to.regress`.
- The current Seurat implementation uses `BPCells::matrix_stats()` and row-wise transforms for scaling, but does not run regression in the `IterableMatrix` method.
- `R/fct_bpcells_backend.R` avoids this gap in the main processing route by using `run_bpcells_pca()` / `run_memory_conserving_pca()` instead of relying on `ScaleData()` for BPCells-backed objects.

### 16. BPCells layer types are optimized for storage

Decision:

- BPCells counts layers should be written as integer-like storage.
- BPCells normalized data layers should be written as float storage rather than raw doubles.

Why:

- BPCells warns that compression performs poorly for non-integer matrices.
- Counts compress better as `uint32_t`, while normalized data is more efficient as `float` than as double.

Implementation notes:

- `R/fct_bpcells_backend.R` uses `optimize_bpcells_matrix_type()` before `write_matrix_dir()`.
- `R/mod_dataInput.R` applies the same optimization in `BPCells_Read10X()`.

### 17. Portable BPCells downloads use a scSpotlight bundle contract

Decision:

- The BPCells download format is a self-identifying tarball bundle, not just a generic compressed folder.
- The download menu also keeps a standard `.Rds` export for compatibility with tooling that expects a plain serialized Seurat object.

Why:

- A plain `.tar.gz` does not indicate whether it contains a valid scSpotlight BPCells-backed Seurat bundle.
- Portable reuse requires a stable contract for locating the entrypoint RDS and the supporting BPCells layer directories.
- Some downstream workflows still expect a conventional `.Rds`, even though that path may need to materialize BPCells-backed layers first.

Implementation notes:

- `R/mod_Download.R` now defaults to `BPCells` format in processing mode.
- `R/mod_Download.R` now uses a single confirm modal before standard `Rds` export for large or BPCells-backed objects.
- `R/mod_Download.R` uses `progressr::withProgressShiny()` for BPCells bundle export and for coarse-grained standard `Rds` export progress.
- `R/fct_bpcells_backend.R` writes bundles containing:
  - `manifest.json`
  - the Seurat `.Rds`
  - `supporting/<assay>/<layer>/...` BPCells directories
  - `load_bundle.R`
  - `README.txt`
- `manifest.json` includes `bundle_type = "scspotlight_bpcells_seurat_bundle"` and `rds_file` so the app can identify valid bundles.

### 18. Bundled BPCells Seurat objects must be loaded from the bundle directory context

Decision:

- Reusable BPCells tarballs should be loaded through the app import path or the bundle loader helper, not by calling `LoadSeuratRds()` on the RDS from an arbitrary working directory.

Why:

- `SeuratObject::LoadSeuratRds()` rehydrates on-disk layers from the cached paths stored in the object.
- For relative paths like `supporting/RNA/counts`, path resolution depends on loading from the bundle directory context.

Implementation notes:

- `R/fct_bpcells_backend.R` provides `load_scspotlight_bundle()` to set the bundle directory context before calling `LoadSeuratRds()`.
- `R/mod_dataInput.R` uses the bundle-aware loader for direct `.Rds` input and for decompressed BPCells bundles.
- The saved bundle RDS now exposes the tool cache under `SaveSeuratRds`, matching what `LoadSeuratRds()` expects.

### 19. `.h5ad` bundle conversion should stream matrices through BPCells

Decision:

- `.h5ad` to BPCells bundle conversion should use `BPCells::open_matrix_anndata_hdf5()` for the matrix payload instead of first materializing a full Seurat object through `anndataR`.

Why:

- Large AnnData inputs can exceed memory limits if `X` is loaded fully into RAM before BPCells conversion.
- BPCells can read AnnData matrices lazily from HDF5, which keeps the conversion path aligned with the app's large-dataset constraints.

Implementation notes:

- `R/fct_bpcells_backend.R` now prefers native BPCells `.h5ad` import and falls back to reconstructing CSR matrices via `rhdf5` when BPCells cannot open the AnnData matrix layout directly.
- Direct `.h5ad` support in `R/mod_dataInput.R` is intentionally disabled for now because real-world AnnData layouts still vary enough to need more validation before interactive load should rely on them.

## Files to Check for Future Changes

If behavior changes again, review these files together:

- `R/app_ui.R`
- `srcjs/index.js`
- `srcjs/modules/arrowReader.js`
- `srcjs/modules/featureSparkLine.js`
- `srcjs/modules/scatter/scatterModel.js`
- `srcjs/modules/deckScatter.js`
- `R/mod_UpdateMetaData.R`
- `R/fct_bpcells_backend.R`
- `R/mod_dataInput.R`
- `R/mod_Download.R`
- `R/mod_InputFeature.R`
- `R/mod_UpdateReduction.R`
- `R/mod_mainClusterPlot.R`
- `R/app_server.R`
- `srcjs/modules/floatingPlots.js`

## Suggested Follow-up Discipline

When changing plot behavior in the future:

1. Update this file with the new rule and rationale.
2. Keep the interaction contract explicit for each floating panel.
3. Re-run `pixi run test-js`.
4. Rebuild the frontend bundle with `pixi run build-js` before manual browser verification.
