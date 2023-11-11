import { message } from './modules/message.js';
import 'shiny';
import { createReglScatterInstance } from './modules/reglScatter.js';
import createScatterplot, { createRenderer } from 'regl-scatterplot';
import * as d3 from "d3";
import { resize_infoBox, update_collapse_icon } from './modules/collapse_infoBox.js';
import * as myWaiter from './modules/myWaiter.js';
export * as myWaiter from './modules/myWaiter.js';


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
var exprMin = null;
var exprMax = null;
var labelData = [];
var panelTitles = [];
var plotMode = null;
var dataColorName = null;
var dataCategoryName = null;
var dataCategoryCellNum = null;
//var highlightPointsIndex = null;
// variable to store expression data
var dataW = null;

// Create a reusable renderer
const renderer = createRenderer();

// code below will ensure the functions were invoked after all the shiny content loaded
// thus here init scatterplot instance
document.addEventListener('DOMContentLoaded', function () {


    // init infoBox size to shrinked
    resize_infoBox(56);
    document.getElementById("infoBox").querySelector(".bslib-full-screen-enter").style.display = "none";
    // Add event listener to infoBox collapsing icon
    const collapsing_icon = document.getElementById("infoBox_show");
    collapsing_icon.addEventListener("click", function() {
        update_collapse_icon();
        if(collapsing_icon.classList.contains("collapsed")){
            resize_infoBox(56);
            // hide full screen button
            document.getElementById("infoBox").querySelector(".bslib-full-screen-enter").style.display = "none";
        }else{
            resize_infoBox(250);
            // show full screen button
            document.getElementById("infoBox").querySelector(".bslib-full-screen-enter").style.display = "";
        }
    });


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

// R waiter package spinners
// keep the style exactly the same with R function
var waiterSpinner = {
  id: "mainClusterPlot-clusterPlot",
  html: '<div class="loaderz-05" style = "color:var(--bs-primary);"></div>',
  color: '#ffffff',
  image: ''
};

// function to create grid view in the element (mainClusterPlot div)
// here will always be div "parent-wrapper"
const createGrid = (elID, ncols, nrows) => {
    // retrieve mainClusterPlot div
    let parentEl = document.getElementById(elID);
    let el = document.createElement("div");
    el.id = "parent-wrapper";
    el.style.display = 'grid';

    // use a min size 300px, in case too may panels
    el.style.gridTemplateColumns = `repeat(${ncols}, minmax(300px, 1fr))`;
    el.style.gridTemplateRows = `repeat(${nrows}, minmax(300px, 1fr))`;
    //el.style.gridTemplateColumns = `repeat(${ncols}, minmax(0px, 1fr))`;
    //el.style.gridTemplateRows = `repeat(${nrows}, minmax(0px, 1fr))`;
    el.style.gap = '0.2rem';
    el.style.width = "100%";
    el.style.height = "100%";
    parentEl.appendChild(el);
};

const createInfoWidget = (elID) => {

    let parentEl = document.getElementById(elID);
    let infoEl = document.createElement("div");
    infoEl.id = "info";
    infoEl.setAttribute("tabindex", "0");
    let infoTitleEl = document.createElement("div");
    infoTitleEl.id = "info-title";
    let infoContentEl = document.createElement("div");
    infoContentEl.id = "info-content";
    let introduction = ["Pan: Click and drag your mouse.",
                        "Zoom: Scroll vertically.",
                        `Rotate: While pressing <kbd>ALT</kbd>, click and drag your mouse.`,
                        `Lasso: Pressing <kbd>SHIFT</kbd> and drag your mouse.`];

    for(let i = 0; i< introduction.length; ++i){
        let li = document.createElement('li');
        li.innerHTML = introduction[i];
        infoContentEl.appendChild(li);
    }

    infoEl.appendChild(infoContentEl);
    infoEl.appendChild(infoTitleEl);
    parentEl.appendChild(infoEl);
};

const createGoBackWidget = (elID) => {

    let parentEl = document.getElementById(elID);
    let iconSVG = `<svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" class="bi bi-arrow-bar-left" viewBox="0 0 16 16" style="position:relative;">
  <path fill-rule="evenodd" d="M12.5 15a.5.5 0 0 1-.5-.5v-13a.5.5 0 0 1 1 0v13a.5.5 0 0 1-.5.5ZM10 8a.5.5 0 0 1-.5.5H3.707l2.147 2.146a.5.5 0 0 1-.708.708l-3-3a.5.5 0 0 1 0-.708l3-3a.5.5 0 1 1 .708.708L3.707 7.5H9.5a.5.5 0 0 1 .5.5Z"/>
</svg>`;
    let iconEl = document.createElement("div");
    iconEl.id = "goBack";
    iconEl.innerHTML = iconSVG;
    iconEl.onclick = tellShinyGoBack;
    parentEl.appendChild(iconEl);
};

const tellShinyGoBack = () => {
    // Tell shiny to go back;
    console.log("Executing go back code");
    Shiny.setInputValue("goBack", 1);
};

const clearMainPlotEl = () => {
    // used to remove "parent-wrapper" div
    let el = document.getElementById("parent-wrapper");
    if(el){
        el.remove();
    }
};

const populate_grid = (gridElID, nPanels) => {
    // populate grid div with canvases
    // each canvas is wrapped by a fill div
    // use nPanels instead of ncols and nrows to handle both even and odd number of panel
    const canvas_wrapper = document.createElement("div");
    // add fill class
    canvas_wrapper.classList.add("html-fill-item");
    canvas_wrapper.classList.add("html-fill-container");
    canvas_wrapper.style.position = "relative";
    // add border style for multiple panels
    if(nPanels > 1){
        canvas_wrapper.style.borderWidth = "1px";
        canvas_wrapper.style.borderStyle = "solid";
        canvas_wrapper.style.borderColor = "#D3D3D3";
    }

    const plotTitle = document.createElement("div");
    plotTitle.classList.add("mainClusterPlotTitle");
    canvas_wrapper.appendChild(plotTitle);

    const canvas = document.createElement("canvas");
    canvas_wrapper.appendChild(canvas);
    //console.log(canvas_wrapper);

    const gridEl = document.getElementById(gridElID);

    for (let i = 0; i < nPanels; i++) {
        //console.log(i);
        const newCanvas = canvas_wrapper.cloneNode({deep: true});
        //console.log(newCanvas);
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

const populate_instance = (scatterplot, data_XY, data_Z, zType, colorName, panelIndex) => {
    // zType could be either "category" or "expr"
    // regl-scatterplot will only treat float numbers of [0,1] as continuous value
    let points = null;
    if(zType == "expr"){
        let zScale = d3.scaleLinear([exprMin, exprMax], [0, 1]);
        let data_Z_converted = data_Z.map((e) => zScale(e));
        points = {
          x: data_XY.X,
          y: data_XY.Y,
          z: data_Z_converted
        };
    }else{
        points = {
          x: data_XY.X,
          y: data_XY.Y,
          z: data_Z
        };
    }
  // color will be assigned by R

  console.log(points);
  scatterplot.clear();

  let opacity = 0.6;
  let pointSize = 3;

  if(data_XY.X.length < 15000){
      opacity = 0.8;
      pointSize = 3;
  }else if(data_XY.X.length > 50000){
      opacity = 0.4;
      pointSize = 1;
  }else if(data_XY.X.length > 1000000){
      opacity = 0.2;
      pointSize = 0.5;
  }else if(data_XY.X.length > 2000000){
      opacity = 0.2;
      pointSize = 0.2;
  }
  scatterplot.set({ colorBy: 'z', opacity: opacity,
                    pointSize: pointSize, pointColor: colorName });

  if(zType == "category"){
      scatterplot.subscribe('pointOver', (pointId) => {
          showNote(
              mainClusterPlot_noteID,
              labelData[panelIndex][pointId],
              dataColorName[panelIndex][dataZ[panelIndex][pointId]]
          );
      });
  }else{
      scatterplot.subscribe('pointOver', (pointId) => {
          showNote(
              mainClusterPlot_noteID,
              labelData[panelIndex][pointId],
              "#DCDCDC"
          );
      });
  }
  scatterplot.subscribe('pointOut', () => { hideNote(mainClusterPlot_noteID); });

  // subscribe select events
  scatterplot.subscribe('select', ({ points: selectedPoints }) => {
    Shiny.setInputValue("selectedPoints", selectedPoints);
  });
  scatterplot.subscribe('deselect', () => {
    Shiny.setInputValue("selectedPoints", null);
  });
  scatterplot.draw(points);
};


// note manipulation to mimic tooltips
const showNote = (noteId, text, color) => {
    let noteEl = document.getElementById(noteId);
    noteEl.style.display = null;
    noteEl.style.opacity = 0.8;
    noteEl.style.background = color;
    noteEl.textContent = text;
};

const hideNote = (noteId) => {
    let noteEl = document.getElementById(noteId);
    noteEl.style.display = "none";
  //noteEl.style.opacity = 0;
};


const createLegendEl = (legendIndex) => {
    // panel one colors data will always be "category" panel
    // and contains all of the category colors

    // But when there is only one category level and one panel
    // it will return a unnested array
    // thus we will have to test dataColorName[0]
    let panelOneColors = [];
    if(Array.isArray(dataColorName[0])){
        panelOneColors = dataColorName[0];
    }else{
        panelOneColors.push(dataColorName[0]);
    }
    let titleData = [];
    if(Array.isArray(dataCategoryName)){
        titleData = dataCategoryName;
    }else{
        titleData.push(dataCategoryName);
    }
    let cellNumberData = [];
    if(Array.isArray(dataCategoryCellNum)){
        cellNumberData = dataCategoryCellNum;
    }else{
        cellNumberData.push(dataCategoryCellNum);
    }
    let color = panelOneColors[legendIndex];
    let title = titleData[legendIndex];
    let number = cellNumberData[legendIndex];
    // legend style modified from broad single cell portal viewer
    const scatterLegend = document.createElement("div");
    scatterLegend.classList.add("scatter-legend");
    scatterLegend.id = "legend_" + legendIndex;

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
};

const highlight_index = (legendIndex) => {
    // return a array of highlight points index array
    let pointsIndex = [];
    pointsIndex = dataZ.map((e,i) => {
        let out = [];
        if(dataZ_type[i] == "category"){
            e.forEach((el, index) => {
                if(el == legendIndex){
                    out.push(index);
                }
            });
        }
        return out;
    });
    // Copy the category index to expr panel
    // to ensure mode "cluster+expr+noSplit" and "cluster+expr+twoSplit" also
    // have highlighted points in the expr panel
    for(let i = 0; i < pointsIndex.length; i++){
        if(pointsIndex[i].length == 0 && dataZ_type[i] == "expr" && dataZ_type[i-1] == "category"){
            pointsIndex[i] = pointsIndex[i-1];
        }
    }
    console.log(pointsIndex);
    return pointsIndex;
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

    // Add spinners for the plot
    // waiter is from R waiter package
    myWaiter.show(waiterSpinner);
    // Only process XY data and init canvases in this function
    console.log(msg);
    let nPanels = msg.nPanels;
    let nCols = null;
    if(nPanels >= 2){
        nCols = 2;
    }else{
        nCols = 1;
    }
    let nRows = Math.ceil(nPanels/nCols);
    // remove all elements in mainClusterPlot element
    clearMainPlotEl();
    // add parent-wrapper element, adjust rows and columns
    createGrid(mainClusterPlotElID, nCols, nRows);
    populate_grid("parent-wrapper", nPanels);
    let canvases = Array.from( document.getElementById(mainClusterPlotElID).querySelectorAll("canvas") );
    //console.log(canvases);
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

    // add info icon element
    createInfoWidget("parent-wrapper");

    // hide spinner
    waiter.hide('mainClusterPlot-clusterPlot');
});

Shiny.addCustomMessageHandler('reglScatter_color', (msg) => {

    // Add spinners for the plot
    // waiter is from R waiter package
    myWaiter.show(waiterSpinner);

    let noteId= null;

    // update color data
    plotMode = msg.mode;
    dataZ = msg.zData;
    console.log(dataZ);
    dataZ_type = msg.zType;
    console.log(dataZ_type);
    exprMin = msg.exprMin;
    exprMax = msg.exprMax;
    labelData = msg.labelData;
    dataColorName = msg.colors;
    dataCategoryName = msg.catNames;
    dataCategoryCellNum = msg.catCellNums;
    console.log(dataColorName);
    console.log(dataCategoryName);
    console.log(dataCategoryCellNum);
    panelTitles = msg.panelTitles;

    mainClusterPlot_scatterplots.forEach((sp, i) => {
        console.log(i);
        populate_instance(sp, dataXY[i], dataZ[i], dataZ_type[i], dataColorName[i], i);
    });

    // Populate panel titles
    document.querySelectorAll(".mainClusterPlotTitle")
        .forEach((e,i) => { e.innerHTML = panelTitles[i]; });

    // Add cluster legends, no legend for "cluster+expr+multiSplit" mode
    if(plotMode != "cluster+expr+multiSplit"){
        const accordions = document.querySelectorAll(".accordion-item");
        const category_accordion = [...accordions].filter((e) => {
            if(e.dataset.value == "analysis_category"){
                return e;
            }
        });
        const category_accordion_body = category_accordion[0].querySelector(".accordion-body");
        category_accordion_body.querySelectorAll(".scatter-legend").forEach((e) => e.remove());
        // By default the category panels will contain all of the category colors even
        // it doesn't contain any scatter belonging to that category
        // Thus here we will use the panel 1 colors data to construct legends
        let panelOneColors = [];
        if(Array.isArray(dataColorName[0])){
            panelOneColors = dataColorName[0];
        }else{
            panelOneColors.push(dataColorName[0]);
        }
        panelOneColors.forEach((e,i) => {
            let legendEl = createLegendEl(i);
            let legendIndex = i;
            // Add hover events
            // note do not use mouseover and mouseout event
            legendEl.onmouseenter = (event) => {
                event.target.style.borderColor = "black";
                event.target.style.borderWidth = "2px";
                console.log("enter event triggered");
                let pointsIndex = highlight_index(legendIndex);
                mainClusterPlot_scatterplots.forEach((sp, index) => {
                    sp.select(pointsIndex[index]);
                });
            };
            legendEl.onmouseleave = (event) => {
                event.target.style.borderColor = "#D3D3D3";
                event.target.style.borderWidth = "1px";
                console.log("leave event triggered");
                // deselect all points
                mainClusterPlot_scatterplots.forEach((sp, index) => {
                    sp.deselect();
                });
            };
            category_accordion_body.appendChild(legendEl);
        });

    }else{
        // remove all legendEls
        let legendEls = document.querySelectorAll(".scatter-legend");
        if(legendEls.length > 0){
            legendEls.forEach((e) => e.remove());
        }
    }

    // hide spinner
    waiter.hide('mainClusterPlot-clusterPlot');
});

Shiny.addCustomMessageHandler('reglScatter_removeGrid', (msg) => {
    clearMainPlotEl();
});

Shiny.addCustomMessageHandler('reglScatter_addGoBack', (msg) => {
    // Go Back widget will only be added when receiving shiny signals
    createGoBackWidget("parent-wrapper");
    // Reset goBack value when creating goBackWidget
    Shiny.setInputValue("goBack", null);
});

