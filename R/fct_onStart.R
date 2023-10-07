#' onStart
#'
#' @description A onStart function for shiny app
#'
#' @noRd
onStart <- function(){
    ## set options
    set_options()
}

#' set options
#'
#' @description set startup options
#'
#' @importFrom future plan availableCores
#' 
#' @noRd
set_options <- function(){

    options(shiny.maxRequestSize=20000*1024^2)
    options(shiny.usecairo = TRUE)

    options(future.globals.maxSize = 20 * 1000 * 1024^2)
    options(Seurat.object.assay.version = "v5")
    plan("multicore", workers = future::availableCores())

    ##RhpcBLASctl::blas_set_num_threads(1) # https://github.com/satijalab/seurat/issues/3991

    ## global settings for spinners
    ##options(spinner.type = 3, spinner.color.background = "#ffffff", spinner.color = "#2c3e50", spinner.size= 0.5)

    ## Has no effects on withWaiter()
    waiter::waiter_set_theme(
        ##html = waiter::spin_loaders(5, color = "black"),
        html = waiter::spin_loaders(5, color = "var(--bs-primary)"),
        color = "#ffffff"
    )
}
