import 'shiny';
//import { createReglScatterInstance } from './modules/reglScatter.js';
import { resize_infoBox, update_collapse_icon } from './modules/collapse_infoBox.js';
import * as myWaiter from './modules/myWaiter.js';
export * as myWaiter from './modules/myWaiter.js';

import { reglScatterCanvas } from './modules/reglScatter.js'

// id of the mainClusterPlot parent div
var mainClusterPlotElID = "mainClusterPlot-clusterPlot";

// legend hover event indicator
// to distinguish legend hover and manualy selecting events
var legendHover = 0;

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

    // Adjust widget elements on scroll
    document.getElementById(mainClusterPlotElID).addEventListener('scroll', () => {
        const containerEl = document.getElementById(mainClusterPlotElID)

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

Shiny.addCustomMessageHandler('transfer_reduction', (msg) => {
    const reductionData = msg;
    reglElementData.updateReductionData(reductionData);
});

Shiny.addCustomMessageHandler('transfer_meta', (msg) => {
    const metaData = msg;
    reglElementData.updateCellMetaData(metaData);
});

Shiny.addCustomMessageHandler('transfer_expression', (msg) => {
    const expressionData = msg;
    reglElementData.updateExpressionData(expressionData);
});

Shiny.addCustomMessageHandler('reglScatter_plot', (msg) => {

    // Add spinners for the plot
    // waiter is from R waiter package
    //myWaiter.show(waiterSpinner);

    // Transfer plotting meta data and init scatterplot
    //console.log("plotMetaData", msg);
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
    reglElementData.updatePlotData();
    console.log(reglElementData.plotMetaData);
    console.log(reglElementData.plotData);
    reglElementData.updateCanvas();
    reglElementData.updateCatLegend();
    reglElementData.updateExpLegend();


    // update legend elements
    const previous_canvas = document.getElementById(reglElementData.plotEl.id);
    if(previous_canvas){
        previous_canvas.remove();
    }
    document.getElementById(mainClusterPlotElID).appendChild(reglElementData.plotEl);

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


    // subscribe select events
    //console.log(reglElementData.plotData);
    reglElementData.scatterplots.forEach((sp, idx) => {
        sp.subscribe('select', ({ points: selectedPoints }) => {

            const hoveredElements = Array.from(document.querySelectorAll(':hover'));

            const filteredElements = hoveredElements.filter(e => {
                return e.classList.contains('scatter-legend')
            });
            // ensure the legend was not hovered
            if(filteredElements.length == 0){
                let selectedCells = selectedPoints.map(i => reglElementData.plotData.cells[idx][i]);
                Shiny.setInputValue("selectedPoints", selectedCells);
            }
        });
    });
    reglElementData.scatterplots.forEach((sp, idx) => {
        sp.subscribe('deselect', () => {
            Shiny.setInputValue("selectedPoints", null);
        });
    });

     // hide spinner
    //waiter.hide('mainClusterPlot-clusterPlot');
});


Shiny.addCustomMessageHandler('reglScatter_removeGrid', (msg) => {
    clearMainPlotEl();
});

Shiny.addCustomMessageHandler('reglScatter_addGoBack', (msg) => {
    // Go Back widget will only be added when receiving shiny signals
    createGoBackWidget("reglScatter");
    // Reset goBack value when creating goBackWidget
    Shiny.setInputValue("goBack", null);
});

Shiny.addCustomMessageHandler('reglScatter_deselect', (msg) => {
    console.log("Deselect points...");
    reglElementData.scatterplots.forEach((sp, i) => {
        sp.deselect();
    });
});
