export function computePanelLayout({
  nPanels,
  containerWidth,
  containerHeight,
  gap,
  minPanelSize = 400,
}) {
  const panels = Math.max(1, nPanels || 1);
  const nCols = panels >= 2 ? 2 : 1;
  const nRows = Math.ceil(panels / nCols);

  const width = Math.max(1, containerWidth || 1);
  const height = Math.max(1, containerHeight || 1);
  const safeGap = Math.max(0, gap || 0);

  // Rule: if viewport can fit two min-width panels, use half viewport width;
  // otherwise use min width and rely on container scroll.
  const halfViewportWidth = (width - safeGap * (nCols - 1)) / nCols;
  const panelWidth =
    halfViewportWidth >= minPanelSize ? Math.floor(halfViewportWidth) : minPanelSize;

  const isSingleRow = panels <= 2;

  if (isSingleRow) {
    const contentWidth = nCols * panelWidth + safeGap * (nCols - 1);
    const contentHeight = Math.max(minPanelSize, height);

    return {
      nCols,
      nRows,
      panelWidth,
      panelHeight: null,
      isSquare: false,
      gridTemplateColumns: `repeat(${nCols}, ${panelWidth}px)`,
      gridTemplateRows: `repeat(${nRows}, minmax(${minPanelSize}px, 1fr))`,
      contentWidth,
      contentHeight,
    };
  }

  // Multi-row: enforce square panels.
  const panelSize = panelWidth;
  const contentWidth = nCols * panelSize + safeGap * (nCols - 1);
  const contentHeight = nRows * panelSize + safeGap * (nRows - 1);

  return {
    nCols,
    nRows,
    panelWidth: panelSize,
    panelHeight: panelSize,
    isSquare: true,
    gridTemplateColumns: `repeat(${nCols}, ${panelSize}px)`,
    gridTemplateRows: `repeat(${nRows}, ${panelSize}px)`,
    contentWidth,
    contentHeight,
  };
}
