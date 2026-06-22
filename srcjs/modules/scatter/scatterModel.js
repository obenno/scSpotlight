import * as d3 from "d3";

export class ScatterModel {
  constructor({ utils = {} } = {}) {
    this.utils = utils;
    this.resetAll();
  }

  resetAll() {
    this.origData = {
      reductionData: {},
      cellMetaData: {},
      expressionData: {},
      pcaStdev: null,
    };

    this.plotData = {
      pointsData: [],
      colorData: [],
      zType: [],
      cells: [],
      panelTitles: [],
      selectedCells: [],
      catLabelCoordinates: [],
      plotFeature: null,
    };

    this.plotMetaData = {
      mode: null,
      nPanels: null,
      group_by: null,
      split_by: null,
      catColors: [],
      selectedFeatures: [],
      moduleScore: false,
      labelSize: 14,
      selectedMeta: null,
    };
  }

  resetPlotState() {
    this.plotData = {
      pointsData: [],
      colorData: [],
      zType: [],
      cells: [],
      panelTitles: [],
      selectedCells: [],
      catLabelCoordinates: [],
      plotFeature: null,
    };

    this.plotMetaData.mode = null;
    this.plotMetaData.nPanels = null;
    this.plotMetaData.group_by = null;
    this.plotMetaData.split_by = null;
    this.plotMetaData.catColors = [];
  }

  validateCellMetaDataPatch(cellMetaDataPatch) {
    const expandMeta = this.utils.expandMeta;
    const existingMeta = this.origData.cellMetaData || {};
    const expectedLength = existingMeta.cells ? expandMeta(existingMeta.cells).length : null;

    Object.entries(cellMetaDataPatch).forEach(([key, value]) => {
      if (!value || value.type === undefined || value.value === undefined) {
        throw new Error(`Invalid metadata patch payload for column ${key}`);
      }

      if (expectedLength !== null) {
        const patchLength = expandMeta(value).length;
        if (patchLength !== expectedLength) {
          throw new Error(
            `Metadata patch length mismatch for ${key}: expected ${expectedLength}, got ${patchLength}`,
          );
        }
      }

      if (
        existingMeta[key] &&
        existingMeta[key].type !== undefined &&
        existingMeta[key].type !== value.type
      ) {
        throw new Error(
          `Metadata patch type mismatch for ${key}: expected ${existingMeta[key].type}, got ${value.type}`,
        );
      }
    });
  }

  setData({
    reductionData = null,
    cellMetaData = null,
    cellMetaDataPatch = null,
    expressionData = null,
    pcaStdev = undefined,
  } = {}) {
    if (reductionData) {
      Object.keys(reductionData).forEach((key) => {
        this.origData.reductionData[key] = reductionData[key];
      });
    }

    if (cellMetaData) {
      this.origData.cellMetaData = cellMetaData;
    }

    if (cellMetaDataPatch) {
      this.validateCellMetaDataPatch(cellMetaDataPatch);
      this.origData.cellMetaData = {
        ...this.origData.cellMetaData,
        ...cellMetaDataPatch,
      };
    }

    if (expressionData) {
      Object.keys(expressionData).forEach((key) => {
        this.origData.expressionData[key] = new Float32Array(expressionData[key]);
      });
    }

    if (pcaStdev !== undefined) {
      this.origData.pcaStdev = pcaStdev ? new Float32Array(pcaStdev) : null;
    }
  }

  setConfig(config = {}) {
    Object.keys(config).forEach((key) => {
      this.plotMetaData[key] = config[key];
    });
  }

  derivePlotMetaData(group_by = null, split_by = null, moduleScore = false) {
    const getMetaLevels = this.utils.getMetaLevels;
    const hue_pal = this.utils.hue_pal;

    const groupByArray = group_by
      ? getMetaLevels(this.origData.cellMetaData[group_by])
      : [];

    const splitByArray = split_by
      ? getMetaLevels(this.origData.cellMetaData[split_by])
      : [];

    const nGroupBy = groupByArray.length;
    const nSplitBy = splitByArray.length;
    const selectedFeatures = this.plotMetaData.selectedFeatures || [];
    const hasSelectedFeature = selectedFeatures.length > 0;

    let plottingMode = null;
    let nPanels = null;
    if (hasSelectedFeature && nSplitBy === 0) {
      plottingMode = "cluster+expr+noSplit";
      nPanels = 2;
    } else if (hasSelectedFeature && nSplitBy === 2) {
      plottingMode = "cluster+expr+twoSplit";
      nPanels = 4;
    } else if (hasSelectedFeature && nSplitBy > 2) {
      plottingMode = "cluster+expr+multiSplit";
      nPanels = nSplitBy;
    } else if (!hasSelectedFeature && nSplitBy > 1) {
      plottingMode = "cluster+multiSplit";
      nPanels = nSplitBy;
    } else {
      plottingMode = "clusterOnly";
      nPanels = 1;
    }

    const catColors = hue_pal(nGroupBy);
    this.plotMetaData = {
      ...this.plotMetaData,
      nPanels,
      mode: plottingMode,
      group_by,
      split_by,
      catColors,
      moduleScore,
    };
    return this.plotMetaData;
  }

  buildPlotData() {
    const metaData = this.origData.cellMetaData;
    const reductionData = this.origData.reductionData;
    const expressionAll = this.origData.expressionData;
    const {
      selectedFeatures,
      moduleScore,
      group_by,
      split_by,
      mode,
      nPanels,
      catColors,
    } = this.plotMetaData;

    const selectedFeature = selectedFeatures[0];
    const expressionData = selectedFeature ? expressionAll[selectedFeature] : [];

    const pointsData = this.prepareXYData(
      reductionData,
      metaData,
      mode,
      nPanels,
      split_by,
    );

    const zData = this.prepareZData(
      metaData,
      expressionData,
      mode,
      nPanels,
      group_by,
      split_by,
      catColors,
      selectedFeature,
      moduleScore,
    );

    for (let i = 0; i < pointsData.length; i++) {
      pointsData[i].z = zData.point_Z_data[i];
    }

    const catLabelCoordinates = [];
    const groupTitles = group_by ? this.utils.getMetaLevels(metaData[group_by]) : [];
    for (let i = 0; i < pointsData.length; i++) {
      if (zData.zType[i] === "category") {
        const panelData = pointsData[i];
        const panelLevels = zData.colorData[i].map((_, levelIdx) => levelIdx);
        const coords = [];
        panelLevels.forEach((level) => {
          const idx = [];
          panelData.z.forEach((v, ii) => {
            if (v === level) idx.push(ii);
          });
          if (idx.length > 0) {
            const xMean = idx.reduce((acc, ii) => acc + panelData.x[ii], 0) / idx.length;
            const yMean = idx.reduce((acc, ii) => acc + panelData.y[ii], 0) / idx.length;
            coords.push({
              x: xMean,
              y: yMean,
              label: groupTitles[level] ?? String(level),
            });
          }
        });
        catLabelCoordinates[i] = coords;
      }
    }

    this.plotData = {
      ...this.plotData,
      pointsData,
      colorData: zData.colorData,
      zType: zData.zType,
      cells: zData.cells,
      panelTitles: zData.panelTitles,
      catLabelCoordinates,
      plotFeature: selectedFeature,
    };

    return this.plotData;
  }

  prepareZData(
    metaData,
    expressionData,
    mode,
    nPanels,
    group_by,
    split_by,
    catColors,
    selectedFeature,
    moduleScore,
    exprColorScale = d3.interpolate("#E5E4E2", "#800080"),
  ) {
    const expandMeta = this.utils.expandMeta;
    const splitArrByMeta = this.utils.splitArrByMeta;
    const convert_stringArr_to_integer = this.utils.convert_stringArr_to_integer;
    const getMetaLevels = this.utils.getMetaLevels;
    const rgbToHex = this.utils.rgbToHex;

    const zData = {
      point_Z_data: [],
      colorData: [],
      zType: [],
      cells: [],
      panelTitles: [],
    };

    const exprTitle = moduleScore ? "ModuleScore" : selectedFeature;
    const exprColorMap = Array(51)
      .fill()
      .map((_, i) => i / 50)
      .map((e) => rgbToHex(exprColorScale(e)));

    switch (mode) {
      case "clusterOnly": {
        if (nPanels === 1) {
          const groupByArray = expandMeta(metaData[group_by]);
          zData.point_Z_data[0] = convert_stringArr_to_integer(groupByArray);
          zData.panelTitles[0] = group_by;
          zData.colorData[0] = catColors;
          zData.zType[0] = "category";
          zData.cells[0] = metaData.cells.value;
        }
        break;
      }
      case "cluster+expr+noSplit": {
        if (nPanels === 2) {
          const groupByArray = expandMeta(metaData[group_by]);
          const cellsArray = expandMeta(metaData.cells);
          zData.point_Z_data[0] = convert_stringArr_to_integer(groupByArray);
          zData.point_Z_data[1] = this.scaleDataZ(expressionData);
          zData.panelTitles[0] = group_by;
          zData.panelTitles[1] = exprTitle;
          zData.colorData[0] = catColors;
          zData.colorData[1] = exprColorMap;
          zData.zType[0] = "category";
          zData.zType[1] = "expr";
          zData.cells[0] = cellsArray;
          zData.cells[1] = cellsArray;
        }
        break;
      }
      case "cluster+expr+twoSplit": {
        if (nPanels === 4) {
          const groupByArray = expandMeta(metaData[group_by]);
          const splitByArray = expandMeta(metaData[split_by]);
          const splitZ = splitArrByMeta(
            convert_stringArr_to_integer(groupByArray),
            splitByArray,
          );
          const splitExpr = splitArrByMeta(expressionData, splitByArray);
          const splitCells = splitArrByMeta(expandMeta(metaData.cells), splitByArray);
          const splitKeys = Object.keys(splitZ);
          for (let i = 0; i < splitKeys.length; i++) {
            const key = splitKeys[i];
            zData.point_Z_data[i * 2] = splitZ[key];
            zData.point_Z_data[i * 2 + 1] = this.scaleDataZ(splitExpr[key]);
            zData.panelTitles[i * 2] = `${key} : ${group_by}`;
            zData.panelTitles[i * 2 + 1] = `${key} : ${exprTitle}`;
            zData.colorData[i * 2] = catColors;
            zData.colorData[i * 2 + 1] = exprColorMap;
            zData.zType[i * 2] = "category";
            zData.zType[i * 2 + 1] = "expr";
            zData.cells[i * 2] = splitCells[key];
            zData.cells[i * 2 + 1] = splitCells[key];
          }
        }
        break;
      }
      case "cluster+multiSplit": {
        const groupByArray = expandMeta(metaData[group_by]);
        const splitByArray = expandMeta(metaData[split_by]);
        const groupByInt = convert_stringArr_to_integer(groupByArray);
        const cellsArray = expandMeta(metaData.cells);
        const splitLevels = getMetaLevels(metaData[split_by]);

        for (let i = 0; i < splitLevels.length; i++) {
          const level = splitLevels[i];
          const indices = [];
          for (let j = 0; j < splitByArray.length; j++) {
            if (splitByArray[j] === level) indices.push(j);
          }
          const pointZ = new Int16Array(indices.length);
          const cellSplit = Array(indices.length);
          for (let j = 0; j < indices.length; j++) {
            pointZ[j] = groupByInt[indices[j]];
            cellSplit[j] = cellsArray[indices[j]];
          }
          zData.point_Z_data[i] = pointZ;
          zData.panelTitles[i] = level;
          zData.colorData[i] = catColors;
          zData.zType[i] = "category";
          zData.cells[i] = cellSplit;
        }
        break;
      }
      case "cluster+expr+multiSplit": {
        const splitByArray = expandMeta(metaData[split_by]);
        const cellsArray = expandMeta(metaData.cells);
        const splitLevels = getMetaLevels(metaData[split_by]);
        for (let i = 0; i < splitLevels.length; i++) {
          const level = splitLevels[i];
          const exprSplit = [];
          const cellSplit = [];
          for (let j = 0; j < splitByArray.length; j++) {
            if (splitByArray[j] === level) {
              exprSplit.push(expressionData[j]);
              cellSplit.push(cellsArray[j]);
            }
          }
          zData.point_Z_data[i] = this.scaleDataZ(exprSplit);
          zData.panelTitles[i] = level;
          zData.colorData[i] = exprColorMap;
          zData.zType[i] = "expr";
          zData.cells[i] = cellSplit;
        }
        break;
      }
    }
    return zData;
  }

  prepareXYData(reductionData, metaData, mode, nPanels, split_by) {
    const expandMeta = this.utils.expandMeta;
    const splitArrByMeta = this.utils.splitArrByMeta;
    const getMetaLevels = this.utils.getMetaLevels;

    const pointXY = [];
    const reductionConverted = this.scaleDataXY(reductionData);

    switch (mode) {
      case "clusterOnly": {
        if (nPanels === 1) {
          pointXY[0] = {
            x: new Float32Array(reductionConverted.X),
            y: new Float32Array(reductionConverted.Y),
          };
        }
        break;
      }
      case "cluster+expr+noSplit": {
        if (nPanels === 2) {
          pointXY[0] = {
            x: new Float32Array(reductionConverted.X),
            y: new Float32Array(reductionConverted.Y),
          };
          pointXY[1] = {
            x: new Float32Array(reductionConverted.X),
            y: new Float32Array(reductionConverted.Y),
          };
        }
        break;
      }
      case "cluster+expr+twoSplit": {
        if (nPanels === 4) {
          const splitByArray = expandMeta(metaData[split_by]);
          const splitX = splitArrByMeta(reductionConverted.X, splitByArray);
          const splitY = splitArrByMeta(reductionConverted.Y, splitByArray);
          const keys = Object.keys(splitX);
          for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            pointXY[i * 2] = {
              x: new Float32Array(splitX[key]),
              y: new Float32Array(splitY[key]),
            };
            pointXY[i * 2 + 1] = {
              x: new Float32Array(splitX[key]),
              y: new Float32Array(splitY[key]),
            };
          }
        }
        break;
      }
      case "cluster+multiSplit":
      case "cluster+expr+multiSplit": {
        const splitByArray = expandMeta(metaData[split_by]);
        const splitLevels = getMetaLevels(metaData[split_by]);
        for (let i = 0; i < splitLevels.length; i++) {
          const level = splitLevels[i];
          const xSplit = [];
          const ySplit = [];
          for (let j = 0; j < splitByArray.length; j++) {
            if (splitByArray[j] === level) {
              xSplit.push(reductionConverted.X[j]);
              ySplit.push(reductionConverted.Y[j]);
            }
          }
          pointXY[i] = { x: new Float32Array(xSplit), y: new Float32Array(ySplit) };
        }
        break;
      }
    }

    return pointXY;
  }

  scaleDataXY(dataXY) {
    const xColumn = dataXY.X;
    const yColumn = dataXY.Y;
    const xmin = d3.min(xColumn);
    const xmax = d3.max(xColumn);
    const ymin = d3.min(yColumn);
    const ymax = d3.max(yColumn);
    const centerX = (xmin + xmax) / 2;
    const centerY = (ymin + ymax) / 2;
    const range = Math.max(xmax - xmin, ymax - ymin, 1e-9);
    const precisionScale = 1e4;
    const compact = (v) => Math.fround(Math.round(v * precisionScale) / precisionScale);
    return {
      X: xColumn.map((x) => compact(((x - centerX) / range) * 2)),
      Y: yColumn.map((y) => compact(((y - centerY) / range) * 2)),
    };
  }

  scaleDataZ(arrayZ) {
    const isArrayLike =
      Array.isArray(arrayZ) ||
      (ArrayBuffer.isView(arrayZ) && !(arrayZ instanceof DataView));
    if (!isArrayLike || arrayZ.length === 0) {
      return new Float32Array(0);
    }
    const values = ArrayBuffer.isView(arrayZ) ? arrayZ : Float32Array.from(arrayZ);
    const minValue = d3.min(values);
    const maxValue = d3.max(values);
    if (!Number.isFinite(minValue) || !Number.isFinite(maxValue)) {
      return new Float32Array(values.length);
    }
    // If all values are equal (e.g., all zero), map to low end of color range.
    if (minValue === maxValue) {
      return new Float32Array(values.length);
    }

    // Keep zero-anchored scaling for non-negative expression values, but
    // preserve dynamic range for mixed-sign vectors (e.g., module scores).
    if (minValue < 0) {
      const zScale = d3.scaleLinear([minValue, maxValue], [0, 1]).nice();
      return Float32Array.from(values, (e) => zScale(e));
    }

    const zScale = d3.scaleLinear([0, maxValue], [0, 1]).nice();
    return Float32Array.from(values, (e) => zScale(e));
  }
}
