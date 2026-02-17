import { OrthographicView, COORDINATE_SYSTEM } from "@deck.gl/core";
import { ScatterplotLayer } from "@deck.gl/layers";
import * as d3 from "d3";
import html2canvas from "html2canvas";
import { ScatterModel } from "./scatter/scatterModel.js";
import { ScatterRenderer } from "./scatter/scatterRenderer.js";
import { ScatterOverlay } from "./scatter/scatterOverlay.js";
import { ScatterInteractions } from "./scatter/scatterInteractions.js";
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
    this.deck = null;
    this.viewStates = {};
    this.baseZoomByView = {};
    this.panelBuffers = [];
    this.globalBounds = null;
    this.scatterplots = [];
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
      if (this.allowResizeBlank && !this.initialLayoutPending) {
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
    console.log("plotMetaData: ", this.plotMetaData);
  }

  clear() {
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
    this.scatterplots = [];
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
    const deckContainer = this.plotEl.querySelector("#deck-container");
    if (deckContainer) {
      deckContainer.style.opacity = "0";
    }
    const crosshair = this.plotEl.querySelector("#crosshair-underlay");
    if (crosshair) {
      crosshair.style.opacity = "0";
    }
    this.clearHoverCrosshair();
    this.hoveredPoint = null;
    this.lastHoverKey = null;
    if (this.noteId) {
      reglScatterCanvas.hideNote(this.noteId);
    }
    const lasso = this.plotEl.querySelector("#lasso-overlay");
    if (lasso) {
      lasso.style.opacity = "0";
    }
    this.setPanelOverlayVisibility(false);
  }

  endResizeBlank() {
    if (!this.isResizeBlank) {
      return;
    }
    this.isResizeBlank = false;
    const deckContainer = this.plotEl.querySelector("#deck-container");
    if (deckContainer) {
      deckContainer.style.opacity = "1";
    }
    const crosshair = this.plotEl.querySelector("#crosshair-underlay");
    if (crosshair) {
      crosshair.style.opacity = "1";
    }
    const lasso = this.plotEl.querySelector("#lasso-overlay");
    if (lasso) {
      lasso.style.opacity = "1";
    }
    this.setPanelOverlayVisibility(true);
  }

  setLabelCanvasVisibility(isVisible) {
    const opacity = isVisible ? "1" : "0";
    this.plotEl.querySelectorAll(".label-canvas").forEach((canvas) => {
      canvas.style.opacity = opacity;
    });
  }

  setPanelOverlayVisibility(isVisible) {
    const opacity = isVisible ? "1" : "0";
    const grid = this.plotEl.querySelector(".deck-overlay-grid");
    if (grid) {
      grid.style.opacity = opacity;
    }
    this.plotEl.querySelectorAll(".mainClusterPlotTitle").forEach((title) => {
      title.style.opacity = opacity;
    });
    this.setLabelCanvasVisibility(isVisible);
  }

  relayoutDeck() {
    if (!this.deck) {
      return;
    }
    const deckContainer = this.plotEl.querySelector("#deck-container");
    this.updateSquarePanelLayout();
    if (!deckContainer || deckContainer.clientWidth < 10 || deckContainer.clientHeight < 10) {
      return;
    }
    const panelEls = Array.from(this.plotEl.querySelectorAll(".deck-panel"));
    const deckWidth = Math.max(
      1,
      Number.parseFloat(deckContainer.style.width) || deckContainer.clientWidth,
    );
    const deckHeight = Math.max(
      1,
      Number.parseFloat(deckContainer.style.height) || deckContainer.clientHeight,
    );
    if (!deckWidth || !deckHeight) {
      return;
    }
    const views = [];
    let invalidPanelSize = false;
    panelEls.forEach((panel, i) => {
      const panelWidth = Math.max(1, panel.clientWidth);
      const panelHeight = Math.max(1, panel.clientHeight);
      if (panelWidth < 10 || panelHeight < 10) {
        invalidPanelSize = true;
      }
      const viewId = `panel_${i}`;
      this.viewStates[viewId] = this.computeViewStateForPanel(
        i,
        panelWidth,
        panelHeight,
      );
      this.lastZoomByView[viewId] = this.viewStates[viewId].zoom;

      views.push(
        new OrthographicView({
          id: viewId,
          x: Math.max(0, panel.offsetLeft),
          y: Math.max(0, panel.offsetTop),
          width: panelWidth,
          height: panelHeight,
          controller: true,
        }),
      );
    });
    if (invalidPanelSize) {
      if (!this.relayoutTimer) {
        this.relayoutTimer = window.setTimeout(() => {
          this.relayoutTimer = null;
          this.relayoutDeck();
        }, 120);
      }
      return;
    }
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

  updateCanvas() {
    // Avoid visible "snap" when multi-panel layout settles from pre-mount to
    // viewport-sized dimensions.
    this.initialLayoutPending = this.plotMetaData.nPanels > 1;
    this.plotEl.style.opacity = this.initialLayoutPending ? "0" : "1";

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

    // keep compatibility with existing index.js usage
    this.scatterplots = [];
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

    const minPanelSize = 400;
    const nPanels = Math.max(1, this.plotMetaData.nPanels || 1);
    const nCols = nPanels >= 2 ? 2 : 1;
    const nRows = Math.ceil(nPanels / nCols);
    const panels = Array.from(overlayGrid.querySelectorAll(".deck-panel"));

    const styles = window.getComputedStyle(overlayGrid);
    const gap = Number.parseFloat(styles.columnGap || styles.gap || "0") || 0;
    const containerWidth = Math.max(1, canvasContainer.clientWidth);

    // Required rule:
    // - If viewport is wide enough for 2 * min panel width, each panel uses 1/2 viewport width
    // - Otherwise each panel uses min width (scroll enabled by container overflow)
    const halfViewportWidth = (containerWidth - gap * (nCols - 1)) / nCols;
    const panelWidth = halfViewportWidth >= minPanelSize ? Math.floor(halfViewportWidth) : minPanelSize;
    // For 1-2 panels, prioritize full viewport usage (no square constraint).
    if (nPanels <= 2) {
      const contentWidth = nCols * panelWidth + gap * (nCols - 1);
      const contentHeight = Math.max(minPanelSize, canvasContainer.clientHeight);
      overlayGrid.style.gridTemplateColumns = `repeat(${nCols}, ${panelWidth}px)`;
      overlayGrid.style.gridTemplateRows = `repeat(${nRows}, minmax(${minPanelSize}px, 1fr))`;
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
        panel.style.aspectRatio = "auto";
      });
      return;
    }

    // For multi-row layouts (>2 panels), enforce square panels.
    const panelSize = panelWidth;
    overlayGrid.style.gridTemplateColumns = `repeat(${nCols}, ${panelSize}px)`;
    overlayGrid.style.gridTemplateRows = `repeat(${nRows}, ${panelSize}px)`;
    const contentWidth = nCols * panelSize + gap * (nCols - 1);
    const contentHeight = nRows * panelSize + gap * (nRows - 1);
    overlayGrid.style.width = `${contentWidth}px`;
    overlayGrid.style.height = `${contentHeight}px`;
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
      panel.style.aspectRatio = "1 / 1";
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
      const xScale = (x) => this.projectToPanel(viewport, x, 0)[0];
      const yScale = (y) => this.projectToPanel(viewport, 0, -y)[1];
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
    const canvasPos = this.projectToCanvas(viewport, target.worldX, target.worldY);
    ScatterOverlay.drawCrosshair(canvas, {
      x: canvasPos[0],
      y: canvasPos[1],
      left: viewport.x,
      top: viewport.y,
      right: viewport.x + viewport.width,
      bottom: viewport.y + viewport.height,
    });
  }

  projectToPanel(viewport, worldX, worldY) {
    const [px, py] = viewport.project([worldX, worldY]);
    const appearsLocal =
      px >= -1 && px <= viewport.width + 1 && py >= -1 && py <= viewport.height + 1;
    if (appearsLocal) {
      return [px, py];
    }
    return [px - viewport.x, py - viewport.y];
  }

  projectToCanvas(viewport, worldX, worldY) {
    const [px, py] = viewport.project([worldX, worldY]);
    const appearsLocal =
      px >= -1 && px <= viewport.width + 1 && py >= -1 && py <= viewport.height + 1;
    if (appearsLocal) {
      return [px + viewport.x, py + viewport.y];
    }
    return [px, py];
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
    const slider = document.createElement("div");
    slider.id = ElId;
    slider.classList.add("label-slider");
    slider.style.position = "absolute";
    slider.style.zIndex = "30";
    slider.style.pointerEvents = "auto";
    const sliderInput = document.createElement("input");
    sliderInput.type = "range";
    sliderInput.value = this.plotMetaData.labelSize;
    sliderInput.min = 0;
    sliderInput.max = 50;
    sliderInput.style.opacity = 0.6;
    sliderInput.style.width = "6rem";
    slider.appendChild(sliderInput);

    sliderInput.addEventListener("mouseover", () => {
      sliderInput.style.opacity = 0.8;
    });
    sliderInput.addEventListener("mouseout", () => {
      sliderInput.style.opacity = 0.6;
    });
    // Add Eventlistener
    sliderInput.addEventListener("input", (event) => {
      this.plotMetaData.labelSize = event.target.value;
      this.showCatLabel();
    });

    this.plotEl.appendChild(slider);

    // Ensure labels are drawn with the initial slider value on first render.
    this.scheduleLabelRedraw("panel_0");
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

  createDeck() {
    const deckContainer = this.plotEl.querySelector("#deck-container");
    if (!deckContainer) {
      return;
    }
    if (deckContainer.clientWidth < 10 || deckContainer.clientHeight < 10) {
      return;
    }
    const panelEls = Array.from(this.plotEl.querySelectorAll(".deck-panel"));
    const nPanels = Math.max(1, panelEls.length);
    const nCols = nPanels >= 2 ? 2 : 1;
    const nRows = Math.ceil(nPanels / nCols);
    const containerWidth = Math.max(
      1,
      Number.parseFloat(deckContainer.style.width) || deckContainer.clientWidth,
    );
    const containerHeight = Math.max(
      1,
      Number.parseFloat(deckContainer.style.height) || deckContainer.clientHeight,
    );
    const fallbackPanelWidth = Math.max(1, containerWidth / nCols);
    const fallbackPanelHeight = Math.max(1, containerHeight / nRows);

    this.panelBuffers = this.buildPanelBuffers();
    this.globalBounds = this.getGlobalBounds();

    const views = [];
    panelEls.forEach((panel, i) => {
      const panelWidth = Math.max(1, panel.clientWidth);
      const panelHeight = Math.max(1, panel.clientHeight);
      const hasPanelRect = panelWidth > 0 && panelHeight > 0;
      const row = Math.floor(i / nCols);
      const col = i % nCols;
      const x = hasPanelRect ? Math.max(0, panel.offsetLeft) : col * fallbackPanelWidth;
      const y = hasPanelRect ? Math.max(0, panel.offsetTop) : row * fallbackPanelHeight;
      const width = hasPanelRect ? panelWidth : fallbackPanelWidth;
      const height = hasPanelRect ? panelHeight : fallbackPanelHeight;
      const viewId = `panel_${i}`;
      views.push(
        new OrthographicView({
          id: viewId,
          x,
          y,
          width,
          height,
          controller: true,
        }),
      );
      this.viewStates[viewId] = this.computeViewStateForPanel(i, width, height);
      this.lastZoomByView[viewId] = this.viewStates[viewId].zoom;
    });

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
      onViewStateChange: ({ viewId, viewState, interactionState }) => {
        if (viewId) {
          const prevState = this.viewStates[viewId] || viewState;
          const prevZoom = this.lastZoomByView[viewId] ?? prevState.zoom;
          const isZooming = Boolean(interactionState && interactionState.isZooming);
          const isDragging = Boolean(
            interactionState && (interactionState.isDragging || interactionState.isPanning),
          );

          if (this.isRelayouting && !isZooming && !isDragging) {
            return prevState;
          }

          const adjustedViewState = { ...viewState };

          // Keep target stable unless user is actively panning.
          if (!isDragging) {
            adjustedViewState.target = prevState.target;
          }

          // Apply zoom damping only for active wheel-zoom interactions.
          if (isZooming) {
            const adjustedZoom =
              prevState.zoom + (viewState.zoom - prevState.zoom) * this.zoomSensitivity;
            adjustedViewState.zoom = Math.max(
              viewState.minZoom ?? -10,
              Math.min(viewState.maxZoom ?? 30, adjustedZoom),
            );
          } else {
            adjustedViewState.zoom = prevState.zoom;
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
            const targets = this.collectHoverCrosshairTarget(
              this.hoveredPoint.panelIdx,
              pointIdx,
            );
            this.clearHoverCrosshair();
            this.drawHoverCrosshair(targets);
          }
          if (Math.abs(adjustedViewState.zoom - prevZoom) > 0.03) {
            this.lastZoomByView[viewId] = adjustedViewState.zoom;
            this.updateLayersDebounced();
          }
        }
      },
      onHover: (info) => this.handleHover(info),
      // Render each panel layer only in its matching viewport.
      layerFilter: ({ layer, viewport }) => {
        if (!layer || !viewport) {
          return false;
        }
        if (!viewport.id) {
          return true;
        }
        if (layer.props && layer.props.panelViewId) {
          return layer.props.panelViewId === viewport.id;
        }
        const layerPanelId = layer.id.split("_").slice(0, 2).join("_");
        return layerPanelId === viewport.id;
      },
      onLoad: () => {
        // Wait until deck canvas and panel viewports settle, then render labels.
        window.requestAnimationFrame(() => {
          window.requestAnimationFrame(() => {
            this.showCatLabel();
            this.setPanelOverlayVisibility(true);
            if (this.initialLayoutPending) {
              this.plotEl.style.opacity = "1";
              this.initialLayoutPending = false;
            }
            this.allowResizeBlank = true;
          });
        });
      },
    });

    const lassoCanvas = this.plotEl.querySelector("#lasso-overlay");
    this.interactions.destroyLasso();
    this.lassoTool = null;
    if (this.mountTimer) {
      window.clearTimeout(this.mountTimer);
      this.mountTimer = null;
    }
    if (lassoCanvas) {
      this.lassoTool = this.interactions.bindLasso({
        container: deckContainer,
        overlayCanvas: lassoCanvas,
        getViewports: () => (this.deck ? this.deck.getViewports() : []),
        getPanelPositions: (panelIdx) => this.panelBuffers[panelIdx]?.positions,
        onSelect: (viewId, indices) => this.handleLassoSelect(viewId, indices),
        onDeselect: () => this.handleLassoDeselect(),
      });
    }

    if (this.onPanelDoubleClick) {
      deckContainer.removeEventListener("dblclick", this.onPanelDoubleClick);
    }
    this.onPanelDoubleClick = (event) => {
      event.preventDefault();
      this.deselectAll();
    };
    deckContainer.addEventListener("dblclick", this.onPanelDoubleClick);
  }

  getPanelBounds(positions) {
    if (!positions || positions.length < 2) {
      return { minX: -1, maxX: 1, minY: -1, maxY: 1 };
    }
    let minX = Infinity;
    let maxX = -Infinity;
    let minY = Infinity;
    let maxY = -Infinity;
    for (let i = 0; i < positions.length; i += 2) {
      const x = positions[i];
      const y = positions[i + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return { minX, maxX, minY, maxY };
  }

  getGlobalBounds() {
    if (!Array.isArray(this.panelBuffers) || this.panelBuffers.length === 0) {
      return { minX: -1, maxX: 1, minY: -1, maxY: 1 };
    }
    let minX = Infinity;
    let maxX = -Infinity;
    let minY = Infinity;
    let maxY = -Infinity;
    this.panelBuffers.forEach((panel) => {
      const bounds = this.getPanelBounds(panel?.positions);
      if (bounds.minX < minX) minX = bounds.minX;
      if (bounds.maxX > maxX) maxX = bounds.maxX;
      if (bounds.minY < minY) minY = bounds.minY;
      if (bounds.maxY > maxY) maxY = bounds.maxY;
    });
    if (!Number.isFinite(minX) || !Number.isFinite(maxX) || !Number.isFinite(minY) || !Number.isFinite(maxY)) {
      return { minX: -1, maxX: 1, minY: -1, maxY: 1 };
    }
    return { minX, maxX, minY, maxY };
  }

  computeViewStateForPanel(panelIdx, panelWidth, panelHeight) {
    const viewId = `panel_${panelIdx}`;
    const bounds = this.globalBounds || this.getGlobalBounds();
    const spanX = Math.max(1e-6, bounds.maxX - bounds.minX);
    const spanY = Math.max(1e-6, bounds.maxY - bounds.minY);
    const span = Math.max(spanX, spanY);
    const targetX = (bounds.minX + bounds.maxX) / 2;
    const targetY = (bounds.minY + bounds.maxY) / 2;
    const minDim = Math.max(1, Math.min(panelWidth, panelHeight));
    const baseZoom = Math.log2((minDim * 0.92) / span);

    this.baseZoomByView[viewId] = baseZoom;

    return {
      target: [targetX, targetY, 0],
      zoom: baseZoom,
      minZoom: -10,
      maxZoom: 30,
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
    const panelFromLayerProp = info?.layer?.props?.panelViewId;
    if (typeof panelFromLayerProp === "string") {
      const idx = Number.parseInt(panelFromLayerProp.replace("panel_", ""), 10);
      if (Number.isFinite(idx)) {
        return idx;
      }
    }

    const layerId = info?.layer?.id;
    if (typeof layerId === "string") {
      const m = /^panel_(\d+)_/.exec(layerId);
      if (m) {
        return Number.parseInt(m[1], 10);
      }
    }

    const viewportId = info?.viewport?.id;
    if (typeof viewportId === "string") {
      const idx = Number.parseInt(viewportId.replace("panel_", ""), 10);
      if (Number.isFinite(idx)) {
        return idx;
      }
    }

    return NaN;
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
    let mode = this.plotMetaData.mode;
    let group_by = this.plotMetaData.group_by;
    let split_by = this.plotMetaData.split_by;
    let metaData = this.origData.cellMetaData;
    let expressionData = this.origData.expressionData;
    let plotFeature = this.plotData.plotFeature;
    let text = null;
    let prefix = null;
    let split_category = {};
    let split_expr = {};

    const groupByArray = group_by ? expandMeta(metaData[group_by]) : [];
    const splitByArray = split_by ? expandMeta(metaData[split_by]) : [];
    switch (mode) {
      case "clusterOnly":
        prefix = "Cat: ";
        text = prefix.concat(groupByArray[pointId]);
        break;
      case "cluster+expr+noSplit":
        if (spIndex == 0) {
          prefix = "Cat: ";
          text = prefix.concat(groupByArray[pointId]);
        } else {
          prefix = "Expr: ";
          text = prefix.concat(
            d3.format(".3f")(expressionData[plotFeature][pointId]),
          );
        }
        break;
      case "cluster+expr+twoSplit":
        split_category = splitArrByMeta(groupByArray, splitByArray);
        split_expr = splitArrByMeta(expressionData[plotFeature], splitByArray);

        if (spIndex === 0) {
          prefix = "Cat: ";
          text = prefix.concat(
            split_category[Object.keys(split_category)[0]][pointId],
          );
        } else if (spIndex === 1) {
          prefix = "Expr: ";
          text = prefix.concat(
            d3.format(".3f")(split_expr[Object.keys(split_expr)[0]][pointId]),
          );
        } else if (spIndex === 2) {
          prefix = "Cat: ";
          text = prefix.concat(
            split_category[Object.keys(split_category)[1]][pointId],
          );
        } else if (spIndex === 3) {
          prefix = "Expr: ";
          text = prefix.concat(
            d3.format(".3f")(split_expr[Object.keys(split_expr)[1]][pointId]),
          );
        }
        break;
      case "cluster+multiSplit":
        split_category = splitArrByMeta(groupByArray, splitByArray);
        prefix = "Cat: ";
        text = prefix.concat(
          split_category[Object.keys(split_category)[spIndex]][pointId],
        );
        break;
      case "cluster+expr+multiSplit":
        split_expr = splitArrByMeta(expressionData[plotFeature], splitByArray);
        prefix = "Expr: ";
        text = prefix.concat(
          d3.format(".3f")(
            split_expr[Object.keys(split_expr)[spIndex]][pointId],
          ),
        );
        break;
    }
    // empty the intermedia data
    split_category = {};
    split_expr = {};
    return text;
  }

  populate_instance(noteId) {
    this.noteId = noteId;
  }

  createNote(noteId) {
    let noteEl = document.createElement("div");
    noteEl.id = noteId;
    noteEl.classList.add("mainClusterPlotNote");
    noteEl.classList.add("shadow");
    noteEl.style.zIndex = "30";

    this.plotEl.appendChild(noteEl);
  }

  // note manipulation to mimic tooltips
  static showNote(noteId, text, color) {
    let noteEl = document.getElementById(noteId);
    noteEl.style.display = null;
    noteEl.style.opacity = 0.8;
    noteEl.style.background = color;
    noteEl.textContent = text;
  }

  static hideNote(noteId) {
    let noteEl = document.getElementById(noteId);
    noteEl.style.display = "none";
  }

  createInfoWidget(infoId) {
    let infoEl = document.createElement("div");
    infoEl.id = infoId;
    infoEl.setAttribute("tabindex", "0");
    infoEl.style.position = "absolute";
    infoEl.style.zIndex = "30";
    infoEl.style.pointerEvents = "auto";
    let infoTitleEl = document.createElement("div");
    infoTitleEl.id = "info-title";
    let infoContentEl = document.createElement("div");
    infoContentEl.id = "info-content";
    let introduction = [
      "Pan: Click and drag your mouse.",
      "Zoom: Scroll vertically.",
      // disable rotate, the label canvas will not synchronize
      //`Rotate: While pressing <kbd>ALT</kbd>, click and drag your mouse.`,
      `Lasso: Pressing <kbd>SHIFT</kbd> and drag your mouse.`,
      "Change slider to adjust label size.",
      "Click download icon to save the image.",
    ];

    for (let i = 0; i < introduction.length; ++i) {
      let li = document.createElement("li");
      li.innerHTML = introduction[i];
      infoContentEl.appendChild(li);
    }

    infoEl.appendChild(infoContentEl);
    infoEl.appendChild(infoTitleEl);
    this.plotEl.appendChild(infoEl);
  }

  createDownloadIcon(elId) {
    const downloadEl = document.createElement("div");
    downloadEl.id = elId;
    downloadEl.style.width = "2rem";
    downloadEl.style.height = "2rem";
    downloadEl.style.position = "absolute";
    downloadEl.style.zIndex = "30";
    downloadEl.style.bottom = "1%";
    downloadEl.style.left = "9.5rem";
    downloadEl.style.padding = "0.2rem";
    //downloadEl.style.backgroundColor = "rgba(var(--bs-secondary-rgb), 0.4)";
    downloadEl.style.display = "flex";
    downloadEl.style.justifyContent = "center";
    downloadEl.style.alignItems = "center";
    downloadEl.style.pointerEvents = "auto";
    //downloadEl.style.overflow = "hidden;"
    //downloadEl.style.transition = "background 0.15s cubic-bezier(0.25, 0.1, 0.25, 1)";

    const ns = "http://www.w3.org/2000/svg";
    const icon = document.createElementNS(ns, "svg");
    icon.setAttribute("width", "100%");
    icon.setAttribute("height", "100%");
    icon.setAttribute("viewBox", "0 0 24 24");
    //icon.style.background = "rgba(255,0,0,0.1)";
    icon.style.overflow = "visible";
    icon.style.width = "100%";
    icon.style.height = "100%";

    const path = document.createElementNS(ns, "path");
    path.setAttribute("d", "M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z");
    path.setAttribute("fill", "#fff");
    path.setAttribute("stroke", "rgba(var(--bs-secondary-rgb), 0.4)"); // Red stroke
    path.setAttribute("stroke-width", "1.5"); // Thin stroke
    icon.appendChild(path);

    downloadEl.appendChild(icon);

    icon.addEventListener("mouseover", () => {
      path.setAttribute("stroke", "rgba(var(--bs-secondary-rgb), 1)");
    });
    icon.addEventListener("mouseout", () => {
      path.setAttribute("stroke", "rgba(var(--bs-secondary-rgb), 0.4)");
    });

    downloadEl.addEventListener("click", () => {
      const scatterCanvas = html2canvas(
        this.plotEl.querySelector("#canvas-wrapper"),
        {
          backgroundColor: null,
          scale: window.devicePixelRatio * 4,
        },
      );
      scatterCanvas.then((canvas) => {
        // create new div with the same dimension
        const scatterWidth = parseFloat(this.plotEl.parentElement.scrollWidth);
        const scatterHeight = parseFloat(
          this.plotEl.parentElement.scrollHeight,
        );

        // clone catLegendEl
        const catLegendClone = this.catLegendEl.cloneNode(true);
        catLegendClone.style.width = "200px";

        // clone expLegendEl
        const expLegendClone = this.expLegendEl.cloneNode(true);
        expLegendClone.style.width = "100%";
        expLegendClone.style.marginLeft = "5px";
        expLegendClone.style.marginRight = "5px";
        expLegendClone.style.height = "10px";

        const tempDiv = document.createElement("div");

        tempDiv.style.width =
          5 + 5 + scatterWidth + 5 + catLegendClone.style.width + 5 + "px";
        tempDiv.style.height =
          Math.max(scatterHeight, catLegendClone.style.height) + "px";

        tempDiv.style.position = "absolute";
        tempDiv.style.left = "-9999px"; // Move off-screen
        tempDiv.style.display = "flex";
        tempDiv.style.justifyContent = "space-between";
        tempDiv.style.alignItems = "center";
        tempDiv.style.overflow = "hidden";

        const canvasColDiv = document.createElement("div");
        canvasColDiv.style.margin = "5px";
        canvasColDiv.style.padding = 0;
        canvasColDiv.style.alignItems = "center";
        canvasColDiv.style.justifyContent = "center";
        canvasColDiv.appendChild(canvas);
        tempDiv.appendChild(canvasColDiv);

        const legendColDiv = document.createElement("div");
        legendColDiv.style.display = "flex";
        legendColDiv.style.flexDirection = "column";
        legendColDiv.style.width = "200px";
        legendColDiv.style.margin = "5px";
        legendColDiv.style.padding = 0;
        legendColDiv.style.alignItems = "center";
        legendColDiv.style.justifyContent = "center";

        legendColDiv.appendChild(catLegendClone);
        legendColDiv.appendChild(expLegendClone);

        tempDiv.appendChild(legendColDiv);

        document.body.appendChild(tempDiv);
        html2canvas(tempDiv, {
          backgroundColor: null, // or 'transparent'
          scale: window.devicePixelRatio * 4,
        }).then((canvas) => {
          downloadCanvasAsPNG(canvas, "scatter.png");
          document.body.removeChild(tempDiv);
        });
      });
    });
    this.plotEl.appendChild(downloadEl);
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
    if (typeof title === "number") {
      title = title.toString();
    }
    // legend style modified from broad single cell portal viewer
    const scatterLegend = document.createElement("div");
    scatterLegend.classList.add("scatter-legend");
    // replace unsafe strings in title and use it as the legend element id
    scatterLegend.id = "legend_" + title.replace(/[^a-zA-Z0-9-_]/g, "_");

    const colorBlock = document.createElement("div");
    colorBlock.classList.add("scatter-legend-icon");
    colorBlock.style.backgroundColor = color;

    const labelEl = document.createElement("span");
    labelEl.classList.add("legend-label");
    labelEl.title = title;
    labelEl.innerHTML = title;

    const numberEl = document.createElement("span");
    numberEl.classList.add("num-points");
    numberEl.title = number + " points in the group";
    numberEl.innerHTML = number;

    const entryEl = document.createElement("div");
    entryEl.classList.add("scatter-legend-entry");
    entryEl.appendChild(labelEl);
    entryEl.appendChild(numberEl);

    scatterLegend.appendChild(colorBlock);
    scatterLegend.appendChild(entryEl);

    return scatterLegend;
  }

  static findIndexes(arr, value) {
    var indexes = [];
    for (var i = 0; i < arr.length; i++) {
      if (arr[i] === value) {
        indexes.push(i);
      }
    }
    return indexes;
  }

  highlight_index(selectedGroupBy) {
    let mode = this.plotMetaData.mode;
    let group_by = this.plotMetaData.group_by;
    let metaData = this.origData.cellMetaData;
    // return a array of highlight points index array
    let pointsIndex = [];

    let factorLevel = {};
    let sortedUniqueArr = [...new Set(expandMeta(metaData[group_by]))].sort(
      sortStringArray,
    );
    sortedUniqueArr.forEach((e, i) => {
      factorLevel[e] = i;
    });

    switch (mode) {
      case "clusterOnly":
        pointsIndex[0] = reglScatterCanvas.findIndexes(
          this.plotData.pointsData[0].z,
          factorLevel[selectedGroupBy],
        );
        break;
      case "cluster+expr+noSplit":
        pointsIndex[0] = reglScatterCanvas.findIndexes(
          this.plotData.pointsData[0].z,
          factorLevel[selectedGroupBy],
        );
        pointsIndex[1] = pointsIndex[0];
        break;
      case "cluster+expr+twoSplit":
        for (let i = 0; i < this.plotData.pointsData.length; i = i + 2) {
          pointsIndex[i] = reglScatterCanvas.findIndexes(
            this.plotData.pointsData[i].z,
            factorLevel[selectedGroupBy],
          );
          pointsIndex[i + 1] = pointsIndex[i];
        }
        break;
      case "cluster+multiSplit":
        pointsIndex = this.plotData.pointsData.map((e) =>
          reglScatterCanvas.findIndexes(e.z, factorLevel[selectedGroupBy]),
        );
    }
    return pointsIndex;
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

const downloadCanvasAsPNG = (canvas, fileName = "canvas.png") => {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (!blob) {
        reject(new Error("Canvas to Blob conversion failed"));
        return;
      }

      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = fileName;

      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);

      URL.revokeObjectURL(url);
      resolve();
    }, "image/png");
  });
};

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
