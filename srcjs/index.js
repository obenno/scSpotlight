import "shiny";
// not sure why waiter was not exposed as library
// cannot import even added it to externals config
// seems nothing wrong in the webpack config
// https://github.com/JohnCoene/waiter/blob/776f9f3ccd27aa3322d6c6d37c47b3d7b1f393e6/webpack.common.js#L64
// https://webpack.js.org/configuration/output/#outputlibrary
// exporting not tested, remove import temporarily
// import "waiter";

import {
  initFullScreenSpinner,
  removeFullScreenSpinner,
  addOverlaySpinner,
} from "./modules/spinner.js";

import { initFloatingPlots } from "./modules/floatingPlots.js";

//import bootstrap-icons
import "bootstrap-icons/font/bootstrap-icons.css";

import {
  reglScatterCanvas,
  expandMeta,
  sortStringArray,
} from "./modules/deckScatter.js";

import {
  initShelter,
  featurePlot,
  vlnPlot,
  dotPlot,
  initWebRInstance,
  qs2ReadFromUrl,
  isIntegerArray,
} from "./modules/webr.js";

import {
  createSparkLine,
  updateSparkLine,
} from "./modules/featureSparkLine.js";

//import './modules/virtualSelect.js'

// keep global variables as small as possible
// query elements inside functions when necessary

// id of the mainClusterPlot parent div
const mainPlotElId = "mainClusterPlot-clusterPlot";
// featurePlot canvas id
const featurePlotElId = "featurePlotCanvas";
// vlnSelect widget id
const vlnDropDownId = "vlnDropDown";
// vlnPlot canvas id
const vlnPlotElId = "VlnPlot";
// dotPlot canvas id
const dotPlotElId = "DotPlot";

// R waiter package spinners
// keep the style exactly the same with R function

var reglElementData = new reglScatterCanvas("reglScatter");

// init webR instance for reading reduction and expr data
// It seems put two async webr jobs in the same instance might cause data processing conflicts
// We found this when reading reduction and meta data with just one instance
let webR;
let shelter;

// global variables to store spinners
let vlnPlotSpinner;
let dotPlotSpinner;
let mainPlotSpinner;

// init normal shelter for webR to gain better control of the r objects
//const shelterInstance = await initShelter(plotWebR);
// code below will ensure the functions were invoked after all the shiny content loaded
// thus here init scatterplot instance
document.addEventListener(
  "DOMContentLoaded",
  function () {
    // Add full screen spinner
    (async () => {
      const fullScreenSpinner = initFullScreenSpinner("App Loading...");
      document.body.prepend(fullScreenSpinner);
      webR = await initWebRInstance();
      shelter = await initShelter(webR);
      removeFullScreenSpinner();
    })();

    // Add floating plot spinners
    vlnPlotSpinner = addOverlaySpinner("floatingVlnPlotBody");
    dotPlotSpinner = addOverlaySpinner("floatingDotPlotBody");
    // Add main plot spinner
    mainPlotSpinner = addOverlaySpinner(mainPlotElId);

    initFloatingPlots({
      hostId: "plotFloatingHost",
      railId: "plotRail",
      leftSidebarId: "leftSidebar",
      leftSidebarRailId: "leftSidebarRail",
      mainBoundsId: mainPlotElId,
      refreshPanelPlot: (panelId) => {
        if (panelId === "floatingVlnPlot") {
          const canvas = document.getElementById(vlnPlotElId);
          if (canvas) updateVlnPlot(canvas);
        }
        if (panelId === "floatingDotPlot") {
          const canvas = document.getElementById(dotPlotElId);
          if (canvas) updateDotPlot(canvas);
        }
      },
      debounce,
    });

    // add select widget to vlnplot box
    const vlnDropDown = createVlnDropend(vlnDropDownId);
    const vlnContainer = document.getElementById(vlnPlotElId).parentElement;
    vlnContainer.prepend(vlnDropDown);

    // Adjust widget elements on scroll
    document.getElementById(mainPlotElId).addEventListener("scroll", () => {
      const containerEl = document.getElementById(mainPlotElId);

      const noteEl = containerEl.querySelector("#scatterPlotNote");

      noteEl.style.bottom = "2%";
      noteEl.style.bottom = `calc(${noteEl.style.bottom} - ${containerEl.scrollTop}px)`;

      const infoEl = containerEl.querySelector("#info");

      infoEl.style.bottom = "1%";
      infoEl.style.bottom = `calc(${infoEl.style.bottom} - ${containerEl.scrollTop}px)`;

      const sliderEl = containerEl.querySelector(".label-slider");
      sliderEl.style.bottom = "1%";
      sliderEl.style.bottom = `calc(${sliderEl.style.bottom} - ${containerEl.scrollTop}px)`;

      const downloadEl = containerEl.querySelector("#downloadIcon");
      downloadEl.style.bottom = "1%";
      downloadEl.style.bottom = `calc(${downloadEl.style.bottom} - ${containerEl.scrollTop}px)`;
    });

    // auto update vlnPlot when resizing
    // Create ResizeObserver instance
    const featurePlotCanvas = document.getElementById(featurePlotElId);
    const vlnPlotCanvas = document.getElementById(vlnPlotElId);
    const dotPlotCanvas = document.getElementById(dotPlotElId);
    const resizeObserver = new ResizeObserver(
      debounce((entries) => {
        for (const entry of entries) {
          if (
            shelter &&
            //shelter2 &&
            Object.keys(reglElementData.origData.cellMetaData).length > 0
          ) {
            // ensure shelter was initiated and reglElementData was populated
            if (entry.target === vlnPlotCanvas && isElementVisible(entry.target)) {
              if (
                !document
                  .getElementById(vlnDropDownId)
                  .querySelector("button")
                  .classList.contains("show")
              ) {
                console.log("resized vlnplot...");
                updateVlnPlot(vlnPlotCanvas);
              }
            }
            if (entry.target === dotPlotCanvas && isElementVisible(entry.target)) {
              console.log("resized dotplot...");
              updateDotPlot(dotPlotCanvas);
            }
            if (
              entry.target === featurePlotCanvas &&
              entry.target.style.display !== "none"
            ) {
              console.log("resized featureplot...");
              updateFeaturePlot(featurePlotCanvas);
            }
          }
        }
      }, 250),
    );

    // start observer
    resizeObserver.observe(featurePlotCanvas);
    resizeObserver.observe(vlnPlotCanvas);
    resizeObserver.observe(dotPlotCanvas);
  },
  false,
);

Shiny.addCustomMessageHandler("createSparkLine", (feature) => {
  const sparkLineEl = createSparkLine(feature);
  const sparkLineContainer = document.getElementById("featureSparkLine");
  sparkLineContainer.appendChild(sparkLineEl);

  const sparkLineArray = [
    ...sparkLineContainer.querySelectorAll(".featureSparkLine"),
  ];
  // notify server that gene expression stored has been changed
  // set the value when start transferring data
  const storedFeatures = sparkLineArray.map((e) => {
    // select the first span element
    return e.querySelector("span").innerHTML;
  });
  // remember to add shiny module id as prefix
  Shiny.setInputValue("inputFeatures-storedFeatures", storedFeatures);
});

Shiny.addCustomMessageHandler("reduction_ready", (msg) => {
  try {
    const xFileURL = window.location.origin + "/data/reduction/" + msg.xFile;
    const yFileURL = window.location.origin + "/data/reduction/" + msg.yFile;
    (async () => {
      // show spinner
      if (mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }

      const df = {};
      const xRes = await qs2ReadFromUrl(webR, shelter, xFileURL);
      df["X"] = new Float32Array(await xRes.toTypedArray());
      const yRes = await qs2ReadFromUrl(webR, shelter, yFileURL);
      df["Y"] = new Float32Array(await yRes.toTypedArray());
      reglElementData.updateReductionData(df);
      await shelter.purge();
      Shiny.setInputValue("reductionProcessed", true, { priority: "event" });
      console.log("reduction", df);

      // do not hide the spinner, since it will trigger the reglScatter_plot immediately
    })().catch((error) => {
      console.error("There was a problem:", error);
      mainPlotSpinner.style.display = "none";
    });
  } catch (error) {
    console.error("There was a problem:", error);
    mainPlotSpinner.style.display = "none";
  }
});

Shiny.addCustomMessageHandler("meta_ready", (msg) => {
  try {
    const metaURL = window.location.origin + "/data/meta/" + msg.metaFile;
    //let meta = {}
    (async () => {
      // show main plot spinner
      if (mainPlotSpinner.style.display === "none") {
        mainPlotSpinner.style.display = "flex";
      }
      const res = await qs2ReadFromUrl(webR, shelter, metaURL);
      const out = {};
      const loadedData = await res.toObject({ depth: 1 });
      console.log(loadedData);
      //const out = await res.toObject();
      for (const key in loadedData) {
        console.log("reading:", key);
        const e = await loadedData[key].toObject({ depth: 1 });
        console.log("reading succeed", e);
        const dataType = await e.type.toString();
        if (dataType === "number") {
          const dataArray = await e.value.toArray();
          if (isIntegerArray(dataArray)) {
            out[key] = {
              type: dataType,
              value: Int32Array.from(dataArray),
            };
          } else {
            out[key] = {
              type: dataType,
              value: Float32Array.from(dataArray),
            };
          }
        } else if (dataType === "category") {
          const dataObject = {};
          const catData = await e.value.toObject({ depth: 1 });

          const catNames = Object.keys(catData);
          for (const cat of catNames) {
            dataObject[cat] = await catData[cat].toTypedArray();
            // original R array starts from 1
            // here convert it to javascript convention
            dataObject[cat] = dataObject[cat].map((e) => e - 1);
          }
          out[key] = { type: dataType, value: dataObject };
        } else {
          out[key] = { type: dataType, value: [] };
        }
      }
      console.log("metaData", out);
      reglElementData.updateCellMetaData(out);
      const nonNumericCols = getNonNumericCols(reglElementData);
      const numericCols = getNumericCols(reglElementData);

      // update vlnplot dropdown list
      emptyDropOptions(vlnDropDownId);
      updateDropOptions(vlnDropDownId, numericCols);

      Shiny.setInputValue("metaCols", nonNumericCols);
      Shiny.setInputValue("metaProcessed", true, { priority: "event" });
      await shelter.purge();

      // do not hide the spinner, since it will trigger the reglScatter_plot immediately
    })().catch((error) => {
      console.error("There was a problem:", error);
      mainPlotSpinner.style.display = "none";
    });
  } catch (error) {
    console.error("There was a problem:", error);
    mainPlotSpinner.style.display = "none";
  }
});

Shiny.addCustomMessageHandler("expr_ready", (msg) => {
  try {
    const exprURL = window.location.origin + "/data/expr/" + msg.exprFile;
    (async () => {
      const expr = {};
      const res = await qs2ReadFromUrl(webR, shelter, exprURL);
      expr[msg.geneName] = new Float32Array(await res.toTypedArray());
      await shelter.purge();
      reglElementData.updateExpressionData(expr);
      console.log("exprData", reglElementData.origData.expressionData);
      const feature = Object.keys(expr)[0];
      const sparkLine = document
        .getElementById("featureSparkLine")
        .querySelectorAll(".featureSparkLine");
      const sparkLineArray = [...sparkLine];
      sparkLineArray.forEach((e) => {
        if (e.querySelector("span").innerHTML == feature) {
          updateSparkLine(e, reglElementData);
        }
      });
    })();
  } catch (error) {
    console.error("There was a problem:", error);
  }
});

Shiny.addCustomMessageHandler("clear_expr", (msg) => {
  // purge exprssion data
  reglElementData.origData.expressionData = {};
  reglElementData.plotMetaData.selectedFeatures = [];
  // remember to add shiny module id as prefix
  Shiny.setInputValue("inputFeatures-storedFeatures", [], {
    priority: "event",
  });
  Shiny.setInputValue("selectedFeatures", [], { priority: "event" });

  // remove all sparkline
  document.getElementById("featureSparkLine").innerHTML = "";

  // hide featurePlot and show scatterplot
  const featurePlotCanvas = document.getElementById(featurePlotElId);
  featurePlotCanvas.style.display = "none";
  reglElementData.plotEl.style.display = "flex";
});

Shiny.addCustomMessageHandler("selectPointsByCategory", (msg) => {
  // handler for selecting cells by category
  const groupBy = msg.groupBy;
  const splitBy = msg.splitBy;
  const selectedGroupBy = msg.selectedGroupBy;
  const selectedSplitBy = msg.selectedSplitBy;
  const selectedCells = [];
  const groupByArray = groupBy
    ? expandMeta(reglElementData.origData.cellMetaData[groupBy])
    : [];
  const splitByArray = splitBy
    ? expandMeta(reglElementData.origData.cellMetaData[splitBy])
    : [];
  const colNames = Object.keys(reglElementData.origData.cellMetaData);
  const cellsArray = colNames.includes("cells")
    ? expandMeta(reglElementData.origData.cellMetaData["cells"])
    : [];
  if (groupBy && selectedGroupBy) {
    if (!splitBy) {
      groupByArray.forEach((e, i) => {
        const currentCell = cellsArray[i];
        if (selectedGroupBy.includes(e)) {
          selectedCells.push(currentCell);
        }
      });
    } else {
      groupByArray.forEach((e, i) => {
        const currentSplitBy = splitByArray[i];
        const currentCell = cellsArray[i];
        if (
          selectedGroupBy.includes(e) &&
          selectedSplitBy.includes(currentSplitBy)
        ) {
          selectedCells.push(currentCell);
        }
      });
    }
  }
  if (selectedCells.length > 0) {
    // update selectedCells in reglElementData
    reglElementData.plotData.selectedCells = selectedCells;
    Shiny.setInputValue("categorySelectedCells", selectedCells, {
      priority: "event",
    });
  }
});

Shiny.addCustomMessageHandler("addNewMeta", (msg) => {
  const newMetaCol = msg.colName;
  const assignAs = msg.colValue;
  console.log("newMetaCol:", newMetaCol);
  console.log("assignAs:", assignAs);
  const metaData = reglElementData.origData.cellMetaData;
  // selectedCells records manually selected points by lasso
  // or category selected cells updated by selectPointsByCategory
  const selectedCells = reglElementData.plotData.selectedCells;
  const colNames = Object.keys(metaData);
  if (colNames.length > 0 && selectedCells.length > 0) {
    const nCells = expandMeta(metaData[Object.keys(metaData)[0]]).length;
    //console.log(Object.keys(metaData).includes(newMetaCol));
    //console.log(!Object.keys(metaData).includes(newMetaCol));
    if (!colNames.includes(newMetaCol)) {
      reglElementData.origData.cellMetaData[newMetaCol] = {
        type: "category",
        value: {
          unknown: Array(nCells)
            .fill(0)
            .map((_, i) => i),
        },
      };
      //console.log(reglElementData.origData.cellMetaData[newMetaCol]);
    }
    const idx = selectedCells.map((e) =>
      expandMeta(metaData["cells"]).indexOf(e),
    );
    console.log("idx", idx);
    //idx.forEach((e) => {
    //  reglElementData.origData.cellMetaData
    //    .getChild(newMetaCol)
    //    .gset(e, assignAs);
    //});
    //
    // arrow vector set function has a bug, the same value will
    // all be replaced by one set() operation, no matter the index
    // parameter used.
    //
    // thus convert to array and replace the value
    //

    let nn = expandMeta(reglElementData.origData.cellMetaData[newMetaCol]);
    console.log("nn", nn);
    idx.forEach((e) => {
      nn[e] = assignAs;
    });
    const result = nn.reduce((acc, val, index) => {
      (acc[val] = acc[val] || []).push(index);
      return acc;
    }, {});
    reglElementData.origData.cellMetaData[newMetaCol].value = result;
  }
  console.log({
    [newMetaCol]: expandMeta(reglElementData.origData.cellMetaData[newMetaCol]),
  });

  const nonNumericCols = Object.keys(
    reglElementData.origData.cellMetaData,
  ).reduce((acc, val, _) => {
    if (reglElementData.origData.cellMetaData[val].type === "category") {
      acc.push(val);
    }
    return acc;
  }, []);
  console.log("nonNumericCols", nonNumericCols);
  Shiny.setInputValue("metaCols", nonNumericCols);
  // send the newMetaCol data to R
  Shiny.setInputValue(
    "newMetaColData",
    {
      [newMetaCol]: expandMeta(
        reglElementData.origData.cellMetaData[newMetaCol],
      ),
    },
    { priority: "event" },
  );
  // deselct points
  reglElementData.deselectAll();
  // reset selectedCells
  Shiny.setInputValue("categorySelectedCells", null, { priority: "event" });
});

Shiny.addCustomMessageHandler("reglScatter_plot", (msg) => {
  // first remove spinner if exists
  if (mainPlotSpinner.style.display === "none") {
    // show spinners for the plot
    console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
    mainPlotSpinner.style.display = "flex";
    console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
  }
  // do necessary cleanups
  // ensure the featurePlot canvas is hidden
  const parentDiv = document.getElementById(mainPlotElId);
  const featurePlotCanvas = document.getElementById(featurePlotElId);
  featurePlotCanvas.style.display = "none";
  reglElementData.plotEl.style.display = "none";

  // clear reglScatterCanvas data including plotMetaData
  console.log("msg: ", msg);
  const group_by = msg.group_by;
  const split_by = msg.split_by;
  const moduleScore = msg.moduleScore;

  // update group_by levels to server side
  let groupByLevels = group_by
    ? new Set(expandMeta(reglElementData.origData.cellMetaData[group_by]))
    : null;
  groupByLevels = group_by ? [...groupByLevels].sort() : null;
  // when split_by == null, this will return a set with size 0
  //     // update split_by levels to server side
  let splitByLevels = split_by
    ? new Set(expandMeta(reglElementData.origData.cellMetaData[split_by]))
    : null;
  splitByLevels = split_by ? [...splitByLevels].sort() : null;
  Shiny.setInputValue("metaColLevels", {
    groupBy: groupByLevels,
    splitBy: splitByLevels,
  });

  reglElementData.clear();
  // update plotMetaData with previous one
  reglElementData.updatePlotMetaData(group_by, split_by, moduleScore);
  // then update with new msg, in case msg is empty
  //reglElementData.updatePlotMetaData(msg);
  console.log("reglElementData.plotMetaData: ", reglElementData.plotMetaData);

  console.log("Generating plotEl");
  // regenerate plot elements
  console.profile("Generating plotEl");
  reglElementData.generatePlotEl();
  console.profileEnd("Generating plotEl");
  console.log("reglElementData :", reglElementData);
  // update legend elements
  parentDiv.appendChild(reglElementData.plotEl);
  // create deck instance after plot element is mounted in DOM
  reglElementData.mountDeck();
  const accordions = document.querySelectorAll(".accordion-item");
  const category_accordion = [...accordions].filter((e) => {
    if (e.dataset.value == "analysis_category") {
      return e;
    }
  });
  const category_accordion_body =
    category_accordion[0].querySelector(".accordion-body");
  category_accordion_body.appendChild(reglElementData.catLegendEl);
  category_accordion_body.appendChild(reglElementData.expLegendEl);

  // return selected points to server side
  reglElementData.setSelectionHandlers({
    onSelect: ({ selectedCells }) => {
      console.log("selectedCells: ", selectedCells);
      Shiny.setInputValue("selectedPoints", selectedCells, {
        priority: "event",
      });
    },
    onDeselect: () => {
      Shiny.setInputValue("selectedPoints", null);
    },
  });

  if (
    Object.keys(reglElementData.plotMetaData.selectedFeatures).length > 1 &&
    !reglElementData.plotMetaData.moduleScore
  ) {
    console.log("Drawing featurePlot...");

    updateFeaturePlot(featurePlotCanvas);
    console.log("featureplot udpated...");
    // show featurePlotCanvas
    featurePlotCanvas.style.display = "flex";

    //reglElementData.plotEl.style.display = "none";
  } else {
    reglElementData.plotEl.style.display = "flex";
  }

  // hide spinner
  if (mainPlotSpinner.style.display !== "none") {
    console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
    mainPlotSpinner.style.display = "none";
    console.log("mainPlotSpinner: ", mainPlotSpinner.style.display);
  }
  //featurePlot().then({});
  const vlnPlotCanvas = document.getElementById(vlnPlotElId);
  const dotPlotCanvas = document.getElementById(dotPlotElId);
  // update vlnplot
  updateVlnPlot(vlnPlotCanvas);
  // update dotplot
  updateDotPlot(dotPlotCanvas);
});

const updateFeaturePlot = (canvas) => {
  // Firstly check the spinners
  if (mainPlotSpinner.style.display === "none") {
    mainPlotSpinner.style.display = "flex";
  }

  const container = canvas.parentElement;
  const rect = container.getBoundingClientRect();
  const containerPadding = getPadding(container);
  const canvasWidth =
    rect.width - containerPadding.left - containerPadding.right;
  const canvasHeight =
    rect.height - containerPadding.top - containerPadding.bottom;
  canvas.width = canvasWidth * 2;
  canvas.height = canvasHeight * 2;
  canvas.style.width = "100%";
  canvas.style.height = "100%";

  if (canvasWidth > 0 && canvasHeight > 0) {
    // It seems that webR does not support typedArray
    const expressionInput = {};
    for (let f of reglElementData.plotMetaData.selectedFeatures) {
      expressionInput[f] = Array.from(
        reglElementData.origData.expressionData[f],
      );
    }
    const drInput = {};
    const colNames = Object.keys(reglElementData.origData.reductionData);
    for (let i of colNames) {
      // webr dataframe convertion doesn't support typed array
      drInput[i] = Array.from(reglElementData.origData.reductionData[i]);
    }
    featurePlot(
      shelter,
      canvasWidth,
      canvasHeight,
      drInput,
      expressionInput,
    ).then((res) => {
      const ctx = canvas.getContext("2d");
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      let img = res.images[0];
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      // hide spinner
      if (mainPlotSpinner.style.display !== "none") {
        mainPlotSpinner.style.display = "none";
      }
      shelter.purge();
    });
  }
};

Shiny.addCustomMessageHandler("reglScatter_deselect", (msg) => {
  console.log("Deselect points...");
  reglElementData.deselectAll();
});

function getPadding(element) {
  const style = element.currentStyle || window.getComputedStyle(element);
  return {
    top: parseInt(style.paddingTop, 10),
    right: parseInt(style.paddingRight, 10),
    bottom: parseInt(style.paddingBottom, 10),
    left: parseInt(style.paddingLeft, 10),
  };
}

const updateVlnPlot = (canvas) => {
  // ensure the infobox panel selected vlnplot
  // id was defined in R's nav_panel() title argument
  //if(infoPanelActive(btmBoxListId) !== "VlnPlot") return false
  if (!canvas || !vlnPlotSpinner) return;

  const hideSpinner = () => {
    vlnPlotSpinner.style.display = "none";
  };
  const showSpinner = () => {
    vlnPlotSpinner.style.display = "flex";
  };

  const container = canvas.parentElement;
  if (!container) {
    hideSpinner();
    return;
  }
  const rect = container.getBoundingClientRect();
  const containerPadding = getPadding(container);
  const canvasWidth =
    rect.width - containerPadding.left - containerPadding.right;
  const canvasHeight =
    rect.height - containerPadding.top - containerPadding.bottom;
  canvas.width = canvasWidth * 2;
  canvas.height = canvasHeight * 2;
  canvas.style.width = "100%";
  canvas.style.height = "100%";

  const ctx = canvas.getContext("2d");
  if (canvasWidth <= 0 || canvasHeight <= 0) {
    hideSpinner();
    return;
  }

  const groupBy = reglElementData.plotMetaData.group_by;
  const groupMeta = groupBy
    ? reglElementData.origData.cellMetaData[groupBy]
    : null;

  if (!groupMeta) {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    hideSpinner();
    return;
  }

  console.log("Updating vlnplot...");
  showSpinner();

  // It seems that webR does not support typedArray
  const expressionInput = {};
  const metaInput = {};
  let expr = false;

  // vlnPlot only illustrates expression of the first selected genes
  if (reglElementData.plotMetaData.selectedFeatures.length > 0) {
    const f = reglElementData.plotMetaData.selectedFeatures[0];
    const exprVec = reglElementData.origData.expressionData[f];
    if (!exprVec) {
      hideSpinner();
      return;
    }
    expressionInput[f] = Array.from(exprVec);
    expr = f;
  } else {
    const numericCols = getNumericCols(reglElementData);
    if (numericCols.length === 0) {
      hideSpinner();
      return;
    }

    const selectedMetaCol = reglElementData.plotMetaData.selectedMeta || numericCols[0];
    if (!reglElementData.origData.cellMetaData[selectedMetaCol]) {
      hideSpinner();
      return;
    }
    metaInput[selectedMetaCol] = expandMeta(
      reglElementData.origData.cellMetaData[selectedMetaCol],
    );
  }

  const groupInput = {};
  groupInput[groupBy] = expandMeta(groupMeta);
  const groupOrder = [...new Set(groupInput[groupBy])].sort(sortStringArray);
  const dfInput = { ...groupInput, ...metaInput, ...expressionInput };
  for (const k of Object.keys(dfInput)) {
    // webr dataframe convertion doesn't support typed array
    dfInput[k] = Array.from(dfInput[k]);
  }
  console.log("vlnPlot inputs: ", dfInput, groupBy, groupOrder, expr);
  vlnPlot(
    shelter,
    canvasWidth,
    canvasHeight,
    dfInput,
    groupBy,
    groupOrder,
    (expr = expr),
    reglElementData.plotMetaData.catColors,
  )
    .then((res) => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const img = res.images[0];
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    })
    .catch((error) => {
      console.error("Failed to update vlnPlot:", error);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
    })
    .finally(() => {
      hideSpinner();
      shelter.purge();
    });
};

const updateDotPlot = (canvas) => {
  // ensure the infobox panel selected vlnplot
  // id was defined in R's nav_panel() title argument
  //if(infoPanelActive(btmBoxListId) !== "DotPlot") return false
  if (!canvas || !dotPlotSpinner) return;

  const hideSpinner = () => {
    dotPlotSpinner.style.display = "none";
  };
  const showSpinner = () => {
    dotPlotSpinner.style.display = "flex";
  };

  const container = canvas.parentElement;
  if (!container) {
    hideSpinner();
    return;
  }
  const rect = container.getBoundingClientRect();
  const containerPadding = getPadding(container);
  const canvasWidth =
    rect.width - containerPadding.left - containerPadding.right;
  const canvasHeight =
    rect.height - containerPadding.top - containerPadding.bottom;
  canvas.width = canvasWidth * 2;
  canvas.height = canvasHeight * 2;
  canvas.style.width = "100%";
  canvas.style.height = "100%";

  const ctx = canvas.getContext("2d");
  if (canvasWidth <= 0 || canvasHeight <= 0) {
    hideSpinner();
    return;
  }

  // It seems that webR does not support typedArray
  const expressionInput = {};
  const features = reglElementData.plotMetaData.selectedFeatures || [];
  // dotPlot only be rendered when there are more than one selected genes
  if (features.length > 1) {
    const missingExpr = features.some(
      (f) => !reglElementData.origData.expressionData[f],
    );
    if (missingExpr) {
      hideSpinner();
      return;
    }

    for (const f of features) {
      expressionInput[f] = Array.from(reglElementData.origData.expressionData[f]);
    }

    const groupBy = reglElementData.plotMetaData.group_by;
    const groupMeta = groupBy
      ? reglElementData.origData.cellMetaData[groupBy]
      : null;
    if (!groupMeta) {
      hideSpinner();
      return;
    }

    const groupInput = {};
    groupInput[groupBy] = expandMeta(groupMeta);

    const dfInput = { ...groupInput, ...expressionInput };

    showSpinner();
    dotPlot(shelter, canvasWidth, canvasHeight, dfInput, groupBy)
      .then((res) => {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        const img = res.images[0];
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      })
      .catch((error) => {
        console.error("Failed to update dotPlot:", error);
        ctx.clearRect(0, 0, canvas.width, canvas.height);
      })
      .finally(() => {
        hideSpinner();
        shelter.purge();
      });
  } else {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    // Set text properties
    ctx.font = "30px Arial";
    ctx.fillStyle = "#636363";
    ctx.textAlign = "left";
    ctx.textBaseline = "top";

    // Draw filled text
    ctx.fillText("Please select at least two features", 10, 10);
    hideSpinner();
  }
};

// Debounce helper function
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

const isElementVisible = (el) => !!(el && el.offsetParent !== null);

// function to replace column with new Vector to simulate mutate operation
// if colName already exists in the table, the child/column will be
// replaced by the new vector; if colName doesn't exist, it will be
// appended to the table as the last column
const tableMutateCol = (table, colName, arrowVector) => {
  const vec = {};
  for (let i = 0; i < table.numCols; i++) {
    const field = table.schema.fields[i].name;
    vec[field] = table.getChildAt(i);
  }
  // replace the old one
  vec[colName] = arrowVector;
  return new Table(vec);
};

// function to create vlnplot dropend button
const createVlnDropend = (Id) => {
  const el = document.createElement("div");
  el.id = Id;
  el.classList.add("btn-group", "dropend");
  el.style.width = "2rem";
  el.style.position = "absolute";
  el.style.zIndex = 1;
  el.style.top = "0.2rem";
  el.style.left = "0.2rem";
  el.style.padding = "0";

  el.style.display = "flex";
  el.style.justifyContent = "center";
  el.style.alignItems = "center";

  const bt = document.createElement("button");
  bt.classList.add("btn", "dropdown-toggle", "p-0");
  bt.type = "button";
  bt.setAttribute("data-bs-toggle", "dropdown");
  bt.setAttribute("aria-expanded", "false");
  const icon = document.createElement("i");
  icon.classList.add("bi", "bi-columns");
  icon.style.fontSize = "1.2rem";
  bt.appendChild(icon);

  const ul = document.createElement("ul");
  ul.classList.add("dropdown-menu");

  const listHeader = document.createElement("li");
  const h = document.createElement("h6");
  h.classList.add("dropdown-header");
  h.innerHTML = "Select numeric meta da ta";
  h.style.color = "var(--bs-primary)";
  listHeader.appendChild(h);
  ul.appendChild(listHeader);

  el.appendChild(bt);
  el.appendChild(ul);

  // add listener
  el.addEventListener("click", function (e) {
    if (e.target.classList.contains("dropdown-item")) {
      e.preventDefault();
      // when clicking, update plotMetaData with selected numeric meta
      reglElementData.plotMetaData.selectedMeta = e.target.textContent;
      console.log("reglElementData.plotMetaData", reglElementData.plotMetaData);
      const vlnPlotCanvas = document.getElementById(vlnPlotElId);
      updateVlnPlot(vlnPlotCanvas);
    }
  });

  return el;
};

// function to update menu options of the dropend button
const updateDropOptions = (btId, list = []) => {
  const bt = document.getElementById(btId);
  const menu = bt.querySelector(".dropdown-menu");

  const listHeader = document.createElement("li");
  const h = document.createElement("h6");
  h.classList.add("dropdown-header");
  h.innerHTML = "Select Numeric Meta Data";
  h.style.color = "var(--bs-primary)";
  listHeader.appendChild(h);
  menu.appendChild(listHeader);

  list.forEach((e) => {
    const item = document.createElement("li");
    const a = document.createElement("a");
    a.classList.add("dropdown-item");
    a.setAttribute("href", "#");
    a.style.fontSize = "0.9rem";
    a.innerHTML = e;
    item.appendChild(a);
    menu.appendChild(item);
  });
};

const emptyDropOptions = (btId) => {
  const bt = document.getElementById(btId);
  const menu = bt.querySelector(".dropdown-menu");
  reglScatterCanvas.removeAllChildNodes(menu);
};

// extract numeric meta columns
const getNumericCols = (reglElementData) => {
  const cols = [];
  Object.keys(reglElementData.origData.cellMetaData).forEach((key) => {
    if (
      reglElementData.origData.cellMetaData[key].type === "number" &&
      key !== "cells"
    ) {
      cols.push(key);
    }
  });
  return cols;
};

// extrac nonNumeric meta columns
const getNonNumericCols = (reglElementData) => {
  const cols = [];
  Object.keys(reglElementData.origData.cellMetaData).forEach((key) => {
    if (
      reglElementData.origData.cellMetaData[key].type === "category" &&
      key !== "cells"
    ) {
      cols.push(key);
    }
  });
  return cols;
};
