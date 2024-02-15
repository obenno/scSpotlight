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

// id of the mainClusterPlot note div
var mainClusterPlot_noteID = "mainClusterPlot-note";

var reductionData = null;
var metaData = null;
var expressionData = null;

// legend hover event indicator
// to distinguish legend hover and manualy selecting events
var legendHover = 0;

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

const scaleDataZ = (arrayZ) => {
    // arrayZ is a numeric array (expressionData)
    // regl-scatterplot treats z values ranging between [0,1] as continuous data
    let minValue = d3.min(arrayZ);
    let maxValue = d3.max(arrayZ);
    let zScale = d3.scaleLinear([minValue, maxValue], [0, 1]).nice();
    let arrayZ_converted = arrayZ.map((e) => zScale(e));
    return arrayZ_converted;
};

//const populate_instance = (scatterplot, data_XY, data_Z, zType, colorName, panelIndex) => {
const populate_instance = (
    scatterplot,
    pointsData,
    pointColor,
    labelData,
    cells,
    zType
) => {
    // zType could be either "category" or "expr"
    // regl-scatterplot will only treat float numbers of [0,1] as continuous value
    let points = null;
    let exprColorScale = d3.interpolate("#D3D3D3", "#6450B5"); // lightgrey, iris

  scatterplot.clear();

  let opacity = 0.6;
  let pointSize = 3;
  let performanceMode = false;

  if(pointsData.x.length < 15000){
      opacity = 0.8;
      pointSize = 5;
  }else if(pointsData.x.length > 50000 && pointsData.x.length <= 500000){
      opacity = 0.6;
      pointSize = 3;
  }else if(pointsData.x.length > 500000 && pointsData.x.length <= 1000000){
      opacity = 0.4;
      pointSize = 1;
      performanceMode = true;
  }else if(pointsData.x.length > 1000000 && pointsData.x.length <= 2000000){
      opacity = 0.2;
      pointSize = 0.5;
      performanceMode = true;
  }else if(pointsData.x.length > 2000000){
      opacity = 0.2;
      pointSize = 0.2;
      performanceMode = true;
  }
  scatterplot.set({ colorBy: 'z',
                    opacity: opacity,
                    pointSize: pointSize,
                    pointColor: pointColor,
                    performanceMode: performanceMode });


    if(zType == "category"){
        scatterplot.subscribe('pointOver', (pointId) => {
            showNote(
                mainClusterPlot_noteID,
                labelData[pointId],
                pointColor[pointsData.z[pointId]]
            );
        });
    }else{
        scatterplot.subscribe('pointOver', (pointId) => {
            showNote(
                mainClusterPlot_noteID,
                labelData[pointId],
                rgbToHex(exprColorScale(pointsData.z[pointId]))
            );
        });
    }

  scatterplot.subscribe('pointOut', () => { hideNote(mainClusterPlot_noteID); });

  // subscribe select events
  scatterplot.subscribe('select', ({ points: selectedPoints }) => {
    if(legendHover == 0){
      let selectedCells = selectedPoints.map(i => cells[i]);
      Shiny.setInputValue("selectedPoints", selectedCells);
    }
  });
  scatterplot.subscribe('deselect', () => {
    Shiny.setInputValue("selectedPoints", null);
  });
  scatterplot.draw(pointsData);
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


const createLegendEl = (title, color, number) => {

    // legend style modified from broad single cell portal viewer
    const scatterLegend = document.createElement("div");
    scatterLegend.classList.add("scatter-legend");
    // replace unsafe strings in title and use it as the legend element id
    scatterLegend.id = "legend_" + title.replace(/[^a-zA-Z0-9-_]/g, '_');

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

const findIndexes = (arr, value) => {
  var indexes = [];
  for (var i = 0; i < arr.length; i++) {
    if (arr[i] === value) {
      indexes.push(i);
    }
  }
  return indexes;
};

const highlight_index = (mode, pointData_z, selectedGroupBy, metaData, group_by) => {
    // return a array of highlight points index array
    let pointsIndex = [];

    let factorLevel = {};
    let uniqueArr = new Set(metaData[group_by]);
    let sortedUniqueArr = Array.from(uniqueArr).sort(sortStringArray);
    sortedUniqueArr.forEach((e,i) => {
        factorLevel[e] = i;
    });

    switch(mode){
    case "clusterOnly":
        pointsIndex[0] = findIndexes(pointData_z[0], factorLevel[selectedGroupBy]);
        break;
    case "cluster+expr+noSplit":
        pointsIndex[0] = findIndexes(pointData_z[0], factorLevel[selectedGroupBy]);
        pointsIndex[1] = pointsIndex[0];
        break;
    case "cluster+expr+twoSplit":
        for(let i = 0; i < pointData_z.length; i=i+2){
            pointsIndex[i] = findIndexes(pointData_z[i], factorLevel[selectedGroupBy]);
            pointsIndex[i+1] = pointsIndex[i];
        }
        break;
    case "cluster+multiSplit":
        pointsIndex = pointData_z.map(e => findIndexes(e, factorLevel[selectedGroupBy]));
    }
    return pointsIndex;
};

Shiny.addCustomMessageHandler('transfer_reduction', (msg) => {
    reductionData = msg;
    console.log("reductionData", reductionData);
});

Shiny.addCustomMessageHandler('transfer_meta', (msg) => {
    metaData = msg;
    console.log("metaData", metaData);
});

Shiny.addCustomMessageHandler('transfer_expression', (msg) => {
    expressionData = msg;
    console.log("expressionData", expressionData);
    console.log("exprMax", d3.max(expressionData));
    console.log("exprMin", d3.min(expressionData));
});


const splitArrByMeta = (Arr, meta) => {
    // split array (reduciton x,y etc.) by meta inforamtion
    // Arr should be reduction.x or reduction.y, which is a numeric array
    // Arr could also be "group_by" stringArray
    let splitOut = {};
    let splitMeta = {};
    if(Arr != null && Arr.length == meta.length){

        let meta_levels = [...new Set(meta)].sort(sortStringArray);
        // split meta to object
        // for loop is faster than forEach(), reduce()
        for(const element of meta_levels){
            let idx_arr = [];
            for(let i=0; i<meta.length; ++i){
                if(meta[i] === element){
                    idx_arr.push(i);
                }
            };
            splitMeta[element] = idx_arr;
        }
        // check Arr and meta has equal length

        for (const [key, value] of Object.entries(splitMeta)) {
            splitOut[key] = value.map(e => Arr[e]);
        };
    }
    return splitOut;
};


const prepare_XY_data = (reductionData, metaData, mode, nPanels, split_by) => {
    // pointData is array of panels' regl-scatterplot x,y input
    // this function process data into an object
    let point_XY_data = [];
    let split_x = null;
    let split_y = null;
    let reductionConverted = scaleDataXY(reductionData);
    switch(mode){
    case "clusterOnly":
        // only one panel
        if(nPanels == 1){
            point_XY_data[0] = {
                x: reductionConverted.X,
                y: reductionConverted.Y
            };
        }
        break;
    case "cluster+expr+noSplit":
        if(nPanels == 2){
            point_XY_data[0] = {
                x: reductionConverted.X,
                y: reductionConverted.Y
            };
            point_XY_data[1] = {
                x: reductionConverted.X,
                y: reductionConverted.Y
            };
        }
        break;
    case "cluster+expr+twoSplit":
        if(nPanels == 4){
            split_x = splitArrByMeta(reductionConverted.X, metaData[split_by]);
            split_y = splitArrByMeta(reductionConverted.Y, metaData[split_by]);
            for(let i = 0; i < Object.keys(split_x).length; i++){
                point_XY_data[i*2] = {
                    x: split_x[Object.keys(split_x)[i]],
                    y: split_y[Object.keys(split_y)[i]],
                };
                point_XY_data[i*2+1] = {
                    x: split_x[Object.keys(split_x)[i]],
                    y: split_y[Object.keys(split_y)[i]],
                };
            }
        }
        break;
    case "cluster+multiSplit":
        split_x = splitArrByMeta(reductionConverted.X, metaData[split_by]);
        split_y = splitArrByMeta(reductionConverted.Y, metaData[split_by]);
        for(let i = 0; i < Object.keys(split_x).length; i++){
            point_XY_data[i] = {
                x: split_x[Object.keys(split_x)[i]],
                y: split_y[Object.keys(split_y)[i]],
            };
        }
        break;
    case "cluster+expr+multiSplit":
        split_x = splitArrByMeta(reductionConverted.X, metaData[split_by]);
        split_y = splitArrByMeta(reductionConverted.Y, metaData[split_by]);
        for(let i = 0; i < Object.keys(split_x).length; i++){
            point_XY_data[i] = {
                x: split_x[Object.keys(split_x)[i]],
                y: split_y[Object.keys(split_y)[i]],
            };
        }
    }
    return point_XY_data;
};

const sortStringArray = (a, b) => {
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

const convert_stringArr_to_integer = (stringArray) => {
    let factorLevel = {};
    let uniqueArr = new Set(stringArray);
    let sortedUniqueArr = Array.from(uniqueArr).sort(sortStringArray);
    sortedUniqueArr.forEach((e,i) => {
        factorLevel[e] = i;
    });
    let integerArray = stringArray.map(e => factorLevel[e]);
    return integerArray;
};

const rgbToHex = (rgbString) => {
  // Convert rgb color string to hex format
  // Split the RGB string into individual values
  var rgbArray = rgbString.substring(4, rgbString.length-1).split(',').map(function(num) {
    return parseInt(num);
  });

  // Convert the individual RGB values to hex
  var hex = '#' + rgbArray.map(function(num) {
    var hexValue = num.toString(16);
    return hexValue.length === 1 ? '0' + hexValue : hexValue;
  }).join('');

  return hex;
};

const prepare_Z_data = ({
    metaData, expressionData,
    mode, nPanels, group_by, split_by,
    catColors,
    selectedFeature,
    moduleScore,
    exprColorScale = d3.interpolate("#D3D3D3", "#6450B5") // lightgrey, iris
} = {}) => {
    // This function prepare Z data and associated data: labels, pointColors etc.
    let zData = {
        point_Z_data: [],
        colorData: [],
        labelData: [],
        zType: [],
        cells: [],
        panelTitles: []
    };
    let split_z = null;
    let split_category = null;
    let split_expr = null;
    let split_cells = null;
    let exprTag = null;
    let catTag = "Cat:";
    let exprTitle = null;

    if(moduleScore){
        exprTag = "ModuleScore:";
        exprTitle = "ModuleScore";
    }else{
        exprTag = "Expr:";
        exprTitle = selectedFeature;
    };
    // d3.interpolate will generate rgb value by default
    let exprColorMap = Array(51).fill().map((e,i) => i/50).map(e => rgbToHex(exprColorScale(e)));
    //console.log("exprColorMap", exprColorMap);
    switch(mode){
    case "clusterOnly":
        if(nPanels == 1){
            // convert metaData array to integer array
            zData["point_Z_data"][0] = convert_stringArr_to_integer(metaData[group_by]);
            zData["labelData"][0] = metaData[group_by].map(e => catTag.concat(e));
            zData["panelTitles"][0] = group_by;
            zData["colorData"][0] = catColors;
            zData["zType"][0] = "category";
            zData["cells"][0] = metaData["cells"];
        }
        break;
    case "cluster+expr+noSplit":
        if(nPanels == 2){
            zData["point_Z_data"][0] = convert_stringArr_to_integer(metaData[group_by]);
            zData["point_Z_data"][1] = scaleDataZ(expressionData); // expr panel
            zData["labelData"][0] = metaData[group_by].map(e => catTag.concat(e));
            zData["labelData"][1] = expressionData.map(e => exprTag.concat(d3.format(".3f")(e)));
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
        if(nPanels == 4){
            split_z = splitArrByMeta(convert_stringArr_to_integer(metaData[group_by]), metaData[split_by]);
            split_category = splitArrByMeta(metaData[group_by], metaData[split_by]);
            split_cells = splitArrByMeta(metaData["cells"], metaData[split_by]);
            split_expr = splitArrByMeta(expressionData, metaData[split_by]);
            for(let i = 0; i < Object.keys(split_z).length; i++){
                zData["point_Z_data"][i*2] = split_z[Object.keys(split_z)[i]];
                zData["labelData"][i*2] = split_category[Object.keys(split_category)[i]].map(e => catTag.concat(e));
                zData["panelTitles"][i*2] = Object.keys(split_category)[i] + " : " + group_by;
                zData["point_Z_data"][i*2+1] = scaleDataZ(split_expr[Object.keys(split_expr)[i]]); // expr panel
                zData["labelData"][i*2+1] = split_expr[Object.keys(split_expr)[i]].map(e => exprTag.concat(d3.format(".3f")(e)));
                zData["panelTitles"][i*2+1] = Object.keys(split_category)[i] + " : " + exprTitle;
                zData["colorData"][i*2] = catColors;
                zData["colorData"][i*2+1] = exprColorMap;
                zData["zType"][i*2] = "category";
                zData["zType"][i*2+1] = "expr";
                zData["cells"][i*2] = split_cells[Object.keys(split_cells)[i]];
                zData["cells"][i*2+1] = zData["cells"][i*2];
            }
        }
        break;
    case "cluster+multiSplit":
        split_z = splitArrByMeta(convert_stringArr_to_integer(metaData[group_by]), metaData[split_by]);
        split_category = splitArrByMeta(metaData[group_by], metaData[split_by]);
        split_cells = splitArrByMeta(metaData["cells"], metaData[split_by]);
        console.log(split_category);
        for(let i = 0; i < Object.keys(split_z).length; i++){
            zData["point_Z_data"][i] = split_z[Object.keys(split_z)[i]];
            zData["labelData"][i] = split_category[Object.keys(split_category)[i]].map(e => catTag.concat(e));
            zData["panelTitles"][i] = Object.keys(split_category)[i];
            zData["colorData"][i] = catColors;
            zData["zType"][i] = "category";
            zData["cells"][i] = split_cells[Object.keys(split_cells)[i]];
        }
        break;
    case "cluster+expr+multiSplit":
        split_expr = splitArrByMeta(expressionData, metaData[split_by]);
        split_cells = splitArrByMeta(metaData["cells"], metaData[split_by]);
        for(let i = 0; i < Object.keys(split_expr).length; i++){
            zData["point_Z_data"][i] = scaleDataZ(split_expr[Object.keys(split_expr)[i]]); // expr panels
            zData["labelData"][i] = split_expr[Object.keys(split_expr)[i]].map(e => exprTag.concat(d3.format(".3f")(e)));
            zData["panelTitles"][i] = Object.keys(split_expr)[i];
            zData["colorData"][i] = exprColorMap;
            zData["zType"][i] = "expr";
            zData["cells"][i] = split_cells[Object.keys(split_cells)[i]];
        }
    }
    return zData;
};

const prepare_plotData = (reductionData, metaData, expressionData,
                          mode, nPanels, group_by, split_by,
                          catColors,
                          selectedFeature,
                          moduleScore) => {
    let plotData = {
        pointsData: [],
        colorData: [],
        labelData: [],
        zType: [],
        cells: [],
        panelTitles: []
    };
    let point_XY_data = prepare_XY_data(reductionData, metaData, mode, nPanels, split_by);
    let zData = prepare_Z_data({
        metaData, expressionData,
        mode, nPanels, group_by, split_by,
        catColors,
        selectedFeature,
        moduleScore
    });
    // create plotData
    for( let i=0; i<nPanels; i++){
        plotData["pointsData"][i] = {
            x: point_XY_data[i].x,
            y: point_XY_data[i].y,
            z: zData["point_Z_data"][i]
        };
    };
    plotData["labelData"] = zData["labelData"];
    plotData["panelTitles"] = zData["panelTitles"];
    plotData["colorData"] = zData["colorData"];
    plotData["zType"] = zData["zType"];
    plotData["cells"] = zData["cells"];
    return plotData;
};

const addScatterLegend = (pointData_z, mode, metaData, group_by, catColors, moduleScore) => {

    const accordions = document.querySelectorAll(".accordion-item");
    const category_accordion = [...accordions].filter((e) => {
        if(e.dataset.value == "analysis_category"){
            return e;
        }
    });
    const category_accordion_body = category_accordion[0].querySelector(".accordion-body");
    // firstly remove old ones if exists
    let oldCatLegend = category_accordion_body.querySelectorAll(".scatter-legend");
    if(oldCatLegend.length > 0){
        oldCatLegend.forEach((e) => e.remove());
    }
    let oldExprLegend = category_accordion_body.querySelectorAll("svg");
    if(oldExprLegend.length > 0){
        oldExprLegend.forEach(e => e.remove());
    }
    // Add cluster legends, no legend for "cluster+expr+multiSplit" mode
    if(mode != "cluster+expr+multiSplit"){

        let catTitles = [...new Set(metaData[group_by])].sort(sortStringArray);
        let catNumbers = catTitles.map((e,i) => {
            let counts = 0;
            metaData[group_by].forEach(d => {
                if(d == e){
                    counts++;
                }
            });
            return counts;
        });
        catColors.forEach((e,i) => {
            let legendEl = createLegendEl(catTitles[i], e, catNumbers[i]);

            // Add hover events
            // note do not use mouseover and mouseout event
            legendEl.onmouseenter = (event) => {
                legendHover = 1;
                event.target.style.borderColor = "black";
                event.target.style.borderWidth = "2px";
                //console.log("enter event triggered");
                let pointsIndex = highlight_index(mode, pointData_z, catTitles[i], metaData, group_by);
                mainClusterPlot_scatterplots.forEach((sp, index) => {
                    sp.select(pointsIndex[index]);
                });
            };
            legendEl.onmouseleave = (event) => {
                legendHover = 0;
                event.target.style.borderColor = "#D3D3D3";
                event.target.style.borderWidth = "1px";
                //console.log("leave event triggered");
                // deselect all points
                mainClusterPlot_scatterplots.forEach((sp, index) => {
                    sp.deselect();
                });
            };
            category_accordion_body.appendChild(legendEl);
        });
    }

    // Add expression legend element
    if(mode === "cluster+expr+noSplit" || mode === "cluster+expr+twoSplit" || mode === "cluster+expr+multiSplit"){
        const exprLegendColor = d3.scaleSequential([d3.min(expressionData), d3.max(expressionData)], d3.interpolate("#D3D3D3", "#6450B5"));
        const exprLegendTitle = moduleScore ? "ModuleScore" : "Expresson";
        const exprLegend = Legend(exprLegendColor, {title: exprLegendTitle, width: 200});
        category_accordion_body.appendChild(exprLegend);
    };
};

// Copyright 2021, Observable Inc.
// Released under the ISC license.
// https://observablehq.com/@d3/color-legend
function Legend(color, {
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
  tickValues
} = {}) {

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

  const svg = d3.create("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", [0, 0, width, height])
      .style("overflow", "visible")
      .style("display", "block");

  let tickAdjust = g => g.selectAll(".tick line").attr("y1", marginTop + marginBottom - height);
  let x;

  // Continuous
  if (color.interpolate) {
    const n = Math.min(color.domain().length, color.range().length);

    x = color.copy().rangeRound(d3.quantize(d3.interpolate(marginLeft, width - marginRight), n));

    svg.append("image")
        .attr("x", marginLeft)
        .attr("y", marginTop)
        .attr("width", width - marginLeft - marginRight)
        .attr("height", height - marginTop - marginBottom)
        .attr("preserveAspectRatio", "none")
        .attr("xlink:href", ramp(color.copy().domain(d3.quantize(d3.interpolate(0, 1), n))).toDataURL());
  }

  // Sequential
  else if (color.interpolator) {
    x = Object.assign(color.copy()
        .interpolator(d3.interpolateRound(marginLeft, width - marginRight)),
        {range() { return [marginLeft, width - marginRight]; }});

    svg.append("image")
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
        tickValues = d3.range(n).map(i => d3.quantile(color.domain(), i / (n - 1)));
      }
      if (typeof tickFormat !== "function") {
        tickFormat = d3.format(tickFormat === undefined ? ",f" : tickFormat);
      }
    }
  }

  // Threshold
  else if (color.invertExtent) {
    const thresholds
        = color.thresholds ? color.thresholds() // scaleQuantize
        : color.quantiles ? color.quantiles() // scaleQuantile
        : color.domain(); // scaleThreshold

    const thresholdFormat
        = tickFormat === undefined ? d => d
        : typeof tickFormat === "string" ? d3.format(tickFormat)
        : tickFormat;

    x = d3.scaleLinear()
        .domain([-1, color.range().length - 1])
        .rangeRound([marginLeft, width - marginRight]);

    svg.append("g")
      .selectAll("rect")
      .data(color.range())
      .join("rect")
        .attr("x", (d, i) => x(i - 1))
        .attr("y", marginTop)
        .attr("width", (d, i) => x(i) - x(i - 1))
        .attr("height", height - marginTop - marginBottom)
        .attr("fill", d => d);

    tickValues = d3.range(thresholds.length);
    tickFormat = i => thresholdFormat(thresholds[i], i);
  }

  // Ordinal
  else {
    x = d3.scaleBand()
        .domain(color.domain())
        .rangeRound([marginLeft, width - marginRight]);

    svg.append("g")
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

  svg.append("g")
      .attr("transform", `translate(0,${height - marginBottom})`)
      .call(d3.axisBottom(x)
        .ticks(ticks, typeof tickFormat === "string" ? tickFormat : undefined)
        .tickFormat(typeof tickFormat === "function" ? tickFormat : undefined)
        .tickSize(tickSize)
        .tickValues(tickValues))
      .call(tickAdjust)
      .call(g => g.select(".domain").remove())
      .call(g => g.append("text")
        .attr("x", marginLeft)
        .attr("y", marginTop + marginBottom - height - 6)
        .attr("fill", "currentColor")
        .attr("text-anchor", "start")
        .attr("font-weight", "bold")
        .attr("class", "title")
        .text(title));

  return svg.node();
}


Shiny.addCustomMessageHandler('reglScatter_plot', (msg) => {

    // Add spinners for the plot
    // waiter is from R waiter package
    //myWaiter.show(waiterSpinner);

    // Transfer plotting meta data and init scatterplot
    console.log("plotMetaData", msg);
    let mode = msg.mode;
    let nPanels = msg.nPanels;
    let group_by = msg.group_by;
    let split_by = msg.split_by;
    let moduleScore = msg.moduleScore;
    let catColors = msg.catColors;
    let selectedFeature = msg.selectedFeature;
    // create plotData
    let plotData = prepare_plotData(reductionData, metaData, expressionData,
                                    mode, nPanels, group_by, split_by,
                                    catColors,
                                    selectedFeature,
                                    moduleScore);
    console.log("plotData", plotData);

    // create plot panel
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
    // info widget on the bottom left corner
    createInfoWidget("parent-wrapper");

    mainClusterPlot_scatterplots.forEach((sp, i) => {
        console.log(i);
        populate_instance(
            sp,
            plotData["pointsData"][i],
            plotData["colorData"][i],
            plotData["labelData"][i],
            plotData["cells"][i],
            plotData["zType"][i]
        );
    });

    // Populate panel titles
    document.querySelectorAll(".mainClusterPlotTitle")
        .forEach((e,i) => { e.innerHTML = plotData.panelTitles[i]; });

    // Add legend elements
    addScatterLegend(plotData["pointsData"].map(e => e.z), mode, metaData, group_by, catColors, moduleScore);

    // hide spinner
    //waiter.hide('mainClusterPlot-clusterPlot');
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

Shiny.addCustomMessageHandler('reglScatter_deselect', (msg) => {
    console.log("Deselect points...");
    mainClusterPlot_scatterplots.forEach((sp, i) => {
        sp.deselect();
    });
});