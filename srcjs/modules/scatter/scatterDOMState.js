export function setLabelCanvasVisibility(plotEl, isVisible) {
  if (!plotEl) return;
  const opacity = isVisible ? "1" : "0";
  plotEl.querySelectorAll(".label-canvas").forEach((canvas) => {
    canvas.style.opacity = opacity;
  });
}

export function setPanelOverlayVisibility(plotEl, isVisible) {
  if (!plotEl) return;
  const opacity = isVisible ? "1" : "0";
  const grid = plotEl.querySelector(".deck-overlay-grid");
  if (grid) {
    grid.style.opacity = opacity;
  }
  plotEl.querySelectorAll(".mainClusterPlotTitle").forEach((title) => {
    title.style.opacity = opacity;
  });
  setLabelCanvasVisibility(plotEl, isVisible);
}

export function setResizeBlankVisibility(plotEl, isVisible) {
  if (!plotEl) return;
  const opacity = isVisible ? "0" : "1";
  const deckContainer = plotEl.querySelector("#deck-container");
  if (deckContainer) {
    deckContainer.style.opacity = opacity;
  }
  const crosshair = plotEl.querySelector("#crosshair-underlay");
  if (crosshair) {
    crosshair.style.opacity = opacity;
  }
  const lasso = plotEl.querySelector("#lasso-overlay");
  if (lasso) {
    lasso.style.opacity = opacity;
  }
  setPanelOverlayVisibility(plotEl, !isVisible);
}
