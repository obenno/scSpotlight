# deckScatter Summary

## Purpose

`deckScatter` is the client-side scatter plotting system for
scSpotlight. It replaces the previous `regl-scatterplot` implementation
with a deck.gl-based renderer while preserving scSpotlight interaction
patterns and visual style.

The implementation is centered around `srcjs/modules/deckScatter.js`
(public orchestration class `reglScatterCanvas`) and a set of focused
helper modules under `srcjs/modules/scatter/`.

------------------------------------------------------------------------

## High-Level Architecture

### 1) Orchestrator

- **`srcjs/modules/deckScatter.js`**
  - Main class: `reglScatterCanvas`
  - Responsibilities:
    - owns public API used by `srcjs/index.js`
    - coordinates data/model state, deck rendering, overlays,
      interactions, lifecycle
    - manages resize/mount/update flow

### 2) Data/Mode Preparation

- **`srcjs/modules/scatter/scatterModel.js`**
  - Responsibilities:
    - accepts raw reduction/meta/expression data
    - derives plotting mode and panel counts (`clusterOnly`,
      `cluster+expr+noSplit`, `cluster+expr+twoSplit`,
      `cluster+multiSplit`, `cluster+expr+multiSplit`)
    - builds panel-wise XY/Z/color/cell/title payloads
    - computes category label coordinates
  - Data guarantees:
    - XY coordinates are stored as `Float32Array`
    - expression scaling output is `Float32Array`
    - expression scale is anchored at zero (`[0, max]`)

### 3) Rendering and View State

- **`srcjs/modules/scatter/scatterRenderer.js`**
  - lightweight Deck lifecycle wrapper (`create`, `setProps`, `destroy`)
- **`srcjs/modules/scatter/scatterDeckController.js`**
  - `panelLayerFilter(...)` for strict panel-to-viewport routing
  - `resolveViewStateUpdate(...)` for zoom damping and relayout-safe
    camera updates
- **`srcjs/modules/scatter/scatterViewState.js`**
  - panel/global bounds helpers
  - computes fitted view state from bounds and panel size
- **`srcjs/modules/scatter/scatterRelayout.js`**
  - computes panel viewport rectangles from measured panel DOM
  - provides invalid-size detection for deferred retry

### 4) Overlay and Coordinates

- **`srcjs/modules/scatter/scatterOverlay.js`**
  - crosshair drawing and canvas clearing
  - crosshair clipping to active panel bounds
- **`srcjs/modules/scatter/scatterCoordinates.js`**
  - world-\>panel and world-\>canvas projection helpers
  - panel index parsing from deck hover pick info

### 5) Interactions

- **`srcjs/modules/scatter/scatterInteractions.js`**
  - binds and manages lasso tool (`srcjs/modules/lasso.js`)
- **`srcjs/modules/lasso.js`**
  - custom shift+drag lasso implementation
  - point-in-polygon selection over panel position buffers

### 6) UI and Legends

- **`srcjs/modules/scatter/scatterUI.js`**
  - creates note/tooltip element
  - creates info widget, label size slider, download icon
  - handles screenshot/export flow using `html2canvas`
- **`srcjs/modules/scatter/scatterLegend.js`**
  - legend entry element creation
  - highlight index computation for legend-hover group highlighting
- **`srcjs/modules/scatter/scatterDOMState.js`**
  - centralized DOM visibility toggles for overlays/label
    canvases/resize-blank transitions
- **`srcjs/modules/scatter/scatterTooltip.js`**
  - mode-aware tooltip text creation for hovered points

### 7) Lifecycle

- **`srcjs/modules/scatter/scatterLifecycle.js`**
  - states: `idle`, `mounting`, `ready`, `resizing`, `clearing`
  - used to gate interactions during transitions

### 8) Deck Controller and Relayout Controller

- **`srcjs/modules/scatter/scatterDeckController.js`**
  - panel-scoped layer filtering
  - view-state update policy (zoom damping + relayout-safe gating)
- **`srcjs/modules/scatter/scatterRelayout.js`**
  - deterministic panel rect derivation for create/relayout phases
  - invalid rect detection for deferred relayout retry

------------------------------------------------------------------------

## Main Flow

1.  R/webR data arrives in browser (`srcjs/index.js`).
2.  `reglScatterCanvas` receives raw data (`updateReductionData`,
    `updateCellMetaData`, `updateExpressionData`).
3.  `updatePlotMetaData(...)` derives mode/panel settings from
    `group.by`, `split.by`, selected feature count.
4.  `updatePlotData()` delegates to `ScatterModel.buildPlotData()`.
5.  `updateCanvas()` creates panel/grid/overlay/widget DOM.
6.  `mountDeck()` waits for usable dimensions, computes layout, and
    calls `createDeck()`.
7.  Deck renders binary scatter layers; overlays and labels are shown
    after `onLoad` settles.

### Sequence Diagram: Initial Render

``` mermaid
sequenceDiagram
  participant IDX as index.js
  participant DS as deckScatter
  participant SM as scatterModel
  participant DL as scatterLayout/scatterRelayout
  participant DR as scatterRenderer(Deck)
  participant UI as scatterUI/scatterDOMState

  IDX->>DS: updateReductionData/updateMeta/updateExpr
  IDX->>DS: updatePlotMetaData(group.by, split.by)
  IDX->>DS: generatePlotEl()
  DS->>SM: buildPlotData()
  DS->>UI: create panel/grid/widgets (hidden overlay)
  IDX->>DS: mountDeck()
  DS->>DL: compute panel layout + view rects
  DS->>DR: create Deck(views, layers, handlers)
  DR-->>DS: onLoad
  DS->>UI: show labels/overlays + lifecycle READY
```

### Sequence Diagram: Resize Transition

``` mermaid
sequenceDiagram
  participant RES as ResizeObserver/window.resize
  participant DS as deckScatter
  participant DOM as scatterDOMState
  participant RL as scatterRelayout
  participant DR as scatterRenderer(Deck)

  RES->>DS: relayoutDebounced()
  DS->>DOM: beginResizeBlank (hide layers/overlays)
  DS->>RL: compute panel rects
  alt invalid panel rects
    DS->>DS: scheduleRelayoutRetry()
  else valid panel rects
    DS->>DR: setProps(width,height,views,viewState,layers)
    DS->>DOM: endResizeBlank (show layers/overlays)
  end
```

### Sequence Diagram: Hover + Crosshair + Tooltip

``` mermaid
sequenceDiagram
  participant Deck as deck.gl onHover
  participant DS as deckScatter
  participant CO as scatterCoordinates
  participant OV as scatterOverlay
  participant TT as scatterTooltip
  participant UI as scatterUI

  Deck->>DS: handleHover(info)
  DS->>CO: parsePanelIndexFromPickInfo(info)
  DS->>DS: update hoveredPoint + hover layers
  DS->>CO: projectWorldToCanvas(viewport, x, y)
  DS->>OV: drawCrosshair(target,bounds)
  DS->>TT: buildHoverText(mode,panel,point)
  DS->>UI: showNoteElement(noteId,text,color)
```

### Sequence Diagram: Lasso Selection

``` mermaid
sequenceDiagram
  participant User as User (Shift+Drag)
  participant LS as lasso.js
  participant SI as scatterInteractions
  participant DS as deckScatter
  participant SH as Shiny input bridge

  User->>LS: draw lasso polygon
  LS->>SI: onSelect(viewId, indices)
  SI->>DS: handleLassoSelect(viewId, indices)
  DS->>DS: map indices -> selected cells
  DS->>DS: apply highlight layers
  DS->>SH: setInputValue('selectedPoints', selectedCells)
```

### Sequence Diagram: Legend Hover Highlight

``` mermaid
sequenceDiagram
  participant User as User (Legend Hover)
  participant DS as deckScatter
  participant LG as scatterLegend
  participant Deck as deck.gl layers

  User->>DS: onmouseenter legend item
  DS->>LG: computeHighlightIndices(mode, pointsData, selectedGroup)
  LG-->>DS: indicesPerPanel
  DS->>DS: applyHighlight() / update color buffers
  DS->>Deck: setProps(layers=createAllLayers())

  User->>DS: onmouseleave legend item
  DS->>DS: clearHighlight()
  DS->>Deck: setProps(layers=createAllLayers())
```

------------------------------------------------------------------------

## Public API (orchestrator)

`reglScatterCanvas` provides both legacy-compatible and newer structured
methods:

- Legacy-compatible calls:
  - `updateReductionData(...)`
  - `updateCellMetaData(...)`
  - `updateExpressionData(...)`
  - `updatePlotMetaData(...)`
  - `generatePlotEl()`
  - `clear()`
- Structured API:
  - `setData(...)`
  - `setConfig(...)`
  - `render()`
  - `update(...)`
  - `resize()`
  - `destroy()`

------------------------------------------------------------------------

## Plot Modes and Panel Semantics

- `clusterOnly`
  - 1 panel, colored by category (`group.by`)
- `cluster+expr+noSplit`
  - 2 panels:
    - left: category
    - right: expression
- `cluster+expr+twoSplit`
  - 4 panels:
    - split1 category, split1 expression
    - split2 category, split2 expression
- `cluster+multiSplit`
  - N panels (N = levels in `split.by`), each colored by `group.by`
- `cluster+expr+multiSplit`
  - N panels (N = levels in `split.by`), expression panel per split
    level

All panel camera extents are aligned via global bounds so panel local
axes are consistent.

------------------------------------------------------------------------

## Rendering/Interaction Behavior

- Single Deck canvas with multiple `OrthographicView` viewports.
- Binary attributes for positions/colors (`Float32Array`, `Uint8Array`).
- Hover:
  - panel-specific highlight ring stack
  - panel-specific clipped crosshair
  - mode-aware tooltip text
- Selection:
  - custom lasso (shift+drag)
  - legend hover group highlight
  - double-click deselect
- Zoom:
  - wheel zoom enabled
  - damped zoom sensitivity
  - double-click zoom disabled

------------------------------------------------------------------------

## Resize Strategy

- Observe deck/wrapper/root and window resize events.
- During resize transition:
  - hide rendered layers/overlays (resize blank)
  - suppress hover artifacts
- After relayout:
  - recompute panel rects and view states
  - redraw layers and labels
  - restore visibility

------------------------------------------------------------------------

## Performance Strategy (large data)

- Use typed arrays for all heavy numeric data.
- Build colors from precomputed palette arrays.
- Use panel-local binary layer data for deck.gl.
- Dynamic point sizing/opacity by point count.
- Dynamic pickability (disable/reenable based on estimated visible
  points).
- Debounced layer updates and relayout updates.

------------------------------------------------------------------------

## Testing and Quality Gates

Vitest suite under `srcjs/modules/scatter/*.test.js` currently covers:

- `scatterModel` (mode logic, split behavior, typed array scaling)
- `scatterLayout` (panel sizing policy)
- `scatterViewState` (bounds/camera fitting)
- `scatterCoordinates` (projection/index parsing)
- `scatterRelayout` (panel rect calculation)
- `scatterDeckController` (layer filter and view-state update policy)
- `scatterTooltip` (hover text logic)
- `scatterLegend` (highlight indexing)
- `scatterLifecycle` (state transitions)
- `scatterDOMState` (overlay/resize visibility toggles)

Current commands:

- `npm test`
- `npm run test:scatter-model`
- `npm run production`

------------------------------------------------------------------------

## Development Requests Implemented (from this migration thread)

### Migration + Visual Consistency

- Replace `regl-scatterplot` with deck.gl.
- Preserve prior visual style and interactions where possible.
- Keep compatibility with existing scSpotlight message flow.

### Interaction/UX

- Implement lasso selection with shift+drag.
- Keep legend hover highlighting and selected-style point rings.
- Add hover point highlight and crosshair.
- Make crosshair panel-specific (only active panel).
- Double-click to deselect points.
- Keep mouse wheel zoom behavior.

### Multi-Panel Correctness

- Fix split.by panel assignment behavior.
- Ensure per-panel layer routing is strict.
- Support cluster-only, expression-only, and split combinations
  correctly.

### Resize Behavior

- Fix disappearance/flicker during resize.
- Hide panel content during resize transition and redraw after settle.
- Avoid unstable initial mount/layout flicker.

### Layout Rules

- Two-column maximum panel layout.
- Enforce min panel size constraints.
- Conditioned square/non-square behavior based on panel count/rows.

### Overlay/Controls Layering

- Ensure info icon, slider, download icon, and tooltip are above panel
  grid.
- Prevent controls from occupying plot layout rows.

### Data/Memory Requirements

- Ensure typed-array paths for heavy numeric data.
- Keep expression scaling anchored to zero.
- Reduce XY precision to reduce memory while retaining visual fidelity.
- Handle constant-expression panels correctly (low-end color, not
  high-end).

### Architecture and Maintainability

- Extract logic into dedicated modules under `srcjs/modules/scatter/`.
- Add focused tests per module.
- Keep `deckScatter` as orchestrator with cleaner method boundaries.

------------------------------------------------------------------------

## Notes for Future Work

- Potential: add browser E2E checks (Playwright) for resize +
  hover/selection interactions.
- Potential: extract final remaining orchestrator-heavy methods from
  `deckScatter` if desired.
- Added in this document: sequence diagrams for initial render and
  resize lifecycle.

------------------------------------------------------------------------

## Troubleshooting by Symptom

### 1) Split panels show wrong colors/data

- Check mode and panel derivation in
  `scatterModel.derivePlotMetaData()`.
- Verify panel-wise slicing in `scatterModel.prepareXYData()` and
  `scatterModel.prepareZData()`.
- Confirm layer routing via `panelLayerFilter(...)` (panel id must match
  viewport id).

### 2) Hover/crosshair only works on first panel

- Verify panel index resolution from pick info in
  `parsePanelIndexFromPickInfo(...)`.
- Verify projection path uses `projectWorldToCanvas(...)` for crosshair
  placement.
- Ensure crosshair clipping bounds come from the hovered panel viewport.

### 3) Labels appear before plot or drift on mode/resize changes

- Ensure panel overlays are hidden until deck `onLoad` settle phase.
- Verify relayout sequence: compute views -\> apply deck props -\>
  redraw labels -\> restore overlay visibility.
- Check `scatterDOMState` visibility toggles for overlay/labels during
  transitions.

### 4) Points disappear during resize

- Confirm resize blank mode is intentionally active during transition.
- Verify relayout retries when panel rects are invalid
  (`hasInvalidPanelRects(...)`).
- Confirm final relayout frame calls label redraw and exits resize blank
  mode.

### 5) Expression colors all look low-end or all high-end

- Verify expression vectors are typed arrays and non-empty.
- Check `scaleDataZ(...)` behavior (zero-anchored, constant-array
  handling).
- Confirm expression color map indexing uses scaled z values in `[0,1]`.

### 6) Widgets not clickable / hidden behind panel

- Verify z-index stacking for note, info, slider, and download icon.
- Ensure widgets are absolute-positioned and not taking layout row
  space.
- Check overlay/grid opacity toggles do not suppress widget visibility
  unexpectedly.

### Debug Checklist Commands

- Run scatter unit suite:
  - `npm test`
- Run focused model checks:
  - `npm run test:scatter-model`
- Rebuild bundle used by app:
  - `npm run production`
- Quick grep targets for common issues:
  - mode/data prep: `srcjs/modules/scatter/scatterModel.js`
  - layout/view rects: `srcjs/modules/scatter/scatterLayout.js`,
    `srcjs/modules/scatter/scatterRelayout.js`
  - view state/camera: `srcjs/modules/scatter/scatterViewState.js`
  - hover/crosshair coord conversion:
    `srcjs/modules/scatter/scatterCoordinates.js`
  - deck event policy: `srcjs/modules/scatter/scatterDeckController.js`
  - overlay/widget visibility:
    `srcjs/modules/scatter/scatterDOMState.js`,
    `srcjs/modules/scatter/scatterUI.js`
