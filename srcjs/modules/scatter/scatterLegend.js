export function createLegendEntryElement(title, color, number) {
  let safeTitle = title;
  if (typeof safeTitle === "number") {
    safeTitle = safeTitle.toString();
  }

  const scatterLegend = document.createElement("div");
  scatterLegend.classList.add("scatter-legend");
  scatterLegend.id = "legend_" + safeTitle.replace(/[^a-zA-Z0-9-_]/g, "_");

  const colorBlock = document.createElement("div");
  colorBlock.classList.add("scatter-legend-icon");
  colorBlock.style.backgroundColor = color;

  const labelEl = document.createElement("span");
  labelEl.classList.add("legend-label");
  labelEl.title = safeTitle;
  labelEl.innerHTML = safeTitle;

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
}

export function findIndexes(arr, value) {
  const indexes = [];
  for (let i = 0; i < arr.length; i++) {
    if (arr[i] === value) {
      indexes.push(i);
    }
  }
  return indexes;
}

export function computeHighlightIndices({
  mode,
  pointsData,
  groupByValues,
  selectedGroupBy,
  sortStringArray,
}) {
  const pointsIndex = [];

  const factorLevel = {};
  const sortedUniqueArr = [...new Set(groupByValues)].sort(sortStringArray);
  sortedUniqueArr.forEach((e, i) => {
    factorLevel[e] = i;
  });
  const selectedLevel = factorLevel[selectedGroupBy];

  switch (mode) {
    case "clusterOnly":
      pointsIndex[0] = findIndexes(pointsData[0].z, selectedLevel);
      break;
    case "cluster+expr+noSplit":
      pointsIndex[0] = findIndexes(pointsData[0].z, selectedLevel);
      pointsIndex[1] = pointsIndex[0];
      break;
    case "cluster+expr+twoSplit":
      for (let i = 0; i < pointsData.length; i += 2) {
        pointsIndex[i] = findIndexes(pointsData[i].z, selectedLevel);
        pointsIndex[i + 1] = pointsIndex[i];
      }
      break;
    case "cluster+multiSplit":
      return pointsData.map((e) => findIndexes(e.z, selectedLevel));
    default:
      return pointsIndex;
  }
  return pointsIndex;
}
