function squaredDistance2D(a, b) {
  const dx = a[0] - b[0];
  const dy = a[1] - b[1];
  return dx * dx + dy * dy;
}

function resolvePanelLocalProjection(viewport, worldX, worldY) {
  const [px, py] = viewport.project([worldX, worldY]);
  if (
    (viewport.x === 0 && viewport.y === 0) ||
    typeof viewport.unproject !== "function"
  ) {
    return [px, py];
  }

  const rawCandidate = [px, py];
  const offsetCandidate = [px - viewport.x, py - viewport.y];
  const worldTarget = [worldX, worldY];
  const rawRoundTrip = viewport.unproject(rawCandidate);
  const offsetRoundTrip = viewport.unproject(offsetCandidate);

  if (!Array.isArray(rawRoundTrip) || !Array.isArray(offsetRoundTrip)) {
    return rawCandidate;
  }

  return squaredDistance2D(offsetRoundTrip, worldTarget) < squaredDistance2D(rawRoundTrip, worldTarget)
    ? offsetCandidate
    : rawCandidate;
}

export function projectWorldToPanel(viewport, worldX, worldY) {
  return resolvePanelLocalProjection(viewport, worldX, worldY);
}

export function projectWorldToCanvas(viewport, worldX, worldY) {
  const [localX, localY] = resolvePanelLocalProjection(viewport, worldX, worldY);
  return [localX + viewport.x, localY + viewport.y];
}

export function parsePanelIndexFromPickInfo(info) {
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
