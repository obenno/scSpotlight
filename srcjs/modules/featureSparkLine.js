import * as d3 from "d3";
import 'jquery-sparkline';

export const createSparkLine = (feature) => {
  const containerEl = document.createElement("span");
  containerEl.classList.add("featureSparkLine");
  containerEl.classList.add("d-flex");
  containerEl.classList.add("align-items-center");
  containerEl.classList.add("mt-1");
  containerEl.classList.add("mb-1");
  containerEl.style.justifyContent = "space-around";
  containerEl.setAttribute("data-status", "initial");


  const geneSymbol = document.createElement("span");
  geneSymbol.classList.add("d-flex");
  geneSymbol.classList.add("align-items-center");
  geneSymbol.style.flexShirk = 0;
  geneSymbol.innerHTML = feature;
  containerEl.appendChild(geneSymbol);

  const sparkLineEl = document.createElement("span");
  sparkLineEl.classList.add("sparkLine");
  sparkLineEl.style.flexGrow = 1;
  sparkLineEl.style.marginLeft = "5px";
  sparkLineEl.style.marginRight = "5px";

  const progressBarOutter = document.createElement("span");
  progressBarOutter.classList.add("progress");
  progressBarOutter.role = "progressbar";
  //sparkLineEl.setAttribute('aria-valuenow', '50');
  //sparkLineEl.setAttribute('aria-valuemin', '0');
  //sparkLineEl.setAttribute('aria-valuemax', '100');

  const progressBarInner = document.createElement("span");
  progressBarInner.classList.add("progress-bar");
  progressBarInner.classList.add("progress-bar-striped");
  progressBarInner.classList.add("progress-bar-animated");
  progressBarInner.style.width = "100%";

  progressBarOutter.appendChild(progressBarInner);
  sparkLineEl.appendChild(progressBarOutter);

  containerEl.appendChild(sparkLineEl);

  const iconDiv = document.createElement("span");
  iconDiv.classList.add("icon-container");
  iconDiv.classList.add("d-flex");
  iconDiv.classList.add("align-items-center");
  iconDiv.style.justifyContent = "space-around";
  iconDiv.style.margeLeft = "2px";
  iconDiv.style.flexShirk = 0;
  const spinner = document.createElement("span");
  spinner.classList.add("spinner-border");
  spinner.classList.add("text-primary");
  spinner.role = "status";
  spinner.style.width = "1rem";
  spinner.style.height = "1rem";
  const spinnerText = document.createElement("span");
  spinnerText.classList.add("visually-hidden");
  spinnerText.innerHTML = "Loading...";
  spinner.appendChild(spinnerText);
  //const squareIcon = document.createElement("i");
  //squareIcon.classList.add("bi-square");
  //squareIcon.style.fontSize = "1rem";
  iconDiv.appendChild(spinner);

  containerEl.appendChild(iconDiv);

  return containerEl;
};

export const updateSparkLine = (containerEl, reglElementData) => {
  // generate square icon svg
  const square = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-square" viewBox="0 0 16 16">
  <path d="M14 1a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V2a1 1 0 0 1 1-1zM2 0a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V2a2 2 0 0 0-2-2z"/>
</svg>`;
  const check2square = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-check2-square" viewBox="0 0 16 16">
  <path d="M3 14.5A1.5 1.5 0 0 1 1.5 13V3A1.5 1.5 0 0 1 3 1.5h8a.5.5 0 0 1 0 1H3a.5.5 0 0 0-.5.5v10a.5.5 0 0 0 .5.5h10a.5.5 0 0 0 .5-.5V8a.5.5 0 0 1 1 0v5a1.5 1.5 0 0 1-1.5 1.5z"/>
  <path d="m8.354 10.354 7-7a.5.5 0 0 0-.708-.708L8 9.293 5.354 6.646a.5.5 0 1 0-.708.708l3 3a.5.5 0 0 0 .708 0"/>
</svg>`;

  containerEl.setAttribute("data-status", "ready");
  // remove spinner
  const iconDiv = containerEl.querySelector(".icon-container");
  iconDiv.querySelector("span").remove();

  // add square
  iconDiv.innerHTML = "";
  iconDiv.innerHTML = square;

  // update sparkline
  const sparkLineEl = containerEl.querySelector(".sparkLine")
  // firstly remove progress bar
  sparkLineEl.querySelector("span").remove();
  const sparkLineSpan = document.createElement("span");
  sparkLineSpan.id = randomId();
  sparkLineSpan.innerHTML = "Loading...";
  sparkLineEl.appendChild(sparkLineSpan);
  const feature = containerEl.querySelector("span").innerHTML;
  const expressionData = reglElementData.origData.expressionData[feature];
  const binExprCount = binArrCount(expressionData, 20);
  // generate sparkline
  $("#" + sparkLineSpan.id)
    .sparkline(binExprCount,
               {
                 type: "bar",
                 barColor: "#A9A9A9",
                 disableTooltips: true,
                 disableHighlight: true
               });
  sparkLineSpan.querySelector("canvas").style.width="100%";

  containerEl.addEventListener('click', function() {
    let currentStatus = this.getAttribute('data-status');
    // Update the status based on current value
    let newStatus;
    const feature = this.querySelector("span").innerHTML;
    switch(currentStatus) {
      case 'ready':
        newStatus = 'checked';
        reglElementData.plotMetaData.selectedFeature.push(feature);
        iconDiv.innerHTML = "";
        iconDiv.innerHTML = check2square;
        //console.log("selectedFeature: ", reglElementData.plotMetaData.selectedFeature);
        break;
      case 'checked':
        newStatus = 'ready';
        let index = reglElementData.plotMetaData.selectedFeature.indexOf(feature);
        if (index !== -1) {
          reglElementData.plotMetaData.selectedFeature.splice(index, 1);
        }
        iconDiv.innerHTML = "";
        iconDiv.innerHTML = square;
        //console.log("selectedFeature: ", reglElementData.plotMetaData.selectedFeature);
        break;
      default:
        newStatus = 'initial';
    }

    // Set the new status
    this.setAttribute('data-status', newStatus);
  });
};

const binArrCount = (arr, nBin) => {
  // https://observablehq.com/@d3/d3-bin
  const binData = d3.bin()
                    .thresholds((data, min, max) =>
                      d3.range(nBin).map(t => min + (t / nBin) * (max - min))
                    )
  // count element numbers in each chunk/bin
  return binData(arr).map(e => e.length);
}

const randomId = (length = 8) => {
  return Math.random().toString(36).substring(2, length + 2);
}
