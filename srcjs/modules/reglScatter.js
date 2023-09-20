import createScatterplot from 'regl-scatterplot';

export function createReglScatterInstance(renderer, canvas) {

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
}
