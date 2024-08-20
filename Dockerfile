# syntax=docker/dockerfile:1.3-labs

#############################################
# Dockerfile to build scSpotlight container #
#############################################

## From seurat docker
FROM r-base:4.4.0

## Maintainer
MAINTAINER oben <obennoname@gmail.com>

## Install pre-requisites
USER root
## BPCells requires libhdf5, which will not be properly handled when installing with pak
RUN apt update && apt install -y libhdf5-dev libxml2-dev libgsl-dev libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype-dev libpng-dev libtiff5-dev libjpeg-dev libglpk-dev libcurl4-openssl-dev pandoc python3

WORKDIR /work
## Install R packages
#### Install harmony
##RUN Rscript -e 'install.packages("harmony")'
#### Install FastMNN
##RUN Rscript -e 'BiocManager::install("batchelor")'

## Install pak
RUN Rscript -e 'install.packages("pak", repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s", .Platform$pkgType, R.Version()$os, R.Version()$arch))'
##RUN Rscript -e 'pak::repo_add(scSpotlight = "https://obenno.r-universe.dev"); pak::pkg_install("scSpotlight");'
RUN Rscript -e 'install.packages("scSpotlight", repos = c("https://obenno.r-universe.dev", "https://cloud.r-project.org"))'
## Install suggested packages
RUN Rscript -e 'pak::repo_add(bpcells = "https://bnprks.r-universe.dev"); pak::pkg_install("BPCells")'
RUN Rscript -e 'pak::repo_add(satijalab = "https://satijalab.r-universe.dev"); pak::pkg_install(c("presto", "glmGamPoi"))'

## Follow Dockstore's guide
## switch back to the ubuntu user so this tool (and the files written) are not owned by root
RUN groupadd -r -g 1001 ubuntu && useradd -m -r -g ubuntu -u 1001 ubuntu
USER ubuntu

## Install scVI
WORKDIR /app
##RUN wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge-pypy3-Linux-x86_64.sh && bash Miniforge-pypy3-Linux-x86_64.sh -b -p /home/ubuntu/miniforge-pypy3 && rm Miniforge-pypy3-Linux-x86_64.sh

## Use interactive shell (-i) to source ~/.bashrc
SHELL ["/bin/bash", "-c", "-i"]
##RUN /home/ubuntu/miniforge-pypy3/bin/mamba init
##RUN conda config --set auto_activate_base false
##RUN mamba create -n scvi-env python=3.9 -y && mamba clean -t -c

# expose 80 port
EXPOSE 8081

## setup default cmd
CMD ["Rscript", "-e", "scSpotlight::run_app(options = list(port = 8081, host = '0.0.0.0', launch.browser = FALSE), runningMode = 'processing')"]
