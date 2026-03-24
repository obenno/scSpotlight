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
  const vfsSourceUrl = `${window.location.origin}/www/webr/vfs/library.data.gz`;
  await webR.evalR(
    `
webr::mount("/library", sourceURL)
.libPaths(c(.libPaths(), "/library"))
if (!requireNamespace("qs2", quietly = TRUE)) {
  webr::install("qs2", repos = "https://repo.r-wasm.org/")
}
if (!requireNamespace("qs2", quietly = TRUE)) {
  stop("Package 'qs2' is required in the webR mounted library and runtime install failed.")
}
library(ggplot2)
library(scales)
library(scattermore)
library(dplyr)
library(patchwork)
library(cowplot)
library(qs2)
options(device=webr::canvas)
`,
    {
      env: {
        sourceURL: vfsSourceUrl,
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
//library(qs2)
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

export async function featurePlot(
  shelter,
  figWidth,
  figHeight,
  dr,
  expr,
  ncol = null,
) {
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
if(is.null(panelNcol)){
  if(length(pList) >=3){
      ncol <- 3
  }else{
      ncol <- length(pList)
  }
}else{
  ncol <- max(1, min(as.integer(panelNcol), length(pList)))
}
wrap_plots(pList, ncol=ncol)
`,
    {
      env: {
        exprList: expr,
        reduction: dr,
        panelNcol: ncol,
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

export async function qs2ReadFromUrl(webR, shelter, url, ext = ".qs2") {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch ${url}: ${response.status} ${response.statusText}`);
  }

  const bytes = new Uint8Array(await response.arrayBuffer());
  const tempPath = `/${Math.random().toString(36).slice(2, 10)}${ext}`;
  await webR.FS.writeFile(tempPath, bytes);

  try {
    return await shelter.evalR(
      `qs2::qs_read(path)`,
      {
        env: { path: tempPath },
        withAutoprint: false,
        captureStreams: true,
        captureConditions: true,
      },
    );
  } finally {
    try {
      await webR.FS.unlink(tempPath);
    } catch (_) {
      // ignore cleanup errors
    }
  }
}

export async function qsReadNumVector(shelter, url) {
  let now = new Date();
  console.log(`start qs reading: ${now.toLocaleTimeString()}`);
  //const randomString = Math.random().toString(36).substring(2, 10);
  //const vfsPath = randomString + ".qs";
  //const uint8Array = new Uint8Array(buffer);
  //await webR.FS.writeFile(vfsPath, uint8Array);

  let res = await shelter.evalR(
    `
d <- local({
  tf <- tempfile(fileext = ".qs2")
  on.exit(unlink(tf), add = TRUE)
  utils::download.file(url, tf, mode = "wb", quiet = TRUE)
  qs2::qs_read(tf)
})
d
`,
    {
      env: {
        url: url,
      },
      withAutoprint: false,
      captureStreams: true,
      captureConditions: true,
    },
  );
  // toTypedArray() return float64
  // convert to float32 array
  const out = new Float32Array(await res.toTypedArray());
  // destroy res to release memory
  await shelter.purge();
  now = new Date();
  console.log(`finished qs reading: ${now.toLocaleTimeString()}`);
  return out;
}

export async function qsReadList(shelter, url) {
  let now = new Date();
  console.log(`start qs reading: ${now.toLocaleTimeString()}`);

  let res = await shelter.evalR(
    `
d <- local({
  tf <- tempfile(fileext = ".qs2")
  on.exit(unlink(tf), add = TRUE)
  utils::download.file(url, tf, mode = "wb", quiet = TRUE)
  qs2::qs_read(tf)
})
d
`,
    {
      env: {
        url: url,
      },
      withAutoprint: false,
      captureStreams: true,
      captureConditions: true,
    },
  );

  let idx = 0;
  const out = {};
  const colNames = Object.keys(await res.toObject({ depth: 1 }));
  //const out = await res.toObject();
  for await (const i of res) {
    const e = await i.toObject({ depth: 1 });

    const dataType = await e.type.toString();
    if (dataType === "number") {
      const dataArray = await e.value.toArray();
      if (isIntegerArray(dataArray)) {
        out[colNames[idx]] = {
          type: dataType,
          value: Int32Array.from(dataArray),
        };
      } else {
        out[colNames[idx]] = {
          type: dataType,
          value: Float32Array.from(dataArray),
        };
      }
    } else if (dataType === "category") {
      const dataObject = {};
      const catData = await e.value.toObject({ depth: 1 });
      const catNames = Object.keys(catData);
      for (const cat of catNames) {
        dataObject[cat] = await catData[cat].toTypedArray();
      }
      out[colNames[idx]] = { type: dataType, value: dataObject };
    } else {
      out[colNames[idx]] = { type: dataType, value: [] };
    }
    //df[colNames[idx]] = out["values"];
    idx++;
  }
  // destroy res to release memory
  await shelter.purge();

  now = new Date();
  console.log(`finished looping: ${now.toLocaleTimeString()}`);
  return out;
}

export async function qsRead(shelter) {
  let fn = await shelter.evalR(
    `
function(url){
    tf <- tempfile(fileext = ".qs2")
    on.exit(unlink(tf), add = TRUE)
    utils::download.file(url, tf, mode = "wb", quiet = TRUE)
    qs2::qs_read(tf)
}
`,
    {
      withAutoprint: false,
      captureStreams: true,
      captureConditions: true,
    },
  );
  return fn;
}

export async function vlnPlot(
  shelter,
  figWidth,
  figHeight,
  df,
  group,
  groupOrder,
  expr = false,
  colors = [],
) {
  let result = await shelter.captureR(
    `
plotVln <- function(df, x, y){
    p <- ggplot(df, aes(x = !!as.symbol(x),
                        y = !!as.symbol(y),
                        fill = !!as.symbol(x))) +
      geom_violin(alpha = 0.8, scale="width")
    if(nrow(df) > 20000){
        p <- p + geom_boxplot(width = 0.2, fill = "white", outlier.shape = NA)
    }else{
        if(!all(pull(df, !!as.symbol(y)) == 0)){
            p <- p + geom_jitter(alpha = 0.5, size =0.6)
        }
    }
    if(length(colors)>0){
        p <- p + scale_fill_manual(values = colors)
    }
    p <- p +
      theme_classic() +
      labs(title = y,
           x = "",
           y = "") +
      theme(legend.position = "none",
            axis.text.x = element_text(angle = 45,
                                       hjust = 1,
                                       vjust =1,
                                       color = "black"))
    return(p)
}

## rename the feature column
## dataframe conversion will check/fix "-"
if(is.character(expr)){
    colnames(df)[ncol(df)] <- expr
}
## check the input df colnames
stopifnot(group %in% colnames(df))
k <- setdiff(colnames(df), group)

pList <- list()
if(!is.null(groupOrder)){
    df[, group] <- factor(df[, group], levels = groupOrder)
}
for(i in seq_along(k)){
    pList[[i]] <- plotVln(df, group, k[i])
}

if(length(pList) >=2){
    ncol <- 2
}else{
    ncol <- ifelse(length(pList) > 0, length(pList), 1)
}
wrap_plots(pList, ncol=ncol)
`,
    {
      env: {
        group: group,
        df: df,
        expr: expr, // dataframe convertion will auto "check/fix" column names
        colors: colors,
        groupOrder: groupOrder,
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
}

export async function dotPlot(
  shelter,
  figWidth,
  figHeight,
  df,
  group,
  groupOrder = null,
) {
  let result = await shelter.captureR(
    `
summarize_expr <- function(df, group, feature){
    d0 <- df %>%
        group_by(!!as.symbol(group)) %>%
        summarize(
            avg.exp = mean(expm1(!!as.symbol(feature))),
            totalCells = n(),
            expressed = sum(!!as.symbol(feature) >0)
        ) %>%
        ungroup()
    d0 <- d0 %>%
        mutate(
            pct.exp = expressed/totalCells,
            features.plot = feature,
            avg.exp.scaled = as.vector(scale(log1p(d0$avg.exp)))
        ) %>%
        dplyr::select(!!as.symbol(group), avg.exp, pct.exp, features.plot, avg.exp.scaled)
    return(d0)
}
features <- setdiff(colnames(df), c("cell", "cells", group)) # ensure no cells column was included
d <- do.call(
    what=rbind,
    args = lapply(features, FUN=function(x){
        summarize_expr(df, group, x)
    })
)

if(!is.null(groupOrder)){
    observed_groups <- unique(as.character(d[[group]]))
    normalized_levels <- intersect(as.character(groupOrder), observed_groups)
    normalized_levels <- c(normalized_levels, setdiff(observed_groups, normalized_levels))
    d[[group]] <- factor(as.character(d[[group]]), levels = normalized_levels)
}

p <- ggplot(d, aes(x = features.plot, y= !!as.symbol(group),
                   fill = avg.exp.scaled, size = pct.exp))+
    geom_point(shape=21, color = "black")+
    scale_fill_gradient(low="white", high="#800080")+
    theme_classic() +
    labs(size = "Pct Expr",
         fill = "Avg Expr",
         title = "",
         x = "",
         y = "") +
    theme(legend.position = "right",
          axis.text.x = element_text(angle = 75,
                                     hjust = 1,
                                     vjust = 1,
                                     color = "black"),
          axis.text.y = element_text(color = "black"))
print(p)
`,
    {
      env: {
        group: group,
        df: df,
        groupOrder: groupOrder,
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
}

// helper function to check integer array and floating number array
export const isFloatArray = (arr) => arr.every((num) => !Number.isInteger(num));
export const isIntegerArray = (arr) => arr.every(Number.isInteger);
