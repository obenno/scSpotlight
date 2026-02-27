export function getPanelBoundsFromPositions(positions) {
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

  if (!Number.isFinite(minX) || !Number.isFinite(maxX) || !Number.isFinite(minY) || !Number.isFinite(maxY)) {
    return { minX: -1, maxX: 1, minY: -1, maxY: 1 };
  }

  return { minX, maxX, minY, maxY };
}

export function getGlobalBoundsFromPanels(panelBuffers = []) {
  if (!Array.isArray(panelBuffers) || panelBuffers.length === 0) {
    return { minX: -1, maxX: 1, minY: -1, maxY: 1 };
  }

  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;

  panelBuffers.forEach((panel) => {
    const bounds = getPanelBoundsFromPositions(panel?.positions);
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

export function computeViewStateFromBounds({
  bounds,
  panelWidth,
  panelHeight,
  padding = 0.92,
  minZoom = -10,
  maxZoom = 30,
}) {
  const safeBounds = bounds || { minX: -1, maxX: 1, minY: -1, maxY: 1 };
  const spanX = Math.max(1e-6, safeBounds.maxX - safeBounds.minX);
  const spanY = Math.max(1e-6, safeBounds.maxY - safeBounds.minY);
  const span = Math.max(spanX, spanY);
  const targetX = (safeBounds.minX + safeBounds.maxX) / 2;
  const targetY = (safeBounds.minY + safeBounds.maxY) / 2;

  const minDim = Math.max(1, Math.min(panelWidth || 1, panelHeight || 1));
  const baseZoom = Math.log2((minDim * padding) / span);

  return {
    target: [targetX, targetY, 0],
    zoom: baseZoom,
    minZoom,
    maxZoom,
    baseZoom,
  };
}
