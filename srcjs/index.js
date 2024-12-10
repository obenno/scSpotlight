import "shiny";
// not sure why waiter was not exposed as library
// cannot import even added it to externals config
// seems nothing wrong in the webpack config
// https://github.com/JohnCoene/waiter/blob/776f9f3ccd27aa3322d6c6d37c47b3d7b1f393e6/webpack.common.js#L64
// https://webpack.js.org/configuration/output/#outputlibrary
// exporting not tested, remove import temporarily
//import "waiter";

import * as spinner from "./modules/myWaiter.js";

import {
  resize_infoBox,
  update_collapse_icon,
} from "./modules/collapse_infoBox.js";

import {
  reglScatterCanvas,
  expandMeta,
  sortStringArray,
} from "./modules/reglScatter.js";
import {
  initShelter,
  featurePlot,
  vlnPlot,
  dotPlot,
  initWebRInstance,
  isIntegerArray,
} from "./modules/webr.js";
import {
  createSparkLine,
  updateSparkLine,
} from "./modules/featureSparkLine.js";

// keep global variables as small as possible
// query elements inside functions when necessary

// id of the mainClusterPlot parent div
const mainPlotElId = "mainClusterPlot-clusterPlot";
// featurePlot canvas id
const featurePlotElId = "featurePlotCanvas";
// vlnPlot canvas id
const vlnPlotElId = "VlnPlot";
// dotPlot canvas id
const dotPlotElId = "DotPlot";

// R waiter package spinners
// keep the style exactly the same with R function
var clusterPlotSpinner = {
  id: mainPlotElId,
  html: '<div class="loaderz-05" style = "color:var(--bs-primary);"></div>',
  color: "#ffffff",
  image: null,
};

var infoBoxContentId = "infoBox_content";
var infoBoxSpinner = {
  id: infoBoxContentId,
  html: '<div class="loaderz-05" style = "color:var(--bs-primary);"></div>',
  color: "#ffffff",
  image: null,
};

// init webR instance for reading reduction and expr data
let webR;
let shelter;
//let metaDataWebR;
//let plotWebR;

(async () => {
  webR = await initWebRInstance();
  shelter = await initShelter(webR);
})();

// init normal shelter for webR to gain better control of the r objects
//const shelterInstance = await initShelter(plotWebR);
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

    // auto update vlnPlot when resizing
    // Create ResizeObserver instance
    const featurePlotCanvas = document.getElementById(featurePlotElId);
    const vlnPlotCanvas = document.getElementById(vlnPlotElId);
    const dotPlotCanvas = document.getElementById(dotPlotElId);
    const resizeObserver = new ResizeObserver(
      debounce((entries) => {
        for (const entry of entries) {
          if (shelter) {
            // ensure shelter was initiated
            if (entry.target === vlnPlotCanvas && panelSelected(entry.target)) {
              console.log("resized vlnplot...");
              updateVlnPlot(vlnPlotCanvas);
            }
            if (entry.target === dotPlotCanvas && panelSelected(entry.target)) {
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

var reglElementData = new reglScatterCanvas("reglScatter");

//const waiter = window.waiter;

const extractNonNumericCol = (reglElementData) => {
  // select non-numeric columns, and transfer to server side
  // input is an arrow table
  const nonNumericCols = [];
  const colNames = reglElementData.origData.cellMetaData.schema.fields.map(
    (field) => field.name,
  );
  for (let k of colNames) {
    let kArray = reglElementData.origData.cellMetaData.getChild(k).toArray();
    if (
      k != "cells" &&
      !kArray.every(
        // retain string and integer number
        // Modulo method is faster then .isInteger()
        (item) => typeof item === "number",
      )
    ) {
      nonNumericCols.push(k);
    }
  }
  return nonNumericCols;
};

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
      const fn = await shelter.evalR(
        "function (url) { qs::qread_url(url, use_alt_rep=TRUE) }",
      );
      const df = {};
      const xRes = await fn.exec(xFileURL);
      df["X"] = new Float32Array(await xRes.toTypedArray());
      const yRes = await fn.exec(yFileURL);
      df["Y"] = new Float32Array(await yRes.toTypedArray());
      reglElementData.updateReductionData(df);
      await shelter.purge();
      Shiny.setInputValue("reductionProcessed", true, { priority: "event" });
      console.log("reduction", df);
    })();
  } catch (error) {
    console.error("There was a problem:", error);
  }
});

Shiny.addCustomMessageHandler("meta_ready", (msg) => {
  try {
    const metaURL = window.location.origin + "/data/meta/" + msg.metaFile;
    //let meta = {}
    (async () => {
      const fn = await shelter.evalR(
        "function (url) { qs::qread_url(url, use_alt_rep=TRUE) }",
      );
      const res = await fn.exec(metaURL);
      let idx = 0;
      const out = {};
      const loadedData = await res.toObject({ depth: 1 });
      const colNames = Object.keys(loadedData);
      //const out = await res.toObject();
      for await (const i of res) {
        const e = await i.toObject({ depth: 1 });

        const dataType = await e.type.toString();
        if (dataType === "number") {
          const dataArray = await e.value.toArray();
          if (isIntegerArray(dataArray)) {
            out[colNames[idx]] = {
              type: dataType,
              value: Int32Array.from(dataArray),
            };
          } else {
            out[colNames[idx]] = {
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
          out[colNames[idx]] = { type: dataType, value: dataObject };
        } else {
          out[colNames[idx]] = { type: dataType, value: [] };
        }
        idx++;
      }
      console.log(out);
      reglElementData.updateCellMetaData(out);
      const nonNumericCols = [];
      Object.keys(out).forEach((key) => {
        if (out[key].type !== "number") {
          nonNumericCols.push(key);
        }
      });
      Shiny.setInputValue("metaCols", nonNumericCols);
      Shiny.setInputValue("metaProcessed", true, { priority: "event" });
      await shelter.purge();
    })();
  } catch (error) {
    console.error("There was a problem:", error);
  }
});

Shiny.addCustomMessageHandler("expr_ready", (msg) => {
  try {
    const exprURL = window.location.origin + "/data/expr/" + msg.exprFile;
    (async () => {
      const fn = await shelter.evalR(
        "function (url) { qs::qread_url(url, use_alt_rep=TRUE) }",
      );
      const expr = {};
      const res = await fn.exec(exprURL);
      expr[msg.geneName] = new Float32Array(await res.toTypedArray());

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
  reglElementData.scatterplots.forEach((e) => e.deselect());
  // reset selectedCells
  Shiny.setInputValue("categorySelectedCells", null, { priority: "event" });
});

Shiny.addCustomMessageHandler("reglScatter_plot", (msg) => {
  // first remove spinner if exists
  try {
    spinner.hideSpinner(clusterPlotSpinner);
  } catch (error) {}
  // Add spinners for the plot
  // waiter is from R waiter package
  spinner.showSpinner(clusterPlotSpinner);

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
        document.querySelectorAll("#" + mainPlotElId + " :hover"),
      );

      // ensure the legend was not hovered
      if (hoveredLegends.length > 0) {
        let selectedCells = selectedPoints.map(
          (i) => reglElementData.plotData.cells[idx][i],
        );
        console.log("selectedCells: ", selectedCells);
        reglElementData.plotData.selectedCells = selectedCells;
        Shiny.setInputValue("selectedPoints", selectedCells, {
          priority: "event",
        });
      }
    });
  });
  reglElementData.scatterplots.forEach((sp, _) => {
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
    console.log("featureplot udpated...");
    // show featurePlotCanvas
    featurePlotCanvas.style.display = "flex";

    //reglElementData.plotEl.style.display = "none";
  } else {
    reglElementData.plotEl.style.display = "flex";
  }

  // hide spinner
  spinner.hideSpinner(clusterPlotSpinner);

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
  try {
    spinner.hideSpinner(clusterPlotSpinner);
  } catch (error) {
    console.error("error: ", error);
  }
  // show spinner
  spinner.showSpinner(clusterPlotSpinner);

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
      spinner.hideSpinner(clusterPlotSpinner);
      shelter.purge();
    });
  }
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

const updateVlnPlot = (canvas) => {
  // Firstly check the spinners
  try {
    spinner.hideSpinner(infoBoxSpinner);
  } catch (error) {
    console.error("error: ", error);
  }
  // show spinner
  spinner.showSpinner(infoBoxSpinner);
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
    console.log("Updating vlnplot...");
    // It seems that webR does not support typedArray
    const expressionInput = {};
    const metaInput = {};
    let expr = false;
    // vlnPlot only illustrates expression of the first selected genes
    if (reglElementData.plotMetaData.selectedFeatures.length > 0) {
      const f = reglElementData.plotMetaData.selectedFeatures[0];
      expressionInput[f] = Array.from(
        reglElementData.origData.expressionData[f],
      );
      expr = f;
    } else {
      let fixedMetaCol = [
        "nCount_RNA",
        "nFeature_RNA",
        "percent.mt",
        "percent.rp",
      ];

      const colNames = Object.keys(reglElementData.origData.cellMetaData);

      for (let i = 0; i < fixedMetaCol.length; i++) {
        if (colNames.includes(fixedMetaCol[i])) {
          metaInput[fixedMetaCol[i]] = expandMeta(
            reglElementData.origData.cellMetaData[fixedMetaCol[i]],
          );
        }
      }
    }
    const groupInput = {};
    groupInput[reglElementData.plotMetaData.group_by] = expandMeta(
      reglElementData.origData.cellMetaData[
        reglElementData.plotMetaData.group_by
      ],
    );
    const groupOrder = [
      ...new Set(groupInput[reglElementData.plotMetaData.group_by]),
    ].sort(sortStringArray);
    const dfInput = { ...groupInput, ...metaInput, ...expressionInput };
    for (const k of Object.keys(dfInput)) {
      // webr dataframe convertion doesn't support typed array
      dfInput[k] = Array.from(dfInput[k]);
    }
    console.log(
      "vlnPlot inputs: ",
      dfInput,
      reglElementData.plotMetaData.group_by,
      groupOrder,
      expr,
    );
    vlnPlot(
      shelter,
      canvasWidth,
      canvasHeight,
      dfInput,
      reglElementData.plotMetaData.group_by,
      groupOrder,
      (expr = expr),
      reglElementData.plotMetaData.catColors,
    ).then((res) => {
      const ctx = canvas.getContext("2d");
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      let img = res.images[0];
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      // hide spinner
      spinner.hideSpinner(infoBoxSpinner);
      shelter.purge();
    });
  }
};

const updateDotPlot = (canvas) => {
  // Firstly check the spinners
  try {
    spinner.hideSpinner(infoBoxSpinner);
  } catch (error) {
    console.error("error: ", error);
  }
  // show spinner
  spinner.showSpinner(infoBoxSpinner);
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
    // dotPlot only be rendered when there are more than one selected genes
    if (reglElementData.plotMetaData.selectedFeatures.length > 1) {
      for (let f of reglElementData.plotMetaData.selectedFeatures) {
        expressionInput[f] = Array.from(
          reglElementData.origData.expressionData[f],
        );
      }

      const groupInput = {};
      groupInput[reglElementData.plotMetaData.group_by] = expandMeta(
        reglElementData.origData.cellMetaData[
          reglElementData.plotMetaData.group_by
        ],
      );

      const dfInput = { ...groupInput, ...expressionInput };

      //for (const k of Object.keys(dfInput)) {
      //  // webr dataframe convertion doesn't support typed array
      //  dfInput[k] = Array.from(dfInput[k]);
      //}

      dotPlot(
        shelter,
        canvasWidth,
        canvasHeight,
        dfInput,
        reglElementData.plotMetaData.group_by,
      ).then((res) => {
        const ctx = canvas.getContext("2d");
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        let img = res.images[0];
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        // hide spinner
        spinner.hideSpinner(infoBoxSpinner);
        // purge R objects
        shelter.purge();
      });
    } else {
      const ctx = canvas.getContext("2d");
      // Set text properties
      //const bodyFontSize = getComputedStyle(document.documentElement)
      //      .getPropertyValue('--bs-body-font-size')
      //      .trim();
      //const bodyFontFamily = getComputedStyle(document.documentElement)
      //      .getPropertyValue('--bs-body-font-family')
      //      .trim();
      ctx.font = "30px Arial"; // Font size and family
      ctx.fillStyle = "#636363"; // Text color
      ctx.textAlign = "left"; // Text alignment
      ctx.textBaseline = "top"; // Vertical alignment

      // Draw filled text
      ctx.fillText("Please select at least two features", 10, 10); // Text, x, y
      // hide spinner
      spinner.hideSpinner(infoBoxSpinner);
    }
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

// function to check if the infoBox panel is selected/active
const panelSelected = (el) => {
  let parent = el.parentElement;
  while (parent) {
    if (parent.dataset.value === el.id) {
      break;
    }
    parent = parent.parentElement;
  }
  return parent && parent.classList.contains("active");
};

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
