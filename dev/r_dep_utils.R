parse_pkg_field <- function(field_value) {
  if (is.na(field_value) || !nzchar(field_value)) {
    return(character())
  }

  pkgs <- unlist(strsplit(field_value, ",", fixed = TRUE), use.names = FALSE)
  pkgs <- trimws(gsub("\\s*\\(.*\\)", "", pkgs))
  pkgs[nzchar(pkgs)]
}

description_packages_for_fields <- function(fields) {
  desc <- read.dcf("DESCRIPTION")[1, ]

  unique(unlist(
    lapply(fields, function(field) {
      if (!field %in% names(desc)) {
        return(character())
      }

      parse_pkg_field(desc[[field]])
    }),
    use.names = FALSE
  ))
}

required_description_packages <- function(include_suggests = FALSE) {
  fields <- c("Depends", "Imports")
  if (isTRUE(include_suggests)) {
    fields <- c(fields, "Suggests")
  }

  required <- description_packages_for_fields(fields)

  setdiff(required, "R")
}

suggested_description_packages <- function() {
  setdiff(description_packages_for_fields("Suggests"), "R")
}

optional_performance_packages <- function() {
  preferred <- c("presto")
  suggested <- suggested_description_packages()

  preferred[preferred %in% suggested]
}

prepare_pixi_r_session <- function(clear_toolchain = FALSE) {
  Sys.setenv(R_LIBS_USER = "", R_LIBS_SITE = "")

  if (!isTRUE(clear_toolchain)) {
    return(invisible(NULL))
  }

  vars <- c(
    "CONDA_PREFIX",
    "CONDA_DEFAULT_ENV",
    "CMAKE_PREFIX_PATH",
    "PKG_CONFIG_PATH",
    "LIBRARY_PATH",
    "CPATH",
    "C_INCLUDE_PATH",
    "CPLUS_INCLUDE_PATH",
    "LD_LIBRARY_PATH"
  )

  present <- vars[nzchar(Sys.getenv(vars, unset = ""))]
  if (length(present)) {
    Sys.unsetenv(present)
  }

  invisible(NULL)
}
