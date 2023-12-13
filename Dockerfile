# syntax=docker/dockerfile:1.3-labs

#############################################
# Dockerfile to build scSpotlight container #
#############################################

## From seurat docker
FROM r-base:4.3.0

## Maintainer
MAINTAINER oben <obennoname@gmail.com>

## Install pre-requisites
USER root
RUN apt update && apt install -y libhdf5-dev libxml2-dev

## Follow Dockstore's guide
## switch back to the ubuntu user so this tool (and the files written) are not owned by root
RUN groupadd -r -g 1001 ubuntu && useradd -m -r -g ubuntu -u 1001 ubuntu
USER ubuntu

WORKDIR /work
## Install R packages
RUN Rscript -e 'install.packages(c("Seurat", "shiny", "bsicons", "bslib", "config", "golem", "htmltools", "promises", "tidyverse", "readxl", "scales", "shinycssloaders", "shinyjs", "shinyWidgets", "waiter"))'
RUN Rscript -e 'install.packages("remotes")'
RUN Rscript -e 'setRepositories(ind = 1:3, addURLs = c("https://satijalab.r-universe.dev", "https://bnprks.r-universe.dev/")); install.packages(c("BPCells", "presto", "glmGamPoi"))'
RUN Rscript -e 'options(timeout=600); remotes::install_github("satijalab/seurat-data", quiet = TRUE)'
RUN Rscript -e 'options(timeout=600); remotes::install_github("satijalab/azimuth", quiet = TRUE)'
RUN Rscript -e 'options(timeout=600); remotes::install_github("satijalab/seurat-wrappers", quiet = TRUE)'
## Install harmony
RUN Rscript -e 'install.packages("harmony")'
## Install FastMNN
RUN Rscript -e 'BiocManager::install("batchelor")'
## Install scVI
RUN wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge-pypy3-Linux-x86_64.sh && bash Miniforge-pypy3-Linux-x86_64.sh -b && conda config --set auto_activate_base false
RUN mamba create -n scvi-env python=3.9 -y && mamba clean -t -c
RUN rm /work/*

## Install scSpotlight
WORKDIR /app
COPY scSpotlight_0.0.0.9000.tar.gz .
RUN Rscript -e 'install.packages("scSpotlight_0.0.0.9000.tar.gz", repo = NULL)'


## expose 80 port
EXPOSE 8081

## setup default cmd
CMD ["Rscript", "-e", "scSpotlight::run_app(options = list(port = 8081, host = '0.0.0.0', launch.browser = FALSE), runningMode = 'processing')"]
