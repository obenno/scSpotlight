export class ScatterOverlay {
  static clearCanvas(canvas) {
    if (!canvas) {
      return;
    }
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
  }

  static drawCrosshair(canvas, target) {
    if (!canvas || !target) {
      return;
    }
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const dpr = window.devicePixelRatio || 1;

    const { x, y, left, top, right, bottom } = target;

    ctx.save();
    // Hard clip to the active panel so the crosshair is panel-specific.
    ctx.beginPath();
    ctx.rect(left * dpr, top * dpr, (right - left) * dpr, (bottom - top) * dpr);
    ctx.clip();

    ctx.strokeStyle = "rgba(170, 170, 170, 0.45)";
    ctx.lineWidth = 1 * dpr;
    ctx.setLineDash([4 * dpr, 4 * dpr]);

    ctx.beginPath();
    ctx.moveTo(x * dpr, top * dpr);
    ctx.lineTo(x * dpr, bottom * dpr);
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(left * dpr, y * dpr);
    ctx.lineTo(right * dpr, y * dpr);
    ctx.stroke();

    ctx.restore();
  }
}
