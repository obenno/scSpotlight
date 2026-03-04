export const resize_infoBox = (mainPlotEl, infoBoxEl, targetHeight) => {
    // This function sets the floating infoBox panel height.
    // mainPlotEl is kept for backward compatibility with existing calls.
    void mainPlotEl;
    if (!infoBoxEl) return;
    infoBoxEl.style.height = `${targetHeight}px`;
    infoBoxEl.style.overflowX = "hidden";
    infoBoxEl.style.overflowY = "auto";
};

export const update_collapse_icon = (iconId) => {
    const iconButton = document.getElementById(iconId);
    if (!iconButton) return;

    const icon = iconButton.querySelector("i");
    if (!icon) return;

    const isExpanded = iconButton.getAttribute("aria-expanded") === "true";
    icon.classList.toggle("bi-arrows-collapse", isExpanded);
    icon.classList.toggle("bi-arrows-angle-expand", !isExpanded);
};
