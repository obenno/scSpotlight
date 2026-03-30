import html2canvas from "html2canvas";

export function createNoteElement(plotEl, noteId) {
  const noteEl = document.createElement("div");
  noteEl.id = noteId;
  noteEl.classList.add("mainClusterPlotNote", "shadow");
  noteEl.style.zIndex = "30";
  plotEl.appendChild(noteEl);
}

export function showNoteElement(noteId, text, color) {
  const noteEl = document.getElementById(noteId);
  if (!noteEl) return;
  noteEl.style.display = null;
  noteEl.style.opacity = 0.8;
  noteEl.style.background = color;
  noteEl.textContent = text;
}

export function hideNoteElement(noteId) {
  const noteEl = document.getElementById(noteId);
  if (!noteEl) return;
  noteEl.style.display = "none";
}

export function createLabelSliderElement({ plotEl, id, labelSize, onInput, onInit }) {
  const slider = document.createElement("div");
  slider.id = id;
  slider.classList.add("label-slider");
  slider.style.position = "absolute";
  slider.style.zIndex = "30";
  slider.style.pointerEvents = "auto";

  const sliderInput = document.createElement("input");
  sliderInput.type = "range";
  sliderInput.value = labelSize;
  sliderInput.min = 0;
  sliderInput.max = 50;
  sliderInput.style.opacity = 0.6;
  sliderInput.style.width = "6rem";
  slider.appendChild(sliderInput);

  sliderInput.addEventListener("mouseover", () => {
    sliderInput.style.opacity = 0.8;
  });
  sliderInput.addEventListener("mouseout", () => {
    sliderInput.style.opacity = 0.6;
  });
  sliderInput.addEventListener("input", (event) => {
    if (typeof onInput === "function") {
      onInput(event.target.value);
    }
  });

  plotEl.appendChild(slider);
  if (typeof onInit === "function") {
    onInit();
  }
}

export function createInfoWidgetElement({ plotEl, id }) {
  const infoEl = document.createElement("div");
  infoEl.id = id;
  infoEl.setAttribute("tabindex", "0");
  infoEl.style.position = "absolute";
  infoEl.style.zIndex = "30";
  infoEl.style.pointerEvents = "auto";

  const infoTitleEl = document.createElement("div");
  infoTitleEl.id = "info-title";
  const infoContentEl = document.createElement("div");
  infoContentEl.id = "info-content";
  const introduction = [
    "Pan: Click and drag your mouse.",
    "Zoom: Scroll vertically.",
    "Lasso: Pressing <kbd>SHIFT</kbd> and drag your mouse.",
    "Change slider to adjust label size.",
    "Click download icon to save the image.",
  ];

  for (let i = 0; i < introduction.length; ++i) {
    const li = document.createElement("li");
    li.innerHTML = introduction[i];
    infoContentEl.appendChild(li);
  }

  infoEl.appendChild(infoContentEl);
  infoEl.appendChild(infoTitleEl);
  plotEl.appendChild(infoEl);
}

export function createCellCountElement({ plotEl, id, count }) {
  const countEl = document.createElement("div");
  countEl.id = id;
  countEl.classList.add("mainClusterPlotCellCount");
  countEl.style.position = "absolute";
  countEl.style.zIndex = "30";
  countEl.style.pointerEvents = "none";

  const formatCount = (value) => new Intl.NumberFormat().format(Math.max(0, Number(value) || 0));
  const createMetric = (label, value, valueClass) => {
    const metricEl = document.createElement("span");
    metricEl.classList.add("cell-count-metric");

    const labelEl = document.createElement("span");
    labelEl.classList.add("cell-count-label");
    labelEl.textContent = label;

    const valueEl = document.createElement("span");
    valueEl.classList.add("cell-count-value", valueClass);
    valueEl.textContent = formatCount(value);

    metricEl.appendChild(labelEl);
    metricEl.appendChild(valueEl);
    return metricEl;
  };

  countEl.appendChild(createMetric("Total", count, "cell-count-total"));
  countEl.appendChild(createMetric("Selected", 0, "cell-count-selected"));
  plotEl.appendChild(countEl);
}

export function updateCellCountElement({ plotEl, id, totalCount = null, selectedCount = null }) {
  const countEl = plotEl?.querySelector(`#${id}`);
  if (!countEl) return;

  const formatCount = (value) => new Intl.NumberFormat().format(Math.max(0, Number(value) || 0));

  if (totalCount != null) {
    const totalEl = countEl.querySelector(".cell-count-total");
    if (totalEl) totalEl.textContent = formatCount(totalCount);
  }

  if (selectedCount != null) {
    const selectedEl = countEl.querySelector(".cell-count-selected");
    if (selectedEl) selectedEl.textContent = formatCount(selectedCount);
  }
}

export function createDownloadIconElement({ plotEl, id, catLegendEl, expLegendEl }) {
  const downloadEl = document.createElement("div");
  downloadEl.id = id;
  downloadEl.style.width = "2rem";
  downloadEl.style.height = "2rem";
  downloadEl.style.position = "absolute";
  downloadEl.style.zIndex = "30";
  downloadEl.style.bottom = "1%";
  downloadEl.style.left = "9.5rem";
  downloadEl.style.padding = "0.2rem";
  downloadEl.style.display = "flex";
  downloadEl.style.justifyContent = "center";
  downloadEl.style.alignItems = "center";
  downloadEl.style.pointerEvents = "auto";

  const ns = "http://www.w3.org/2000/svg";
  const icon = document.createElementNS(ns, "svg");
  icon.setAttribute("width", "100%");
  icon.setAttribute("height", "100%");
  icon.setAttribute("viewBox", "0 0 24 24");
  icon.style.overflow = "visible";
  icon.style.width = "100%";
  icon.style.height = "100%";

  const path = document.createElementNS(ns, "path");
  path.setAttribute("d", "M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z");
  path.setAttribute("fill", "#fff");
  path.setAttribute("stroke", "rgba(var(--bs-secondary-rgb), 0.4)");
  path.setAttribute("stroke-width", "1.5");
  icon.appendChild(path);

  downloadEl.appendChild(icon);

  icon.addEventListener("mouseover", () => {
    path.setAttribute("stroke", "rgba(var(--bs-secondary-rgb), 1)");
  });
  icon.addEventListener("mouseout", () => {
    path.setAttribute("stroke", "rgba(var(--bs-secondary-rgb), 0.4)");
  });

  downloadEl.addEventListener("click", () => {
    const scatterCanvas = html2canvas(plotEl.querySelector("#canvas-wrapper"), {
      backgroundColor: null,
      scale: window.devicePixelRatio * 4,
    });
    scatterCanvas.then((canvas) => {
      const scatterWidth = parseFloat(plotEl.parentElement.scrollWidth);
      const scatterHeight = parseFloat(plotEl.parentElement.scrollHeight);

      const catLegendClone = catLegendEl.cloneNode(true);
      catLegendClone.style.width = "200px";

      const expLegendClone = expLegendEl.cloneNode(true);
      expLegendClone.style.width = "100%";
      expLegendClone.style.marginLeft = "5px";
      expLegendClone.style.marginRight = "5px";
      expLegendClone.style.height = "10px";

      const tempDiv = document.createElement("div");
      tempDiv.style.width = 5 + 5 + scatterWidth + 5 + catLegendClone.style.width + 5 + "px";
      tempDiv.style.height = Math.max(scatterHeight, catLegendClone.style.height) + "px";
      tempDiv.style.position = "absolute";
      tempDiv.style.left = "-9999px";
      tempDiv.style.display = "flex";
      tempDiv.style.justifyContent = "space-between";
      tempDiv.style.alignItems = "center";
      tempDiv.style.overflow = "hidden";

      const canvasColDiv = document.createElement("div");
      canvasColDiv.style.margin = "5px";
      canvasColDiv.style.padding = 0;
      canvasColDiv.style.alignItems = "center";
      canvasColDiv.style.justifyContent = "center";
      canvasColDiv.appendChild(canvas);
      tempDiv.appendChild(canvasColDiv);

      const legendColDiv = document.createElement("div");
      legendColDiv.style.display = "flex";
      legendColDiv.style.flexDirection = "column";
      legendColDiv.style.width = "200px";
      legendColDiv.style.margin = "5px";
      legendColDiv.style.padding = 0;
      legendColDiv.style.alignItems = "center";
      legendColDiv.style.justifyContent = "center";
      legendColDiv.appendChild(catLegendClone);
      legendColDiv.appendChild(expLegendClone);
      tempDiv.appendChild(legendColDiv);

      document.body.appendChild(tempDiv);
      html2canvas(tempDiv, {
        backgroundColor: null,
        scale: window.devicePixelRatio * 4,
      }).then((mergedCanvas) => {
        downloadCanvasAsPNG(mergedCanvas, "scatter.png");
        document.body.removeChild(tempDiv);
      });
    });
  });

  plotEl.appendChild(downloadEl);
}

function downloadCanvasAsPNG(canvas, fileName = "canvas.png") {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (!blob) {
        reject(new Error("Canvas to Blob conversion failed"));
        return;
      }

      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = fileName;

      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);

      URL.revokeObjectURL(url);
      resolve();
    }, "image/png");
  });
}
