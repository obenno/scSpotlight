benchmark_default_root <- function() {
  temp_root <- Sys.getenv("SCSPOTLIGHT_TEMP_ROOT", "")
  default_root <- if (nzchar(trimws(temp_root))) {
    file.path(temp_root, "benchmarks", "explore-1m")
  } else {
    file.path(getwd(), "benchmarks", ".tmp", "explore-1m")
  }
  root <- Sys.getenv(
    "SCSPOTLIGHT_BENCHMARK_ROOT",
    default_root
  )
  normalizePath(root, winslash = "/", mustWork = FALSE)
}

benchmark_representative_source_md5 <- "7933979b0faf179ce2674be6e4baed81"
benchmark_evidence_max_rss_limit_bytes <- 6000000000

benchmark_default_results_file <- function() {
  output_file <- Sys.getenv(
    "SCSPOTLIGHT_BENCHMARK_RESULTS_FILE",
    file.path(benchmark_default_root(), "results.json")
  )
  normalizePath(output_file, winslash = "/", mustWork = FALSE)
}

benchmark_cell_count <- function() {
  cell_count <- suppressWarnings(as.integer(Sys.getenv(
    "SCSPOTLIGHT_BENCHMARK_CELL_COUNT",
    "1000000"
  )))
  if (is.na(cell_count) || cell_count < 1L) {
    stop("SCSPOTLIGHT_BENCHMARK_CELL_COUNT must be a positive integer.")
  }
  cell_count
}

benchmark_cell_identity <- function(cell_ids) {
  cell_ids <- as.character(cell_ids)
  if (
    !length(cell_ids) ||
      any(is.na(cell_ids) | !nzchar(cell_ids)) ||
      anyDuplicated(cell_ids)
  ) {
    stop("Benchmark Cell IDs must be non-empty and unique.", call. = FALSE)
  }

  identity_file <- tempfile("scspotlight_benchmark_cell_identity_")
  on.exit(unlink(identity_file, force = TRUE), add = TRUE)
  connection <- file(identity_file, open = "wb")
  connection_closed <- FALSE
  on.exit(
    if (!connection_closed) {
      close(connection)
    },
    add = TRUE
  )
  writeBin(as.integer(length(cell_ids)), connection, size = 4L, endian = "little")
  encoded_ids <- enc2utf8(cell_ids)
  writeBin(
    as.integer(nchar(encoded_ids, type = "bytes")),
    connection,
    size = 4L,
    endian = "little"
  )
  writeChar(encoded_ids, connection, eos = NULL, useBytes = TRUE)
  close(connection)
  connection_closed <- TRUE

  unname(tools::md5sum(identity_file)[[1]])
}

benchmark_execution_source_root <- function() {
  execution_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  if (
    !file.exists(file.path(execution_root, "DESCRIPTION")) ||
      !dir.exists(file.path(execution_root, "R"))
  ) {
    stop(
      "Benchmark commands must run from an scSpotlight package checkout.",
      call. = FALSE
    )
  }

  configured_root <- trimws(Sys.getenv("SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT", ""))
  if (nzchar(configured_root)) {
    configured_root <- normalizePath(
      configured_root,
      winslash = "/",
      mustWork = TRUE
    )
    if (!identical(configured_root, execution_root)) {
      stop(
        paste(
          "SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT must match the current working",
          "directory so benchmark evidence names the code being measured."
        ),
        call. = FALSE
      )
    }
  }

  Sys.setenv(SCSPOTLIGHT_BENCHMARK_SOURCE_ROOT = execution_root)
  execution_root
}

benchmark_bundle_paths <- function(root = benchmark_default_root()) {
  bundle_name <- "scspotlight-explore-1m"
  list(
    root = root,
    bundle_dir = file.path(root, bundle_name),
    archive = file.path(root, paste0(bundle_name, ".explore-parquet.zip")),
    manifest = file.path(root, bundle_name, "manifest.json")
  )
}

benchmark_read_proc_status <- function(pid = Sys.getpid()) {
  status_file <- file.path("/proc", as.integer(pid), "status")
  if (!file.exists(status_file)) {
    return(list(rss_kb = NA_real_, hwm_kb = NA_real_))
  }

  status <- readLines(status_file, warn = FALSE)
  read_kb <- function(label) {
    line <- status[startsWith(status, paste0(label, ":"))]
    if (!length(line)) {
      return(NA_real_)
    }
    suppressWarnings(as.numeric(sub("^.*?:[[:space:]]*([0-9]+).*$", "\\1", line[[1]])))
  }

  list(
    rss_kb = read_kb("VmRSS"),
    hwm_kb = read_kb("VmHWM")
  )
}

benchmark_command_version <- function(command, args = "--version") {
  output <- tryCatch(
    system2(command, args, stdout = TRUE, stderr = FALSE),
    error = function(...) character()
  )
  output <- trimws(output)
  if (length(output) && nzchar(output[[1]])) output[[1]] else NA_character_
}

benchmark_text_md5 <- function(text) {
  hash_file <- tempfile("scspotlight_benchmark_hash_")
  on.exit(unlink(hash_file), add = TRUE)
  writeLines(enc2utf8(text), hash_file, useBytes = TRUE)
  unname(tools::md5sum(hash_file)[[1]])
}

benchmark_environment_fingerprint <- function(environment) {
  environment$environment_fingerprint <- NULL
  benchmark_text_md5(jsonlite::toJSON(
    environment,
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  ))
}

benchmark_environment <- function(source_root = getwd()) {
  source_root <- normalizePath(source_root, winslash = "/", mustWork = TRUE)
  memory <- tryCatch(readLines("/proc/meminfo", warn = FALSE), error = function(...) character())
  memory_line <- memory[startsWith(memory, "MemTotal:")]
  cpu_info <- tryCatch(readLines("/proc/cpuinfo", warn = FALSE), error = function(...) character())
  cpu_model_line <- cpu_info[startsWith(cpu_info, "model name")]
  memory_total_kb <- suppressWarnings(as.numeric(sub(
    "^MemTotal:[[:space:]]*([0-9]+).*$",
    "\\1",
    if (length(memory_line)) memory_line[[1]] else NA_character_
  )))

  environment <- list(
    timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    os = paste(Sys.info()[c("sysname", "release", "machine")], collapse = " "),
    r_version = R.version.string,
    r_platform = R.version$platform,
    pixi_version = benchmark_command_version("pixi"),
    node_version = benchmark_command_version("node"),
    npm_version = benchmark_command_version("npm"),
    package_versions = list(
      scSpotlight = as.character(utils::packageVersion("scSpotlight")),
      arrow = as.character(utils::packageVersion("arrow")),
      duckdb = as.character(utils::packageVersion("duckdb"))
    ),
    cpu_model = if (length(cpu_model_line)) {
      sub("^model name[[:space:]]*:[[:space:]]*", "", cpu_model_line[[1]])
    } else {
      NA_character_
    },
    memory_total_kb = memory_total_kb,
    available_cores = parallel::detectCores(logical = TRUE),
    lockfiles = list(
      pixi_toml_md5 = benchmark_file_md5(file.path(source_root, "pixi.toml")),
      pixi_lock_md5 = benchmark_file_md5(file.path(source_root, "pixi.lock")),
      package_lock_md5 = benchmark_file_md5(file.path(source_root, "package-lock.json"))
    )
  )
  environment$environment_fingerprint <- benchmark_environment_fingerprint(
    environment
  )
  environment
}

benchmark_git_revision <- function(source_root = getwd()) {
  source_root <- normalizePath(source_root, winslash = "/", mustWork = TRUE)
  revision <- tryCatch(
    system2(
      "git",
      c("-C", shQuote(source_root), "rev-parse", "HEAD"),
      stdout = TRUE,
      stderr = FALSE
    ),
    error = function(...) character()
  )
  revision <- trimws(revision)
  if (length(revision) == 1L && nzchar(revision)) revision else NA_character_
}

benchmark_git_provenance <- function(source_root = getwd()) {
  source_root <- normalizePath(source_root, winslash = "/", mustWork = TRUE)
  revision <- benchmark_git_revision(source_root)
  if (is.na(revision)) {
    return(list(
      source_revision = NA_character_,
      source_dirty = NA,
      source_worktree_snapshot_id = NA_character_,
      source_status_porcelain = character()
    ))
  }

  status <- tryCatch(
    system2(
      "git",
      c(
        "-C",
        shQuote(source_root),
        "status",
        "--porcelain=v1",
        "--untracked-files=all"
      ),
      stdout = TRUE,
      stderr = FALSE
    ),
    error = function(...) character()
  )
  status <- status[nzchar(trimws(status))]
  if (!length(status)) {
    return(list(
      source_revision = revision,
      source_dirty = FALSE,
      source_worktree_snapshot_id = revision,
      source_status_porcelain = character()
    ))
  }

  snapshot_root <- Sys.getenv("SCSPOTLIGHT_TEMP_ROOT", "")
  if (!nzchar(trimws(snapshot_root))) {
    snapshot_root <- tempdir()
  }
  dir.create(snapshot_root, recursive = TRUE, showWarnings = FALSE)
  snapshot_file <- tempfile(
    "scspotlight_benchmark_worktree_",
    tmpdir = snapshot_root
  )
  on.exit(unlink(snapshot_file), add = TRUE)
  diff_status <- tryCatch(
    system2(
      "git",
      c(
        "-C",
        shQuote(source_root),
        "diff",
        "--no-ext-diff",
        "--binary",
        "--full-index",
        "HEAD"
      ),
      stdout = snapshot_file,
      stderr = FALSE
    ),
    error = function(...) 1L
  )
  if (!identical(as.integer(diff_status), 0L)) {
    return(list(
      source_revision = revision,
      source_dirty = TRUE,
      source_worktree_snapshot_id = NA_character_,
      source_status_porcelain = status
    ))
  }

  untracked_files <- tryCatch(
    system2(
      "git",
      c(
        "-C",
        shQuote(source_root),
        "ls-files",
        "--others",
        "--exclude-standard"
      ),
      stdout = TRUE,
      stderr = FALSE
    ),
    error = function(...) character()
  )
  untracked_files <- sort(unique(untracked_files[nzchar(untracked_files)]))
  snapshot_connection <- file(snapshot_file, open = "ab")
  snapshot_connection_closed <- FALSE
  on.exit(
    if (!snapshot_connection_closed) {
      close(snapshot_connection)
    },
    add = TRUE
  )
  writeBin(charToRaw("\n-- scspotlight benchmark untracked files --\n"), snapshot_connection)
  for (path in untracked_files) {
    source_path <- file.path(source_root, path)
    if (!file.exists(source_path) || dir.exists(source_path)) {
      next
    }
    size <- unname(file.info(source_path)$size)
    writeBin(
      charToRaw(paste0("\n-- path: ", path, " size: ", size, " --\n")),
      snapshot_connection
    )
    if (is.finite(size) && size > 0) {
      writeBin(readBin(source_path, what = "raw", n = size), snapshot_connection)
    }
  }
  close(snapshot_connection)
  snapshot_connection_closed <- TRUE

  snapshot_id <- tryCatch(
    system2("git", c("hash-object", snapshot_file), stdout = TRUE, stderr = FALSE),
    error = function(...) character()
  )
  snapshot_id <- trimws(snapshot_id)
  snapshot_id <- if (length(snapshot_id) == 1L && nzchar(snapshot_id)) {
    snapshot_id
  } else {
    NA_character_
  }

  list(
    source_revision = revision,
    source_dirty = TRUE,
    source_worktree_snapshot_id = snapshot_id,
    source_status_porcelain = status
  )
}

benchmark_file_md5 <- function(path) {
  if (!file.exists(path)) {
    return(NA_character_)
  }
  unname(tools::md5sum(path)[[1]])
}

benchmark_evidence_status <- function(
  result,
  source_root = getwd(),
  current_provenance = NULL,
  current_environment = NULL
) {
  reasons <- character()
  add_reason <- function(reason) {
    reasons <<- c(reasons, reason)
  }
  scalar_character <- function(value) {
    is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
  }
  scalar_number <- function(value) {
    is.numeric(value) && length(value) == 1L && is.finite(value)
  }

  source_root <- normalizePath(source_root, winslash = "/", mustWork = TRUE)
  if (is.null(current_provenance)) {
    current_provenance <- benchmark_git_provenance(source_root)
  }
  if (is.null(current_environment)) {
    current_environment <- benchmark_environment(source_root)
  }
  current_revision <- current_provenance$source_revision
  provenance <- result$provenance
  environment <- result$environment
  artifact_kind <- provenance$artifact_kind
  representative_kinds <- c(
    "cellxgene_real_h5ad",
    "cellxgene_real_explore_bundle"
  )

  if (!identical(as.integer(result$schema_version), 2L)) {
    add_reason("Evidence must use benchmark schema version 2.")
  }
  if (!scalar_character(artifact_kind) || !artifact_kind %in% representative_kinds) {
    add_reason("Evidence must use a representative processed 1M+ artifact.")
  }
  if (
    !scalar_character(provenance$biological_representativeness) ||
      identical(provenance$biological_representativeness, "not claimed")
  ) {
    add_reason("Evidence must explicitly record representative biological provenance.")
  }
  if (
    !scalar_number(result$workload$cell_count) ||
      result$workload$cell_count < 1000000
  ) {
    add_reason("Evidence workload must contain at least 1,000,000 cells.")
  }
  if (
    !scalar_character(provenance$source_revision) ||
      !grepl("^[0-9a-f]{40,64}$", provenance$source_revision)
  ) {
    add_reason("Evidence must record an exact git SHA.")
  } else if (!identical(provenance$source_revision, current_revision)) {
    add_reason("Evidence git SHA does not match the current git SHA.")
  }
  if (!identical(provenance$source_dirty, FALSE)) {
    add_reason("Current evidence must be produced from a clean worktree.")
  }
  if (!identical(current_provenance$source_dirty, FALSE)) {
    add_reason("The checkout used to validate current evidence must be clean.")
  }
  if (
    !scalar_character(provenance$source_worktree_snapshot_id) ||
      !identical(
        provenance$source_worktree_snapshot_id,
        provenance$source_revision
      )
  ) {
    add_reason("Clean evidence snapshot ID must equal its git SHA.")
  }
  if (length(provenance$source_status_porcelain)) {
    add_reason("Current evidence must record an empty porcelain status.")
  }
  if (!scalar_character(provenance$source_md5)) {
    add_reason("Representative evidence must record the input artifact MD5.")
  } else if (!identical(
    provenance$source_md5,
    benchmark_representative_source_md5
  )) {
    add_reason("Evidence input artifact MD5 does not match the representative fixture.")
  }

  required_environment <- c(
    "timestamp_utc",
    "os",
    "r_version",
    "r_platform",
    "pixi_version",
    "node_version",
    "npm_version",
    "cpu_model",
    "environment_fingerprint"
  )
  for (field in required_environment) {
    if (!scalar_character(environment[[field]])) {
      add_reason(paste0("Evidence environment is missing ", field, "."))
    }
  }
  for (field in c("memory_total_kb", "available_cores")) {
    if (!scalar_number(environment[[field]])) {
      add_reason(paste0("Evidence environment is missing ", field, "."))
    }
  }
  if (
    scalar_character(environment$environment_fingerprint) &&
      !identical(
        environment$environment_fingerprint,
        benchmark_environment_fingerprint(environment)
      )
  ) {
    add_reason("Evidence environment fingerprint does not match its recorded fields.")
  }
  required_packages <- c("scSpotlight", "arrow", "duckdb")
  for (pkg in required_packages) {
    recorded <- environment$package_versions[[pkg]]
    current <- current_environment$package_versions[[pkg]]
    if (!scalar_character(recorded)) {
      add_reason(paste0("Evidence environment is missing package version ", pkg, "."))
    } else if (!scalar_character(current) || !identical(recorded, current)) {
      add_reason(paste0(
        "Evidence package version ",
        pkg,
        " does not match the active environment."
      ))
    }
  }
  runtime_version_fields <- c(
    "r_version",
    "r_platform",
    "pixi_version",
    "node_version",
    "npm_version"
  )
  for (field in runtime_version_fields) {
    recorded <- environment[[field]]
    current <- current_environment[[field]]
    if (
      scalar_character(recorded) &&
        (!scalar_character(current) || !identical(recorded, current))
    ) {
      add_reason(paste0(
        "Evidence environment ",
        field,
        " does not match the active environment."
      ))
    }
  }
  host_character_fields <- c("os", "cpu_model")
  for (field in host_character_fields) {
    recorded <- environment[[field]]
    current <- current_environment[[field]]
    if (
      scalar_character(recorded) &&
        (!scalar_character(current) || !identical(recorded, current))
    ) {
      add_reason(paste0(
        "Evidence host ",
        field,
        " does not match the active host."
      ))
    }
  }
  host_numeric_fields <- c("memory_total_kb", "available_cores")
  for (field in host_numeric_fields) {
    recorded <- environment[[field]]
    current <- current_environment[[field]]
    if (
      scalar_number(recorded) &&
        (!scalar_number(current) || !identical(as.numeric(recorded), as.numeric(current)))
    ) {
      add_reason(paste0(
        "Evidence host ",
        field,
        " does not match the active host."
      ))
    }
  }
  lockfile_names <- c(
    pixi_toml_md5 = "pixi.toml",
    pixi_lock_md5 = "pixi.lock",
    package_lock_md5 = "package-lock.json"
  )
  for (lock_name in names(current_environment$lockfiles)) {
    recorded <- environment$lockfiles[[lock_name]]
    current <- current_environment$lockfiles[[lock_name]]
    display_name <- unname(lockfile_names[[lock_name]])
    if (!scalar_character(recorded)) {
      add_reason(paste0("Evidence environment is missing ", display_name, " MD5."))
    } else if (!identical(recorded, current)) {
      add_reason(paste0("Evidence ", display_name, " does not match the current lockfile."))
    }
  }

  if (
    !scalar_number(result$browser$first_view_latency_ms) ||
      result$browser$first_view_latency_ms < 0
  ) {
    add_reason("Evidence is missing browser first-View latency.")
  }
  if (
    !scalar_number(result$browser$selected_gene_expression_end_to_end_latency_ms) ||
      result$browser$selected_gene_expression_end_to_end_latency_ms < 0
  ) {
    add_reason("Evidence is missing selected-gene end-to-end latency.")
  }
  if (!scalar_number(result$browser$server_rss$peak_process_hwm_bytes)) {
    add_reason("Evidence is missing peak Shiny process RSS in bytes.")
  }
  if (!scalar_number(result$browser$browser_memory$runtime_heap_used_bytes)) {
    add_reason("Evidence is missing settled browser heap usage.")
  }
  if (!scalar_character(result$browser$environment$browser_version)) {
    add_reason("Evidence is missing the browser version.")
  }

  acceptance <- result$acceptance
  rss_limit_bytes <- acceptance$rss_limit_bytes
  if (
    !scalar_number(rss_limit_bytes) ||
      rss_limit_bytes <= 0 ||
      rss_limit_bytes > benchmark_evidence_max_rss_limit_bytes
  ) {
    add_reason(paste0(
      "Evidence RSS limit must be a positive value no greater than ",
      benchmark_evidence_max_rss_limit_bytes,
      " bytes."
    ))
    rss_limit_bytes <- NA_real_
  }
  raw_rss_gates <- list(
    processing_rss_under_limit = list(
      value = result$processing$rss_gate$peak_bytes,
      label = "processing RSS"
    ),
    browser_visualization_rss_under_limit = list(
      value = result$browser$browser_memory$runtime_heap_used_bytes,
      label = "browser visualization memory"
    ),
    browser_server_rss_under_limit = list(
      value = result$browser$server_rss$peak_process_hwm_bytes,
      label = "browser server RSS"
    ),
    chromium_rss_under_limit = list(
      value = result$browser$chromium_rss$peak_aggregate_hwm_bytes,
      label = "Chromium RSS"
    )
  )
  for (gate_name in names(raw_rss_gates)) {
    gate <- raw_rss_gates[[gate_name]]
    measured_passed <- is.finite(rss_limit_bytes) &&
      scalar_number(gate$value) &&
      gate$value >= 0 &&
      gate$value < rss_limit_bytes
    if (!measured_passed) {
      add_reason(paste0(
        "Evidence ", gate$label,
        " measurement must be non-negative and below its recorded limit."
      ))
    }
    if (!identical(acceptance[[gate_name]], measured_passed)) {
      add_reason(paste0(
        "Evidence ", gate_name,
        " does not match its raw ", gate$label,
        " measurement."
      ))
    }
  }
  evidence_status_names <- grep(
    "_evidence_status$",
    names(acceptance),
    value = TRUE
  )
  evidence_passed <- length(evidence_status_names) && all(vapply(
    evidence_status_names,
    function(name) identical(acceptance[[name]], "passed"),
    logical(1)
  ))
  if (!evidence_passed) {
    add_reason("Every evidence acceptance status must be passed.")
  }
  required_rss_gate_names <- c(
    "processing_rss_under_limit",
    "browser_visualization_rss_under_limit",
    "browser_server_rss_under_limit",
    "chromium_rss_under_limit"
  )
  missing_rss_gates <- setdiff(required_rss_gate_names, names(acceptance))
  if (length(missing_rss_gates)) {
    add_reason(paste0(
      "Evidence is missing required RSS gate(s): ",
      paste(missing_rss_gates, collapse = ", "),
      "."
    ))
  }
  rss_gate_names <- grep("_rss_under_limit$", names(acceptance), value = TRUE)
  if (
    !length(rss_gate_names) ||
      any(!vapply(rss_gate_names, function(name) isTRUE(acceptance[[name]]), logical(1)))
  ) {
    add_reason("Every named RSS gate must be present and passed.")
  }

  list(
    current = !length(reasons),
    reasons = unique(reasons),
    source_revision = provenance$source_revision,
    current_revision = current_revision,
    checked_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
}

benchmark_summary <- function(samples) {
  samples <- as.numeric(samples)
  list(
    samples = samples,
    min = min(samples),
    median = stats::median(samples),
    max = max(samples)
  )
}

benchmark_elapsed <- function(operation) {
  before <- benchmark_read_proc_status()
  started <- proc.time()[["elapsed"]]
  value <- operation()
  elapsed_ms <- round((proc.time()[["elapsed"]] - started) * 1000, 3)
  after <- benchmark_read_proc_status()
  list(
    value = value,
    elapsed_ms = elapsed_ms,
    rss_before_kb = before$rss_kb,
    rss_after_kb = after$rss_kb,
    hwm_after_kb = after$hwm_kb
  )
}

benchmark_write_structural_explore_bundle <- function(
  root = benchmark_default_root(),
  cell_count = benchmark_cell_count(),
  force = FALSE
) {
  if (!requireNamespace("arrow", quietly = TRUE) ||
      !requireNamespace("jsonlite", quietly = TRUE) ||
      !requireNamespace("zip", quietly = TRUE)) {
    stop("The 1M benchmark requires arrow, jsonlite, and zip.")
  }

  paths <- benchmark_bundle_paths(root)
  if (file.exists(paths$archive) && file.exists(paths$manifest) && !isTRUE(force)) {
    return(paths)
  }
  if (dir.exists(paths$root) && length(list.files(paths$root, all.files = TRUE, no.. = TRUE))) {
    stop(
      "Benchmark output already exists but is incomplete. Set SCSPOTLIGHT_BENCHMARK_REBUILD=true after removing the generated benchmark directory.",
      call. = FALSE
    )
  }

  dir.create(paths$bundle_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(paths$bundle_dir, "reductions"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(paths$bundle_dir, "expression"), recursive = TRUE, showWarnings = FALSE)

  cell_idx <- seq_len(cell_count) - 1L
  cell_id <- sprintf("BenchmarkCell_%07d", seq_len(cell_count))
  cluster_levels <- sprintf("cluster_%02d", seq_len(20L))
  batch_levels <- c("batch_a", "batch_b")

  arrow::write_parquet(
    data.frame(cell_idx = cell_idx, cell_id = cell_id, stringsAsFactors = FALSE),
    file.path(paths$bundle_dir, "cells.parquet"),
    compression = "zstd"
  )

  arrow::write_parquet(
    data.frame(
      .scspotlight_cell_idx = cell_idx,
      orig.ident = rep("synthetic_structural_1m", cell_count),
      cluster = cluster_levels[(cell_idx %% length(cluster_levels)) + 1L],
      batch = batch_levels[(cell_idx %% length(batch_levels)) + 1L],
      nFeature_RNA = 400L + (cell_idx %% 5000L),
      nCount_RNA = 1000L + (cell_idx %% 25000L),
      percent.mt = as.numeric(cell_idx %% 100L) / 10,
      stringsAsFactors = FALSE
    ),
    file.path(paths$bundle_dir, "metadata.parquet"),
    compression = "zstd"
  )

  angle <- as.numeric(cell_idx) / 5000
  arrow::write_parquet(
    data.frame(
      cell_idx = cell_idx,
      UMAP_1 = sin(angle) + as.numeric(cell_idx %% 97L) / 97,
      UMAP_2 = cos(angle) + as.numeric(cell_idx %% 89L) / 89
    ),
    file.path(paths$bundle_dir, "reductions", "umap.parquet"),
    compression = "zstd"
  )

  arrow::write_parquet(
    data.frame(
      feature_idx = c(0L, 1L),
      feature = c("BENCHMARK_GENE", "CONTROL_GENE"),
      assay = c("RNA", "RNA"),
      layer = c("data", "data"),
      block = c(0L, 0L),
      stringsAsFactors = FALSE
    ),
    file.path(paths$bundle_dir, "features.parquet"),
    compression = "zstd"
  )

  nonzero_idx <- seq.int(0L, cell_count - 1L, by = 20L)
  arrow::write_parquet(
    data.frame(
      feature_idx = rep.int(0L, length(nonzero_idx)),
      cell_idx = nonzero_idx,
      value = as.numeric((nonzero_idx %% 97L) + 1L) / 100
    ),
    file.path(paths$bundle_dir, "expression", "block_00000.parquet"),
    compression = "zstd"
  )

  jsonlite::write_json(
    list(
      bundle_type = "scspotlight_explore_parquet_bundle",
      schema_version = 2L,
      created_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      scspotlight_version = as.character(utils::packageVersion("scSpotlight")),
      assay = "RNA",
      layer = "data",
      assays = list(list(name = "RNA", layers = list("data"))),
      default_assay = "RNA",
      cell_count = cell_count,
      feature_count = 2L,
      block_size = 1024L,
      expression_layout = "feature_row_groups_v1",
      cell_identity = benchmark_cell_identity(cell_id),
      expression_compression = "zstd",
      reductions = "umap",
      benchmark_fixture = list(
        kind = "synthetic_structural_workload",
        purpose = "exercise the Explore Parquet, DuckDB, Arrow IPC, Shiny, and Chromium paths at one million cells",
        biological_representativeness = "not claimed"
      )
    ),
    paths$manifest,
    auto_unbox = TRUE,
    pretty = TRUE
  )

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(paths$root)
  zip::zipr(
    zipfile = paths$archive,
    files = basename(paths$bundle_dir),
    root = ".",
    recurse = TRUE,
    include_directories = TRUE,
    compression_level = 0L
  )
  paths
}
