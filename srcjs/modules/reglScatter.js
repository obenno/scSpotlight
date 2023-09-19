import createScatterplot from 'regl-scatterplot';

export function createReglScatterInstance(elID) {

    let widgetDev = document.querySelector('#' + elID);
    console.log(widgetDev);
    let canvas = document.createElement('canvas');
    //let { width, height } = widgetDev.getBoundingClientRect();
    //let width = "100%";
    //let height = 400;
    // Add canvas to widget container
    widgetDev.appendChild(canvas);
    //console.log("width: " + width);
    //console.log("height: "+ height);
    //define reglScatter options
    let scatterplot = createScatterplot({
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
}
