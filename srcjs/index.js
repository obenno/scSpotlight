import { message } from './modules/message.js';
import 'shiny';
import { createReglScatterInstance } from './modules/reglScatter.js';
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
var mainClusterPlot_scatterplot = null;
// id of the mainClusterPlot parent div
var mainClusterPlotElID = "mainClusterPlot-clusterPlot";
// id of the mainClusterPlot note div
var mainClusterPlot_noteID = "mainClusterPlot-note";
// variable to store reduction dimension data
var dataXY = null;
// variable to store category and color data
// z store translated value
var dataZ = null;
var dataColorName = null;
var dataCategoryName = null;
// variable to store expression data
var dataW = null;


// code below will ensure the functions were invoked after all the shiny content loaded
// thus here init scatterplot instance
document.addEventListener('DOMContentLoaded', function () {
    // do something here ...
    mainClusterPlot_scatterplot = createReglScatterInstance(mainClusterPlotElID);
    // Add resize function to mainClusterPlot device
    var ro = new ResizeObserver(entries => {
        for (let entry of entries) {
            let { width, height } = entry.target.getBoundingClientRect();
            // Remove padding and margin
            let paddingTop = window.getComputedStyle(entry.target).paddingTop;
            let paddingBottom = window.getComputedStyle(entry.target).paddingBottom;
            let marginTop = window.getComputedStyle(entry.target).marginTop;
            let marginBottom = window.getComputedStyle(entry.target).marginBottom;
            paddingTop = parseInt(paddingTop);
            paddingBottom = parseInt(paddingBottom);
            marginTop = parseInt(marginTop);
            marginBottom = parseInt(marginBottom);


            let paddingLeft = window.getComputedStyle(entry.target).paddingLeft;
            let paddingRight = window.getComputedStyle(entry.target).paddingRight;
            let marginLeft = window.getComputedStyle(entry.target).marginLeft;
            let marginRight = window.getComputedStyle(entry.target).marginRight;
            paddingLeft = parseInt(paddingLeft);
            paddingRight = parseInt(paddingRight);
            marginLeft = parseInt(marginLeft);
            marginRight = parseInt(marginRight);

            height = height - paddingTop - paddingBottom - marginTop - marginBottom;
            width = width - paddingLeft - paddingRight - marginLeft - marginRight;

            if(entry.target.id == mainClusterPlotElID){
                //console.log("width: "+width);
                //console.log("height: "+height);
                mainClusterPlot_scatterplot.set({ width: width, height: height });
            }
            //console.log('Element:', entry.target);
            //console.log(`Element size: ${width}px x ${height}px`);
        }
    });
    // observe mainClusterPlot
    ro.observe(document.querySelector("#" + mainClusterPlotElID));

}, false);

const scaleDataXY = (dataXY) => {
  // data is the object transformed from R
  // column name: X, Y
  let xmin = d3.min(dataXY.X);
  let xmax = d3.max(dataXY.X);
  let ymin = d3.min(dataXY.Y);
  let ymax = d3.max(dataXY.Y);
  let dataMin = d3.min([xmin, ymin]);
  let dataMax = d3.max([xmax, ymax]);
  console.log(dataMin);
  const dScale = d3.scaleLinear([dataMin, dataMax], [-1, 1]).nice();
  let data = {
    X: dataXY.X.map(dScale),
    Y: dataXY.Y.map(dScale)
  };

  return data;
};

const populate_instance = (scatterplot, dataXY, dataZ, colorName, noteId) => {

  let points = {
    x: dataXY.X,
    y: dataXY.Y,
    z: dataZ
  };
  // color will be assigned by R

  console.log(points);
  scatterplot.clear();

  let opacity = 0.6;
  let pointSize = 3;
  if(dataXY.X.length < 15000){
      opacity = 0.8;
      pointSize = 6;
  }else if(dataXY.X.length > 100000){
      opacity = 0.4;
      pointSize = 3;
  }else if(dataXY.X.length > 1000000){
      opacity = 0.2;
      pointSize = 1;
  }else if(dataXY.X.length > 2000000){
      opacity = 0.2;
      pointSize = 0.5;
  }
    scatterplot.set({ colorBy: 'z', opacity: opacity,
                      pointSize: pointSize, pointColor: colorName });
  console.log(dataCategoryName);
  console.log(dataColorName);
  //console.log(noteId);
  scatterplot.subscribe('pointOver', (pointId) => {
      if(dataZ){
          showNote(
              noteId,
              dataCategoryName[dataZ[pointId]],
              dataColorName[dataZ[pointId]]
          );
      }
  });
  scatterplot.subscribe('pointOut', () => { hideNote(noteId); });
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

    //let elID = msg.id;
    let scatterplot = null;
    let noteId = null;
    if(msg.id == mainClusterPlotElID){
        scatterplot = mainClusterPlot_scatterplot;
        noteId = mainClusterPlot_noteID;
    }
    console.log("created");
    // update reduction points data
    dataXY = scaleDataXY(msg.pointsData);
    //console.log(dataXY);
    populate_instance(scatterplot, dataXY, dataZ,
                      dataColorName,
                      noteId);
});

Shiny.addCustomMessageHandler('reglScatter_color', (msg) => {

    //let elID = msg.id;
    let scatterplot = null;
    let noteId= null;
    if(msg.id == mainClusterPlotElID){
        scatterplot = mainClusterPlot_scatterplot;
        noteId = mainClusterPlot_noteID;
    }
    // update color data
    dataZ = msg.colorsData.catValues;
    dataCategoryName = msg.catNames;
    //console.log(dataZ);
    //console.log(dataCategoryName);
    dataColorName = msg.catColors;
    //console.log(dataColorName);
    //console.log(colors);
    //scatterplot_setColor(scatterplot, colors);
    populate_instance(scatterplot, dataXY, dataZ,
                      dataColorName,
                      noteId);
});
