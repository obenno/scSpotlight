#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom dplyr filter
#' @importFrom dplyr mutate
#' @importFrom dplyr select
#' @importFrom readr read_csv
#' @importFrom readr read_tsv
#' @importFrom shiny req
#' @importFrom methods as slot slot<- slotNames
#' @importFrom stats na.omit rnorm
#' @importFrom utils head read.delim read.table str untar
#' @importFrom SeuratObject ExtractField
#' @importFrom tibble column_to_rownames
#' @importFrom tibble rownames_to_column
#' @import bslib
## usethis namespace: end
NULL

utils::globalVariables(c("geneName", "percent.mt", "seuratObj"))
