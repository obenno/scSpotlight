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

## Files to Check for Future Changes

If behavior changes again, review these files together:

- `R/app_ui.R`
- `srcjs/index.js`
- `srcjs/modules/arrowReader.js`
- `srcjs/modules/featureSparkLine.js`
- `srcjs/modules/scatter/scatterModel.js`
- `srcjs/modules/deckScatter.js`
- `R/mod_UpdateMetaData.R`
- `R/mod_mainClusterPlot.R`
- `R/app_server.R`
- `srcjs/modules/floatingPlots.js`

## Suggested Follow-up Discipline

When changing plot behavior in the future:

1. Update this file with the new rule and rationale.
2. Keep the interaction contract explicit for each floating panel.
3. Re-run `pixi run test-js`.
4. Rebuild the frontend bundle with `pixi run build-js` before manual browser verification.
