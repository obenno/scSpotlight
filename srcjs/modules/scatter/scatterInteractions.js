import { LassoTool } from "../lasso.js";

export class ScatterInteractions {
  constructor() {
    this.lassoTool = null;
  }

  bindLasso({
    container,
    overlayCanvas,
    getViewports,
    getPanelPositions,
    onSelect,
    onDeselect,
  }) {
    this.destroyLasso();
    if (!container || !overlayCanvas) {
      return null;
    }
    this.lassoTool = new LassoTool({
      container,
      overlayCanvas,
      getViewports,
      getPanelPositions,
      onSelect,
      onDeselect,
    });
    return this.lassoTool;
  }

  clearLasso() {
    if (this.lassoTool) {
      this.lassoTool.clear();
    }
  }

  destroyLasso() {
    if (this.lassoTool) {
      this.lassoTool.destroy();
      this.lassoTool = null;
    }
  }
}
