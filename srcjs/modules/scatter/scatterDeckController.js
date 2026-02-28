export function panelLayerFilter({ layer, viewport }) {
  if (!layer || !viewport) {
    return false;
  }
  if (!viewport.id) {
    return true;
  }
  if (layer.props && layer.props.panelViewId) {
    return layer.props.panelViewId === viewport.id;
  }
  const layerPanelId = layer.id.split("_").slice(0, 2).join("_");
  return layerPanelId === viewport.id;
}

export function resolveViewStateUpdate({
  prevState,
  nextState,
  interactionState,
  isRelayouting,
  zoomSensitivity,
}) {
  const prev = prevState || nextState;
  const current = { ...nextState };

  const isZooming = Boolean(interactionState && interactionState.isZooming);
  const isDragging = Boolean(
    interactionState && (interactionState.isDragging || interactionState.isPanning),
  );

  if (isRelayouting && !isZooming && !isDragging) {
    return { next: prev, shouldApply: false, isZooming: false };
  }

  // Keep target fixed unless user is actively dragging.
  if (!isDragging) {
    current.target = prev.target;
  }

  // Apply zoom damping only while actively zooming.
  if (isZooming) {
    const adjustedZoom = prev.zoom + (nextState.zoom - prev.zoom) * zoomSensitivity;
    current.zoom = Math.max(
      nextState.minZoom ?? -10,
      Math.min(nextState.maxZoom ?? 30, adjustedZoom),
    );
  } else {
    current.zoom = prev.zoom;
  }

  return { next: current, shouldApply: true, isZooming };
}
