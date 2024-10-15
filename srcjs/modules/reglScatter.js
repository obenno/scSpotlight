import createScatterplot, { createRenderer } from "regl-scatterplot";
import * as d3 from "d3";
import html2canvas from "html2canvas";

export class reglScatterCanvas {
  // this will create a element containing all the elements of the scatter plot
  // typical we usd a containerID "parent-wrapper"
  constructor(containerID) {
    // create parent container
    this.plotEl = document.createElement("div");
    this.plotEl.id = containerID;
    // by default, use 100% to fit into outside container
    this.plotEl.style.width = "100%";
    this.plotEl.style.height = "100%";

    // category legend element
    this.catLegendEl = document.createElement("div");
    this.catLegendEl.id = containerID + "-" + "catLegend";
    this.catLegendEl.classList.add("html-fill-container");

    // expression legend element
    this.expLegendEl = document.createElement("div");
    this.expLegendEl.id = containerID + "-" + "expLegend";
    this.expLegendEl.classList.add("html-fill-container");

    // init origData slot to store orignal data
    this.origData = {
      reductionData: {},
      cellMetaData: {},
      expressionData: {},
    };
    // init plotData
    this.plotData = {
      pointsData: [],
      colorData: [],
      labelData: [],
      zType: [],
      cells: [],
      panelTitles: [],
    };
    // init plotMetaData
    this.plotMetaData = {
      mode: null,
      nPanels: null,
      group_by: null,
      split_by: null,
      catColors: [],
      selectedFeatures: [],
      moduleScore: false,
      labelSize: 0,
    };

    // Create a reusable renderer
    this.renderer = createRenderer();
    // Create empty array to store scatterplots instances
    this.scatterplots = [];
  }

  updateReductionData(reductionData) {
    for (let key in reductionData) {
      this.origData.reductionData[key] = new Float32Array(reductionData[key]);
    }
  }

  updateCellMetaData(cellMetaData) {
    this.origData.cellMetaData = cellMetaData;
  }

  updateExpressionData(expressionData) {
    for (let key in expressionData) {
      this.origData.expressionData[key] = new Float32Array(expressionData[key]);
    }
  }

  updatePlotMetaData(group_by = null, split_by = null, moduleScore = false) {
    // update plotMetaData according to input group_by and split_by infromation
    // supported mode:
    // clusterOnly             => normal scatter only
    // cluster+expr+noSplit    => when selected one feature and split_by == null
    // cluster+expr+twoSplit   => when selected one feature, and split_by has two levels
    // cluster+multiSplit      => no selected feature, split_by != null
    // cluster+expr+multiSplit => when selected one feature, and split_by has more than two levels
    const nGroupBy = group_by
      ? new Set(this.origData.cellMetaData[group_by]).size
      : 0;
    const nSplitBy = split_by
      ? new Set(this.origData.cellMetaData[split_by]).size
      : 0;
    // confirm plotting mode
    let plottingMode = "clusterOnly";
    let nPanels = 1;
    if (this.plotMetaData.selectedFeatures.length === 1 && nSplitBy === 0) {
      plottingMode = "cluster+expr+noSplit";
      nPanels = 2;
    } else if (
      this.plotMetaData.selectedFeatures.length === 1 &&
      nSplitBy === 2
    ) {
      plottingMode = "cluster+expr+twoSplit";
      nPanels = 4;
    } else if (
      this.plotMetaData.selectedFeatures.length === 1 &&
      nSplitBy > 2
    ) {
      plottingMode = "cluster+expr+multiSplit";
      nPanels = nSplitBy;
    } else if (
      this.plotMetaData.selectedFeatures.length === 0 &&
      nSplitBy > 1
    ) {
      plottingMode = "cluster+multiSplit";
      nPanels = nSplitBy;
    } else {
      plottingMode = "clusterOnly";
      nPanels = 1;
    }
    const catColors = hue_pal(nGroupBy);
    const plotMetaData = {
      nPanels: nPanels,
      mode: plottingMode,
      group_by: group_by,
      split_by: split_by,
      catColors: catColors,
      moduleScore: moduleScore,
    };
    console.log("plotMetaData: ", plotMetaData);
    for (let key in plotMetaData) {
      this.plotMetaData[key] = plotMetaData[key];
    }
  }

  clear() {
    // clear elements and plotData
    while (this.plotEl.firstChild) {
      this.plotEl.firstChild.remove();
    }
    while (this.catLegendEl.firstChild) {
      this.catLegendEl.firstChild.remove();
    }
    while (this.expLegendEl.firstChild) {
      this.expLegendEl.firstChild.remove();
    }
    // clear previous scatterplot instances, important!
    this.scatterplots.forEach((e) => {
      if (!e.get("isDestroyed")) {
        e.destroy();
      }
    });

    // Note: origData will not to modified or removed, only clear plotData and plotMetaData
    this.plotData = {
      pointsData: [],
      colorData: [],
      labelData: [],
      zType: [],
      cells: [],
      panelTitles: [],
    };

    // clear plotMetaData
    // this.plotMetaData.labelSize shall remains the same as previous
    this.plotMetaData.mode = null;
    this.plotMetaData.nPanels = null;
    this.plotMetaData.group_by = null;
    this.plotMetaData.split_by = null;
    this.plotMetaData.catColors = [];
    //this.plotMetaData.selectedFeatures = [];
    //this.plotMetaData.moduleScore = false;

    this.renderer.refresh();

    // add element position adjustment observer
    //const adjustObserver = new MutationObserver((mutationList, observer) => {
    //    for (const mutation of mutationList) {
    //        if(mutation.target.parentElement){
    //            mutation.target.parentElement.addEventListener('scroll', () => {
    //                const containerEl = entry.target.parentElement;
    //
    //                const infoEl = containerEl.querySelector("#info");
    //                infoEl.style.bottom = "1%";
    //                infoEl.style.bottom = `calc(${infoEl.style.bottom} - ${containerEl.scrollTop}px)`;
    //
    //                const noteEl = containerEl.querySelector("#scatterPlotNote");
    //                noteEl.style.bottom = "2%";
    //                noteEl.style.bottom = `calc(${noteEl.style.bottom} - ${containerEl.scrollTop}px)`;
    //            });
    //        }
    //    }
    //});
    //
    //adjustObserver.observe(this.plotEl, { attributes: true, childList: true, subtree: true });
  }

  generatePlotEl() {
    this.updatePlotData();
    this.updateCanvas();
    this.updateCatLegend();
    this.updateExpLegend();
  }

  updateCanvas() {
    // append canvas elements, wrapped by an outter element with id "canvas-wrapper"
    this.createCanvas("canvas-wrapper");
    // create and append note element with id: scatterPlotNote
    this.createNote("scatterPlotNote");
    // create info widget
    this.createInfoWidget("info");
    // create slider widget
    this.createLabelSlider("labelSlider");
    // create download icon
    this.createDownloadIcon("downloadIcon");

    this.renderer.refresh();
    // Create scatter instances
    this.scatterplots = Array.from(
      this.plotEl.querySelectorAll(".scatter-canvas"),
    ).map((canvas) =>
      this.constructor.createReglScatterInstance(this.renderer, canvas),
    );

    // populate all of the instances
    this.populate_instance("scatterPlotNote");
    this.showCatLabel();

    // remove pointsData in plotData to save memory
    //this.plotData.pointsData = [];
  }

  updatePlotData() {
    // reset plotData
    let plotData = {
      pointsData: [],
      colorData: [],
      labelData: [],
      zType: [],
      cells: [],
      panelTitles: [],
    };

    let point_XY_data = this.constructor.prepare_XY_data(
      this.origData.reductionData,
      this.origData.cellMetaData,
      this.plotMetaData.mode,
      this.plotMetaData.nPanels,
      this.plotMetaData.split_by,
    );
    console.log("point_XY_data", point_XY_data);
    // select the first gene in expression data
    //let selectedFeature = Object.keys(this.origData.expressionData)[0] ?? null;
    //this.updatePlotMetaData({ "selectedFeature" : [selectedFeature] });
    let zData = this.constructor.prepare_Z_data(
      this.origData.cellMetaData,
      this.origData.expressionData[this.plotMetaData.selectedFeatures],
      this.plotMetaData.mode,
      this.plotMetaData.nPanels,
      this.plotMetaData.group_by,
      this.plotMetaData.split_by,
      this.plotMetaData.catColors,
      this.plotMetaData.selectedFeatures,
      this.plotMetaData.moduleScore,
    );
    console.log("zData: ", zData);
    // create plotData
    for (let i = 0; i < this.plotMetaData.nPanels; i++) {
      plotData["pointsData"][i] = {
        x: point_XY_data[i].x,
        y: point_XY_data[i].y,
        z: zData["point_Z_data"][i],
      };
    }

    // labelData stores note/tooltip data
    plotData["labelData"] = zData["labelData"];
    plotData["panelTitles"] = zData["panelTitles"];
    plotData["colorData"] = zData["colorData"];
    plotData["zType"] = zData["zType"];
    plotData["cells"] = zData["cells"];

    // generate category label data for each panel
    let catTitles = [
      ...new Set(this.origData.cellMetaData[this.plotMetaData.group_by]),
    ].sort(sortStringArray);

    // generate category label coordinates
    // for each panel, assign empty value for expr panel
    let labelCoordinates = [];
    for (let k = 0; k < plotData.pointsData.length; ++k) {
      labelCoordinates[k] = [];
      let labelData = plotData.pointsData[k].z;
      catTitles.forEach((e, i) => {
        let x_data = [];
        let y_data = [];
        labelData.forEach((el, idx) => {
          let label = catTitles[el];
          if (label == e) {
            x_data.push(plotData.pointsData[k].x[idx]);
            y_data.push(plotData.pointsData[k].y[idx]);
          }
        });

        labelCoordinates[k].push({
          x: d3.mean(x_data),
          y: d3.mean(y_data),
          label: e,
        });
      });
    }

    // catLabelData stores cat label coordinates for each panel
    plotData["catLabelCoordinates"] = labelCoordinates;
    this.plotData = plotData;
  }

  // function to create grid view in the element (mainClusterPlot div)
  // here will always be div "parent-wrapper"
  createCanvas(canvasContainerID) {
    // create plot panel
    let nCols = null;

    if (this.plotMetaData.nPanels >= 2) {
      nCols = 2;
    } else {
      nCols = 1;
    }
    let nRows = Math.ceil(this.plotMetaData.nPanels / nCols);

    // retrieve mainClusterPlot div
    let canvasContainer = document.createElement("div");
    canvasContainer.id = canvasContainerID;
    canvasContainer.style.display = "grid";

    // use a min size 300px, in case too may panels
    canvasContainer.style.gridTemplateColumns = `repeat(${nCols}, minmax(300px, 1fr))`;
    canvasContainer.style.gridTemplateRows = `repeat(${nRows}, minmax(300px, 1fr))`;
    //el.style.gridTemplateColumns = `repeat(${ncols}, minmax(0px, 1fr))`;
    //el.style.gridTemplateRows = `repeat(${nrows}, minmax(0px, 1fr))`;
    canvasContainer.style.gap = "0.2rem";
    canvasContainer.style.width = "100%";
    canvasContainer.style.height = "100%";

    for (let i = 0; i < this.plotMetaData.nPanels; i++) {
      const canvas_wrapper = document.createElement("div");
      // add fill class
      canvas_wrapper.classList.add("html-fill-item");
      canvas_wrapper.classList.add("html-fill-container");
      canvas_wrapper.style.position = "relative";
      // add border style for multiple panels
      if (this.plotMetaData.nPanels > 1) {
        canvas_wrapper.style.borderWidth = "1px";
        canvas_wrapper.style.borderStyle = "solid";
        canvas_wrapper.style.borderColor = "#D3D3D3";
      }

      const plotTitle = document.createElement("div");
      plotTitle.classList.add("mainClusterPlotTitle");
      plotTitle.innerHTML = this.plotData.panelTitles[i];
      canvas_wrapper.appendChild(plotTitle);

      const scatterCanvas = document.createElement("canvas");
      scatterCanvas.classList.add("scatter-canvas");
      scatterCanvas.style.position = "absolute";
      scatterCanvas.style.width = "100%";
      scatterCanvas.style.height = "100%";
      //scatterCanvas.style.zIndex = 1;
      canvas_wrapper.appendChild(scatterCanvas);

      const labelCanvas = document.createElement("canvas");
      labelCanvas.classList.add("label-canvas");
      labelCanvas.style.position = "absolute";
      labelCanvas.style.width = "100%";
      labelCanvas.style.height = "100%";
      labelCanvas.style.inset = 0;
      labelCanvas.style.pointerEvents = "none";
      labelCanvas.width = "600px";
      labelCanvas.height = "600px";
      // Add resize events to label canvas
      const canvasObserver = new ResizeObserver((entries) => {
        for (const entry of entries) {
          const { width, height } = entry.target.getBoundingClientRect();
          //canvas.width = window.innerWidth * window.devicePixelRatio;
          //canvas.height = window.innerHeight * window.devicePixelRatio;
          entry.target.width = width * window.devicePixelRatio;
          entry.target.height = height * window.devicePixelRatio;
        }
      });
      canvasObserver.observe(labelCanvas);

      canvas_wrapper.appendChild(labelCanvas);

      canvasContainer.appendChild(canvas_wrapper);
    }
    this.plotEl.appendChild(canvasContainer);
  }

  showCatLabel() {
    // Add label
    this.scatterplots.forEach((sp, idx) => {
      //console.log("baseFontSize: ", baseFontSize);
      sp.subscribe("drawing", ({ xScale, yScale }) => {
        let sliderInput = this.plotEl
          .querySelector(".label-slider")
          .querySelector("input");
        let baseFontSize = sliderInput ? sliderInput.value : 0;
        if (typeof this.plotData.catLabelCoordinates[idx] != "undefined") {
          this.constructor.fillLabelCanvas(
            this.plotData.catLabelCoordinates[idx],
            Array.from(this.plotEl.querySelectorAll(".label-canvas"))[idx],
            baseFontSize,
            xScale,
            yScale,
          );
        }
      });
    });
  }

  createLabelSlider(ElId) {
    const slider = document.createElement("div");
    slider.id = ElId;
    slider.classList.add("label-slider");
    const sliderInput = document.createElement("input");
    sliderInput.type = "range";
    sliderInput.value = this.plotMetaData.labelSize;
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
    // Add Eventlistener
    sliderInput.addEventListener("input", (event) => {
      this.plotMetaData.labelSize = event.target.value;
      let canvas = Array.from(this.plotEl.querySelectorAll(".label-canvas"));
      canvas.forEach((e, i) =>
        this.constructor.fillLabelCanvas(
          this.plotData.catLabelCoordinates[i],
          e,
          event.target.value,
          this.scatterplots[i].get("xScale"),
          this.scatterplots[i].get("yScale"),
        ),
      );
    });

    this.plotEl.appendChild(slider);
  }

  static fillLabelCanvas(
    labelCoordinates,
    textCanvas,
    baseFontSize,
    xScale,
    yScale,
  ) {
    // https://github.com/flekschas/regl-scatterplot/blob/master/example/text-labels.js#L128
    // here labelCoordinates was calculated by original point data
    //
    const ctx = textCanvas.getContext("2d");
    ctx.clearRect(0, 0, textCanvas.width, textCanvas.height);
    ctx.fillStyle = "rgba(0, 0, 0, 1)";
    //const baseFontSize = 20;

    ctx.font = `700 ${baseFontSize * window.devicePixelRatio}px Arial, Helvetica, sans-serif`;
    ctx.textAlign = "center";
    // add shadow
    ctx.shadowOffsetX = 3;
    ctx.shadowOffsetY = 3;
    ctx.shadowColor = "rgba(0,0,0,0.3)";
    ctx.shadowBlur = 4;
    const dpr = window.devicePixelRatio;

    for (let i = 0; i < labelCoordinates.length; i++) {
      const x = labelCoordinates[i].x;
      const y = labelCoordinates[i].y;
      ctx.fillText(
        labelCoordinates[i].label,
        xScale(x) * dpr,
        yScale(y) * dpr,
        // if use on single points, add a little adjustment
        //yScale(y) * dpr - baseFontSize * 1.2 * dpr
      );
    }
  }

  static createReglScatterInstance(renderer, canvas) {
    // init reglScatter instance
    // share a renderer created before invoking this function
    let scatterplot = createScatterplot({
      renderer,
      canvas,
      //width,
      //height,
      xScale: d3.scaleLinear().domain([-1, 1]).nice(),
      yScale: d3.scaleLinear().domain([-1, 1]).nice(),
      lassoMinDelay: 10,
      lassoMinDist: 2,
      showReticle: true,
      reticleColor: [1, 1, 0.878431373, 0.33],
      pointSize: 3,
      opacity: 0.5,
      keyMap: { shift: "lasso" }, // disable rotate
      lassoOnLongPress: true,
      lassoInitiator: true,
    });

    return scatterplot;
  }

  generateNoteText(spIndex, pointId) {
    let mode = this.plotMetaData.mode;
    let group_by = this.plotMetaData.group_by;
    let split_by = this.plotMetaData.split_by;
    let metaData = this.origData.cellMetaData;
    let expressionData = this.origData.expressionData;
    let selectedFeature = this.plotMetaData.selectedFeatures[0];
    let text = null;
    let prefix = null;
    let split_category = {};
    let split_expr = {};
    switch (mode) {
      case "clusterOnly":
        prefix = "Cat: ";
        text = prefix.concat(metaData[group_by][pointId]);
        break;
      case "cluster+expr+noSplit":
        if (spIndex == 0) {
          prefix = "Cat: ";
          text = prefix.concat(metaData[group_by][pointId]);
        } else {
          prefix = "Expr: ";
          text = prefix.concat(
            d3.format(".3f")(expressionData[selectedFeature][pointId]),
          );
        }
        break;
      case "cluster+expr+twoSplit":
        split_category = splitArrByMeta(metaData[group_by], metaData[split_by]);
        split_expr = splitArrByMeta(
          expressionData[selectedFeature],
          metaData[split_by],
        );

        if (spIndex === 0) {
          prefix = "Cat: ";
          text = prefix.concat(
            split_category[Object.keys(split_category)[0]][pointId],
          );
        } else if (spIndex === 1) {
          prefix = "Expr: ";
          text = prefix.concat(
            d3.format(".3f")(split_expr[Object.keys(split_expr)[0]][pointId]),
          );
        } else if (spIndex === 2) {
          prefix = "Cat: ";
          text = prefix.concat(
            split_category[Object.keys(split_category)[1]][pointId],
          );
        } else if (spIndex === 3) {
          prefix = "Expr: ";
          text = prefix.concat(
            d3.format(".3f")(split_expr[Object.keys(split_expr)[1]][pointId]),
          );
        }
        break;
      case "cluster+multiSplit":
        split_category = splitArrByMeta(metaData[group_by], metaData[split_by]);
        prefix = "Cat: ";
        text = prefix.concat(
          split_category[Object.keys(split_category)[spIndex]][pointId],
        );
      case "cluster+expr+multiSplit":
        split_expr = splitArrByMeta(
          expressionData[selectedFeature],
          metaData[split_by],
        );
        prefix = "Expr: ";
        text = prefix.concat(
          d3.format(".3f")(
            split_expr[Object.keys(split_expr)[spIndex]][pointId],
          ),
        );
        break;
    }
    // empty the intermedia data
    split_category = {};
    split_expr = {};
    return text;
  }

  populate_instance(noteId) {
    // zType could be either "category" or "expr"
    // regl-scatterplot will only treat float numbers of [0,1] as continuous value
    let exprColorScale = d3.interpolate("#E5E4E2", "#800080"); // lightgrey, iris

    for (let i = 0; i < this.scatterplots.length; i++) {
      let scatterplot = this.scatterplots[i];
      // clear scatter instance
      scatterplot.clear();
      // init options
      let opacity = 0.6;
      let pointSize = 3;
      let performanceMode = false;
      let pointsData = this.plotData["pointsData"][i];

      if (pointsData.x.length < 15000) {
        opacity = 0.8;
        pointSize = 5;
      } else if (pointsData.x.length > 50000 && pointsData.x.length <= 500000) {
        opacity = 0.6;
        pointSize = 3;
      } else if (
        pointsData.x.length > 500000 &&
        pointsData.x.length <= 1000000
      ) {
        opacity = 0.4;
        pointSize = 1;
        performanceMode = true;
      } else if (
        pointsData.x.length > 1000000 &&
        pointsData.x.length <= 2000000
      ) {
        opacity = 0.2;
        pointSize = 0.5;
        performanceMode = true;
      } else if (pointsData.x.length > 2000000) {
        opacity = 0.2;
        pointSize = 0.2;
        performanceMode = true;
      }

      // set scatter
      scatterplot.set({
        colorBy: "z",
        opacity: opacity,
        pointSize: pointSize,
        pointColor: this.plotData["colorData"][i],
        performanceMode: performanceMode,
      });

      let zType = this.plotData["zType"][i];
      if (zType == "category") {
        scatterplot.subscribe("pointOver", (pointId) => {
          let text = this.generateNoteText(i, pointId);
          reglScatterCanvas.showNote(
            noteId,
            text,
            this.plotData.colorData[i][this.plotData.pointsData[i].z[pointId]],
          );
        });
      } else {
        scatterplot.subscribe("pointOver", (pointId) => {
          let text = this.generateNoteText(i, pointId);
          reglScatterCanvas.showNote(
            noteId,
            text,
            rgbToHex(exprColorScale(this.plotData.pointsData[i].z[pointId])),
          );
        });
      }

      scatterplot.subscribe("pointOut", () => {
        reglScatterCanvas.hideNote(noteId);
      });

      // select or other events could be subscribed after creating the instance
      scatterplot.draw(pointsData);
    }
  }

  createNote(noteId) {
    let noteEl = document.createElement("div");
    noteEl.id = noteId;
    noteEl.classList.add("mainClusterPlotNote");
    noteEl.classList.add("shadow");

    this.plotEl.appendChild(noteEl);
  }

  // note manipulation to mimic tooltips
  static showNote(noteId, text, color) {
    let noteEl = document.getElementById(noteId);
    noteEl.style.display = null;
    noteEl.style.opacity = 0.8;
    noteEl.style.background = color;
    noteEl.textContent = text;
  }

  static hideNote(noteId) {
    let noteEl = document.getElementById(noteId);
    noteEl.style.display = "none";
  }

  createInfoWidget(infoId) {
    let infoEl = document.createElement("div");
    infoEl.id = infoId;
    infoEl.setAttribute("tabindex", "0");
    let infoTitleEl = document.createElement("div");
    infoTitleEl.id = "info-title";
    let infoContentEl = document.createElement("div");
    infoContentEl.id = "info-content";
    let introduction = [
      "Pan: Click and drag your mouse.",
      "Zoom: Scroll vertically.",
      // disable rotate, the label canvas will not synchronize
      //`Rotate: While pressing <kbd>ALT</kbd>, click and drag your mouse.`,
      `Lasso: Pressing <kbd>SHIFT</kbd> and drag your mouse.`,
      "Change slider to adjust label size.",
      "Click download icon to save the image.",
    ];

    for (let i = 0; i < introduction.length; ++i) {
      let li = document.createElement("li");
      li.innerHTML = introduction[i];
      infoContentEl.appendChild(li);
    }

    infoEl.appendChild(infoContentEl);
    infoEl.appendChild(infoTitleEl);
    this.plotEl.appendChild(infoEl);
  }

  createDownloadIcon(elId) {
    const downloadEl = document.createElement("div");
    downloadEl.id = elId;
    downloadEl.style.width = "2rem";
    downloadEl.style.height = "2rem";
    downloadEl.style.position = "absolute";
    downloadEl.style.zIndex = 1;
    downloadEl.style.bottom = "1%";
    downloadEl.style.left = "9.5rem";
    downloadEl.style.padding = "0.2rem";
    //downloadEl.style.backgroundColor = "rgba(var(--bs-secondary-rgb), 0.4)";
    downloadEl.style.display = "flex";
    downloadEl.style.justifyContent = "center";
    downloadEl.style.alignItems = "center";
    //downloadEl.style.overflow = "hidden;"
    //downloadEl.style.transition = "background 0.15s cubic-bezier(0.25, 0.1, 0.25, 1)";

    const ns = "http://www.w3.org/2000/svg";
    const icon = document.createElementNS(ns, "svg");
    icon.setAttribute("width", "100%");
    icon.setAttribute("height", "100%");
    icon.setAttribute("viewBox", "0 0 24 24");
    //icon.style.background = "rgba(255,0,0,0.1)";
    icon.style.overflow = "visible";
    icon.style.width = "100%";
    icon.style.height = "100%";

    const path = document.createElementNS(ns, "path");
    path.setAttribute("d", "M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z");
    path.setAttribute("fill", "#fff");
    path.setAttribute("stroke", "rgba(var(--bs-secondary-rgb), 0.4)"); // Red stroke
    path.setAttribute("stroke-width", "1.5"); // Thin stroke
    icon.appendChild(path);

    downloadEl.appendChild(icon);

    icon.addEventListener("mouseover", () => {
      path.setAttribute("stroke", "rgba(var(--bs-secondary-rgb), 1)");
    });
    icon.addEventListener("mouseout", () => {
      path.setAttribute("stroke", "rgba(var(--bs-secondary-rgb), 0.4)");
    });

    downloadEl.addEventListener("click", () => {
      const scatterCanvas = html2canvas(
        this.plotEl.querySelector("#canvas-wrapper"),
        {
          backgroundColor: null,
          scale: window.devicePixelRatio * 4,
        },
      );
      scatterCanvas.then((canvas) => {
        // create new div with the same dimension
        const scatterWidth = parseFloat(this.plotEl.parentElement.scrollWidth);
        const scatterHeight = parseFloat(
          this.plotEl.parentElement.scrollHeight,
        );

        // clone catLegendEl
        const catLegendClone = this.catLegendEl.cloneNode(true);
        catLegendClone.style.width = "200px";

        // clone expLegendEl
        const expLegendClone = this.expLegendEl.cloneNode(true);
        expLegendClone.style.width = "100%";
        expLegendClone.style.marginLeft = "5px";
        expLegendClone.style.marginRight = "5px";
        expLegendClone.style.height = "10px";

        const tempDiv = document.createElement("div");

        tempDiv.style.width =
          5 + 5 + scatterWidth + 5 + catLegendClone.style.width + 5 + "px";
        tempDiv.style.height =
          Math.max(scatterHeight, catLegendClone.style.height) + "px";

        tempDiv.style.position = "absolute";
        tempDiv.style.left = "-9999px"; // Move off-screen
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
          backgroundColor: null, // or 'transparent'
          scale: window.devicePixelRatio * 4,
        }).then((canvas) => {
          downloadCanvasAsPNG(canvas, "scatter.png");
          document.body.removeChild(tempDiv);
        });
      });
    });
    this.plotEl.appendChild(downloadEl);
  }

  static prepare_Z_data(
    metaData,
    expressionData,
    mode,
    nPanels,
    group_by,
    split_by,
    catColors,
    selectedFeature,
    moduleScore,
    exprColorScale = d3.interpolate("#E5E4E2", "#800080"), // platinum, purple
  ) {
    // This function prepare Z data and associated data: labels, pointColors etc.
    let zData = {
      point_Z_data: [],
      colorData: [],
      //labelData: [],
      zType: [],
      cells: [],
      panelTitles: [],
    };
    let split_z = null;
    let split_category = null;
    let split_expr = null;
    let split_cells = null;
    let exprTitle = null;
    let exprTag = null;

    if (moduleScore) {
      exprTag = "ModuleScore: ";
      exprTitle = "ModuleScore";
    } else {
      exprTag = "Expr: ";
      exprTitle = selectedFeature;
    }
    // d3.interpolate will generate rgb value by default
    let exprColorMap = Array(51)
      .fill()
      .map((e, i) => i / 50)
      .map((e) => rgbToHex(exprColorScale(e)));
    //console.log("exprColorMap", exprColorMap);
    switch (mode) {
      case "clusterOnly":
        if (nPanels == 1) {
          // convert metaData array to integer array
          zData["point_Z_data"][0] = convert_stringArr_to_integer(
            metaData[group_by],
          );
          //zData["labelData"][0] = metaData[group_by].map((e) =>
          //  catTag.concat(e),
          //);
          zData["panelTitles"][0] = group_by;
          zData["colorData"][0] = catColors;
          zData["zType"][0] = "category";
          zData["cells"][0] = metaData["cells"];
        }
        break;
      case "cluster+expr+noSplit":
        if (nPanels == 2) {
          zData["point_Z_data"][0] = convert_stringArr_to_integer(
            metaData[group_by],
          );
          zData["point_Z_data"][1] =
            reglScatterCanvas.scaleDataZ(expressionData); // expr panel
          //zData["labelData"][0] = metaData[group_by].map((e) =>
          //  catTag.concat(e),
          //);
          //zData["labelData"][1] = [];
          //expressionData.forEach((e, i) => {
          //  zData["labelData"][1][i] = exprTag.concat(d3.format(".3f")(e));
          //});
          zData["panelTitles"][0] = group_by;
          zData["panelTitles"][1] = exprTitle;
          zData["colorData"][0] = catColors;
          zData["colorData"][1] = exprColorMap;
          zData["zType"][0] = "category";
          zData["zType"][1] = "expr";
          zData["cells"][0] = metaData["cells"];
          zData["cells"][1] = metaData["cells"];
        }
        break;
      case "cluster+expr+twoSplit":
        if (nPanels == 4) {
          split_z = splitArrByMeta(
            convert_stringArr_to_integer(metaData[group_by]),
            metaData[split_by],
          );
          split_category = splitArrByMeta(
            metaData[group_by],
            metaData[split_by],
          );
          split_cells = splitArrByMeta(metaData["cells"], metaData[split_by]);
          split_expr = splitArrByMeta(expressionData, metaData[split_by]);
          for (let i = 0; i < Object.keys(split_z).length; i++) {
            zData["point_Z_data"][i * 2] = split_z[Object.keys(split_z)[i]];
            //zData["labelData"][i * 2] = split_category[
            //  Object.keys(split_category)[i]
            //].map((e) => catTag.concat(e));
            zData["panelTitles"][i * 2] =
              Object.keys(split_category)[i] + " : " + group_by;
            zData["point_Z_data"][i * 2 + 1] = reglScatterCanvas.scaleDataZ(
              split_expr[Object.keys(split_expr)[i]],
            ); // expr panel
            //zData["labelData"][i * 2 + 1] = [];
            //split_expr[Object.keys(split_expr)[i]].forEach((e, idx) => {
            //  zData["labelData"][i * 2 + 1][idx] = exprTag.concat(
            //    d3.format(".3f")(e),
            //  );
            //});
            zData["panelTitles"][i * 2 + 1] =
              Object.keys(split_category)[i] + " : " + exprTitle;
            zData["colorData"][i * 2] = catColors;
            zData["colorData"][i * 2 + 1] = exprColorMap;
            zData["zType"][i * 2] = "category";
            zData["zType"][i * 2 + 1] = "expr";
            zData["cells"][i * 2] = split_cells[Object.keys(split_cells)[i]];
            zData["cells"][i * 2 + 1] = zData["cells"][i * 2];
          }
        }
        break;
      case "cluster+multiSplit":
        split_z = splitArrByMeta(
          convert_stringArr_to_integer(metaData[group_by]),
          metaData[split_by],
        );
        split_category = splitArrByMeta(metaData[group_by], metaData[split_by]);
        split_cells = splitArrByMeta(metaData["cells"], metaData[split_by]);

        for (let i = 0; i < Object.keys(split_z).length; i++) {
          zData["point_Z_data"][i] = split_z[Object.keys(split_z)[i]];
          //zData["labelData"][i] = split_category[
          //  Object.keys(split_category)[i]
          //].map((e) => catTag.concat(e));
          zData["panelTitles"][i] = Object.keys(split_category)[i];
          zData["colorData"][i] = catColors;
          zData["zType"][i] = "category";
          zData["cells"][i] = split_cells[Object.keys(split_cells)[i]];
        }
        break;
      case "cluster+expr+multiSplit":
        split_expr = splitArrByMeta(expressionData, metaData[split_by]);
        split_cells = splitArrByMeta(metaData["cells"], metaData[split_by]);
        for (let i = 0; i < Object.keys(split_expr).length; i++) {
          zData["point_Z_data"][i] = reglScatterCanvas.scaleDataZ(
            split_expr[Object.keys(split_expr)[i]],
          ); // expr panels
          //zData["labelData"][i] = [];
          //split_expr[Object.keys(split_expr)[i]].forEach((e, idx) => {
          //  zData["labelData"][i][idx] = exprTag.concat(d3.format(".3f")(e));
          //});
          zData["panelTitles"][i] = Object.keys(split_expr)[i];
          zData["colorData"][i] = exprColorMap;
          zData["zType"][i] = "expr";
          zData["cells"][i] = split_cells[Object.keys(split_cells)[i]];
        }
    }
    return zData;
  }

  static prepare_XY_data(reductionData, metaData, mode, nPanels, split_by) {
    // pointData is array of panels' regl-scatterplot x,y input
    // this function process data into an object
    let point_XY_data = [];
    let split_x = null;
    let split_y = null;
    let reductionConverted = reglScatterCanvas.scaleDataXY(reductionData);
    switch (mode) {
      case "clusterOnly":
        // only one panel
        if (nPanels == 1) {
          point_XY_data[0] = {
            x: reductionConverted.X,
            y: reductionConverted.Y,
          };
        }
        break;
      case "cluster+expr+noSplit":
        if (nPanels == 2) {
          point_XY_data[0] = {
            x: reductionConverted.X,
            y: reductionConverted.Y,
          };
          point_XY_data[1] = {
            x: reductionConverted.X,
            y: reductionConverted.Y,
          };
        }
        break;
      case "cluster+expr+twoSplit":
        if (nPanels == 4) {
          split_x = splitArrByMeta(reductionConverted.X, metaData[split_by]);
          split_y = splitArrByMeta(reductionConverted.Y, metaData[split_by]);
          for (let i = 0; i < Object.keys(split_x).length; i++) {
            point_XY_data[i * 2] = {
              x: split_x[Object.keys(split_x)[i]],
              y: split_y[Object.keys(split_y)[i]],
            };
            point_XY_data[i * 2 + 1] = {
              x: split_x[Object.keys(split_x)[i]],
              y: split_y[Object.keys(split_y)[i]],
            };
          }
        }
        break;
      case "cluster+multiSplit":
        split_x = splitArrByMeta(reductionConverted.X, metaData[split_by]);
        split_y = splitArrByMeta(reductionConverted.Y, metaData[split_by]);
        for (let i = 0; i < Object.keys(split_x).length; i++) {
          point_XY_data[i] = {
            x: split_x[Object.keys(split_x)[i]],
            y: split_y[Object.keys(split_y)[i]],
          };
        }
        break;
      case "cluster+expr+multiSplit":
        split_x = splitArrByMeta(reductionConverted.X, metaData[split_by]);
        split_y = splitArrByMeta(reductionConverted.Y, metaData[split_by]);
        for (let i = 0; i < Object.keys(split_x).length; i++) {
          point_XY_data[i] = {
            x: split_x[Object.keys(split_x)[i]],
            y: split_y[Object.keys(split_y)[i]],
          };
        }
    }
    return point_XY_data;
  }

  static scaleDataXY(dataXY) {
    // data is the object transformed from R
    // column name: X, Y
    let xmin = d3.min(dataXY.X);
    let xmax = d3.max(dataXY.X);
    let ymin = d3.min(dataXY.Y);
    let ymax = d3.max(dataXY.Y);
    let dataMin = d3.min([xmin, ymin]);
    let dataMax = d3.max([xmax, ymax]);

    const dScale = d3.scaleLinear([dataMin, dataMax], [-1, 1]).nice();
    let data = {
      X: dataXY.X.map(dScale),
      Y: dataXY.Y.map(dScale),
    };

    return data;
  }

  static scaleDataZ(arrayZ) {
    // arrayZ is a numeric array (expressionData)
    // regl-scatterplot treats z values ranging between [0,1] as continuous data
    let minValue = d3.min(arrayZ);
    let maxValue = d3.max(arrayZ);
    let zScale = d3.scaleLinear([minValue, maxValue], [0, 1]).nice();
    let arrayZ_converted = arrayZ.map((e) => zScale(e));
    return arrayZ_converted;
  }

  updateCatLegend() {
    const pointData_z = this.plotData["pointsData"].map((e) => e.z);

    // Add cluster legends, no legend for "cluster+expr+multiSplit" mode
    if (this.plotMetaData.mode != "cluster+expr+multiSplit") {
      let catTitles = [
        ...new Set(this.origData.cellMetaData[this.plotMetaData.group_by]),
      ].sort(sortStringArray);
      let catNumbers = catTitles.map((e, i) => {
        let counts = 0;
        this.origData.cellMetaData[this.plotMetaData.group_by].forEach((d) => {
          if (d == e) {
            counts++;
          }
        });
        return counts;
      });
      this.plotMetaData.catColors.forEach((e, i) => {
        let legendEl = this.constructor.createLegendEl(
          catTitles[i],
          e,
          catNumbers[i],
        );

        // Add hover events
        // note do not use mouseover and mouseout event
        legendEl.onmouseenter = (event) => {
          event.target.style.borderColor = "black";
          event.target.style.borderWidth = "2px";
          //console.log("enter event triggered");
          let pointsIndex = this.highlight_index(catTitles[i]);

          this.scatterplots.forEach((sp, index) => {
            sp.select(pointsIndex[index]);
          });
        };
        legendEl.onmouseleave = (event) => {
          event.target.style.borderColor = "#D3D3D3";
          event.target.style.borderWidth = "1px";
          // deselect all points
          this.scatterplots.forEach((sp, index) => {
            sp.deselect();
          });
        };
        this.catLegendEl.appendChild(legendEl);
      });
    }
  }

  updateExpLegend() {
    // Add expression legend element
    if (
      this.plotMetaData.mode === "cluster+expr+noSplit" ||
      this.plotMetaData.mode === "cluster+expr+twoSplit" ||
      this.plotMetaData.mode === "cluster+expr+multiSplit"
    ) {
      const exprArray =
        this.origData.expressionData[this.plotMetaData.selectedFeatures];
      const exprLegendColor = d3.scaleSequential(
        [d3.min(exprArray), d3.max(exprArray)],
        d3.interpolate("#E5E4E2", "#800080"),
      );
      const exprLegendTitle = this.plotMetaData.moduleScore
        ? "ModuleScore"
        : "Expresson";
      const exprLegend = Legend(exprLegendColor, {
        title: exprLegendTitle,
        width: 200,
      });
      this.expLegendEl.appendChild(exprLegend);
    }
  }

  static createLegendEl(title, color, number) {
    if (typeof title === "number") {
      title = title.toString();
    }
    // legend style modified from broad single cell portal viewer
    const scatterLegend = document.createElement("div");
    scatterLegend.classList.add("scatter-legend");
    // replace unsafe strings in title and use it as the legend element id
    scatterLegend.id = "legend_" + title.replace(/[^a-zA-Z0-9-_]/g, "_");

    const colorBlock = document.createElement("div");
    colorBlock.classList.add("scatter-legend-icon");
    colorBlock.style.backgroundColor = color;

    const labelEl = document.createElement("span");
    labelEl.classList.add("legend-label");
    labelEl.title = title;
    labelEl.innerHTML = title;

    const numberEl = document.createElement("span");
    numberEl.classList.add("num-points");
    numberEl.title = number + " points in the group";
    numberEl.innerHTML = number;

    const entryEl = document.createElement("div");
    entryEl.classList.add("scatter-legend-entry");
    entryEl.appendChild(labelEl);
    entryEl.appendChild(numberEl);

    scatterLegend.appendChild(colorBlock);
    scatterLegend.appendChild(entryEl);

    return scatterLegend;
  }

  static findIndexes(arr, value) {
    var indexes = [];
    for (var i = 0; i < arr.length; i++) {
      if (arr[i] === value) {
        indexes.push(i);
      }
    }
    return indexes;
  }

  highlight_index(selectedGroupBy) {
    let mode = this.plotMetaData.mode;
    let group_by = this.plotMetaData.group_by;
    let metaData = this.origData.cellMetaData;
    // return a array of highlight points index array
    let pointsIndex = [];

    let factorLevel = {};
    let uniqueArr = new Set(metaData[group_by]);
    let sortedUniqueArr = Array.from(uniqueArr).sort(sortStringArray);
    sortedUniqueArr.forEach((e, i) => {
      factorLevel[e] = i;
    });

    switch (mode) {
      case "clusterOnly":
        pointsIndex[0] = reglScatterCanvas.findIndexes(
          this.plotData.pointsData[0].z,
          factorLevel[selectedGroupBy],
        );
        break;
      case "cluster+expr+noSplit":
        pointsIndex[0] = reglScatterCanvas.findIndexes(
          this.plotData.pointsData[0].z,
          factorLevel[selectedGroupBy],
        );
        pointsIndex[1] = pointsIndex[0];
        break;
      case "cluster+expr+twoSplit":
        for (let i = 0; i < this.plotData.pointsData.length; i = i + 2) {
          pointsIndex[i] = reglScatterCanvas.findIndexes(
            this.plotData.pointsData[i].z,
            factorLevel[selectedGroupBy],
          );
          pointsIndex[i + 1] = pointsIndex[i];
        }
        break;
      case "cluster+multiSplit":
        pointsIndex = this.plotData.pointsData.map((e) =>
          reglScatterCanvas.findIndexes(e.z, factorLevel[selectedGroupBy]),
        );
    }
    return pointsIndex;
  }
}

export const splitArrByMeta = (Arr, meta) => {
  // split array (reduciton x,y etc.) by meta inforamtion
  // Arr should be reduction.x or reduction.y, which is a numeric array
  // Arr could also be "group_by" stringArray
  let splitOut = {};
  if (Arr != null && Arr.length == meta.length) {
    let meta_levels = [...new Set(meta)].sort(sortStringArray);
    // split meta to object
    // for loop is faster than forEach(), reduce()
    for (const element of meta_levels) {
      splitOut[element] = [];
      for (let i = 0; i < meta.length; ++i) {
        if (meta[i] === element) {
          splitOut[element].push(Arr[i]);
        }
      }
      if (Arr instanceof Int32Array) {
        splitOut[element] = new Int32Array(splitOut[element]);
      } else if (Arr instanceof Float32Array) {
        splitOut[element] = new Float32Array(splitOut[element]);
      } else if (Arr instanceof Int16Array) {
        splitOut[element] = new Int16Array(splitOut[element]);
      }
    }
  }
  return splitOut;
};

export const convert_stringArr_to_integer = (stringArray) => {
  let factorLevel = {};
  let uniqueArr = new Set(stringArray);
  let sortedUniqueArr = Array.from(uniqueArr).sort(sortStringArray);
  sortedUniqueArr.forEach((e, i) => {
    factorLevel[e] = i;
  });
  let integerArray = stringArray.map((e) => factorLevel[e]);
  return new Int16Array(integerArray);
};

export const rgbToHex = (rgbString) => {
  // Convert rgb color string to hex format
  // Split the RGB string into individual values
  var rgbArray = rgbString
    .substring(4, rgbString.length - 1)
    .split(",")
    .map(function (num) {
      return parseInt(num);
    });

  // Convert the individual RGB values to hex
  var hex =
    "#" +
    rgbArray
      .map(function (num) {
        var hexValue = num.toString(16);
        return hexValue.length === 1 ? "0" + hexValue : hexValue;
      })
      .join("");

  return hex;
};

export const sortStringArray = (a, b) => {
  // Array sort function
  // input: ['1', '2', '10', 'apple', '5', 'orange']
  // output: ['1', '2', '5', '10', 'apple', 'orange']
  if (!isNaN(a) && !isNaN(b)) {
    return parseInt(a) - parseInt(b);
  } else if (!isNaN(a)) {
    return -1;
  } else if (!isNaN(b)) {
    return 1;
  } else {
    return a.localeCompare(b);
  }
};

// Copyright 2021, Observable Inc.
// Released under the ISC license.
// https://observablehq.com/@d3/color-legend
export function Legend(
  color,
  {
    title,
    tickSize = 6,
    width = 320,
    height = 44 + tickSize,
    marginTop = 18,
    marginRight = 0,
    marginBottom = 16 + tickSize,
    marginLeft = 0,
    ticks = width / 64,
    tickFormat,
    tickValues,
  } = {},
) {
  function ramp(color, n = 256) {
    const canvas = document.createElement("canvas");
    canvas.width = n;
    canvas.height = 1;
    const context = canvas.getContext("2d");
    for (let i = 0; i < n; ++i) {
      context.fillStyle = color(i / (n - 1));
      context.fillRect(i, 0, 1, 1);
    }
    return canvas;
  }

  const svg = d3
    .create("svg")
    .attr("width", width)
    .attr("height", height)
    .attr("viewBox", [0, 0, width, height])
    .style("overflow", "visible")
    .style("display", "block");

  let tickAdjust = (g) =>
    g.selectAll(".tick line").attr("y1", marginTop + marginBottom - height);
  let x;

  // Continuous
  if (color.interpolate) {
    const n = Math.min(color.domain().length, color.range().length);

    x = color
      .copy()
      .rangeRound(
        d3.quantize(d3.interpolate(marginLeft, width - marginRight), n),
      );

    svg
      .append("image")
      .attr("x", marginLeft)
      .attr("y", marginTop)
      .attr("width", width - marginLeft - marginRight)
      .attr("height", height - marginTop - marginBottom)
      .attr("preserveAspectRatio", "none")
      .attr(
        "xlink:href",
        ramp(
          color.copy().domain(d3.quantize(d3.interpolate(0, 1), n)),
        ).toDataURL(),
      );
  }

  // Sequential
  else if (color.interpolator) {
    x = Object.assign(
      color
        .copy()
        .interpolator(d3.interpolateRound(marginLeft, width - marginRight)),
      {
        range() {
          return [marginLeft, width - marginRight];
        },
      },
    );

    svg
      .append("image")
      .attr("x", marginLeft)
      .attr("y", marginTop)
      .attr("width", width - marginLeft - marginRight)
      .attr("height", height - marginTop - marginBottom)
      .attr("preserveAspectRatio", "none")
      .attr("xlink:href", ramp(color.interpolator()).toDataURL());

    // scaleSequentialQuantile doesn’t implement ticks or tickFormat.
    if (!x.ticks) {
      if (tickValues === undefined) {
        const n = Math.round(ticks + 1);
        tickValues = d3
          .range(n)
          .map((i) => d3.quantile(color.domain(), i / (n - 1)));
      }
      if (typeof tickFormat !== "function") {
        tickFormat = d3.format(tickFormat === undefined ? ",f" : tickFormat);
      }
    }
  }

  // Threshold
  else if (color.invertExtent) {
    const thresholds = color.thresholds
      ? color.thresholds() // scaleQuantize
      : color.quantiles
        ? color.quantiles() // scaleQuantile
        : color.domain(); // scaleThreshold

    const thresholdFormat =
      tickFormat === undefined
        ? (d) => d
        : typeof tickFormat === "string"
          ? d3.format(tickFormat)
          : tickFormat;

    x = d3
      .scaleLinear()
      .domain([-1, color.range().length - 1])
      .rangeRound([marginLeft, width - marginRight]);

    svg
      .append("g")
      .selectAll("rect")
      .data(color.range())
      .join("rect")
      .attr("x", (d, i) => x(i - 1))
      .attr("y", marginTop)
      .attr("width", (d, i) => x(i) - x(i - 1))
      .attr("height", height - marginTop - marginBottom)
      .attr("fill", (d) => d);

    tickValues = d3.range(thresholds.length);
    tickFormat = (i) => thresholdFormat(thresholds[i], i);
  }

  // Ordinal
  else {
    x = d3
      .scaleBand()
      .domain(color.domain())
      .rangeRound([marginLeft, width - marginRight]);

    svg
      .append("g")
      .selectAll("rect")
      .data(color.domain())
      .join("rect")
      .attr("x", x)
      .attr("y", marginTop)
      .attr("width", Math.max(0, x.bandwidth() - 1))
      .attr("height", height - marginTop - marginBottom)
      .attr("fill", color);

    tickAdjust = () => {};
  }

  svg
    .append("g")
    .attr("transform", `translate(0,${height - marginBottom})`)
    .call(
      d3
        .axisBottom(x)
        .ticks(ticks, typeof tickFormat === "string" ? tickFormat : undefined)
        .tickFormat(typeof tickFormat === "function" ? tickFormat : undefined)
        .tickSize(tickSize)
        .tickValues(tickValues),
    )
    .call(tickAdjust)
    .call((g) => g.select(".domain").remove())
    .call((g) =>
      g
        .append("text")
        .attr("x", marginLeft)
        .attr("y", marginTop + marginBottom - height - 6)
        .attr("fill", "currentColor")
        .attr("text-anchor", "start")
        .attr("font-weight", "bold")
        .attr("class", "title")
        .text(title),
    );

  return svg.node();
}

const downloadCanvasAsPNG = (canvas, fileName = "canvas.png") => {
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
};

export function hue_pal(
  n = 15,
  h = [0, 360],
  c = 100,
  l = 65,
  h_start = 15,
  direction = 1,
  hex = true,
) {
  // Ensure n is a positive integer
  n = Math.max(1, Math.round(n));

  // Normalize hue range
  let h_range = h[1] - h[0];
  if (h_range < 0) h_range += 360;

  // Calculate hue step
  let hue_step = h_range / n;

  // Generate colors
  let colors = [];
  for (let i = 0; i < n; i++) {
    let hue = (h_start + i * hue_step * direction) % 360;
    if (hue < 0) hue += 360;
    if (hex) {
      colors.push(hslToHex(hue, c, l));
    } else {
      colors.push(`hsl(${hue}, ${c}%, ${l}%)`);
    }
  }

  return colors;
}

// Helper function to convert HSL to HEX
const hslToHex = (h, s, l) => {
  l /= 100;
  const a = (s * Math.min(l, 1 - l)) / 100;
  const f = (n) => {
    const k = (n + h / 30) % 12;
    const color = l - a * Math.max(Math.min(k - 3, 9 - k, 1), -1);
    return Math.round(255 * color)
      .toString(16)
      .padStart(2, "0");
  };
  return `#${f(0)}${f(8)}${f(4)}`;
};
