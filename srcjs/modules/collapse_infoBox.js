export const resize_infoBox = (targetHeight) => {
    // This function is to set the height of infoBox

    // get main plotting area height
    const mainEl = document.getElementById("infoBox").parentElement;
    const mainEl_height = parseFloat(mainEl.getBoundingClientRect().height);
    const marginTop = parseFloat(mainEl.style.marginTop || window.getComputedStyle(mainEl).marginTop);
    const marginBottom = parseFloat(mainEl.style.marginBottom || window.getComputedStyle(mainEl).marginBottom);
    const paddingTop = parseFloat(mainEl.style.paddingTop || window.getComputedStyle(mainEl).paddingTop);
    const paddingBottom = parseFloat(mainEl.style.paddingBottom || window.getComputedStyle(mainEl).paddingBottom);
    const plotting_height = mainEl_height - marginTop - marginBottom - paddingTop -paddingBottom;

    const mainClusterPlotEl = document.getElementById("mainClusterPlot-mainClusterPlot");
    const tabEl = document.getElementById("infoBox");

    //const mainClusterPlotEl_height = parseFloat(mainClusterPlotEl.style.height);
    //const tabEl_height = parseFloat(tabEl.style.height);
    //collapse infoBox, targetHeight = 56;
    //collapse infoBox, targetHeight = 250;
    tabEl.style.height = (targetHeight/plotting_height*1000).toString() + "px";
    mainClusterPlotEl.style.height = ((1-targetHeight/plotting_height)*1000).toString() + "px";
};

export const update_collapse_icon = () => {
    const collapsing_svg = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-arrows-collapse" viewBox="0 0 16 16">
  <path fill-rule="evenodd" d="M1 8a.5.5 0 0 1 .5-.5h13a.5.5 0 0 1 0 1h-13A.5.5 0 0 1 1 8Zm7-8a.5.5 0 0 1 .5.5v3.793l1.146-1.147a.5.5 0 0 1 .708.708l-2 2a.5.5 0 0 1-.708 0l-2-2a.5.5 0 1 1 .708-.708L7.5 4.293V.5A.5.5 0 0 1 8 0Zm-.5 11.707-1.146 1.147a.5.5 0 0 1-.708-.708l2-2a.5.5 0 0 1 .708 0l2 2a.5.5 0 0 1-.708.708L8.5 11.707V15.5a.5.5 0 0 1-1 0v-3.793Z"/>
</svg>`;
    const expanding_svg = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-arrows-angle-expand" viewBox="0 0 16 16">
  <path fill-rule="evenodd" d="M5.828 10.172a.5.5 0 0 0-.707 0l-4.096 4.096V11.5a.5.5 0 0 0-1 0v3.975a.5.5 0 0 0 .5.5H4.5a.5.5 0 0 0 0-1H1.732l4.096-4.096a.5.5 0 0 0 0-.707zm4.344-4.344a.5.5 0 0 0 .707 0l4.096-4.096V4.5a.5.5 0 1 0 1 0V.525a.5.5 0 0 0-.5-.5H11.5a.5.5 0 0 0 0 1h2.768l-4.096 4.096a.5.5 0 0 0 0 .707z"/>
</svg>`;
    let icon = document.getElementById("infoBox_show");
    if(icon.querySelector("svg").classList.contains('bi-arrows-angle-expand')){
        icon.querySelector("svg").remove();
        icon.innerHTML = collapsing_svg;
    }else if(icon.querySelector("svg").classList.contains('bi-arrows-collapse')){
        icon.querySelector("svg").remove();
        icon.innerHTML = expanding_svg;
    }
};