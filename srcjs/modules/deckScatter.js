import { OrthographicView, COORDINATE_SYSTEM } from "@deck.gl/core";
import { ScatterplotLayer } from "@deck.gl/layers";
import * as d3 from "d3";
import { ScatterModel } from "./scatter/scatterModel.js";
import { ScatterRenderer } from "./scatter/scatterRenderer.js";
import { ScatterOverlay } from "./scatter/scatterOverlay.js";
import { ScatterInteractions } from "./scatter/scatterInteractions.js";
import { ScatterLifecycle } from "./scatter/scatterLifecycle.js";
import { computePanelLayout } from "./scatter/scatterLayout.js";
import {
  getGlobalBoundsFromPanels,
  computeViewStateFromBounds,
} from "./scatter/scatterViewState.js";
import {
  panelLayerFilter,
  resolveViewStateUpdate,
} from "./scatter/scatterDeckController.js";
import {
  projectWorldToPanel,
  projectWorldToCanvas,
  parsePanelIndexFromPickInfo,
} from "./scatter/scatterCoordinates.js";
import { buildHoverText } from "./scatter/scatterTooltip.js";
import {
  getPanelViewRects,
  hasInvalidPanelRects,
} from "./scatter/scatterRelayout.js";
import {
  createLabelSliderElement,
  createInfoWidgetElement,
  createDownloadIconElement,
  createNoteElement,
  showNoteElement,
  hideNoteElement,
} from "./scatter/scatterUI.js";
import {
  setLabelCanvasVisibility as setLabelCanvasVisibilityInDOM,
  setPanelOverlayVisibility as setPanelOverlayVisibilityInDOM,
  setResizeBlankVisibility,
} from "./scatter/scatterDOMState.js";
import {
  createLegendEntryElement,
  findIndexes as findLegendIndexes,
  computeHighlightIndices,
} from "./scatter/scatterLegend.js";
//import { tableFromArrays } from "apache-arrow";

export class reglScatterCanvas {
  // this will create a element containing all the elements of the scatter plot
  // typical we usd a containerID "parent-wrapper"
  constructor(containerID) {
    // create parent container
    this.plotEl = document.createElement("div");
    this.plotEl.id = containerID;
    // by default, use 100% to fit into outside container
    this.plotEl.style.width = "100%";
    this.plotEl.style.height = "100%";
    this.plotEl.style.position = "relative";
    this.plotEl.style.overflow = "auto";

    // category legend element
    this.catLegendEl = document.createElement("div");
    this.catLegendEl.id = containerID + "-" + "catLegend";
    this.catLegendEl.classList.add("html-fill-container");

    // expression legend element
    this.expLegendEl = document.createElement("div");
    this.expLegendEl.id = containerID + "-" + "expLegend";
    this.expLegendEl.classList.add("html-fill-container");

    this.model = new ScatterModel({
      utils: {
        splitArrByMeta,
        convert_stringArr_to_integer,
        rgbToHex,
        sortStringArray,
        hue_pal,
        expandMeta,
      },
    });
    // Keep backward-compatible property names used by index.js
    this.origData = this.model.origData;
    this.plotData = this.model.plotData;
    this.plotMetaData = this.model.plotMetaData;

    this.renderer = new ScatterRenderer();
    this.interactions = new ScatterInteractions();
    this.lifecycle = new ScatterLifecycle();
    this.deck = null;
    this.viewStates = {};
    this.baseZoomByView = {};
    this.panelBuffers = [];
    this.globalBounds = null;
    this.noteId = null;
    this.hoveredPoint = null;
    this.highlightByPanel = null;
    this.lassoTool = null;
    this.selectionHandlers = { onSelect: null, onDeselect: null };
    this.mountTimer = null;
    this.resizeObserver = null;
    this.lastZoomByView = {};
    this.labelRaf = null;
    this.pendingLabelViews = new Set();
    // Lower scroll-wheel zoom aggressiveness (1 = default).
    this.zoomSensitivity = 0.35;
    this.lastHoverKey = null;
    this.relayoutTimer = null;
    this.isRelayouting = false;
    this.isResizeBlank = false;
    this.allowResizeBlank = false;
    this.initialLayoutPending = false;
    this.onPanelDoubleClick = null;
    this.onWindowResize = () => {
      if (this.allowResizeBlank && !this.initialLayoutPending && this.lifecycle.isReady()) {
        this.beginResizeBlank();
      }
      this.relayoutDebounced();
    };
    this.updateLayersDebounced = this.debounce(() => {
      if (this.deck) {
        this.deck.setProps({ layers: this.createAllLayers() });
      }
    }, 16);
    this.relayoutDebounced = this.debounce(() => {
      this.relayoutDeck();
    }, 120);
  }

  updateReductionData(reductionData) {
    this.model.setData({ reductionData });
    this.origData = this.model.origData;
  }

  updateCellMetaData(cellMetaData) {
    this.model.setData({ cellMetaData });
    this.origData = this.model.origData;
  }

  updateExpressionData(expressionData) {
    this.model.setData({ expressionData });
    this.origData = this.model.origData;
  }

  updatePlotMetaData(group_by = null, split_by = null, moduleScore = false) {
    this.model.plotMetaData.selectedFeatures = this.plotMetaData.selectedFeatures;
    this.model.plotMetaData.moduleScore = this.plotMetaData.moduleScore;
    this.plotMetaData = this.model.derivePlotMetaData(
      group_by,
      split_by,
      moduleScore,
    );
  }

  clear() {
    this.lifecycle.setClearing();
    // clear elements and plotData
    while (this.plotEl.firstChild) {
      this.constructor.removeAllChildNodes(this.plotEl);
    }
    while (this.catLegendEl.firstChild) {
      this.constructor.removeAllChildNodes(this.catLegendEl);
    }
    while (this.expLegendEl.firstChild) {
      this.constructor.removeAllChildNodes(this.expLegendEl);
    }
    this.renderer.destroy();
    this.deck = null;
    this.interactions.destroyLasso();
    this.lassoTool = null;
    if (this.labelRaf) {
      window.cancelAnimationFrame(this.labelRaf);
      this.labelRaf = null;
    }
    this.pendingLabelViews.clear();
    if (this.mountTimer) {
      window.clearTimeout(this.mountTimer);
      this.mountTimer = null;
    }
    if (this.relayoutTimer) {
      window.clearTimeout(this.relayoutTimer);
      this.relayoutTimer = null;
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = null;
    }
    window.removeEventListener("resize", this.onWindowResize);
    this.viewStates = {};
    this.baseZoomByView = {};
    this.lastZoomByView = {};
    this.panelBuffers = [];
    this.globalBounds = null;
    this.highlightByPanel = null;
    this.hoveredPoint = null;
    this.lastHoverKey = null;
    this.isRelayouting = false;
    this.isResizeBlank = false;
    this.allowResizeBlank = false;
    this.initialLayoutPending = false;
    if (this.onPanelDoubleClick) {
      const deckContainer = this.plotEl.querySelector("#deck-container");
      if (deckContainer) {
        deckContainer.removeEventListener("dblclick", this.onPanelDoubleClick);
      }
      this.onPanelDoubleClick = null;
    }

    // Keep origData but reset plot-derived state through model.
    this.model.resetPlotState();
    this.plotData = this.model.plotData;
    this.plotMetaData = this.model.plotMetaData;
    //this.plotMetaData.selectedFeatures = [];
    //this.plotMetaData.moduleScore = false;

    // add element position adjustment observer
    //const adjustObserver = new MutationObserver((mutationList, observer) => {
    //    for (const mutation of mutationList) {
    //        if(mutation.target.parentElement){
    //            mutation.target.parentElement.addEventListener('scroll', () => {
    //                const containerEl = entry.target.parentElement;
    //
    //                const infoEl = containerEl.querySelector("#info");
    //                infoEl.style.bottom = "1%";
    //                infoEl.style.bottom = `calc(${infoEl.style.bottom} - ${containerEl.scrollTop}px)`;
    //
    //                const noteEl = containerEl.querySelector("#scatterPlotNote");
    //                noteEl.style.bottom = "2%";
    //                noteEl.style.bottom = `calc(${noteEl.style.bottom} - ${containerEl.scrollTop}px)`;
    //            });
    //        }
    //    }
    //});
    //
    //adjustObserver.observe(this.plotEl, { attributes: true, childList: true, subtree: true });
    this.lifecycle.setIdle();
  }

  static removeAllChildNodes(parent) {
    while (parent.firstChild) {
      reglScatterCanvas.removeNodeAndListeners(parent.firstChild);
    }
  }

  static removeNodeAndListeners(node) {
    // Remove event listeners
    const clone = node.cloneNode(false); // Shallow clone
    node.parentNode.replaceChild(clone, node);

    // Recursively remove child nodes
    while (clone.firstChild) {
      reglScatterCanvas.removeNodeAndListeners(clone.firstChild);
    }

    // Remove the node from its parent
    if (clone.parentNode) {
      clone.parentNode.removeChild(clone);
    }
  }

  generatePlotEl() {
    this.updatePlotData();
    this.updateCanvas();
    this.updateCatLegend();
    this.updateExpLegend();
  }

  // New simplified public API
  setData(data = {}) {
    this.model.setData(data);
    this.origData = this.model.origData;
  }

  setConfig(config = {}) {
    this.model.setConfig(config);
    this.plotMetaData = this.model.plotMetaData;
  }

  render() {
    this.generatePlotEl();
    this.mountDeck();
    return this;
  }

  update({ data = null, config = null } = {}) {
    if (data) {
      this.setData(data);
    }
    if (config) {
      this.setConfig(config);
    }
    return this.render();
  }

  resize() {
    this.relayoutDebounced();
  }

  destroy() {
    this.clear();
  }

  mountDeck() {
    if (this.deck) {
      return;
    }
    const deckContainer = this.plotEl.querySelector("#deck-container");
    if (!deckContainer) {
      return;
    }
    if (deckContainer.clientWidth < 10 || deckContainer.clientHeight < 10) {
      if (!this.mountTimer) {
        this.mountTimer = window.setTimeout(() => {
          this.mountTimer = null;
          this.mountDeck();
        }, 100);
      }
      return;
    }
    if (this.mountTimer) {
      window.clearTimeout(this.mountTimer);
      this.mountTimer = null;
    }
    this.updateSquarePanelLayout();
    this.lifecycle.setMounting();
    this.createDeck();
    if (!this.resizeObserver) {
      this.resizeObserver = new ResizeObserver(() => {
        if (this.allowResizeBlank) {
          this.beginResizeBlank();
        }
        this.relayoutDebounced();
      });
      this.resizeObserver.observe(deckContainer);
      const canvasContainer = this.plotEl.querySelector("#canvas-wrapper");
      if (canvasContainer) {
        this.resizeObserver.observe(canvasContainer);
      }
      this.resizeObserver.observe(this.plotEl);
      window.addEventListener("resize", this.onWindowResize);
    }
    // Do not force an immediate second relayout after createDeck();
    // it can cause a visible panel "snap" during initial multi-panel mount.
  }

  beginResizeBlank() {
    if (this.isResizeBlank) {
      return;
    }
    this.isResizeBlank = true;
    this.lifecycle.setResizing();
    setResizeBlankVisibility(this.plotEl, true);
    this.clearHoverCrosshair();
    this.hoveredPoint = null;
    this.lastHoverKey = null;
    if (this.noteId) {
      reglScatterCanvas.hideNote(this.noteId);
    }
  }

  endResizeBlank() {
    if (!this.isResizeBlank) {
      return;
    }
    this.isResizeBlank = false;
    this.lifecycle.setReady();
    setResizeBlankVisibility(this.plotEl, false);
  }

  setLabelCanvasVisibility(isVisible) {
    setLabelCanvasVisibilityInDOM(this.plotEl, isVisible);
  }

  setPanelOverlayVisibility(isVisible) {
    setPanelOverlayVisibilityInDOM(this.plotEl, isVisible);
  }

  getDeckContainerAndSize() {
    const deckContainer = this.plotEl.querySelector("#deck-container");
    if (!deckContainer || deckContainer.clientWidth < 10 || deckContainer.clientHeight < 10) {
      return null;
    }

    const width = Math.max(
      1,
      Number.parseFloat(deckContainer.style.width) || deckContainer.clientWidth,
    );
    const height = Math.max(
      1,
      Number.parseFloat(deckContainer.style.height) || deckContainer.clientHeight,
    );

    if (!width || !height) {
      return null;
    }

    return { deckContainer, width, height };
  }

  computeRelayoutViews(panelEls, deckWidth, deckHeight) {
    const viewRects = this.computeViewRectsForPanels(panelEls, deckWidth, deckHeight);
    const views = this.buildViewsFromRects(viewRects);
    return { viewRects, views };
  }

  applyRelayoutProps(deckWidth, deckHeight, views) {
    this.isRelayouting = true;
    this.deck.setProps({
      width: deckWidth,
      height: deckHeight,
      views,
      viewState: { ...this.viewStates },
      layers: this.createAllLayers(),
    });

    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        this.isRelayouting = false;
      });
    });
  }

  finalizeRelayoutFrame() {
    window.requestAnimationFrame(() => {
      this.showCatLabel();
      this.clearHoverCrosshair();
      this.endResizeBlank();
      if (this.initialLayoutPending) {
        this.plotEl.style.opacity = "1";
        this.initialLayoutPending = false;
      }
      this.allowResizeBlank = true;
    });
  }

  relayoutDeck() {
    if (!this.deck) {
      return;
    }
    this.updateSquarePanelLayout();
    const deck = this.getDeckContainerAndSize();
    if (!deck) {
      return;
    }
    const { width: deckWidth, height: deckHeight } = deck;

    const panelEls = Array.from(this.plotEl.querySelectorAll(".deck-panel"));
    const { viewRects, views } = this.computeRelayoutViews(
      panelEls,
      deckWidth,
      deckHeight,
    );

    if (hasInvalidPanelRects(viewRects)) {
      this.scheduleRelayoutRetry();
      return;
    }

    this.applyRelayoutProps(deckWidth, deckHeight, views);
    this.finalizeRelayoutFrame();
  }

  updateCanvas() {
    // Avoid visible "snap" when multi-panel layout settles from pre-mount to
    // viewport-sized dimensions.
    this.initialLayoutPending = this.plotMetaData.nPanels > 1;
    this.plotEl.style.opacity = this.initialLayoutPending ? "0" : "1";
    this.lifecycle.setMounting();

    // append canvas elements, wrapped by an outter element with id "canvas-wrapper"
    this.createCanvas("canvas-wrapper");
    // Avoid showing panel labels/titles before Deck has finished first paint/layout.
    this.setPanelOverlayVisibility(false);
    // create and append note element with id: scatterPlotNote
    this.createNote("scatterPlotNote");
    // create info widget
    this.createInfoWidget("info");
    // create slider widget
    this.createLabelSlider("labelSlider");
    // create download icon
    this.createDownloadIcon("downloadIcon");

    this.noteId = "scatterPlotNote";

  }

  updatePlotData() {
    this.model.plotMetaData = this.plotMetaData;
    this.model.origData = this.origData;
    this.plotData = this.model.buildPlotData();
    this.model.plotData = this.plotData;
  }

  // function to create grid view in the element (mainClusterPlot div)
  // here will always be div "parent-wrapper"
  createCanvas(canvasContainerID) {
    // create plot panel
    let nCols = null;

    if (this.plotMetaData.nPanels >= 2) {
      nCols = 2;
    } else {
      nCols = 1;
    }
    let nRows = Math.ceil(this.plotMetaData.nPanels / nCols);
    const panelGap = "0.2rem";

    let canvasContainer = document.createElement("div");
    canvasContainer.id = canvasContainerID;
    canvasContainer.style.position = "relative";
    canvasContainer.style.width = "100%";
    canvasContainer.style.height = "100%";
    canvasContainer.style.overflow = "auto";

    const deckContainer = document.createElement("div");
    deckContainer.id = "deck-container";
    deckContainer.style.position = "absolute";
    deckContainer.style.inset = "0";
    deckContainer.style.zIndex = "2";
    deckContainer.style.background = "transparent";
    deckContainer.style.pointerEvents = "auto";
    canvasContainer.appendChild(deckContainer);

    const crosshairCanvas = document.createElement("canvas");
    crosshairCanvas.id = "crosshair-underlay";
    crosshairCanvas.style.position = "absolute";
    crosshairCanvas.style.inset = "0";
    crosshairCanvas.style.width = "100%";
    crosshairCanvas.style.height = "100%";
    crosshairCanvas.style.zIndex = "1";
    crosshairCanvas.style.pointerEvents = "none";
    const crosshairObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const { width, height } = entry.target.getBoundingClientRect();
        entry.target.width = width * window.devicePixelRatio;
        entry.target.height = height * window.devicePixelRatio;
      }
    });
    crosshairObserver.observe(crosshairCanvas);
    canvasContainer.appendChild(crosshairCanvas);

    const overlayGrid = document.createElement("div");
    overlayGrid.classList.add("deck-overlay-grid");
    overlayGrid.style.position = "absolute";
    overlayGrid.style.inset = "0";
    overlayGrid.style.display = "grid";
    overlayGrid.style.gridTemplateColumns = `repeat(${nCols}, minmax(400px, 1fr))`;
    overlayGrid.style.gridTemplateRows = `repeat(${nRows}, minmax(400px, 1fr))`;
    overlayGrid.style.gap = panelGap;
    overlayGrid.style.width = "max-content";
    overlayGrid.style.height = "max-content";
    overlayGrid.style.minWidth = "100%";
    overlayGrid.style.minHeight = "100%";
    overlayGrid.style.zIndex = "3";
    overlayGrid.style.pointerEvents = "none";
    overlayGrid.style.background = "transparent";
    overlayGrid.style.justifyContent = "start";
    overlayGrid.style.alignContent = "start";

    for (let i = 0; i < this.plotMetaData.nPanels; i++) {
      const panel = document.createElement("div");
      panel.classList.add("deck-panel");
      panel.dataset.viewId = `panel_${i}`;
      panel.style.position = "relative";
      panel.style.pointerEvents = "none";
      panel.style.background = "transparent";
      panel.style.overflow = "hidden";
      panel.style.boxSizing = "border-box";
      panel.style.minWidth = "400px";
      panel.style.minHeight = "400px";
      panel.style.aspectRatio = "auto";
      if (this.plotMetaData.nPanels > 1) {
        panel.style.borderWidth = "1px";
        panel.style.borderStyle = "solid";
        panel.style.borderColor = "#D3D3D3";
      }

      const plotTitle = document.createElement("div");
      plotTitle.classList.add("mainClusterPlotTitle");
      plotTitle.innerHTML = this.plotData.panelTitles[i];
      panel.appendChild(plotTitle);

      const labelCanvas = document.createElement("canvas");
      labelCanvas.classList.add("label-canvas");
      labelCanvas.dataset.viewId = `panel_${i}`;
      labelCanvas.style.position = "absolute";
      labelCanvas.style.width = "100%";
      labelCanvas.style.height = "100%";
      labelCanvas.style.inset = 0;
      labelCanvas.style.pointerEvents = "none";
      labelCanvas.width = 600;
      labelCanvas.height = 600;
      const canvasObserver = new ResizeObserver((entries) => {
        for (const entry of entries) {
          const { width, height } = entry.target.getBoundingClientRect();
          entry.target.width = width * window.devicePixelRatio;
          entry.target.height = height * window.devicePixelRatio;
        }
      });
      canvasObserver.observe(labelCanvas);

      panel.appendChild(labelCanvas);

      overlayGrid.appendChild(panel);
    }

    canvasContainer.appendChild(overlayGrid);

    const lassoCanvas = document.createElement("canvas");
    lassoCanvas.id = "lasso-overlay";
    lassoCanvas.style.position = "absolute";
    lassoCanvas.style.inset = "0";
    lassoCanvas.style.width = "100%";
    lassoCanvas.style.height = "100%";
    lassoCanvas.style.zIndex = "4";
    lassoCanvas.style.pointerEvents = "none";
    const lassoObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const { width, height } = entry.target.getBoundingClientRect();
        entry.target.width = width * window.devicePixelRatio;
        entry.target.height = height * window.devicePixelRatio;
      }
    });
    lassoObserver.observe(lassoCanvas);
    canvasContainer.appendChild(lassoCanvas);

    this.plotEl.appendChild(canvasContainer);
    this.updateSquarePanelLayout();
  }

  updateSquarePanelLayout() {
    const canvasContainer = this.plotEl.querySelector("#canvas-wrapper");
    const overlayGrid = this.plotEl.querySelector(".deck-overlay-grid");
    const deckContainer = this.plotEl.querySelector("#deck-container");
    const crosshairCanvas = this.plotEl.querySelector("#crosshair-underlay");
    const lassoCanvas = this.plotEl.querySelector("#lasso-overlay");
    if (!canvasContainer || !overlayGrid) {
      return;
    }

    const nPanels = Math.max(1, this.plotMetaData.nPanels || 1);
    const panels = Array.from(overlayGrid.querySelectorAll(".deck-panel"));

    const styles = window.getComputedStyle(overlayGrid);
    const gap = Number.parseFloat(styles.columnGap || styles.gap || "0") || 0;
    const layout = computePanelLayout({
      nPanels,
      containerWidth: Math.max(1, canvasContainer.clientWidth),
      containerHeight: Math.max(1, canvasContainer.clientHeight),
      gap,
      minPanelSize: 400,
    });

    overlayGrid.style.gridTemplateColumns = layout.gridTemplateColumns;
    overlayGrid.style.gridTemplateRows = layout.gridTemplateRows;
    const contentWidth = layout.contentWidth;
    const contentHeight = layout.contentHeight;
    overlayGrid.style.width = `${contentWidth}px`;
    overlayGrid.style.height = `${contentHeight}px`;
    overlayGrid.style.minHeight = "100%";
    if (deckContainer) {
      deckContainer.style.width = `${contentWidth}px`;
      deckContainer.style.height = `${contentHeight}px`;
    }
    if (crosshairCanvas) {
      crosshairCanvas.style.width = `${contentWidth}px`;
      crosshairCanvas.style.height = `${contentHeight}px`;
    }
    if (lassoCanvas) {
      lassoCanvas.style.width = `${contentWidth}px`;
      lassoCanvas.style.height = `${contentHeight}px`;
    }
    panels.forEach((panel) => {
      panel.style.aspectRatio = layout.isSquare ? "1 / 1" : "auto";
    });
  }

  showCatLabel(viewIds = null) {
    if (!this.deck) {
      return;
    }
    const sliderInput = this.plotEl.querySelector(".label-slider input");
    const sliderValue = sliderInput ? Number.parseFloat(sliderInput.value) : NaN;
    const baseFontSize = Number.isFinite(sliderValue)
      ? sliderValue
      : Number.parseFloat(this.plotMetaData.labelSize) || 14;
    let viewports = [];
    try {
      viewports = this.deck.getViewports();
    } catch (error) {
      return;
    }
    if (!Array.isArray(viewports) || viewports.length === 0) {
      return;
    }
    const filterIds = viewIds ? new Set(viewIds) : null;
    const canvases = Array.from(this.plotEl.querySelectorAll(".label-canvas"));
    viewports.forEach((viewport) => {
      if (filterIds && !filterIds.has(viewport.id)) {
        return;
      }
      const idx = Number.parseInt(viewport.id.replace("panel_", ""), 10);
      if (!Number.isFinite(idx)) {
        return;
      }
      if (!canvases[idx] || typeof viewport.project !== "function") {
        return;
      }
      const xScale = (x) => projectWorldToPanel(viewport, x, 0)[0];
      const yScale = (y) => projectWorldToPanel(viewport, 0, -y)[1];
      if (typeof this.plotData.catLabelCoordinates[idx] !== "undefined") {
        this.constructor.fillLabelCanvas(
          this.plotData.catLabelCoordinates[idx],
          canvases[idx],
          baseFontSize,
          xScale,
          yScale,
        );
      }
    });
  }

  scheduleLabelRedraw(viewId) {
    if (!viewId) {
      return;
    }
    this.pendingLabelViews.add(viewId);
    if (this.labelRaf) {
      return;
    }
    this.labelRaf = window.requestAnimationFrame(() => {
      this.labelRaf = null;
      const ids = Array.from(this.pendingLabelViews);
      this.pendingLabelViews.clear();
      try {
        this.showCatLabel(ids);
      } catch (error) {
        console.warn("Label redraw skipped:", error);
      }
    });
  }

  clearHoverCrosshair() {
    const canvas = this.plotEl.querySelector("#crosshair-underlay");
    ScatterOverlay.clearCanvas(canvas);
  }

  drawHoverCrosshair(target) {
    if (!this.deck) {
      return;
    }
    if (!target) {
      this.clearHoverCrosshair();
      return;
    }
    const canvas = this.plotEl.querySelector("#crosshair-underlay");
    const viewport = this.deck.getViewports().find((vp) => vp.id === target.viewId);
    if (!viewport) {
      this.clearHoverCrosshair();
      return;
    }
    const canvasPos = projectWorldToCanvas(viewport, target.worldX, target.worldY);
    ScatterOverlay.drawCrosshair(canvas, {
      x: canvasPos[0],
      y: canvasPos[1],
      left: viewport.x,
      top: viewport.y,
      right: viewport.x + viewport.width,
      bottom: viewport.y + viewport.height,
    });
  }

  collectHoverCrosshairTarget(panelIdx, pointIdx) {
    const panel = this.panelBuffers[panelIdx];
    if (!panel || pointIdx < 0 || pointIdx >= panel.nPoints) {
      return null;
    }
    return {
      viewId: `panel_${panelIdx}`,
      worldX: panel.positions[pointIdx * 2],
      worldY: panel.positions[pointIdx * 2 + 1],
    };
  }

  createLabelSlider(ElId) {
    createLabelSliderElement({
      plotEl: this.plotEl,
      id: ElId,
      labelSize: this.plotMetaData.labelSize,
      onInput: (value) => {
        this.plotMetaData.labelSize = value;
        this.showCatLabel();
      },
      onInit: () => {
        this.scheduleLabelRedraw("panel_0");
      },
    });
  }

  static fillLabelCanvas(
    labelCoordinates,
    textCanvas,
    baseFontSize,
    xScale,
    yScale,
  ) {
    // https://github.com/flekschas/regl-scatterplot/blob/master/example/text-labels.js#L128
    // here labelCoordinates was calculated by original point data
    //
    const ctx = textCanvas.getContext("2d");
    ctx.clearRect(0, 0, textCanvas.width, textCanvas.height);
    ctx.fillStyle = "rgba(0, 0, 0, 1)";
    //const baseFontSize = 20;

    ctx.font = `700 ${baseFontSize * window.devicePixelRatio}px Arial, Helvetica, sans-serif`;
    ctx.textAlign = "center";
    // add shadow
    ctx.shadowOffsetX = 3;
    ctx.shadowOffsetY = 3;
    ctx.shadowColor = "rgba(0,0,0,0.3)";
    ctx.shadowBlur = 4;
    const dpr = window.devicePixelRatio;

    for (let i = 0; i < labelCoordinates.length; i++) {
      const x = labelCoordinates[i].x;
      const y = labelCoordinates[i].y;
      ctx.fillText(
        labelCoordinates[i].label,
        xScale(x) * dpr,
        yScale(y) * dpr,
        // if use on single points, add a little adjustment
        //yScale(y) * dpr - baseFontSize * 1.2 * dpr
      );
    }
  }

  computeViewRectsForPanels(panelEls, containerWidth, containerHeight) {
    const nPanels = Math.max(1, panelEls.length);
    const nCols = nPanels >= 2 ? 2 : 1;
    const nRows = Math.ceil(nPanels / nCols);
    const fallbackPanelWidth = Math.max(1, containerWidth / nCols);
    const fallbackPanelHeight = Math.max(1, containerHeight / nRows);
    return getPanelViewRects({
      panelEls,
      nCols,
      nRows,
      fallbackPanelWidth,
      fallbackPanelHeight,
    });
  }

  buildViewsFromRects(viewRects) {
    return viewRects.map((r) => {
      this.viewStates[r.viewId] = this.computeViewStateForPanel(
        r.panelIdx,
        r.width,
        r.height,
      );
      this.lastZoomByView[r.viewId] = this.viewStates[r.viewId].zoom;
      return new OrthographicView({
        id: r.viewId,
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height,
        controller: true,
      });
    });
  }

  scheduleRelayoutRetry() {
    if (!this.relayoutTimer) {
      this.relayoutTimer = window.setTimeout(() => {
        this.relayoutTimer = null;
        this.relayoutDeck();
      }, 120);
    }
  }

  createDeck() {
    const deckContainer = this.plotEl.querySelector("#deck-container");
    if (!deckContainer) {
      return;
    }
    if (deckContainer.clientWidth < 10 || deckContainer.clientHeight < 10) {
      return;
    }
    const panelEls = Array.from(this.plotEl.querySelectorAll(".deck-panel"));
    const containerWidth = Math.max(
      1,
      Number.parseFloat(deckContainer.style.width) || deckContainer.clientWidth,
    );
    const containerHeight = Math.max(
      1,
      Number.parseFloat(deckContainer.style.height) || deckContainer.clientHeight,
    );

    this.panelBuffers = this.buildPanelBuffers();
    this.globalBounds = getGlobalBoundsFromPanels(this.panelBuffers);

    const viewRects = this.computeViewRectsForPanels(
      panelEls,
      containerWidth,
      containerHeight,
    );
    const views = this.buildViewsFromRects(viewRects);

    this.deck = this.renderer.create({
      parent: deckContainer,
      width: "100%",
      height: "100%",
      views,
      viewState: this.viewStates,
      controller: {
        doubleClickZoom: false,
        scrollZoom: true,
      },
      getCursor: () => "default",
      layers: this.createAllLayers(),
      glOptions: { preserveDrawingBuffer: true },
      onViewStateChange: (args) => this.handleDeckViewStateChange(args),
      onHover: (info) => this.handleHover(info),
      layerFilter: panelLayerFilter,
      onLoad: () => this.handleDeckOnLoad(),
    });
    this.setupLassoBinding(deckContainer);
    this.setupDoubleClickDeselect(deckContainer);
  }

  handleDeckViewStateChange({ viewId, viewState, interactionState }) {
    if (!viewId) {
      return;
    }
    const prevState = this.viewStates[viewId] || viewState;
    const prevZoom = this.lastZoomByView[viewId] ?? prevState.zoom;
    const { next: adjustedViewState, shouldApply } = resolveViewStateUpdate({
      prevState,
      nextState: viewState,
      interactionState,
      isRelayouting: this.isRelayouting,
      zoomSensitivity: this.zoomSensitivity,
    });

    if (!shouldApply) {
      return prevState;
    }

    this.viewStates[viewId] = adjustedViewState;
    this.deck.setProps({ viewState: { ...this.viewStates } });
    this.scheduleLabelRedraw(viewId);

    if (
      !this.isResizeBlank &&
      this.hoveredPoint &&
      `panel_${this.hoveredPoint.panelIdx}` === viewId
    ) {
      const pointIdx = this.hoveredPoint.pointIdx;
      const target = this.collectHoverCrosshairTarget(
        this.hoveredPoint.panelIdx,
        pointIdx,
      );
      this.clearHoverCrosshair();
      this.drawHoverCrosshair(target);
    }

    if (Math.abs(adjustedViewState.zoom - prevZoom) > 0.03) {
      this.lastZoomByView[viewId] = adjustedViewState.zoom;
      this.updateLayersDebounced();
    }

    return adjustedViewState;
  }

  handleDeckOnLoad() {
    // Wait until deck canvas and panel viewports settle, then render labels.
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        this.showCatLabel();
        this.setPanelOverlayVisibility(true);
        if (this.initialLayoutPending) {
          this.plotEl.style.opacity = "1";
          this.initialLayoutPending = false;
        }
        this.lifecycle.setReady();
        this.allowResizeBlank = true;
      });
    });
  }

  setupLassoBinding(deckContainer) {
    const lassoCanvas = this.plotEl.querySelector("#lasso-overlay");
    this.interactions.destroyLasso();
    this.lassoTool = null;
    if (this.mountTimer) {
      window.clearTimeout(this.mountTimer);
      this.mountTimer = null;
    }
    if (!lassoCanvas) {
      return;
    }
    this.lassoTool = this.interactions.bindLasso({
      container: deckContainer,
      overlayCanvas: lassoCanvas,
      getViewports: () => (this.deck ? this.deck.getViewports() : []),
      getPanelPositions: (panelIdx) => this.panelBuffers[panelIdx]?.positions,
      onSelect: (viewId, indices) => this.handleLassoSelect(viewId, indices),
      onDeselect: () => this.handleLassoDeselect(),
    });
  }

  setupDoubleClickDeselect(deckContainer) {
    if (this.onPanelDoubleClick) {
      deckContainer.removeEventListener("dblclick", this.onPanelDoubleClick);
    }
    this.onPanelDoubleClick = (event) => {
      event.preventDefault();
      this.deselectAll();
    };
    deckContainer.addEventListener("dblclick", this.onPanelDoubleClick);
  }

  computeViewStateForPanel(panelIdx, panelWidth, panelHeight) {
    const viewId = `panel_${panelIdx}`;
    const bounds = this.globalBounds || getGlobalBoundsFromPanels(this.panelBuffers);
    const viewState = computeViewStateFromBounds({
      bounds,
      panelWidth,
      panelHeight,
      padding: 0.92,
      minZoom: -10,
      maxZoom: 30,
    });
    this.baseZoomByView[viewId] = viewState.baseZoom;
    return {
      target: viewState.target,
      zoom: viewState.zoom,
      minZoom: viewState.minZoom,
      maxZoom: viewState.maxZoom,
    };
  }

  getPointOptions(nPoints) {
    let opacity = 0.6;
    let pointSize = 2;
    let pickable = true;
    if (nPoints < 15000) {
      opacity = 0.8;
      pointSize = 4;
    } else if (nPoints < 50000) {
      opacity = 0.7;
      pointSize = 3;
    } else if (nPoints < 500000) {
      opacity = 0.6;
      pointSize = 2;
    } else if (nPoints < 1000000) {
      opacity = 0.5;
      pointSize = 1;
    } else if (nPoints < 2000000) {
      opacity = 0.4;
      pointSize = 0.5;
    } else {
      opacity = 0.2;
      pointSize = 0.2;
      // Picking gets expensive at extreme scales.
      pickable = false;
    }
    return { opacity, pointSize, pickable };
  }

  buildPanelBuffers() {
    return this.plotData.pointsData.map((pointsData, i) => {
      const nPoints = pointsData.x.length;
      const { opacity, pointSize, pickable } = this.getPointOptions(nPoints);
      const alpha = Math.round(opacity * 255);
      const positions = new Float32Array(nPoints * 2);
      const colors = new Uint8Array(nPoints * 4);
      const zType = this.plotData.zType[i];
      const panelColorData = this.plotData.colorData[i] || [];

      // Precompute RGB palette once per panel to avoid per-point color parsing.
      const rgbPalette = panelColorData.map((hex) => {
        const rgb = d3.color(hex);
        return [rgb?.r ?? 128, rgb?.g ?? 128, rgb?.b ?? 128];
      });
      const paletteMax = Math.max(0, rgbPalette.length - 1);

      for (let j = 0; j < nPoints; j++) {
        positions[j * 2] = pointsData.x[j];
        positions[j * 2 + 1] = -pointsData.y[j];

        let rgb = [128, 128, 128];
        if (zType === "category") {
          const idx = pointsData.z[j];
          rgb = rgbPalette[idx] || rgb;
        } else if (paletteMax > 0) {
          const t = Math.min(1, Math.max(0, Number(pointsData.z[j]) || 0));
          const idx = Math.min(paletteMax, Math.round(t * paletteMax));
          rgb = rgbPalette[idx] || rgb;
        }

        colors[j * 4] = rgb[0];
        colors[j * 4 + 1] = rgb[1];
        colors[j * 4 + 2] = rgb[2];
        colors[j * 4 + 3] = alpha;
      }

      return {
        positions,
        colors,
        baseColors: new Uint8Array(colors),
        pointSize,
        opacity,
        pickable,
        nPoints,
      };
    });
  }

  getPointHexColor(panelIdx, zValue, zType) {
    if (zType === "category") {
      return this.plotData.colorData[panelIdx][zValue] ?? "#808080";
    }

    // Match regl-scatterplot behavior by indexing the precomputed 51-color map.
    const exprColorMap = this.plotData.colorData[panelIdx] || [];
    if (exprColorMap.length > 0) {
      const t = Math.min(1, Math.max(0, Number(zValue) || 0));
      const idx = Math.min(exprColorMap.length - 1, Math.round(t * (exprColorMap.length - 1)));
      return exprColorMap[idx] ?? "#808080";
    }
    return "#808080";
  }

  getPointScale(viewId) {
    const currentZoom = this.viewStates[viewId]?.zoom ?? this.baseZoomByView[viewId] ?? 0;
    const baseZoom = this.baseZoomByView[viewId] ?? currentZoom;
    const zoomDelta = currentZoom - baseZoom;
    const scaling = Math.pow(2, zoomDelta);
    if (scaling >= 1) {
      return Math.asinh(scaling) / Math.asinh(1);
    }
    return Math.max(0.1, scaling);
  }

  estimateVisiblePointCount(nPoints, viewId) {
    const currentZoom = this.viewStates[viewId]?.zoom ?? this.baseZoomByView[viewId] ?? 0;
    const baseZoom = this.baseZoomByView[viewId] ?? currentZoom;
    const zoomDelta = currentZoom - baseZoom;
    const scale = Math.pow(2, zoomDelta);
    // Approximate visible fraction in 2D as inverse area scale.
    const visibleFraction = 1 / Math.max(1, scale * scale);
    return nPoints * visibleFraction;
  }

  shouldEnablePicking(panel, viewId) {
    // Keep previous behavior for small/medium datasets.
    if (panel.pickable) {
      return true;
    }
    // For very large datasets, re-enable picking only when zoomed in enough
    // that the estimated visible points are manageable.
    const estimatedVisible = this.estimateVisiblePointCount(panel.nPoints, viewId);
    return estimatedVisible <= 250000;
  }

  createAllLayers() {
    const layers = [];
    this.panelBuffers.forEach((panel, i) => {
      const viewId = `panel_${i}`;
      const radiusPixels = Math.max(0.1, (panel.pointSize / 2) * this.getPointScale(viewId));
      layers.push(
        new ScatterplotLayer({
          id: `${viewId}_base`,
          panelViewId: viewId,
          data: {
            length: panel.nPoints,
            attributes: {
              getPosition: { value: panel.positions, size: 2 },
              getFillColor: { value: panel.colors, size: 4 },
            },
          },
          getRadius: radiusPixels,
          coordinateSystem: COORDINATE_SYSTEM.CARTESIAN,
          radiusUnits: "pixels",
          radiusMinPixels: 0.1,
          radiusMaxPixels: 100,
          stroked: false,
          pickable: this.shouldEnablePicking(panel, viewId),
          autoHighlight: false,
          updateTriggers: {
            getRadius: [radiusPixels],
          },
        }),
      );

      const selectedIndices = this.highlightByPanel?.[i] || [];
      if (selectedIndices.length > 0) {
        const highlightLayers = this.createHighlightLayers(
          viewId,
          panel,
          selectedIndices,
          radiusPixels,
        );
        layers.push(...highlightLayers);
      }

      if (this.hoveredPoint && this.hoveredPoint.panelIdx === i) {
        const hoverLayers = this.createHighlightLayers(
          viewId,
          panel,
          [this.hoveredPoint.pointIdx],
          radiusPixels,
          "hover",
        );
        layers.push(...hoverLayers);
      }
    });
    return layers;
  }

  createHighlightLayers(
    viewId,
    panel,
    selectedIndices,
    radiusPixels,
    layerPrefix = "highlight",
  ) {
    const n = selectedIndices.length;
    const highlightedPositions = new Float32Array(n * 2);
    const highlightedColors = new Uint8Array(n * 4);
    for (let i = 0; i < n; i++) {
      const idx = selectedIndices[i];
      highlightedPositions[i * 2] = panel.positions[idx * 2];
      highlightedPositions[i * 2 + 1] = panel.positions[idx * 2 + 1];
      highlightedColors[i * 4] = panel.baseColors[idx * 4];
      highlightedColors[i * 4 + 1] = panel.baseColors[idx * 4 + 1];
      highlightedColors[i * 4 + 2] = panel.baseColors[idx * 4 + 2];
      highlightedColors[i * 4 + 3] = 255;
    }

    const bgColor = [26, 26, 46, 255];
    const common = {
      coordinateSystem: COORDINATE_SYSTEM.CARTESIAN,
      radiusUnits: "pixels",
      radiusMinPixels: 0.1,
      radiusMaxPixels: 100,
      stroked: false,
      pickable: false,
    };

    return [
      new ScatterplotLayer({
        id: `${viewId}_${layerPrefix}_outer`,
        panelViewId: viewId,
        data: {
          length: n,
          attributes: {
            getPosition: { value: highlightedPositions, size: 2 },
            getFillColor: { value: highlightedColors, size: 4 },
          },
        },
        getRadius: radiusPixels + 3,
        ...common,
      }),
      new ScatterplotLayer({
        id: `${viewId}_${layerPrefix}_inner`,
        panelViewId: viewId,
        data: {
          length: n,
          attributes: {
            getPosition: { value: highlightedPositions, size: 2 },
          },
        },
        getFillColor: bgColor,
        getRadius: radiusPixels + 2,
        ...common,
      }),
      new ScatterplotLayer({
        id: `${viewId}_${layerPrefix}_body`,
        panelViewId: viewId,
        data: {
          length: n,
          attributes: {
            getPosition: { value: highlightedPositions, size: 2 },
            getFillColor: { value: highlightedColors, size: 4 },
          },
        },
        getRadius: radiusPixels + 1,
        ...common,
      }),
    ];
  }

  handleHover(info) {
    if (!this.noteId) {
      return;
    }
    if (!this.lifecycle.isReady()) {
      this.clearHoverCrosshair();
      return;
    }
    if (this.isResizeBlank) {
      this.clearHoverCrosshair();
      return;
    }
    if (!info?.picked) {
      if (this.hoveredPoint) {
        this.hoveredPoint = null;
        this.lastHoverKey = null;
        if (this.deck) {
          this.deck.setProps({ layers: this.createAllLayers() });
        }
      }
      this.clearHoverCrosshair();
      reglScatterCanvas.hideNote(this.noteId);
      return;
    }
    const panelIdx = this.getPanelIndexFromPickInfo(info);
    if (!Number.isFinite(panelIdx) || info.index == null || info.index < 0) {
      this.clearHoverCrosshair();
      reglScatterCanvas.hideNote(this.noteId);
      return;
    }

    const hoverKey = `${panelIdx}:${info.index}`;
    if (this.lastHoverKey !== hoverKey) {
      this.hoveredPoint = { panelIdx, pointIdx: info.index };
      this.lastHoverKey = hoverKey;
      if (this.deck) {
        this.deck.setProps({ layers: this.createAllLayers() });
      }
    }

    const panel = this.panelBuffers[panelIdx];
    if (panel) {
      const targets = this.collectHoverCrosshairTarget(panelIdx, info.index);
      this.clearHoverCrosshair();
      this.drawHoverCrosshair(targets);
    }

    const text = this.generateNoteText(panelIdx, info.index);
    if (this.plotData.zType[panelIdx] === "category") {
      const color = this.plotData.colorData[panelIdx][this.plotData.pointsData[panelIdx].z[info.index]];
      reglScatterCanvas.showNote(this.noteId, text, color);
    } else {
      const color = this.getPointHexColor(
        panelIdx,
        this.plotData.pointsData[panelIdx].z[info.index],
        "expr",
      );
      reglScatterCanvas.showNote(this.noteId, text, color);
    }
  }

  getPanelIndexFromPickInfo(info) {
    return parsePanelIndexFromPickInfo(info);
  }

  applyHighlight() {
    if (!this.highlightByPanel) {
      return;
    }
    this.panelBuffers.forEach((panel, panelIdx) => {
      panel.colors.set(panel.baseColors);
      const selected = new Set(this.highlightByPanel[panelIdx] || []);
      for (let i = 0; i < panel.nPoints; i++) {
        const alphaIdx = i * 4 + 3;
        // Keep non-selected points at their original opacity.
        // Only selected points become transparent in base layer,
        // then they are re-drawn with highlight layers on top.
        panel.colors[alphaIdx] = selected.has(i)
          ? 0
          : panel.baseColors[alphaIdx];
      }
    });
    if (this.deck) {
      this.deck.setProps({ layers: this.createAllLayers() });
    }
  }

  clearHighlight() {
    this.highlightByPanel = null;
    this.panelBuffers.forEach((panel) => {
      panel.colors.set(panel.baseColors);
    });
    if (this.deck) {
      this.deck.setProps({ layers: this.createAllLayers() });
    }
  }

  setSelectionHandlers({ onSelect = null, onDeselect = null } = {}) {
    this.selectionHandlers = { onSelect, onDeselect };
  }

  handleLassoSelect(viewId, indices) {
    const panelIdx = Number.parseInt(String(viewId).replace("panel_", ""), 10);
    if (!Number.isFinite(panelIdx) || !Array.isArray(indices)) {
      return;
    }
    const panelCells = this.plotData.cells[panelIdx] || [];
    const selectedCells = indices.map((idx) => panelCells[idx]).filter((v) => v !== undefined);
    this.plotData.selectedCells = selectedCells;
    this.highlightByPanel = this.panelBuffers.map((_, i) => (i === panelIdx ? indices : []));
    this.applyHighlight();
    if (this.selectionHandlers.onSelect) {
      this.selectionHandlers.onSelect({ panelIdx, indices, selectedCells });
    }
  }

  handleLassoDeselect() {
    this.plotData.selectedCells = [];
    this.clearHighlight();
    if (this.selectionHandlers.onDeselect) {
      this.selectionHandlers.onDeselect();
    }
  }

  deselectAll() {
    this.interactions.clearLasso();
    this.handleLassoDeselect();
    this.clearHighlight();
  }

  debounce(fn, delay) {
    let timeoutId;
    return (...args) => {
      clearTimeout(timeoutId);
      timeoutId = setTimeout(() => fn(...args), delay);
    };
  }

  generateNoteText(spIndex, pointId) {
    const mode = this.plotMetaData.mode;
    const group_by = this.plotMetaData.group_by;
    const split_by = this.plotMetaData.split_by;
    const metaData = this.origData.cellMetaData;
    const expressionData = this.origData.expressionData;
    const plotFeature = this.plotData.plotFeature;

    const groupByArray = group_by ? expandMeta(metaData[group_by]) : [];
    const splitByArray = split_by ? expandMeta(metaData[split_by]) : [];
    const exprValues = plotFeature ? expressionData[plotFeature] : [];

    return buildHoverText({
      mode,
      panelIndex: spIndex,
      pointIndex: pointId,
      groupByValues: groupByArray,
      splitByValues: splitByArray,
      expressionValues: exprValues,
      splitArrByMeta,
      formatExpr: (v) => d3.format(".3f")(v),
    });
  }

  createNote(noteId) {
    createNoteElement(this.plotEl, noteId);
  }

  // note manipulation to mimic tooltips
  static showNote(noteId, text, color) {
    showNoteElement(noteId, text, color);
  }

  static hideNote(noteId) {
    hideNoteElement(noteId);
  }

  createInfoWidget(infoId) {
    createInfoWidgetElement({ plotEl: this.plotEl, id: infoId });
  }

  createDownloadIcon(elId) {
    createDownloadIconElement({
      plotEl: this.plotEl,
      id: elId,
      catLegendEl: this.catLegendEl,
      expLegendEl: this.expLegendEl,
    });
  }

  updateCatLegend() {
    //const pointData_z = this.plotData["pointsData"].map((e) => e.z);
    const groupByArray = this.plotMetaData.group_by
      ? expandMeta(this.origData.cellMetaData[this.plotMetaData.group_by])
      : [];

    const splitByArray = this.plotMetaData.split_by
      ? expandMeta(this.origData.cellMetaData[this.plotMetaData.split_by])
      : [];
    // Add cluster legends, no legend for "cluster+expr+multiSplit" mode
    if (this.plotMetaData.mode != "cluster+expr+multiSplit") {
      let catTitles = [...new Set(groupByArray)].sort(sortStringArray);
      let catNumbers = catTitles.map((e, i) => {
        let counts = 0;
        groupByArray.forEach((d) => {
          if (d == e) {
            counts++;
          }
        });
        return counts;
      });
      this.plotMetaData.catColors.forEach((e, i) => {
        let legendEl = this.constructor.createLegendEl(
          catTitles[i],
          e,
          catNumbers[i],
        );

        // Add hover events
        // note do not use mouseover and mouseout event
        legendEl.onmouseenter = (event) => {
          event.target.style.borderColor = "black";
          event.target.style.borderWidth = "2px";
          let pointsIndex = this.highlight_index(catTitles[i]);
          this.highlightByPanel = pointsIndex;
          this.applyHighlight();
        };
        legendEl.onmouseleave = (event) => {
          event.target.style.borderColor = "#D3D3D3";
          event.target.style.borderWidth = "1px";
          this.clearHighlight();
        };
        this.catLegendEl.appendChild(legendEl);
      });
    }
  }

  updateExpLegend() {
    // Add expression legend element
    if (
      this.plotMetaData.mode === "cluster+expr+noSplit" ||
      this.plotMetaData.mode === "cluster+expr+twoSplit" ||
      this.plotMetaData.mode === "cluster+expr+multiSplit"
    ) {
      const exprArray =
        this.origData.expressionData[this.plotMetaData.selectedFeatures];
      const exprLegendColor = d3.scaleSequential(
        [d3.min(exprArray), d3.max(exprArray)],
        d3.interpolate("#E5E4E2", "#800080"),
      );
      const exprLegendTitle = this.plotMetaData.moduleScore
        ? "ModuleScore"
        : "Expresson";
      const exprLegend = Legend(exprLegendColor, {
        title: exprLegendTitle,
        width: 200,
      });
      this.expLegendEl.appendChild(exprLegend);
    }
  }

  static createLegendEl(title, color, number) {
    return createLegendEntryElement(title, color, number);
  }

  static findIndexes(arr, value) {
    return findLegendIndexes(arr, value);
  }

  highlight_index(selectedGroupBy) {
    const mode = this.plotMetaData.mode;
    const group_by = this.plotMetaData.group_by;
    const groupByValues = expandMeta(this.origData.cellMetaData[group_by]);
    return computeHighlightIndices({
      mode,
      pointsData: this.plotData.pointsData,
      groupByValues,
      selectedGroupBy,
      sortStringArray,
    });
  }
}

export const splitArrByMeta = (Arr, meta) => {
  // split array (reduciton x,y etc.) by meta inforamtion
  // Arr should be reduction.x or reduction.y, which is a numeric array
  // Arr could also be "group_by" stringArray
  let splitOut = {};
  if (Arr != null && Arr.length == meta.length) {
    let meta_levels = [...new Set(meta)].sort(sortStringArray);
    // split meta to object
    // for loop is faster than forEach(), reduce()
    for (const element of meta_levels) {
      splitOut[element] = [];
      for (let i = 0; i < meta.length; ++i) {
        if (meta[i] === element) {
          splitOut[element].push(Arr[i]);
        }
      }
      if (Arr instanceof Int32Array) {
        splitOut[element] = new Int32Array(splitOut[element]);
      } else if (Arr instanceof Float32Array) {
        splitOut[element] = new Float32Array(splitOut[element]);
      } else if (Arr instanceof Int16Array) {
        splitOut[element] = new Int16Array(splitOut[element]);
      }
    }
  }
  return splitOut;
};

export const convert_stringArr_to_integer = (stringArray) => {
  let factorLevel = {};
  let uniqueArr = new Set(stringArray);
  let sortedUniqueArr = Array.from(uniqueArr).sort(sortStringArray);
  sortedUniqueArr.forEach((e, i) => {
    factorLevel[e] = i;
  });
  let integerArray = stringArray.map((e) => factorLevel[e]);
  return new Int16Array(integerArray);
};

export const rgbToHex = (rgbString) => {
  // Convert rgb color string to hex format
  // Split the RGB string into individual values
  var rgbArray = rgbString
    .substring(4, rgbString.length - 1)
    .split(",")
    .map(function (num) {
      return parseInt(num);
    });

  // Convert the individual RGB values to hex
  var hex =
    "#" +
    rgbArray
      .map(function (num) {
        var hexValue = num.toString(16);
        return hexValue.length === 1 ? "0" + hexValue : hexValue;
      })
      .join("");

  return hex;
};

export const sortStringArray = (a, b) => {
  // Array sort function
  // input: ['1', '2', '10', 'apple', '5', 'orange']
  // output: ['1', '2', '5', '10', 'apple', 'orange']
  if (!isNaN(a) && !isNaN(b)) {
    return parseInt(a) - parseInt(b);
  } else if (!isNaN(a)) {
    return -1;
  } else if (!isNaN(b)) {
    return 1;
  } else {
    return a.localeCompare(b);
  }
};

// Copyright 2021, Observable Inc.
// Released under the ISC license.
// https://observablehq.com/@d3/color-legend
export function Legend(
  color,
  {
    title,
    tickSize = 6,
    width = 320,
    height = 44 + tickSize,
    marginTop = 18,
    marginRight = 0,
    marginBottom = 16 + tickSize,
    marginLeft = 0,
    ticks = width / 64,
    tickFormat,
    tickValues,
  } = {},
) {
  function ramp(color, n = 256) {
    const canvas = document.createElement("canvas");
    canvas.width = n;
    canvas.height = 1;
    const context = canvas.getContext("2d");
    for (let i = 0; i < n; ++i) {
      context.fillStyle = color(i / (n - 1));
      context.fillRect(i, 0, 1, 1);
    }
    return canvas;
  }

  const svg = d3
    .create("svg")
    .attr("width", width)
    .attr("height", height)
    .attr("viewBox", [0, 0, width, height])
    .style("overflow", "visible")
    .style("display", "block");

  let tickAdjust = (g) =>
    g.selectAll(".tick line").attr("y1", marginTop + marginBottom - height);
  let x;

  // Continuous
  if (color.interpolate) {
    const n = Math.min(color.domain().length, color.range().length);

    x = color
      .copy()
      .rangeRound(
        d3.quantize(d3.interpolate(marginLeft, width - marginRight), n),
      );

    svg
      .append("image")
      .attr("x", marginLeft)
      .attr("y", marginTop)
      .attr("width", width - marginLeft - marginRight)
      .attr("height", height - marginTop - marginBottom)
      .attr("preserveAspectRatio", "none")
      .attr(
        "xlink:href",
        ramp(
          color.copy().domain(d3.quantize(d3.interpolate(0, 1), n)),
        ).toDataURL(),
      );
  }

  // Sequential
  else if (color.interpolator) {
    x = Object.assign(
      color
        .copy()
        .interpolator(d3.interpolateRound(marginLeft, width - marginRight)),
      {
        range() {
          return [marginLeft, width - marginRight];
        },
      },
    );

    svg
      .append("image")
      .attr("x", marginLeft)
      .attr("y", marginTop)
      .attr("width", width - marginLeft - marginRight)
      .attr("height", height - marginTop - marginBottom)
      .attr("preserveAspectRatio", "none")
      .attr("xlink:href", ramp(color.interpolator()).toDataURL());

    // scaleSequentialQuantile doesn’t implement ticks or tickFormat.
    if (!x.ticks) {
      if (tickValues === undefined) {
        const n = Math.round(ticks + 1);
        tickValues = d3
          .range(n)
          .map((i) => d3.quantile(color.domain(), i / (n - 1)));
      }
      if (typeof tickFormat !== "function") {
        tickFormat = d3.format(tickFormat === undefined ? ",f" : tickFormat);
      }
    }
  }

  // Threshold
  else if (color.invertExtent) {
    const thresholds = color.thresholds
      ? color.thresholds() // scaleQuantize
      : color.quantiles
        ? color.quantiles() // scaleQuantile
        : color.domain(); // scaleThreshold

    const thresholdFormat =
      tickFormat === undefined
        ? (d) => d
        : typeof tickFormat === "string"
          ? d3.format(tickFormat)
          : tickFormat;

    x = d3
      .scaleLinear()
      .domain([-1, color.range().length - 1])
      .rangeRound([marginLeft, width - marginRight]);

    svg
      .append("g")
      .selectAll("rect")
      .data(color.range())
      .join("rect")
      .attr("x", (d, i) => x(i - 1))
      .attr("y", marginTop)
      .attr("width", (d, i) => x(i) - x(i - 1))
      .attr("height", height - marginTop - marginBottom)
      .attr("fill", (d) => d);

    tickValues = d3.range(thresholds.length);
    tickFormat = (i) => thresholdFormat(thresholds[i], i);
  }

  // Ordinal
  else {
    x = d3
      .scaleBand()
      .domain(color.domain())
      .rangeRound([marginLeft, width - marginRight]);

    svg
      .append("g")
      .selectAll("rect")
      .data(color.domain())
      .join("rect")
      .attr("x", x)
      .attr("y", marginTop)
      .attr("width", Math.max(0, x.bandwidth() - 1))
      .attr("height", height - marginTop - marginBottom)
      .attr("fill", color);

    tickAdjust = () => {};
  }

  svg
    .append("g")
    .attr("transform", `translate(0,${height - marginBottom})`)
    .call(
      d3
        .axisBottom(x)
        .ticks(ticks, typeof tickFormat === "string" ? tickFormat : undefined)
        .tickFormat(typeof tickFormat === "function" ? tickFormat : undefined)
        .tickSize(tickSize)
        .tickValues(tickValues),
    )
    .call(tickAdjust)
    .call((g) => g.select(".domain").remove())
    .call((g) =>
      g
        .append("text")
        .attr("x", marginLeft)
        .attr("y", marginTop + marginBottom - height - 6)
        .attr("fill", "currentColor")
        .attr("text-anchor", "start")
        .attr("font-weight", "bold")
        .attr("class", "title")
        .text(title),
    );

  return svg.node();
}

export function hue_pal(
  n = 15,
  h = [0 + 15, 360 + 15],
  c = 100,
  l = 65,
  hStart = 0,
  direction = 1,
) {
  // Input validation
  if (!Array.isArray(h) || h.length !== 2) {
    throw new Error("h must have length 2");
  }
  if (typeof l !== "number") {
    throw new Error("l must be a single number");
  }
  if (typeof c !== "number") {
    throw new Error("c must be a single number");
  }
  // Ensure n is a positive integer
  n = Math.max(1, Math.round(n));

  // Adjust hue range if too small
  if (Math.abs(h[1] - h[0]) % 360 < 1) {
    h[1] = h[1] - 360 / n;
  }

  // Generate hue sequence
  const step = (h[1] - h[0]) / (n - 1);
  const hues = d3.range(h[0], h[1] + step, step);
  // Apply hue start and modulo 360
  const adjustedHues = hues.map((hue) => (hue + hStart) % 360);
  let colors = adjustedHues.map((e) => d3.hcl(e, c, l).formatHex());

  return direction === -1 ? colors.reverse() : colors;
}

// Helper function to expand meta column data
export const expandMeta = (metaList) => {
  if (metaList.type === "number") {
    return metaList.value;
  } else if (metaList.type === "category") {
    const totalLength = Object.values(metaList.value).reduce(
      (sum, arr) => sum + arr.length,
      0,
    );
    let out = Array(totalLength).fill(null);
    Object.keys(metaList.value).forEach((key) => {
      metaList.value[key].forEach((e) => {
        out[e] = key;
      });
    });
    return out;
  } else {
    return null;
  }
};
