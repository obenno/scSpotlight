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

benchmark_environment <- function() {
  memory <- tryCatch(readLines("/proc/meminfo", warn = FALSE), error = function(...) character())
  memory_line <- memory[startsWith(memory, "MemTotal:")]
  cpu_info <- tryCatch(readLines("/proc/cpuinfo", warn = FALSE), error = function(...) character())
  cpu_model_line <- cpu_info[startsWith(cpu_info, "model name")]
  memory_total_kb <- suppressWarnings(as.numeric(sub(
    "^MemTotal:[[:space:]]*([0-9]+).*$",
    "\\1",
    if (length(memory_line)) memory_line[[1]] else NA_character_
  )))

  list(
    timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    os = paste(Sys.info()[c("sysname", "release", "machine")], collapse = " "),
    r_version = R.version.string,
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
    available_cores = parallel::detectCores(logical = TRUE)
  )
}

benchmark_git_revision <- function() {
  revision <- tryCatch(
    system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE),
    error = function(...) character()
  )
  revision <- trimws(revision)
  if (length(revision) == 1L && nzchar(revision)) revision else NA_character_
}

benchmark_git_provenance <- function() {
  revision <- benchmark_git_revision()
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
      c("status", "--porcelain=v1", "--untracked-files=all"),
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
      c("diff", "--no-ext-diff", "--binary", "--full-index", "HEAD"),
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
      c("ls-files", "--others", "--exclude-standard"),
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
    if (!file.exists(path) || dir.exists(path)) {
      next
    }
    size <- unname(file.info(path)$size)
    writeBin(
      charToRaw(paste0("\n-- path: ", path, " size: ", size, " --\n")),
      snapshot_connection
    )
    if (is.finite(size) && size > 0) {
      writeBin(readBin(path, what = "raw", n = size), snapshot_connection)
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
      schema_version = 1L,
      created_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      scspotlight_version = as.character(utils::packageVersion("scSpotlight")),
      assay = "RNA",
      layer = "data",
      assays = list(list(name = "RNA", layers = list("data"))),
      default_assay = "RNA",
      cell_count = cell_count,
      feature_count = 2L,
      block_size = 1024L,
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
