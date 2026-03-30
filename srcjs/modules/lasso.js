import { projectWorldToCanvas } from "./scatter/scatterCoordinates.js";

export class LassoTool {
  constructor({
    container,
    overlayCanvas,
    getViewports,
    getPanelPositions,
    onSelect,
    onDeselect,
  }) {
    this.container = container;
    this.overlayCanvas = overlayCanvas;
    this.getViewports = getViewports;
    this.getPanelPositions = getPanelPositions;
    this.onSelect = onSelect;
    this.onDeselect = onDeselect;

    this.active = false;
    this.activeViewId = null;
    this.path = [];

    this.handlePointerDown = this.handlePointerDown.bind(this);
    this.handlePointerMove = this.handlePointerMove.bind(this);
    this.handlePointerUp = this.handlePointerUp.bind(this);

    this.container.addEventListener("pointerdown", this.handlePointerDown);
    window.addEventListener("pointermove", this.handlePointerMove);
    window.addEventListener("pointerup", this.handlePointerUp);
  }

  clear() {
    this.active = false;
    this.activeViewId = null;
    this.path = [];
    const ctx = this.overlayCanvas.getContext("2d");
    ctx.clearRect(0, 0, this.overlayCanvas.width, this.overlayCanvas.height);
  }

  destroy() {
    this.clear();
    this.container.removeEventListener("pointerdown", this.handlePointerDown);
    window.removeEventListener("pointermove", this.handlePointerMove);
    window.removeEventListener("pointerup", this.handlePointerUp);
  }

  handlePointerDown(event) {
    if (!event.shiftKey) {
      return;
    }
    const p = this.toLocalPoint(event);
    const viewport = this.pickViewport(p.x, p.y);
    if (!viewport) {
      return;
    }
    event.preventDefault();
    this.active = true;
    this.activeViewId = viewport.id;
    this.path = [p];
    this.drawPath();
  }

  handlePointerMove(event) {
    if (!this.active) {
      return;
    }
    const p = this.toLocalPoint(event);
    this.path.push(p);
    this.drawPath();
  }

  handlePointerUp() {
    if (!this.active) {
      return;
    }
    const activeViewId = this.activeViewId;
    const polygon = this.path.slice();
    this.clear();
    if (polygon.length < 3) {
      if (this.onDeselect) {
        this.onDeselect();
      }
      return;
    }

    const viewport = this.getViewports().find((vp) => vp.id === activeViewId);
    if (!viewport) {
      return;
    }
    const panelIdx = Number.parseInt(activeViewId.replace("panel_", ""), 10);
    if (!Number.isFinite(panelIdx)) {
      return;
    }
    const positions = this.getPanelPositions(panelIdx);
    if (!positions) {
      return;
    }

    const selected = this.pickPointsInPolygon(positions, viewport, polygon);
    if (selected.length > 0) {
      if (this.onSelect) {
        this.onSelect(activeViewId, selected);
      }
    } else if (this.onDeselect) {
      this.onDeselect();
    }
  }

  toLocalPoint(event) {
    const rect = this.container.getBoundingClientRect();
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }

  pickViewport(x, y) {
    const viewports = this.getViewports();
    for (let i = 0; i < viewports.length; i++) {
      const vp = viewports[i];
      const inX = x >= vp.x && x <= vp.x + vp.width;
      const inY = y >= vp.y && y <= vp.y + vp.height;
      if (inX && inY) {
        return vp;
      }
    }
    return null;
  }

  drawPath() {
    const ctx = this.overlayCanvas.getContext("2d");
    const dpr = window.devicePixelRatio || 1;
    ctx.clearRect(0, 0, this.overlayCanvas.width, this.overlayCanvas.height);
    if (this.path.length < 2) {
      return;
    }
    ctx.save();
    ctx.strokeStyle = "rgba(0, 0, 0, 0.8)";
    ctx.fillStyle = "rgba(255, 255, 0, 0.15)";
    ctx.lineWidth = 1.5 * dpr;
    ctx.beginPath();
    ctx.moveTo(this.path[0].x * dpr, this.path[0].y * dpr);
    for (let i = 1; i < this.path.length; i++) {
      ctx.lineTo(this.path[i].x * dpr, this.path[i].y * dpr);
    }
    ctx.stroke();
    ctx.restore();
  }

  pickPointsInPolygon(positions, viewport, polygon) {
    const selected = [];
    const bbox = this.getPolygonBBox(polygon);
    const nPoints = positions.length / 2;
    for (let i = 0; i < nPoints; i++) {
      const worldX = positions[i * 2];
      const worldY = positions[i * 2 + 1];
      const [px, py] = projectWorldToCanvas(viewport, worldX, worldY);
      if (px < bbox.minX || px > bbox.maxX || py < bbox.minY || py > bbox.maxY) {
        continue;
      }
      if (this.pointInPolygon(px, py, polygon)) {
        selected.push(i);
      }
    }
    return selected;
  }

  getPolygonBBox(polygon) {
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (let i = 0; i < polygon.length; i++) {
      const p = polygon[i];
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return { minX, minY, maxX, maxY };
  }

  pointInPolygon(px, py, polygon) {
    let inside = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      const xi = polygon[i].x;
      const yi = polygon[i].y;
      const xj = polygon[j].x;
      const yj = polygon[j].y;
      const intersect =
        yi > py !== yj > py &&
        px < ((xj - xi) * (py - yi)) / (yj - yi + Number.EPSILON) + xi;
      if (intersect) {
        inside = !inside;
      }
    }
    return inside;
  }
}
