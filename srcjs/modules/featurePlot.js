import { WebR } from 'webr';

export async function initFeaturePlotWebR() {

  const webR = new WebR();
  await webR.init();

  // Create mountpoint
  await webR.FS.mkdir('/library');

  // Download image data
  const data = await fetch('www/webr/vfs/library.data');
  const metadata = await fetch('www/webr/vfs/library.js.metadata');

  // Mount image data
  const options = {
    packages: [{
      blob: await data.blob(),
      metadata: await metadata.json(),
    }],
  };

  await webR.FS.mount("WORKERFS", options, '/library');
  await webR.evalR('.libPaths(c(.libPaths(), "/library"))');

  //const shelter = new webR.Shelter();
  let shelter = await new webR.Shelter();

  //let result = await shelter.captureR('print(rnorm(10,5,1))');

  //console.log('Output obtained from running `rnorm` from webR:');
  //console.log(result.output);

  shelter.purge();

  await webR.evalR(`
library(ggplot2)
library(scales)
library(scattermore)
library(dplyr)
library(patchwork)
library(cowplot)
options(device=webr::canvas)
`);

  return(shelter)
}

export async function featurePlot(shelter, figWidth, figHeight, dr, expr){


  let result = await shelter.captureR(`
mapColor <- function(x, low = "#E5E4E2", high = "#800080"){
  ## default colors:
  ## low: #E5E4E -> Platinum
  ## hight: #800080 -> purple
  scales::pal_seq_gradient(low = low, high = high)(rescale(x))
}
plotFeature <- function(expr, raster = FALSE){
  if(raster || nrow(expr)>30000){

    color_palette <- mapColor(1:100)
    legend_data <- data.frame(
      y = seq(min(expr[,3]), max(expr[,3]), length.out = 100),
      x = rep(1, 100)
    )

    p0 <- ggplot(legend_data, aes(x = x, y = y, fill = y)) +
      geom_tile() +
      scale_fill_gradientn(colors = color_palette) +
      scale_y_continuous(name = NULL,
                         position = "right",
                         expand = expansion(0),
                         breaks = seq(min(expr[,3]), max(expr[,3]), length.out = 5),
                         labels = round(seq(min(expr[,3]), max(expr[,3]), length.out = 5), 2)) +
      theme_classic() +
      theme(
        plot.background = element_rect(fill= "white", color = NULL),
        legend.position = "none",
        axis.line.x = element_blank(),
        axis.text.x = element_blank(),
        axis.ticks.x = element_blank(),
        axis.text.y = element_text(hjust = 0, size = rel(1)),
        axis.title.y = element_text(angle = 90, vjust = 0.5),
        panel.border = element_blank(),
        plot.margin = margin(50.5, 0.5, 50.5, 0.5)

      )+
      xlab("")+
      ylab("")+
      ggtitle("expr")
    p <- ggplot()+
      geom_scattermost(xy = expr[,1:2], color = mapColor(expr[,3]))+
      xlab(colnames(expr)[1])+
      ylab(colnames(expr)[2])+
      theme_classic()+
      ggtitle(colnames(expr)[3])+
      theme(plot.title = element_text(face ="bold", hjust=0.5))

    plot_grid(p, p0, rel_widths=c(1, 0.1))
  }else{
    p <- ggplot(expr, aes(x=expr[,1], y=expr[,2], color=expr[,3]))+
      geom_point()+
      scale_color_gradient(low = "#E5E4E2", high = "#800080", name="expr")+
      xlab(colnames(expr)[1])+
      ylab(colnames(expr)[2])+
      theme_classic()+
      ggtitle(colnames(expr)[3])+
      theme(plot.title = element_text(face ="bold", hjust=0.5))
  }
}

features <- colnames(exprList)

pList <- list()
for(i in seq_along(features)){
    df <- cbind(reduction, exprList[i])
    colnames(df)[1] <- "DR1"
    colnames(df)[2] <- "DR2"
    if(nrow(df) >  30000){
        raster <- TRUE
    }else{
        raster <- FALSE
    }
    pList[[i]] <- plotFeature(df, raster = raster)
}
if(length(pList) >=3){
    ncol <- 3
}else{
    ncol <- length(pList)
}
wrap_plots(pList, ncol=ncol)
`, {
  env: {
    exprList: expr,
    reduction: dr
  },
  captureGraphics: {
    width: figWidth,
    height: figHeight,
    bg: "cornsilk"
  },
  withAutoprint: true,
  captureStreams: true,
  captureConditions: true
});

  return(result);
  //console.log("new library: ", res);
}
