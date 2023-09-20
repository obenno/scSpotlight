import { message } from './modules/message.js';
import 'shiny';
import { createReglScatterInstance } from './modules/reglScatter.js';
import createScatterplot, { createRenderer } from 'regl-scatterplot';
import * as d3 from "d3";

// In shiny server use:
// session$sendCustomMessage('show-packer', 'hello packer!')
Shiny.addCustomMessageHandler('show-packer', (msg) => {
  message(msg);
});


// instance resize function, use in "onresize" property
//const reglScatter_resize = (containerID, scatterplot) => {
//    let { width, height } = document.querySelector('#' + containerID).getBoundingClientRect();
//    console.log(width);
//    console.log(height);
//    scatterplot.set({ width, height });
//};

// create mainClusterPlot instance
// window load checking is import, or query will fail
var mainClusterPlot_scatterplots = null;
// id of the mainClusterPlot parent div
var mainClusterPlotElID = "mainClusterPlot-clusterPlot";
// ncols and nrows of the main cluster plot grid
var ncols = 1;
var nrows = 1;
// id of the mainClusterPlot note div
var mainClusterPlot_noteID = "mainClusterPlot-note";
// variable to store reduction dimension data
var dataXY = [];
// variable to store category and color data
// z store translated value
var dataZ = [];
var dataZ_type = [];
var dataColorName = null;
var dataCategoryName = null;
// variable to store expression data
var dataW = null;

// Create a reusable renderer
const renderer = createRenderer();

// code below will ensure the functions were invoked after all the shiny content loaded
// thus here init scatterplot instance
document.addEventListener('DOMContentLoaded', function () {
    // do something here ...
    //mainClusterPlot_scatterplot = createReglScatterInstance(mainClusterPlotElID);
    // Add resize function to mainClusterPlot device
    //var ro = new ResizeObserver(entries => {
    //    for (let entry of entries) {
    //        let { width, height } = entry.target.getBoundingClientRect();
    //        // Remove padding and margin
    //        let paddingTop = window.getComputedStyle(entry.target).paddingTop;
    //        let paddingBottom = window.getComputedStyle(entry.target).paddingBottom;
    //        let marginTop = window.getComputedStyle(entry.target).marginTop;
    //        let marginBottom = window.getComputedStyle(entry.target).marginBottom;
    //        paddingTop = parseInt(paddingTop);
    //        paddingBottom = parseInt(paddingBottom);
    //        marginTop = parseInt(marginTop);
    //        marginBottom = parseInt(marginBottom);
    //
    //
    //        let paddingLeft = window.getComputedStyle(entry.target).paddingLeft;
    //        let paddingRight = window.getComputedStyle(entry.target).paddingRight;
    //        let marginLeft = window.getComputedStyle(entry.target).marginLeft;
    //        let marginRight = window.getComputedStyle(entry.target).marginRight;
    //        paddingLeft = parseInt(paddingLeft);
    //        paddingRight = parseInt(paddingRight);
    //        marginLeft = parseInt(marginLeft);
    //        marginRight = parseInt(marginRight);
    //
    //        height = height - paddingTop - paddingBottom - marginTop - marginBottom;
    //        width = width - paddingLeft - paddingRight - marginLeft - marginRight;
    //
    //        if(entry.target.id == mainClusterPlotElID){
    //            //console.log("width: "+width);
    //            //console.log("height: "+height);
    //            mainClusterPlot_scatterplot.set({ width: width, height: height });
    //        }
    //        //console.log('Element:', entry.target);
    //        //console.log(`Element size: ${width}px x ${height}px`);
    //    }
    //});
    //// observe mainClusterPlot
    //ro.observe(document.querySelector("#" + mainClusterPlotElID));

}, false);


// function to create grid view in the element (mainClusterPlot div)
// here will always be div "parent-wrapper"
const createGrid = (elID, ncols, nrows) => {
    // retrieve mainClusterPlot div
    let parentEl = document.getElementById(elID);
    let el = document.createElement("div");
    el.id = "parent-wrapper";
    el.style.display = 'grid';
    el.style.gridTemplateColumns = `repeat(${ncols}, minmax(0, 1fr))`;
    el.style.gridTemplateRows = `repeat(${nrows}, minmax(0, 1fr))`;
    el.style.gap = '0.2rem';
    el.style.width = "100%";
    el.style.height = "100%";
    parentEl.appendChild(el);
};

const clearMainPlotEl = () => {
    // used to remove "parent-wrapper" div
    let el = document.getElementById("parent-wrapper");
    if(el){
        el.remove();
    }
};

const populate_grid = (gridElID, ncols, nrows) => {
    // populate grid div with canvases
    // each canvas is wrapped by a fill div
    const canvas_wrapper = document.createElement("div");
    // add fill class
    canvas_wrapper.classList.add("html-fill-item");
    canvas_wrapper.classList.add("html-fill-container");
    // add border style for multiple panels
    if(ncols > 1){
        canvas_wrapper.style.borderWidth = "1px";
        canvas_wrapper.style.borderStyle = "solid";
        canvas_wrapper.style.borderColor = "#D3D3D3";
    }
    const canvas = document.createElement("canvas");
    canvas_wrapper.appendChild(canvas);
    console.log(canvas_wrapper);

    const gridEl = document.getElementById(gridElID);

    for (let i = 0; i < ncols * nrows; i++) {
        console.log(i);
        const newCanvas = canvas_wrapper.cloneNode({deep: true});
        console.log(newCanvas);
        gridEl.appendChild(newCanvas);
    }
};

const scaleDataXY = (dataXY) => {
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
    Y: dataXY.Y.map(dScale)
  };

  return data;
};

const populate_instance = (scatterplot, dataXY, dataZ, zType, colorName) => {
    // zType could be either "category" or "expr"
    // regl-scatterplot will only treat float numbers of [0,1] as continuous value
    let points = null;
    if(zType == "expr"){
        let minZ = d3.min(dataZ);
        let maxZ = d3.max(dataZ);
        let zScale = d3.scaleLinear([minZ, maxZ], [0, 1]);
        let dataZ_converted = dataZ.map((e) => zScale(e));
        points = {
          x: dataXY.X,
          y: dataXY.Y,
          z: dataZ_converted
        };
    }else{
        points = {
          x: dataXY.X,
          y: dataXY.Y,
          z: dataZ
        };
    }
  // color will be assigned by R

  console.log(points);
  scatterplot.clear();

  let opacity = 0.6;
  let pointSize = 3;

  if(dataXY.X.length < 15000){
      opacity = 0.8;
      pointSize = 3;
  }else if(dataXY.X.length > 50000){
      opacity = 0.4;
      pointSize = 1;
  }else if(dataXY.X.length > 1000000){
      opacity = 0.2;
      pointSize = 0.5;
  }else if(dataXY.X.length > 2000000){
      opacity = 0.2;
      pointSize = 0.2;
  }
  scatterplot.set({ colorBy: 'z', opacity: opacity,
                    pointSize: pointSize, pointColor: colorName });

  //console.log(dataCategoryName);
  //console.log(dataColorName);
  //console.log(noteId);
  //scatterplot.subscribe('pointOver', (pointId) => {
  //    if(dataZ){
  //        showNote(
  //            noteId,
  //            dataCategoryName[dataZ[pointId]],
  //            dataColorName[dataZ[pointId]]
  //        );
  //    }
  //});
    //scatterplot.subscribe('pointOut', () => { hideNote(noteId); });
    scatterplot.draw(points);
};


// note manipulation to mimic tooltips
const showNote = (noteId, text, color) => {
  let noteEl = document.getElementById(noteId);
  noteEl.style.opacity = 1;
  noteEl.style.background = color;
  noteEl.textContent = text;
};

const hideNote = (noteId) => {
  let noteEl = document.getElementById(noteId);
  noteEl.style.opacity = 0;
};

//Shiny.addCustomMessageHandler('reglScatter', (msg) => {
//
//    //let elID = msg.id;
//    let scatterplot = null;
//    if(msg.id == mainClusterPlotElID){
//        scatterplot = mainClusterPlot_scatterplot;
//    }
//    console.log("created");
//    let data = msg.pointsData;
//    let colors = msg.colorsData.catColors;
//    console.log(data);
//    console.log(colors);
//    //scatterplot_setColor(scatterplot, colors);
//    populate_instance(scatterplot, data);
//});

Shiny.addCustomMessageHandler('reglScatter_reduction', (msg) => {

    // Only process XY data and init canvases in this function
    console.log(msg);
    let nCols = msg.nCols;
    let nRows = msg.nRows;
    // remove all elements in mainClusterPlot element
    clearMainPlotEl();
    // add parent-wrapper element, adjust rows and columns
    createGrid(mainClusterPlotElID, nCols, nRows);
    populate_grid("parent-wrapper", nCols, nRows);
    let canvases = Array.from( document.getElementById(mainClusterPlotElID).querySelectorAll("canvas") );
    console.log(canvases);
    renderer.refresh();

    mainClusterPlot_scatterplots = canvases.map((canvas) =>
       createReglScatterInstance(renderer, canvas)
    );
    console.log(mainClusterPlot_scatterplots.length);
    ////console.log(mainClusterPlot_scatterplots);
    ////console.log("here");
    //    let noteId = mainClusterPlot_noteID;
    ////}
    // update reduction points data
    console.log(msg.pointsData);
    //dataXY = scaleDataXY(msg.pointsData);
    //console.log(dataXY);
    ////mainClusterPlot_scatterplots.forEach((sp, i) => {
    ////    sp.draw({
    ////      x: dataXY.X,
    ////      y: dataXY.Y
    ////    });
    ////});
    //populate_instance(mainClusterPlot_scatterplots[0], dataXY, dataZ,
    //                  dataColorName,
    //                  noteId);

    dataXY = msg.pointsData.map((d) => scaleDataXY(d));

});

Shiny.addCustomMessageHandler('reglScatter_color', (msg) => {

    //let elID = msg.id;
    let scatterplot = null;
    let noteId= null;

    // update color data
    dataZ = msg.zData;
    dataCategoryName = msg.catNames;
    dataZ_type = msg.zType;
    //console.log(dataZ_type);
    //console.log(dataCategoryName);
    dataColorName = msg.colors;
    console.log(dataColorName);
    //console.log(colors);
    //scatterplot_setColor(scatterplot, colors);
    //populate_instance(scatterplot, dataXY, dataZ,
    //                  dataColorName,
    //                  noteId);

    mainClusterPlot_scatterplots.forEach((sp, i) => {
        console.log(i);
        populate_instance(sp, dataXY[i], dataZ[i], dataZ_type[i], dataColorName[i]);
    });
});
