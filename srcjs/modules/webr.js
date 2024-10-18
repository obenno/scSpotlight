import { WebR } from "webr";

// It seems that using webr::mount in mulitple
// instances will cause downloading issue.
// Not sure if it's the problem of message channel type
// revert to single webr instance for now.

export async function initWebR() {
  const webR = new WebR();
  await webR.init();
  return webR;
}

export async function initWebRInstance() {
  const webR = await initWebR();
  // Create mountpoint
  //await webR.FS.mkdir("/library");

  // Download image data
  //const data = await fetch("www/webr/vfs/library.data.gz");
  //const metadata = await fetch("www/webr/vfs/library.js.metadata");
  //
  //// Mount image data
  //const options = {
  //  packages: [
  //    {
  //      blob: await data.blob(),
  //      metadata: await metadata.json(),
  //    },
  //  ],
  //};
  //
  //await webR.FS.mount("WORKERFS", options, "/library");
  const currentPageUrl = window.location.href;
  await webR.evalR(
    `
webr::mount("/library", paste0(domainURL, "www/webr/vfs/library.data"))
.libPaths(c(.libPaths(), "/library"))
library(ggplot2)
library(scales)
library(scattermore)
library(dplyr)
library(patchwork)
library(cowplot)
library(qs)
options(device=webr::canvas)
`,
    {
      env: {
        domainURL: currentPageUrl,
      },
    },
  );

  return webR;
}

//export async function initQSWebR() {
//  const webR = await initWebR();
//  // Create mountpoint
//  //await webR.FS.mkdir("/library");
//
//  // Download image data
//  //const data = await fetch("www/webr/vfs/library.data.gz");
//  //const metadata = await fetch("www/webr/vfs/library.js.metadata");
//  //
//  //// Mount image data
//  //const options = {
//  //  packages: [
//  //    {
//  //      blob: await data.blob(),
//  //      metadata: await metadata.json(),
//  //    },
//  //  ],
//  //};
//  //
//  //await webR.FS.mount("WORKERFS", options, "/library");
//  //await webR.evalR('.libPaths(c(.libPaths(), "/library"))');
//  const currentPageUrl = window.location.href;
//  console.log(currentPageUrl);
//  await webR.evalR(
//    `
//webr::mount("/library", paste0(domainURL, "www/webr/vfs/library.data"))
//.libPaths(c(.libPaths(), "/library"))
//library(dplyr)
//library(qs)
//options(device=webr::canvas)
//`,
//    {
//      env: {
//        domainURL: currentPageUrl,
//      },
//    },
//  );
//
//  return webR;
//}

export async function initShelter(webR) {
  let shelter = await new webR.Shelter();
  shelter.purge();
  return shelter;
}

export async function featurePlot(shelter, figWidth, figHeight, dr, expr) {
  let result = await shelter.captureR(
    `
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
`,
    {
      env: {
        exprList: expr,
        reduction: dr,
      },
      captureGraphics: {
        width: figWidth,
        height: figHeight,
        bg: "cornsilk",
      },
      withAutoprint: true,
      captureStreams: true,
      captureConditions: true,
    },
  );

  return result;
  //console.log("new library: ", res);
}

export async function readQS(webR, buffer) {
  const randomString = Math.random().toString(36).substring(2, 10);
  const vfsPath = randomString + ".qs";
  const uint8Array = new Uint8Array(buffer);
  await webR.FS.writeFile(vfsPath, uint8Array);
  let res = await webR.evalR(
    `
d <- qs::qread(qsFile, use_alt_rep=TRUE) %>%
    as.data.frame()
## convert factor column to character ones
for(i in 1:ncol(d)){
    if(is.factor(d[, i])){
        d[, i] <- as.character(d[, i])
    }
}
d
`,
    {
      env: {
        qsFile: vfsPath,
      },
      withAutoprint: false,
      captureStreams: true,
      captureConditions: true,
    },
  );
  // delete the file
  await webR.FS.unlink(vfsPath);
  // RDataFrame.toObject() will convert df to json array
  // rownames will be omitted
  const df = await res.toObject();
  // destroy res to release memory
  await webR.destroy(res);
  for (const key in df) {
    if (Array.isArray(df[key]) && df[key].length > 0) {
      const firstElement = df[key][0];
      if (typeof firstElement === "number") {
        // Check if all elements are integers
        // modulo operation is much faster than .isInteger()
        const isIntArray = df[key].every((num) => num % 1 === 0);

        if (isIntArray) {
          df[key] = new Int32Array(df[key]);
        } else {
          df[key] = new Float32Array(df[key]);
        }
      }
    }
  }
  return df;
}
