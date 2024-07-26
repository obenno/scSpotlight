import createScatterplot, { createRenderer } from 'regl-scatterplot';
import * as d3 from "d3";

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
            cellMetaData:  {},
            expressionData: []
        }
        // init plotData
        this.plotData = {
            pointsData: [],
            colorData: [],
            labelData: [],
            zType: [],
            cells: [],
            panelTitles: []
        };
        // init plotMetaData
        this.plotMetaData = {
            mode: null,
            nPanels: null,
            group_by: null,
            split_by: null,
            catColors: [],
            selectedFeature: null,
            moduleScore: false
        };

        // Create a reusable renderer
        this.renderer = createRenderer();

    }

    updateReductionData(reductionData) {
        this.origData.reductionData = reductionData
    }

    updateCellMetaData(cellMetaData) {
        this.origData.cellMetaData = cellMetaData
    }

    updateExpressionData(expressionData) {
        this.origData.expressionData = expressionData
    }

    updatePlotMetaData(plotMetaData){
        this.plotMetaData = plotMetaData
    }


    clear() {
        // clear elements and plotData
        const plotElId = this.plotEl.id;
        this.plotEl = document.createElement("div");
        this.plotEl.id = plotElId;
        // by default, use 100% to fit into outside container
        this.plotEl.style.width = "100%";
        this.plotEl.style.height = "100%";

        const catLegendElId = this.catLegendEl.id;
        this.catLegendEl = document.createElement("div");
        this.catLegendEl.id = catLegendElId;
        this.catLegendEl.classList.add("html-fill-container");

        const expLegendElId = this.expLegendEl.id;
        this.expLegendEl = document.createElement("div");
        this.expLegendEl.id = expLegendElId;
        this.expLegendEl.classList.add("html-fill-container");

        // Note: origData will not to modified or removed, only clear plotData and plotMetaData
        this.plotData = {
            pointsData: [],
            colorData: [],
            labelData: [],
            zType: [],
            cells: [],
            panelTitles: []
        };
        // init plotMetaData
        this.plotMetaData = {
            mode: null,
            nPanels: null,
            group_by: null,
            split_by: null,
            catColors: [],
            selectedFeature: null,
            moduleScore: false
        };

        this.renderer.refresh();
    }

    updateCanvas() {
        // append canvas elements, wrapped by an outter element with id "canvas-wrapper"
        this.createCanvas("canvas-wrapper");
        // create and append note element with id: scatterPlotNote
        this.createNote("scatterPlotNote");
        // create info widget
        this.createInfoWidget("info");

        this.renderer.refresh();
        // Create scatter instances
        this.scatterplots = Array.from(this.plotEl.querySelectorAll(".scatter-canvas")).map((canvas) =>
            this.constructor.createReglScatterInstance(this.renderer, canvas)
        );

        this.scatterplots.forEach((sp, i) => {
            this.constructor.populate_instance(
                sp,
                this.plotData["pointsData"][i],
                this.plotData["colorData"][i],
                this.plotData["labelData"][i],
                this.plotData["cells"][i],
                this.plotData["zType"][i],
                "scatterPlotNote"
            );
        });

        this.showCatLabel();
    }

    updatePlotData() {
        let plotData = {
            pointsData: [],
            colorData: [],
            labelData: [],
            zType: [],
            cells: [],
            panelTitles: []
        };
        let point_XY_data = this.constructor.prepare_XY_data(
            this.origData.reductionData,
            this.origData.cellMetaData,
            this.plotMetaData.mode,
            this.plotMetaData.nPanels,
            this.plotMetaData.split_by
        );
        let zData = this.constructor.prepare_Z_data(
            this.origData.cellMetaData,
            this.origData.expressionData,
            this.plotMetaData.mode,
            this.plotMetaData.nPanels,
            this.plotMetaData.group_by,
            this.plotMetaData.split_by,
            this.plotMetaData.catColors,
            this.plotMetaData.selectedFeature,
            this.plotMetaData.moduleScore
        );
        // create plotData
        for( let i=0; i<this.plotMetaData.nPanels; i++){
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
        this.plotData = plotData;
    };

    // function to create grid view in the element (mainClusterPlot div)
    // here will always be div "parent-wrapper"
    createCanvas(canvasContainerID) {

        // create plot panel
        let nCols = null;

        if(this.plotMetaData.nPanels >= 2){
            nCols = 2;
        }else{
            nCols = 1;
        }
        let nRows = Math.ceil(this.plotMetaData.nPanels/nCols);

        // retrieve mainClusterPlot div
        let canvasContainer = document.createElement("div");
        canvasContainer.id = canvasContainerID;
        canvasContainer.style.display = 'grid';

        // use a min size 300px, in case too may panels
        canvasContainer.style.gridTemplateColumns = `repeat(${nCols}, minmax(300px, 1fr))`;
        canvasContainer.style.gridTemplateRows = `repeat(${nRows}, minmax(300px, 1fr))`;
        //el.style.gridTemplateColumns = `repeat(${ncols}, minmax(0px, 1fr))`;
        //el.style.gridTemplateRows = `repeat(${nrows}, minmax(0px, 1fr))`;
        canvasContainer.style.gap = '0.2rem';
        canvasContainer.style.width = "100%";
        canvasContainer.style.height = "100%";


        for (let i = 0; i < this.plotMetaData.nPanels; i++) {
            const canvas_wrapper = document.createElement("div");
            // add fill class
            canvas_wrapper.classList.add("html-fill-item");
            canvas_wrapper.classList.add("html-fill-container");
            canvas_wrapper.style.position = "relative";
            // add border style for multiple panels
            if(this.plotMetaData.nPanels > 1){
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
            labelCanvas.style.pointerEvents = 'none';
            //labelCanvas.style.zIndex = 0;
            canvas_wrapper.appendChild(labelCanvas);

            canvasContainer.appendChild(canvas_wrapper);
        }
        this.plotEl.appendChild(canvasContainer);
    };

    showCatLabel() {
        // generate category name
        let catTitles = [...new Set(this.origData.cellMetaData[this.plotMetaData.group_by])].sort(sortStringArray);
        // get category panel index
        let catPanel = this.plotData.zType.map((e,i) => {
            if(e === "category"){
                return i
            }
        })

        //console.log(catTitles);
        let labelcoordinates = [];
        for(let k = 0; k < this.plotData.pointsData.length; ++k){
            labelcoordinates[k] = [];
            catTitles.forEach((e,i) => {
                let x_data = [];
                let y_data = [];
                this.plotData.labelData[k].forEach((el, idx) => {
                    let label = el.replace("Cat:", "");
                    if(label == e){
                        x_data.push(this.plotData.pointsData[k].x[idx])
                        y_data.push(this.plotData.pointsData[k].y[idx])
                    }

                });

                labelcoordinates[k][i] = [d3.mean(x_data), d3.mean(y_data)];
            });

        }


        // Add label
        Array.from(this.plotEl.querySelectorAll(".label-canvas")).forEach((e,i) => {
            const ctx = e.getContext("2d");
            ctx.clearRect(0, 0, e.width, e.height);
            ctx.font = "30px Arial";
            ctx.fillText("Hello", 50, 50);
            for(let k = 0; k < catTitles.length; ++k){
                ctx.fillText(catTitles[k],labelcoordinates[i][0],labelcoordinates[i][1]);
            };
        });

    }

    removeCatLabel() {

    }

    static createReglScatterInstance(renderer, canvas) {

        // init reglScatter instance
        // share a renderer created before invoking this function
        let scatterplot = createScatterplot({
            renderer,
            canvas,
            //width,
            //height,
            lassoMinDelay: 10,
            lassoMinDist: 2,
            showReticle: true,
            reticleColor: [1, 1, 0.878431373, 0.33],
            pointSize: 3,
            opacity: 0.5,
            lassoOnLongPress: true,
            lassoInitiator: true,
        });

        return scatterplot;
    };

    static populate_instance (
        scatterplot,
        pointsData,
        pointColor,
        labelData,
        cells,
        zType,
        noteId
    ){
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
                reglScatterCanvas.showNote(
                    noteId,
                    labelData[pointId],
                    pointColor[pointsData.z[pointId]]
                );
            });
        }else{
            scatterplot.subscribe('pointOver', (pointId) => {
                reglScatterCanvas.showNote(
                    noteId,
                    labelData[pointId],
                    rgbToHex(exprColorScale(pointsData.z[pointId]))
                );
            });
        }

        scatterplot.subscribe('pointOut', () => { reglScatterCanvas.hideNote(noteId); });

        // select or other events could be subscribed after creating the instance
        scatterplot.draw(pointsData);
    };

    createNote(noteId) {
        let noteEl = document.createElement('div');
        noteEl.id = noteId;
        noteEl.classList.add("mainClusterPlotNote");
        noteEl.classList.add("shadow");
        this.plotEl.appendChild(noteEl);
    };

    // note manipulation to mimic tooltips
    static showNote(noteId, text, color) {
        let noteEl = document.getElementById(noteId);
        noteEl.style.display = null;
        noteEl.style.opacity = 0.8;
        noteEl.style.background = color;
        noteEl.textContent = text;
    };

    static hideNote(noteId) {
        let noteEl = document.getElementById(noteId);
        noteEl.style.display = "none";
    };

    createInfoWidget(infoId) {

        let infoEl = document.createElement("div");
        infoEl.id = infoId;
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
        this.plotEl.appendChild(infoEl);

    };

    static prepare_Z_data (
        metaData,
        expressionData,
        mode,
        nPanels,
        group_by,
        split_by,
        catColors,
        selectedFeature,
        moduleScore,
        exprColorScale = d3.interpolate("#D3D3D3", "#6450B5") // lightgrey, iris
    ) {
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
                    zData["point_Z_data"][1] = reglScatterCanvas.scaleDataZ(expressionData); // expr panel
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
                    zData["point_Z_data"][i] = reglScatterCanvas.scaleDataZ(split_expr[Object.keys(split_expr)[i]]); // expr panels
                    zData["labelData"][i] = split_expr[Object.keys(split_expr)[i]].map(e => exprTag.concat(d3.format(".3f")(e)));
                    zData["panelTitles"][i] = Object.keys(split_expr)[i];
                    zData["colorData"][i] = exprColorMap;
                    zData["zType"][i] = "expr";
                    zData["cells"][i] = split_cells[Object.keys(split_cells)[i]];
                }
        }
        return zData;
    };

    static prepare_XY_data(reductionData, metaData, mode, nPanels, split_by) {
        // pointData is array of panels' regl-scatterplot x,y input
        // this function process data into an object
        let point_XY_data = [];
        let split_x = null;
        let split_y = null;
        let reductionConverted = reglScatterCanvas.scaleDataXY(reductionData);
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
            Y: dataXY.Y.map(dScale)
        };

        return data;
    };

    static scaleDataZ(arrayZ) {
        // arrayZ is a numeric array (expressionData)
        // regl-scatterplot treats z values ranging between [0,1] as continuous data
        let minValue = d3.min(arrayZ);
        let maxValue = d3.max(arrayZ);
        let zScale = d3.scaleLinear([minValue, maxValue], [0, 1]).nice();
        let arrayZ_converted = arrayZ.map((e) => zScale(e));
        return arrayZ_converted;
    };

    updateCatLegend() {

        const pointData_z = this.plotData["pointsData"].map(e => e.z);

        // Add cluster legends, no legend for "cluster+expr+multiSplit" mode
        if(this.plotMetaData.mode != "cluster+expr+multiSplit"){

            let catTitles = [...new Set(this.origData.cellMetaData[this.plotMetaData.group_by])].sort(sortStringArray);
            let catNumbers = catTitles.map((e,i) => {
                let counts = 0;
                this.origData.cellMetaData[this.plotMetaData.group_by].forEach(d => {
                    if(d == e){
                        counts++;
                    }
                });
                return counts;
            });
            this.plotMetaData.catColors.forEach((e,i) => {
                let legendEl = this.constructor.createLegendEl(
                    catTitles[i], e, catNumbers[i]
                );

                // Add hover events
                // note do not use mouseover and mouseout event
                legendEl.onmouseenter = (event) => {
                    event.target.style.borderColor = "black";
                    event.target.style.borderWidth = "2px";
                    //console.log("enter event triggered");
                    let pointsIndex = this.constructor.highlight_index(
                        this.plotMetaData.mode,
                        pointData_z,
                        catTitles[i],
                        this.origData.cellMetaData,
                        this.plotMetaData.group_by
                    );

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

    };

    updateExpLegend(){
        // Add expression legend element
        if(this.plotMetaData.mode === "cluster+expr+noSplit" || this.plotMetaData.mode === "cluster+expr+twoSplit" || this.plotMetaData.mode === "cluster+expr+multiSplit"){
            const exprLegendColor = d3.scaleSequential([d3.min(this.origData.expressionData), d3.max(this.origData.expressionData)], d3.interpolate("#D3D3D3", "#6450B5"));
            const exprLegendTitle = this.plotMetaData.moduleScore ? "ModuleScore" : "Expresson";
            const exprLegend = Legend(exprLegendColor, {title: exprLegendTitle, width: 200});
            this.expLegendEl.appendChild(exprLegend);
        };
    };

    static createLegendEl(title, color, number) {

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

    static findIndexes(arr, value) {
        var indexes = [];
        for (var i = 0; i < arr.length; i++) {
            if (arr[i] === value) {
                indexes.push(i);
            }
        }
        return indexes;
    };

    static highlight_index(mode, pointData_z, selectedGroupBy, metaData, group_by) {
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
                pointsIndex[0] = reglScatterCanvas.findIndexes(pointData_z[0], factorLevel[selectedGroupBy]);
                break;
            case "cluster+expr+noSplit":
                pointsIndex[0] = reglScatterCanvas.findIndexes(pointData_z[0], factorLevel[selectedGroupBy]);
                pointsIndex[1] = pointsIndex[0];
                break;
            case "cluster+expr+twoSplit":
                for(let i = 0; i < pointData_z.length; i=i+2){
                    pointsIndex[i] = reglScatterCanvas.findIndexes(pointData_z[i], factorLevel[selectedGroupBy]);
                    pointsIndex[i+1] = pointsIndex[i];
                }
                break;
            case "cluster+multiSplit":
                pointsIndex = pointData_z.map(e => reglScatterCanvas.findIndexes(e, factorLevel[selectedGroupBy]));
        }
        return pointsIndex;
    };

};

export const splitArrByMeta = (Arr, meta) => {
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

export const convert_stringArr_to_integer = (stringArray) => {
    let factorLevel = {};
    let uniqueArr = new Set(stringArray);
    let sortedUniqueArr = Array.from(uniqueArr).sort(sortStringArray);
    sortedUniqueArr.forEach((e,i) => {
        factorLevel[e] = i;
    });
    let integerArray = stringArray.map(e => factorLevel[e]);
    return integerArray;
};

export const rgbToHex = (rgbString) => {
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
export function Legend(color, {
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
};
