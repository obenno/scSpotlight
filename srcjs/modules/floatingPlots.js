const PANEL_MARGIN_PX = 8;
const DEFAULT_MIN_WIDTH_PX = 320;
const DEFAULT_MIN_HEIGHT_PX = 180;
const RAIL_LEFT_OFFSET_PX = 6;
const RAIL_MIN_TOP_PX = 56;
const LEFT_RAIL_SYNC_DELAY_MS = 140;
const LEFT_RAIL_PANEL_DELAY_MS = 120;
const WINDOW_RESIZE_DEBOUNCE_MS = 100;
const FLOATING_PLOTS_REFRESH_EVENT = "scspotlight:floatingPlotsRefresh";
const LEFT_SIDEBAR_RAIL_TOP_GAP_PX = 10;

const getFloatingPanelLimits = (boundsRect, margin = PANEL_MARGIN_PX) => {
  const availableWidth = Math.max(1, boundsRect.width - margin * 2);
  const availableHeight = Math.max(1, boundsRect.height - margin * 2);

  return {
    minWidth: Math.min(DEFAULT_MIN_WIDTH_PX, availableWidth),
    minHeight: Math.min(DEFAULT_MIN_HEIGHT_PX, availableHeight),
    maxWidth: availableWidth,
    maxHeight: availableHeight,
  };
};

const clampToRange = (value, min, max) => {
  if (max < min) {
    return min;
  }
  return Math.min(max, Math.max(min, value));
};

const setPanelRect = ({ panelEl, width, height, left, top }) => {
  if (Number.isFinite(width)) panelEl.style.width = `${Math.round(width)}px`;
  if (Number.isFinite(height)) panelEl.style.height = `${Math.round(height)}px`;
  if (Number.isFinite(left)) panelEl.style.left = `${Math.round(left)}px`;
  if (Number.isFinite(top)) panelEl.style.top = `${Math.round(top)}px`;
};

const noop = () => {};

const getPanelConfigsById = (panelConfigs = []) => {
  return new Map(
    panelConfigs
      .filter((config) => config && typeof config.id === "string" && config.id)
      .map((config) => [
        config.id,
        {
          ...config,
          refresh:
            typeof config.refresh === "function" ? config.refresh : noop,
          onResize:
            typeof config.onResize === "function" ? config.onResize : noop,
        },
      ]),
  );
};

const buildPanelEntries = ({ host, rail, panelConfigs = [] }) => {
  const panelConfigsById = getPanelConfigsById(panelConfigs);
  const panelElements = [...host.querySelectorAll(".plot-floating-panel")];
  const railButtons = [...rail.querySelectorAll(".plot-rail-btn")];
  const railButtonsById = new Map(
    railButtons
      .map((button) => [button.dataset.target, button])
      .filter(([panelId]) => Boolean(panelId)),
  );

  const panelEntries = panelElements
    .map((panelEl, idx) => {
      const panelId = panelEl.id;
      if (!panelId) return null;

      const panelConfig = panelConfigsById.get(panelId) || {
        id: panelId,
        refresh: noop,
        onResize: noop,
      };

      return {
        ...panelConfig,
        panelEl,
        buttonEl: railButtonsById.get(panelId) || null,
        initialLeft: 340 + idx * 24,
        initialTop: 120 + idx * 20,
      };
    })
    .filter(Boolean);

  return {
    panelEntries,
    panelEntriesById: new Map(panelEntries.map((entry) => [entry.id, entry])),
  };
};

const normalizePanelIds = (panelIds, panelEntries) => {
  if (typeof panelIds === "string") {
    return panelIds ? [panelIds] : [];
  }

  if (!Array.isArray(panelIds) || panelIds.length === 0) {
    return panelEntries.map((entry) => entry.id).filter(Boolean);
  }

  return panelIds.filter(Boolean);
};

const attachTopRightResizeHandle = (panelEl, getBoundsRect) => {
  if (!panelEl || panelEl.querySelector(".plot-floating-top-resize")) return null;

  const handle = document.createElement("div");
  handle.className = "plot-floating-top-resize";
  panelEl.appendChild(handle);

  let isResizing = false;
  let startX = 0;
  let startY = 0;
  let startWidth = 0;
  let startHeight = 0;
  let startLeft = 0;
  let startTop = 0;

  const onMouseMove = (e) => {
    if (!isResizing) return;

    const dx = e.clientX - startX;
    const dy = e.clientY - startY;

    const boundsRect = getBoundsRect();
    const { minWidth, minHeight, maxWidth } = getFloatingPanelLimits(
      boundsRect,
      PANEL_MARGIN_PX,
    );

    const widthLimit = Math.min(
      maxWidth,
      boundsRect.right - startLeft - PANEL_MARGIN_PX,
    );
    const nextWidth = Math.min(
      Math.max(minWidth, widthLimit),
      Math.max(minWidth, startWidth + dx),
    );

    const minTop = boundsRect.top + PANEL_MARGIN_PX;
    const maxTop = Math.min(
      startTop + startHeight - minHeight,
      boundsRect.bottom - minHeight - PANEL_MARGIN_PX,
    );
    const nextTop = clampToRange(startTop + dy, minTop, maxTop);

    const maxHeightFromTop = Math.max(
      1,
      boundsRect.bottom - nextTop - PANEL_MARGIN_PX,
    );
    const nextHeight = Math.min(
      maxHeightFromTop,
      Math.max(minHeight, startHeight - dy),
    );

    setPanelRect({
      panelEl,
      width: nextWidth,
      height: nextHeight,
      top: nextTop,
    });
  };

  const onMouseUp = () => {
    isResizing = false;
    document.body.style.userSelect = "";
    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("mouseup", onMouseUp);
  };

  handle.addEventListener("mousedown", (e) => {
    e.preventDefault();
    e.stopPropagation();
    isResizing = true;
    startX = e.clientX;
    startY = e.clientY;

    const rect = panelEl.getBoundingClientRect();
    startWidth = rect.width;
    startHeight = rect.height;
    startLeft = rect.left;
    startTop = rect.top;

    document.body.style.userSelect = "none";
    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("mouseup", onMouseUp);
  });

  return handle;
};

const initFloatingPlotWindows = ({
  host,
  rail,
  leftSidebar,
  getMainBoundsRect,
  panelConfigs,
  debounce,
}) => {
  if (!host || !rail || !leftSidebar) return;
  if (host.dataset.floatingPlotsInitialized === "true") return;
  host.dataset.floatingPlotsInitialized = "true";

  const { panelEntries, panelEntriesById } = buildPanelEntries({
    host,
    rail,
    panelConfigs,
  });
  let zIndexSeed = 1600;

  const getPanelEntry = (panelId) => panelEntriesById.get(panelId) || null;

  const runPanelRefresh = (panelId) => {
    const panelEntry = getPanelEntry(panelId);
    if (!panelEntry) return;
    panelEntry.refresh({ panelId, panelEl: panelEntry.panelEl });
  };

  const clampPanelToBounds = (panel) => {
    if (!panel || panel.style.display === "none") return;
    const boundsRect = getMainBoundsRect();
    const margin = PANEL_MARGIN_PX;
    const rect = panel.getBoundingClientRect();
    const { minWidth, minHeight, maxWidth, maxHeight } =
      getFloatingPanelLimits(boundsRect, margin);

    const width = Math.min(maxWidth, Math.max(minWidth, rect.width));
    const height = Math.min(maxHeight, Math.max(minHeight, rect.height));

    const minLeft = boundsRect.left + margin;
    const maxLeft = boundsRect.right - width - margin;
    const minTop = boundsRect.top + margin;
    const maxTop = boundsRect.bottom - height - margin;

    const left = clampToRange(rect.left, minLeft, maxLeft);
    const top = clampToRange(rect.top, minTop, maxTop);

    setPanelRect({ panelEl: panel, width, height, left, top });
  };

  const focusPanel = (panel) => {
    zIndexSeed += 1;
    panel.style.zIndex = String(zIndexSeed);
  };

  const refreshOpenPanels = (panelIds = []) => {
    normalizePanelIds(panelIds, panelEntries).forEach((panelId) => {
      const panel = getPanelEntry(panelId)?.panelEl || null;
      if (!panel || panel.style.display === "none") return;

      clampPanelToBounds(panel);
      runPanelRefresh(panelId);
    });
  };

  const setRailPosition = () => {
    const mainRect = getMainBoundsRect();
    const railRect = rail.getBoundingClientRect();
    const bottomGap = Math.max(24, Math.round(mainRect.height * 0.1));
    const targetTop = mainRect.bottom - railRect.height - bottomGap;
    const minTop = mainRect.top + RAIL_MIN_TOP_PX;
    rail.style.top = `${Math.max(minTop, targetTop)}px`;
    rail.style.left = `${mainRect.left + RAIL_LEFT_OFFSET_PX}px`;
  };

  const syncRailButtonState = () => {
    panelEntries.forEach(({ id: panelId, panelEl, buttonEl }) => {
      if (!buttonEl) return;
      const panel = panelEl;
      const isOpen = panel && panel.style.display !== "none";
      buttonEl.classList.toggle("active", Boolean(isOpen));
      buttonEl.setAttribute("aria-pressed", isOpen ? "true" : "false");
    });
  };

  setRailPosition();
  window.addEventListener(
    "resize",
    debounce(setRailPosition, WINDOW_RESIZE_DEBOUNCE_MS),
  );

  const leftLayout = leftSidebar.closest(".bslib-sidebar-layout");
  if (leftLayout) {
    let railSyncFrame = null;
    const syncDuringTransition = () => {
      setRailPosition();
      railSyncFrame = window.requestAnimationFrame(syncDuringTransition);
    };

    leftLayout.addEventListener("transitionstart", () => {
      if (railSyncFrame === null) {
        railSyncFrame = window.requestAnimationFrame(syncDuringTransition);
      }
    });

    leftLayout.addEventListener("transitionend", () => {
      if (railSyncFrame !== null) {
        window.cancelAnimationFrame(railSyncFrame);
        railSyncFrame = null;
      }
      setRailPosition();
    });
    const leftToggle = leftLayout.querySelector(
      '.collapse-toggle[aria-controls="leftSidebar"]',
    );
    if (leftToggle) {
      const toggleObserver = new MutationObserver(() => {
        window.setTimeout(setRailPosition, LEFT_RAIL_SYNC_DELAY_MS);
      });
      toggleObserver.observe(leftToggle, {
        attributes: true,
        attributeFilter: ["aria-expanded"],
      });
    }
  }

  panelEntries.forEach((panelEntry) => {
    const { panelEl: panel, initialLeft, initialTop } = panelEntry;

    panel.style.left = `${initialLeft}px`;
    panel.style.top = `${initialTop}px`;

    attachTopRightResizeHandle(panel, getMainBoundsRect);

    const header = panel.querySelector(".plot-floating-header");
    let dragging = false;
    let dragOffsetX = 0;
    let dragOffsetY = 0;

    const onDragMove = (event) => {
      if (!dragging) return;
      const boundsRect = getMainBoundsRect();
      const rect = panel.getBoundingClientRect();
      const width = Math.min(
        rect.width,
        Math.max(1, boundsRect.width - PANEL_MARGIN_PX * 2),
      );
      const height = Math.min(
        rect.height,
        Math.max(1, boundsRect.height - PANEL_MARGIN_PX * 2),
      );
      const nextLeft = clampToRange(
        event.clientX - dragOffsetX,
        boundsRect.left + PANEL_MARGIN_PX,
        boundsRect.right - width - PANEL_MARGIN_PX,
      );
      const nextTop = clampToRange(
        event.clientY - dragOffsetY,
        boundsRect.top + PANEL_MARGIN_PX,
        boundsRect.bottom - height - PANEL_MARGIN_PX,
      );
      setPanelRect({ panelEl: panel, left: nextLeft, top: nextTop });
    };

    const onDragEnd = () => {
      dragging = false;
      document.body.style.userSelect = "";
      document.removeEventListener("mousemove", onDragMove);
      document.removeEventListener("mouseup", onDragEnd);
    };

    if (header) {
      header.addEventListener("mousedown", (event) => {
        if (
          event.target.closest(".plot-floating-close") ||
          event.target.closest(".plot-floating-action")
        ) {
          return;
        }
        dragging = true;
        focusPanel(panel);
        const rect = panel.getBoundingClientRect();
        dragOffsetX = event.clientX - rect.left;
        dragOffsetY = event.clientY - rect.top;
        document.body.style.userSelect = "none";
        document.addEventListener("mousemove", onDragMove);
        document.addEventListener("mouseup", onDragEnd);
      });
    }

    panel.addEventListener("mousedown", () => focusPanel(panel));

    const panelResizeObserver = new ResizeObserver(() => {
      clampPanelToBounds(panel);
      if (panel.style.display !== "none") {
        panelEntry.onResize({ panelId: panelEntry.id, panelEl: panel });
      }
    });
    panelResizeObserver.observe(panel);

    clampPanelToBounds(panel);
  });

  rail.addEventListener("click", (event) => {
    const button = event.target.closest(".plot-rail-btn");
    if (!button) return;
    const panelId = button.dataset.target;
    const panel = getPanelEntry(panelId)?.panelEl || null;
    if (!panel) return;

    const isOpen = panel.style.display !== "none";
    if (isOpen) {
      panel.style.display = "none";
      syncRailButtonState();
      return;
    }

    panel.style.display = "block";
    focusPanel(panel);
    clampPanelToBounds(panel);
    syncRailButtonState();
    runPanelRefresh(panelId);
  });

  window.addEventListener(FLOATING_PLOTS_REFRESH_EVENT, (event) => {
    const panelIds = event.detail?.panelIds;
    refreshOpenPanels(panelIds);
  });

  host.addEventListener("click", (event) => {
    const closeButton = event.target.closest(".plot-floating-close");
    if (!closeButton) return;
    const panelId = closeButton.dataset.closeTarget;
    const panel = getPanelEntry(panelId)?.panelEl || null;
    if (panel) {
      panel.style.display = "none";
      syncRailButtonState();
    }
  });

  window.addEventListener(
    "resize",
    debounce(() => {
      panelEntries.forEach(({ panelEl }) => clampPanelToBounds(panelEl));
      setRailPosition();
    }, WINDOW_RESIZE_DEBOUNCE_MS),
  );

  syncRailButtonState();
};

const initLeftSidebarIconRail = ({ leftSidebar, rail }) => {
  if (!leftSidebar || !rail) return;
  if (rail.dataset.leftSidebarRailInitialized === "true") return;

  const layout = leftSidebar.closest(".bslib-sidebar-layout");
  if (!layout) return;

  const toggleBtn = layout.querySelector(
    '.collapse-toggle[aria-controls="leftSidebar"]',
  );
  if (!toggleBtn) return;

  rail.dataset.leftSidebarRailInitialized = "true";

  const syncLeftRailPosition = () => {
    const layoutRect = layout.getBoundingClientRect();
    const toggleRect = toggleBtn.getBoundingClientRect();
    const nextTop = Math.max(
      12,
      Math.round(toggleRect.bottom - layoutRect.top + LEFT_SIDEBAR_RAIL_TOP_GAP_PX),
    );
    rail.style.top = `${nextTop}px`;
  };

  const syncRailVisibility = () => {
    const isOpen = toggleBtn.getAttribute("aria-expanded") === "true";
    rail.classList.toggle("visible", !isOpen);
    syncLeftRailPosition();
  };

  syncRailVisibility();

  const toggleObserver = new MutationObserver(syncRailVisibility);
  toggleObserver.observe(toggleBtn, {
    attributes: true,
    attributeFilter: ["aria-expanded"],
  });

  window.addEventListener(
    "resize",
    () => {
      syncLeftRailPosition();
    },
  );

  rail.addEventListener("click", (event) => {
    const button = event.target.closest(".left-sidebar-rail-btn");
    if (!button) return;

    const panelIndex = Number.parseInt(button.dataset.panelIndex || "0", 10);
    if (Number.isNaN(panelIndex)) return;

    if (toggleBtn.getAttribute("aria-expanded") !== "true") {
      toggleBtn.click();
    }

    window.setTimeout(() => {
      const accordionButtons = leftSidebar.querySelectorAll(".accordion-button");
      const targetButton = accordionButtons[panelIndex];
      if (targetButton) {
        accordionButtons.forEach((accordionButton, idx) => {
          if (
            idx !== panelIndex &&
            accordionButton.getAttribute("aria-expanded") === "true"
          ) {
            accordionButton.click();
          }
        });

        if (targetButton.getAttribute("aria-expanded") !== "true") {
          targetButton.click();
        }
      }
    }, LEFT_RAIL_PANEL_DELAY_MS);
  });
};

export const initFloatingPlots = ({
  hostId,
  railId,
  leftSidebarId,
  leftSidebarRailId,
  mainBoundsId,
  panelConfigs,
  debounce,
}) => {
  if (typeof debounce !== "function") {
    throw new TypeError(
      "initFloatingPlots requires a debounce function",
    );
  }

  const host = document.getElementById(hostId);
  const rail = document.getElementById(railId);
  const leftSidebar = document.getElementById(leftSidebarId);
  const leftSidebarRail = document.getElementById(leftSidebarRailId);

  const getMainBoundsRect = () => {
    const mainPanel = document.getElementById(mainBoundsId);
    if (mainPanel) {
      return mainPanel.getBoundingClientRect();
    }
    if (!host) {
      return document.body.getBoundingClientRect();
    }
    return host.getBoundingClientRect();
  };

  initLeftSidebarIconRail({
    leftSidebar,
    rail: leftSidebarRail,
  });

  initFloatingPlotWindows({
    host,
    rail,
    leftSidebar,
    getMainBoundsRect,
    panelConfigs,
    debounce,
  });
};

export const requestFloatingPlotRefresh = (panelIds = []) => {
  window.dispatchEvent(
    new CustomEvent(FLOATING_PLOTS_REFRESH_EVENT, {
      detail: { panelIds },
    }),
  );
};
