parse_pkg_field <- function(field_value) {
    if (is.na(field_value) || !nzchar(field_value)) {
        return(character())
    }

    pkgs <- unlist(strsplit(field_value, ",", fixed = TRUE), use.names = FALSE)
    pkgs <- trimws(gsub("\\s*\\(.*\\)", "", pkgs))
    pkgs[nzchar(pkgs)]
}

required_description_packages <- function(include_suggests = FALSE) {
    desc <- read.dcf("DESCRIPTION")[1, ]
    fields <- c("Depends", "Imports")
    if (isTRUE(include_suggests)) {
        fields <- c(fields, "Suggests")
    }

    required <- unique(unlist(lapply(fields, function(field) {
        if (!field %in% names(desc)) {
            return(character())
        }
        parse_pkg_field(desc[[field]])
    }), use.names = FALSE))

    setdiff(required, "R")
}
