export function getPanelViewRects({
  panelEls,
  nCols,
  nRows,
  fallbackPanelWidth,
  fallbackPanelHeight,
}) {
  const rects = [];
  for (let i = 0; i < panelEls.length; i++) {
    const panel = panelEls[i];
    const rawPanelWidth = panel.clientWidth || 0;
    const rawPanelHeight = panel.clientHeight || 0;
    const hasPanelRect = rawPanelWidth > 0 && rawPanelHeight > 0;
    const panelWidth = hasPanelRect ? Math.max(1, rawPanelWidth) : fallbackPanelWidth;
    const panelHeight = hasPanelRect ? Math.max(1, rawPanelHeight) : fallbackPanelHeight;
    const row = Math.floor(i / nCols);
    const col = i % nCols;

    rects.push({
      panelIdx: i,
      viewId: `panel_${i}`,
      x: hasPanelRect ? Math.max(0, panel.offsetLeft || 0) : col * fallbackPanelWidth,
      y: hasPanelRect ? Math.max(0, panel.offsetTop || 0) : row * fallbackPanelHeight,
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
