import "shiny";
//import { createReglScatterInstance } from './modules/reglScatter.js';
import {
  resize_infoBox,
  update_collapse_icon,
} from "./modules/collapse_infoBox.js";
import * as myWaiter from "./modules/myWaiter.js";
export * as myWaiter from "./modules/myWaiter.js";

import { reglScatterCanvas } from "./modules/reglScatter.js";
import {
  initWebR,
  initShelter,
  readQS,
  featurePlot,
} from "./modules/featurePlot.js";
import {
  createSparkLine,
  updateSparkLine,
} from "./modules/featureSparkLine.js";
//import * as arrow from "apache-arrow";

// id of the mainClusterPlot parent div
const mainPlotElId = "mainClusterPlot-clusterPlot";

// init webR instances
const webR = await initWebR();
// init normal shelter for webR to gain better control of the r objects
const shelterInstance = await initShelter(webR);

// code below will ensure the functions were invoked after all the shiny content loaded
// thus here init scatterplot instance
document.addEventListener(
  "DOMContentLoaded",
  function () {
    // Get infoBoxId
    const infoBoxEl =
      document.getElementById("bottom_box").parentElement.parentElement;
    const mainPlotEl = document.getElementById(mainPlotElId);
    // init infoBox size to shrinked
    resize_infoBox(mainPlotEl, infoBoxEl, 56);
    infoBoxEl.querySelector(".bslib-full-screen-enter").style.display = "none";
    // Add event listener to infoBox collapsing icon
    const collapsing_icon = document.getElementById("infoBox_show");
    collapsing_icon.addEventListener("click", function () {
      update_collapse_icon(this.id);
      if (collapsing_icon.classList.contains("collapsed")) {
        resize_infoBox(mainPlotEl, infoBoxEl, 56);
        // hide full screen button
        infoBoxEl.querySelector(".bslib-full-screen-enter").style.display =
          "none";
      } else {
        resize_infoBox(mainPlotEl, infoBoxEl, 250);
        // show full screen button
        infoBoxEl.querySelector(".bslib-full-screen-enter").style.display = "";
      }
    });

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
  },
  false,
);

var reglElementData = new reglScatterCanvas("reglScatter");

// R waiter package spinners
// keep the style exactly the same with R function
var waiterSpinner = {
  id: "mainClusterPlot-clusterPlot",
  html: '<div class="loaderz-05" style = "color:var(--bs-primary);"></div>',
  color: "#ffffff",
  image: "",
};

const extractNonNumericCol = (reglElementData) => {
  // select non-numeric columns, and transfer to server side
  const nonNumericCols = [];
  for (let k of Object.keys(reglElementData.origData.cellMetaData)) {
    if (
      !reglElementData.origData.cellMetaData[k].every(
        // retain string and integer number
        // Modulo method is faster then .isInteger()
        (item) => typeof item === "number" && item % 1 != 0,
      )
    ) {
      nonNumericCols.push(k);
    }
  }
  return nonNumericCols;
};

//Shiny.addCustomMessageHandler('transfer_expression', (msg) => {
//    const expressionData = decodeAndDecompress(msg);
//    console.log(expressionData);
//    if(expressionData){
//        reglElementData.updateExpressionData(expressionData);
//    }else{
//        // purge exprssion data
//        reglElementData.updateExpressionData({});
//    }
//});

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
    fetch("data/" + msg)
      .then((file) => file.arrayBuffer())
      .then(async (buffer) => await readQS(webR, buffer))
      .then((df) => {
        console.log("qs df: ", df);
        reglElementData.updateReductionData(df);
        Shiny.setInputValue("reductionProcessed", true, { priority: "event" });
      });
  } catch (error) {
    console.error("There was a problem:", error);
  }
  // msg is the expr binary file name on the server
  //fetchBinaryFile("data/" + msg).then(data => {
  //    if (data) {
  //        //console.log('Binary data fetched successfully:', data);
  //        // Process the binary data as needed
  //        const reductionData = decodeDataBinary(data);
  //
  //        reglElementData.updateReductionData(reductionData);
  //        //console.log("reductionData", reglElementData.origData.reductionData);
  //        Shiny.setInputValue("reductionProcessed", true, { priority: "event" });
  //    }
  //
  //});
});

Shiny.addCustomMessageHandler("meta_ready", (msg) => {
  try {
    fetch("data/" + msg)
      .then((file) => file.arrayBuffer())
      .then(async (buffer) => await readQS(webR, buffer))
      .then((metaData) => {
        console.log("qs meta", metaData);
        reglElementData.updateCellMetaData(metaData);
        const nonNumericCols = extractNonNumericCol(reglElementData);
        Shiny.setInputValue("metaCols", nonNumericCols);
        //console.log("metaData", reglElementData.origData.cellMetaData);
        Shiny.setInputValue("metaProcessed", true, { priority: "event" });
      });
  } catch (error) {
    console.error("There was a problem:", error);
  }
});

Shiny.addCustomMessageHandler("expr_ready", (msg) => {
  try {
    fetch("data/" + msg)
      .then((file) => file.arrayBuffer())
      .then(async (buffer) => await readQS(webR, buffer))
      .then((exprData) => {
        console.log("qs expr", exprData);
        reglElementData.updateExpressionData(exprData);
        console.log("exprData", reglElementData.origData.expressionData);
        const feature = Object.keys(exprData)[0];
        const sparkLine = document
          .getElementById("featureSparkLine")
          .querySelectorAll(".featureSparkLine");
        const sparkLineArray = [...sparkLine];
        sparkLineArray.forEach((e) => {
          if (e.querySelector("span").innerHTML == feature) {
            updateSparkLine(e, reglElementData);
          }
        });
      });
  } catch (error) {
    console.error("There was a problem:", error);
  }
  // msg is the expr binary file name on the server
  //fetchBinaryFile("data/" + msg).then((data) => {
  //  if (data) {
  //    //console.log('Binary data fetched successfully:', data);
  //    // Process the binary data as needed
  //    const expressionData = decodeDataBinary(data);
  //
  //    reglElementData.updateExpressionData(expressionData);
  //    //console.log("exprData", expressionData);
  //    console.log("exprData", reglElementData.origData.expressionData);
  //    const feature = Object.keys(expressionData)[0];
  //    const sparkLine = document
  //      .getElementById("featureSparkLine")
  //      .querySelectorAll(".featureSparkLine");
  //    const sparkLineArray = [...sparkLine];
  //    sparkLineArray.forEach((e) => {
  //      if (e.querySelector("span").innerHTML == feature) {
  //        updateSparkLine(e, reglElementData);
  //      }
  //    });
  //  }
  //});
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
  const featurePlotCanvas = document.getElementById("featurePlotCanvas");
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
  if (groupBy && selectedGroupBy) {
    if (!splitBy) {
      reglElementData.origData.cellMetaData[groupBy].forEach((e, i) => {
        const currentCell = reglElementData.origData.cellMetaData["cells"][i];
        if (selectedGroupBy.includes(e)) {
          selectedCells.push(currentCell);
        }
      });
    } else {
      reglElementData.origData.cellMetaData[groupBy].forEach((e, i) => {
        const currentSplitBy =
          reglElementData.origData.cellMetaData[splitBy][i];
        const currentCell = reglElementData.origData.cellMetaData["cells"][i];
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
  const selectedCells = reglElementData.plotData.selectedCells;

  if (Object.keys(metaData).length > 0 && selectedCells.length > 0) {
    const nCells = metaData[Object.keys(metaData)[0]].length;
    //console.log(Object.keys(metaData).includes(newMetaCol));
    //console.log(!Object.keys(metaData).includes(newMetaCol));
    if (!Object.keys(metaData).includes(newMetaCol)) {
      reglElementData.origData.cellMetaData[newMetaCol] =
        Array(nCells).fill("unknown");
      //console.log(reglElementData.origData.cellMetaData);
    }
    const idx = selectedCells.map((e) => metaData["cells"].indexOf(e));
    idx.forEach((e) => {
      reglElementData.origData.cellMetaData[newMetaCol][e] = assignAs;
    });
  }
  console.log(
    "reglElementData.origData.cellMetaData:",
    reglElementData.origData.cellMetaData,
  );
  const nonNumericCols = extractNonNumericCol(reglElementData);
  Shiny.setInputValue("metaCols", nonNumericCols);
  // deselct points
  reglElementData.scatterplots.forEach((e) => e.deselect());
  // reset selectedCells
  Shiny.setInputValue("categorySelectedCells", null, { priority: "event" });
});

Shiny.addCustomMessageHandler("reglScatter_plot", (msg) => {
  // Add spinners for the plot
  // waiter is from R waiter package
  //myWaiter.show(waiterSpinner);

  // do necessary cleanups
  // ensure the featurePlot canvas is hidden
  const parentDiv = document.getElementById(mainPlotElId);
  const featurePlotCanvas = document.getElementById("featurePlotCanvas");
  featurePlotCanvas.style.display = "none";
  reglElementData.plotEl.style.display = "none";

  // create a shallow copy to store previous value
  //const previous_plotMetaData = {...reglElementData.plotMetaData};
  //console.log("previous_plotMetaData: ", previous_plotMetaData);
  //console.log("reglElementData: ", reglElementData);
  // clear reglScatterCanvas data including plotMetaData
  console.log("msg: ", msg);
  const group_by = msg.group_by;
  const split_by = msg.split_by;
  const moduleScore = msg.moduleScore;

  // update group_by levels to server side
  let groupByLevels = new Set(reglElementData.origData.cellMetaData[group_by]);
  groupByLevels = [...groupByLevels].sort();
  // when split_by == null, this will return a set with size 0
  //     // update split_by levels to server side
  let splitByLevels = new Set(reglElementData.origData.cellMetaData[split_by]);
  splitByLevels = [...splitByLevels].sort();
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
  reglElementData.generatePlotEl();
  console.log("reglElementData :", reglElementData);
  // update legend elements
  parentDiv.appendChild(reglElementData.plotEl);
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
  reglElementData.scatterplots.forEach((sp, idx) => {
    sp.subscribe("select", ({ points: selectedPoints }) => {
      const hoveredLegends = Array.from(
        document.querySelectorAll("#reglScatter-catLegend :hover"),
      );

      // ensure the legend was not hovered
      if (hoveredLegends.length == 0) {
        let selectedCells = selectedPoints.map(
          (i) => reglElementData.plotData.cells[idx][i],
        );
        reglElementData.plotData.selectedCells = selectedCells;
        Shiny.setInputValue("selectedPoints", selectedCells);
      }
    });
  });
  reglElementData.scatterplots.forEach((sp, idx) => {
    sp.subscribe("deselect", () => {
      reglElementData.plotData.selectedCells = [];
      Shiny.setInputValue("selectedPoints", null);
    });
  });

  if (
    Object.keys(reglElementData.plotMetaData.selectedFeatures).length > 1 &&
    !reglElementData.plotMetaData.moduleScore
  ) {
    console.log("Drawing featurePlot...");
    updateFeaturePlot(featurePlotCanvas);

    // show featurePlotCanvas
    featurePlotCanvas.style.display = "flex";
    //reglElementData.plotEl.style.display = "none";
  } else {
    reglElementData.plotEl.style.display = "flex";
  }

  // hide spinner
  //waiter.hide('mainClusterPlot-clusterPlot');

  //featurePlot().then({});
});

const updateFeaturePlot = (canvas) => {
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

  // It seems that webR does not support typedArray
  const expressionInput = {};
  for (let f of reglElementData.plotMetaData.selectedFeatures) {
    expressionInput[f] = Array.from(reglElementData.origData.expressionData[f]);
  }
  const drInput = {};
  for (let i of Object.keys(reglElementData.origData.reductionData)) {
    drInput[i] = Array.from(reglElementData.origData.reductionData[i]);
  }
  //console.log("reglElementData.origData.expressionData: ", reglElementData.origData.expressionData);
  //console.log(expressionInput);
  featurePlot(
    shelterInstance,
    canvasWidth,
    canvasHeight,
    drInput,
    //reglElementData.origData.reductionData,
    //reglElementData.origData.expressionData)
    expressionInput,
  ).then((res) => {
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    let img = res.images[0];
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
  });
  shelterInstance.purge();
};

Shiny.addCustomMessageHandler("reglScatter_deselect", (msg) => {
  console.log("Deselect points...");
  reglElementData.scatterplots.forEach((sp, i) => {
    sp.deselect();
  });
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
