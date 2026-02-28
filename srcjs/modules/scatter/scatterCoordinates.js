export function projectWorldToPanel(viewport, worldX, worldY) {
  const [px, py] = viewport.project([worldX, worldY]);
  const appearsLocal =
    px >= -1 && px <= viewport.width + 1 && py >= -1 && py <= viewport.height + 1;
  if (appearsLocal) {
    return [px, py];
  }
  return [px - viewport.x, py - viewport.y];
}

export function projectWorldToCanvas(viewport, worldX, worldY) {
  const [px, py] = viewport.project([worldX, worldY]);
  const appearsLocal =
    px >= -1 && px <= viewport.width + 1 && py >= -1 && py <= viewport.height + 1;
  if (appearsLocal) {
    return [px + viewport.x, py + viewport.y];
  }
  return [px, py];
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
