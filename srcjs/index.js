import 'shiny';
//import { createReglScatterInstance } from './modules/reglScatter.js';
import { resize_infoBox, update_collapse_icon } from './modules/collapse_infoBox.js';
import * as myWaiter from './modules/myWaiter.js';
export * as myWaiter from './modules/myWaiter.js';

import { reglScatterCanvas } from './modules/reglScatter.js';
import { initFeaturePlotWebR, featurePlot } from './modules/featurePlot.js';


// id of the mainClusterPlot parent div
const mainPlotElId = "mainClusterPlot-clusterPlot";
var featurePlotCanvas = null;

// legend hover event indicator
// to distinguish legend hover and manualy selecting events
var legendHover = 0;

// init webR instances
var shelterInstance = null;
try {
    initFeaturePlotWebR().then(result => {
        shelterInstance = result;
    });
} catch (error) {
    console.error("initFeaturePlotWebR failed: ", error.message);
    // Handle any errors
}

// code below will ensure the functions were invoked after all the shiny content loaded
// thus here init scatterplot instance
document.addEventListener('DOMContentLoaded', function () {

    // Get infoBoxId
    const infoBoxEl = document.getElementById("bottom_box").parentElement.parentElement;
    const mainPlotEl = document.getElementById(mainPlotElId);
    // init infoBox size to shrinked
    resize_infoBox(mainPlotEl, infoBoxEl, 56);
    infoBoxEl.querySelector(".bslib-full-screen-enter").style.display = "none";
    // Add event listener to infoBox collapsing icon
    const collapsing_icon = document.getElementById("infoBox_show");
    collapsing_icon.addEventListener("click", function() {
        update_collapse_icon(this.id);
        if(collapsing_icon.classList.contains("collapsed")){
            resize_infoBox(mainPlotEl, infoBoxEl, 56);
            // hide full screen button
            infoBoxEl.querySelector(".bslib-full-screen-enter").style.display = "none";
        }else{
            resize_infoBox(mainPlotEl, infoBoxEl, 250);
            // show full screen button
            infoBoxEl.querySelector(".bslib-full-screen-enter").style.display = "";
        }
    });

    // Adjust widget elements on scroll
    document.getElementById(mainPlotElId).addEventListener('scroll', () => {
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
    });

    // get featurePlot canvas
    featurePlotCanvas = document.getElementById("featurePlotCanvas");
    // Add featurePlot canvas resize observer
    // Create a ResizeObserver instance
    //const resizeObserver = new ResizeObserver(entries => {
    //    for (let entry of entries) {
    //        // This callback is triggered when the observed div is resized
    //        const { width, height } = entry.contentRect;
    //        console.log(`Div resized to ${width}x${height}`);
    //        console.log(featurePlotCanvas.style.display);
    //        if(featurePlotCanvas.style.display != "none"){
    //            updateFeaturePlot(featurePlotCanvas);
    //        }
    //    }
    //});
    // Start observing the div
    //resizeObserver.observe(featurePlotCanvas.parentElement);

}, false);

var reglElementData = new reglScatterCanvas("reglScatter");

// R waiter package spinners
// keep the style exactly the same with R function
var waiterSpinner = {
  id: "mainClusterPlot-clusterPlot",
  html: '<div class="loaderz-05" style = "color:var(--bs-primary);"></div>',
  color: '#ffffff',
  image: ''
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
    let el = document.getElementById("canvas-wrapper");
    if(el){
        el.remove();
    }
};


Shiny.addCustomMessageHandler('transfer_reduction', (msg) => {
    const reductionData = msg;
    reglElementData.updateReductionData(reductionData);
});

Shiny.addCustomMessageHandler('transfer_meta', (msg) => {
    const metaData = msg;
    reglElementData.updateCellMetaData(metaData);
});


// Function to decompress gzipped data
function decompressData(compressedData) {
  return new Promise((resolve, reject) => {
    const ds = new DecompressionStream('gzip');
    const decompressedStream = new Response(compressedData).body.pipeThrough(ds);
    new Response(decompressedStream).arrayBuffer().then(resolve).catch(reject);
  });
}

Shiny.addCustomMessageHandler('transfer_expression', (msg) => {
    //onst expressionData = decompressData(msg).then(decompressedBuffer => {
    //   new Uint8Array(decompressedBuffer);
    //);
    const expressionData = msg;
    console.log("expressionData: ", msg);
    if(expressionData){
        reglElementData.updateExpressionData(expressionData);
    }else{
        // purge exprssion data
        reglElementData.updateExpressionData({});
    }
});

Shiny.addCustomMessageHandler('reglScatter_plot', (msg) => {

    // Add spinners for the plot
    // waiter is from R waiter package
    //myWaiter.show(waiterSpinner);

    // ensure the featurePlot canvas is hidden
    featurePlotCanvas.style.display = "none";

    // Transfer plotting meta data and init scatterplot
    let mode = msg.mode;
    let nPanels = msg.nPanels;
    let group_by = msg.group_by;
    let split_by = msg.split_by;
    let moduleScore = msg.moduleScore;
    let catColors = msg.catColors;
    let selectedFeature = msg.selectedFeature;

    // ensure catColors is an array
    if(typeof catColors === "string"){
        catColors = [catColors];
    }

    // update reglScatterCanvas data
    reglElementData.clear();
    // have to invoke update method in order
    reglElementData.updatePlotMetaData({
        mode: mode,
        nPanels: nPanels,
        group_by: group_by,
        split_by: split_by,
        moduleScore: moduleScore,
        catColors: catColors,
        selectedFeature: selectedFeature
    });

    reglElementData.generatePlotEl();
    console.log("Generated plotEl");

    console.log("reglElementData :", reglElementData);

    // update legend elements
    const previous_canvas = document.getElementById(reglElementData.plotEl.id);
    if(previous_canvas){
        previous_canvas.remove();
    }
    document.getElementById(mainPlotElId).appendChild(reglElementData.plotEl);

    const accordions = document.querySelectorAll(".accordion-item");
    const category_accordion = [...accordions].filter((e) => {
        if(e.dataset.value == "analysis_category"){
            return e;
        }
    });
    const category_accordion_body = category_accordion[0].querySelector(".accordion-body");
    // firstly remove old ones if exists
    const previous_catLegend = category_accordion_body.querySelectorAll(".scatter-legend");
    if(previous_catLegend.length > 0){
        previous_catLegend.forEach((e) => e.remove());
    }
    category_accordion_body.appendChild(reglElementData.catLegendEl);

    const previous_expLegend = category_accordion_body.querySelectorAll("svg");
    if(previous_expLegend.length > 0){
        previous_expLegend.forEach(e => e.remove());
    }
    category_accordion_body.appendChild(reglElementData.expLegendEl);


    // return selected points to server side
    //reglElementData.scatterplots.forEach((sp, idx) => {
    //    sp.subscribe('select', ({ points: selectedPoints }) => {
    //
    //        const hoveredElements = Array.from(document.querySelectorAll(':hover'));
    //
    //        const filteredElements = hoveredElements.filter(e => {
    //            return e.classList.contains('scatter-legend');
    //        });
    //        // ensure the legend was not hovered
    //        if(filteredElements.length == 0){
    //            let selectedCells = selectedPoints.map(i => reglElementData.plotData.cells[idx][i]);
    //            Shiny.setInputValue("selectedPoints", selectedCells);
    //        }
    //    });
    //});
    //reglElementData.scatterplots.forEach((sp, idx) => {
    //    sp.subscribe('deselect', () => {
    //        Shiny.setInputValue("selectedPoints", null);
    //    });
    //});


    if(Object.keys(reglElementData.origData.expressionData).length > 1 &&
      !reglElementData.plotMetaData.moduleScore){

        console.log("Drawing featurePlot...");
        updateFeaturePlot(featurePlotCanvas);

    }


     // hide spinner
    //waiter.hide('mainClusterPlot-clusterPlot');

    //featurePlot().then({});

});

const updateFeaturePlot = (canvas) => {
    const container = canvas.parentElement;
    const rect = container.getBoundingClientRect();
    const containerPadding = getPadding(container);
    const canvasWidth = rect.width - containerPadding.left - containerPadding.right;
    const canvasHeight = rect.height - containerPadding.top - containerPadding.bottom;
    canvas.width = canvasWidth;
    canvas.height = canvasHeight;
    featurePlot(shelterInstance, canvasWidth, canvasHeight,
                reglElementData.origData.reductionData,
                reglElementData.origData.expressionData)
        .then(res => {
            const ctx = canvas.getContext("2d");
            ctx.clearRect(0, 0, canvasWidth, canvasHeight);
            let img = res.images[0];
            ctx.drawImage(img, 0, 0, canvasWidth, canvasHeight);
            canvas.style.display = "flex";
            // hidder reglscatter div
            reglElementData.plotEl.style.display = "none";
        });
    shelterInstance.purge();
};



//Shiny.addCustomMessageHandler('reglScatter_removeGrid', (msg) => {
//    clearMainPlotEl();
//});
//
//Shiny.addCustomMessageHandler('reglScatter_addGoBack', (msg) => {
//    // Go Back widget will only be added when receiving shiny signals
//    createGoBackWidget("reglScatter");
//    // Reset goBack value when creating goBackWidget
//    Shiny.setInputValue("goBack", null);
//});

Shiny.addCustomMessageHandler('reglScatter_deselect', (msg) => {
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
    left: parseInt(style.paddingLeft, 10)
  };
}
