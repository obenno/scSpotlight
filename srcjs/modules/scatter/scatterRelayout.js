export function getPanelViewRects({
  panelEls,
  nCols,
  nRows,
  fallbackPanelWidth,
  fallbackPanelHeight,
  referenceEl,
}) {
  const rects = [];
  const referenceRect =
    referenceEl && typeof referenceEl.getBoundingClientRect === "function"
      ? referenceEl.getBoundingClientRect()
      : null;

  for (let i = 0; i < panelEls.length; i++) {
    const panel = panelEls[i];
    const panelRect =
      typeof panel.getBoundingClientRect === "function" ? panel.getBoundingClientRect() : null;
    const rawPanelWidth = panelRect?.width || panel.clientWidth || 0;
    const rawPanelHeight = panelRect?.height || panel.clientHeight || 0;
    const hasPanelRect = rawPanelWidth > 0 && rawPanelHeight > 0;
    const panelWidth = hasPanelRect ? Math.max(1, rawPanelWidth) : fallbackPanelWidth;
    const panelHeight = hasPanelRect ? Math.max(1, rawPanelHeight) : fallbackPanelHeight;
    const row = Math.floor(i / nCols);
    const col = i % nCols;
    const x =
      hasPanelRect && referenceRect && panelRect
        ? Math.max(0, panelRect.left - referenceRect.left)
        : hasPanelRect
          ? Math.max(0, panel.offsetLeft || 0)
          : col * fallbackPanelWidth;
    const y =
      hasPanelRect && referenceRect && panelRect
        ? Math.max(0, panelRect.top - referenceRect.top)
        : hasPanelRect
          ? Math.max(0, panel.offsetTop || 0)
          : row * fallbackPanelHeight;

    rects.push({
      panelIdx: i,
      viewId: `panel_${i}`,
      x,
      y,
      width: panelWidth,
      height: panelHeight,
      isInvalidSize: rawPanelWidth < 10 || rawPanelHeight < 10,
    });
  }
  return rects;
}

export function hasInvalidPanelRects(rects) {
  return rects.some((r) => r.isInvalidSize);
}
