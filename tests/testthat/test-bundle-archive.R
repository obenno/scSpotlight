test_that("create_bundle_archive builds a zip bundle archive", {
  skip_if_not_installed("zip")

  create_bundle_archive <- getFromNamespace(
    "create_bundle_archive",
    "scSpotlight"
  )

  root_dir <- tempfile("bundle_archive_")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  bundle_dir <- file.path(root_dir, "bundle")
  dir.create(bundle_dir)
  writeLines("hello", file.path(bundle_dir, "README.txt"))

  archive_file <- file.path(root_dir, "bundle.zip")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(root_dir)

  expect_invisible(create_bundle_archive(archive_file, "bundle"))
  expect_true(file.exists(archive_file))

  extract_dir <- tempfile("bundle_extract_")
  dir.create(extract_dir)
  on.exit(unlink(extract_dir, recursive = TRUE, force = TRUE), add = TRUE)

  zip::unzip(archive_file, exdir = extract_dir)
  expect_true(file.exists(file.path(extract_dir, "bundle", "README.txt")))
})

test_that("is_absolute_bundle_path recognizes Windows and UNC paths", {
  is_absolute_bundle_path <- getFromNamespace(
    "is_absolute_bundle_path",
    "scSpotlight"
  )

  expect_true(is_absolute_bundle_path("C:/tmp/bundle.zip"))
  expect_true(is_absolute_bundle_path("C:\\tmp\\bundle.zip"))
  expect_true(is_absolute_bundle_path("\\\\server\\share\\bundle.zip"))
  expect_true(is_absolute_bundle_path("/tmp/bundle.zip"))
  expect_false(is_absolute_bundle_path("bundle.zip"))
})

test_that("create_bundle_archive preserves bundle paths across directories", {
  skip_if_not_installed("zip")

  create_bundle_archive <- getFromNamespace(
    "create_bundle_archive",
    "scSpotlight"
  )

  root_dir <- tempfile("bundle_archive_root_")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  work_root <- file.path(root_dir, "work")
  output_root <- file.path(root_dir, "output")
  dir.create(work_root)
  dir.create(output_root)

  bundle_dir <- file.path(work_root, "bundle")
  dir.create(bundle_dir)
  writeLines("hello", file.path(bundle_dir, "README.txt"))

  archive_file <- file.path(output_root, "bundle.zip")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(work_root)

  expect_invisible(create_bundle_archive(archive_file, "bundle"))
  expect_true(file.exists(archive_file))

  extract_dir <- tempfile("bundle_extract_crossdir_")
  dir.create(extract_dir)
  on.exit(unlink(extract_dir, recursive = TRUE, force = TRUE), add = TRUE)

  zip::unzip(archive_file, exdir = extract_dir)
  expect_true(file.exists(file.path(extract_dir, "bundle", "README.txt")))
})

test_that("decompress_matrix_input removes unrecognized default extractions", {
  skip_if_not_installed("zip")

  decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )

  root_dir <- tempfile("unrecognized_archive_")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  source_dir <- file.path(root_dir, "source")
  dir.create(source_dir)
  writeLines(
    "not a supported Dataset Artifact",
    file.path(source_dir, "README.txt")
  )

  archive_file <- file.path(root_dir, "unrecognized.zip")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(source_dir)
  zip::zipr(archive_file, "README.txt")

  temp_root <- file.path(root_dir, "extract")
  result <- decompress_matrix_input(
    basename(archive_file),
    archive_file,
    temp_root = temp_root
  )
  extraction_roots <- list.files(
    temp_root,
    pattern = "^matrixDir",
    full.names = TRUE,
    all.files = TRUE
  )

  expect_identical(result, character())
  expect_identical(extraction_roots, character())
})

test_that("archive validation rejects non-file and non-directory members", {
  assert_safe_archive_entries <- getFromNamespace(
    "assert_safe_archive_entries",
    "scSpotlight"
  )

  expect_error(
    assert_safe_archive_entries(
      list(
        entries = "matrix.mtx",
        types = "fifo",
        uncompressed_sizes = 0
      ),
      archive_type = "tar"
    ),
    "unsafe entries"
  )
})

test_that("archive validation enforces entry-count limits", {
  assert_safe_archive_entries <- getFromNamespace(
    "assert_safe_archive_entries",
    "scSpotlight"
  )
  withr::local_options(scSpotlight.archive.max_entries = 2L)

  expect_error(
    assert_safe_archive_entries(
      list(
        entries = c("a", "b", "c"),
        types = rep("file", 3L),
        uncompressed_sizes = rep(1, 3L)
      ),
      archive_type = "zip"
    ),
    "too many entries"
  )
})

test_that("tar archives containing FIFOs are rejected before extraction", {
  skip_on_os("windows")
  skip_if(Sys.which("tar") == "")
  skip_if(Sys.which("mkfifo") == "")

  decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  root_dir <- tempfile("fifo_archive_")
  source_dir <- file.path(root_dir, "source")
  temp_root <- file.path(root_dir, "extract")
  dir.create(source_dir, recursive = TRUE)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  fifo_path <- file.path(source_dir, "matrix.mtx")
  expect_equal(system2(Sys.which("mkfifo"), fifo_path), 0L)
  archive_file <- file.path(root_dir, "fifo.tar.gz")
  expect_equal(
    system2(
      Sys.which("tar"),
      c("-czf", archive_file, "-C", source_dir, "matrix.mtx")
    ),
    0L
  )

  expect_error(
    decompress_matrix_input(
      basename(archive_file),
      archive_file,
      temp_root = temp_root
    ),
    "unsafe entries"
  )
  expect_false(dir.exists(temp_root) && length(list.files(temp_root)) > 0L)
})

test_that("tar PAX metadata consumes the preflight expanded-byte budget", {
  skip_on_os("windows")
  skip_if(Sys.which("tar") == "")

  decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  list_tar_archive_entries <- getFromNamespace(
    "list_tar_archive_entries",
    "scSpotlight"
  )
  root_dir <- tempfile("pax_archive_")
  source_dir <- file.path(root_dir, "source")
  temp_root <- file.path(root_dir, "extract")
  dir.create(source_dir, recursive = TRUE)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  file_name <- paste0(strrep("a", 180L), ".mtx")
  writeLines("1", file.path(source_dir, file_name))
  archive_file <- file.path(root_dir, "pax.tar.gz")
  expect_equal(
    system2(
      Sys.which("tar"),
      c("--format=pax", "-czf", archive_file, "-C", source_dir, file_name)
    ),
    0L
  )

  listed <- list_tar_archive_entries(archive_file)
  expect_gt(listed$preflight_expanded_size, sum(listed$uncompressed_sizes))
  withr::local_options(scSpotlight.archive.max_expanded_bytes = 100L)

  expect_error(
    decompress_matrix_input(
      basename(archive_file),
      archive_file,
      temp_root = temp_root
    ),
    "expanded-size limit"
  )
  expect_false(dir.exists(temp_root) && length(list.files(temp_root)) > 0L)
})

test_that("unsafe PAX metadata is rejected before extraction", {
  decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  root_dir <- tempfile("duplicate_pax_archive_")
  temp_root <- file.path(root_dir, "extract")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  encode_base256 <- function(value, width) {
    field <- raw(width)
    for (index in rev(seq_len(width))) {
      field[[index]] <- as.raw(value %% 256L)
      value <- value %/% 256L
    }
    field[[1L]] <- as.raw(bitwOr(as.integer(field[[1L]]), 128L))
    field
  }
  pax_record <- function(key, value) {
    body <- paste0(key, "=", value, "\n")
    record_length <- nchar(body, type = "bytes") + 3L
    repeat {
      record <- paste0(record_length, " ", body)
      actual_length <- nchar(record, type = "bytes")
      if (actual_length == record_length) {
        return(record)
      }
      record_length <- actual_length
    }
  }
  tar_header <- function(name, size, type_flag, base256 = FALSE) {
    header <- raw(512L)
    name_bytes <- charToRaw(name)
    header[seq_along(name_bytes)] <- name_bytes
    header[101:108] <- c(charToRaw("0000644"), as.raw(0))
    header[125:136] <- if (isTRUE(base256)) {
      encode_base256(size, 12L)
    } else {
      c(charToRaw(sprintf("%011o", size)), as.raw(0))
    }
    header[137:148] <- c(charToRaw("00000000000"), as.raw(0))
    header[[157L]] <- charToRaw(type_flag)
    header[258:262] <- charToRaw("ustar")
    header[263:264] <- charToRaw("00")
    header[149:156] <- charToRaw("        ")
    checksum <- sum(as.integer(header))
    header[149:156] <- c(
      charToRaw(sprintf("%06o", checksum)),
      as.raw(0),
      charToRaw(" ")
    )
    header
  }

  pax_payloads <- list(
    duplicate_size = paste0(
      pax_record("size", "2"),
      pax_record("size", "8388608")
    ),
    sparse = pax_record("GNU.sparse.realsize", "12884901888")
  )

  for (case_name in names(pax_payloads)) {
    archive_file <- file.path(root_dir, paste0(case_name, ".tar.gz"))
    pax_payload <- pax_payloads[[case_name]]
    pax_size <- nchar(pax_payload, type = "bytes")
    connection <- gzfile(archive_file, open = "wb")
    writeBin(c(
      tar_header("PaxHeader", pax_size, "x"),
      charToRaw(pax_payload),
      raw((512L - pax_size %% 512L) %% 512L),
      tar_header("matrix.mtx", 2L, "0", base256 = TRUE),
      charToRaw("1\n"),
      raw(510L),
      raw(1024L)
    ), connection)
    close(connection)

    extraction_started <- FALSE
    testthat::local_mocked_bindings(
      extract_validated_tar_archive = function(...) {
        extraction_started <<- TRUE
      },
      .package = "scSpotlight"
    )

    expect_error(
      decompress_matrix_input(
        basename(archive_file),
        archive_file,
        temp_root = temp_root
      ),
      "unsafe metadata"
    )
    expect_false(extraction_started)
    expect_false(dir.exists(temp_root) && length(list.files(temp_root)) > 0L)
  }
})

test_that("tar control headers count against the archive entry limit", {
  decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  root_dir <- tempfile("pax_entry_limit_archive_")
  archive_file <- file.path(root_dir, "pax-entry-limit.tar.gz")
  temp_root <- file.path(root_dir, "extract")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  pax_record <- function(key, value) {
    body <- paste0(key, "=", value, "\n")
    record_length <- nchar(body, type = "bytes") + 3L
    repeat {
      record <- paste0(record_length, " ", body)
      actual_length <- nchar(record, type = "bytes")
      if (actual_length == record_length) {
        return(record)
      }
      record_length <- actual_length
    }
  }
  tar_header <- function(name, size, type_flag) {
    header <- raw(512L)
    name_bytes <- charToRaw(name)
    header[seq_along(name_bytes)] <- name_bytes
    header[101:108] <- c(charToRaw("0000644"), as.raw(0))
    header[125:136] <- c(charToRaw(sprintf("%011o", size)), as.raw(0))
    header[137:148] <- c(charToRaw("00000000000"), as.raw(0))
    header[[157L]] <- charToRaw(type_flag)
    header[258:262] <- charToRaw("ustar")
    header[263:264] <- charToRaw("00")
    header[149:156] <- charToRaw("        ")
    checksum <- sum(as.integer(header))
    header[149:156] <- c(
      charToRaw(sprintf("%06o", checksum)),
      as.raw(0),
      charToRaw(" ")
    )
    header
  }
  pax_payload <- pax_record("comment", "one")
  pax_size <- nchar(pax_payload, type = "bytes")
  connection <- gzfile(archive_file, open = "wb")
  writeBin(c(
    tar_header("PaxHeader.1", pax_size, "x"),
    charToRaw(pax_payload),
    raw((512L - pax_size %% 512L) %% 512L),
    tar_header("PaxHeader.2", pax_size, "x"),
    charToRaw(pax_payload),
    raw((512L - pax_size %% 512L) %% 512L),
    tar_header("matrix.mtx", 2L, "0"),
    charToRaw("1\n"),
    raw(510L),
    raw(1024L)
  ), connection)
  close(connection)
  withr::local_options(scSpotlight.archive.max_entries = 2L)

  extraction_started <- FALSE
  testthat::local_mocked_bindings(
    extract_validated_tar_archive = function(...) {
      extraction_started <<- TRUE
    },
    .package = "scSpotlight"
  )

  expect_error(
    decompress_matrix_input(
      basename(archive_file),
      archive_file,
      temp_root = temp_root
    ),
    "too many entries"
  )
  expect_false(extraction_started)
  expect_false(dir.exists(temp_root) && length(list.files(temp_root)) > 0L)
})

test_that("tar numeric metadata supports GNU base-256 sizes", {
  tar_octal_number <- getFromNamespace("tar_octal_number", "scSpotlight")
  field <- as.raw(c(128L, rep(0L, 10L), 128L))

  expect_identical(tar_octal_number(field, 1L, 12L), 128)
})

test_that("GNU base-256 tar sizes use a compatible validated extractor", {
  skip_if(Sys.which("tar") == "")

  decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  list_tar_archive_entries <- getFromNamespace(
    "list_tar_archive_entries",
    "scSpotlight"
  )
  root_dir <- tempfile("base256_archive_")
  archive_file <- file.path(root_dir, "base256.tar.gz")
  temp_root <- file.path(root_dir, "extract")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  encode_base256 <- function(value, width) {
    field <- raw(width)
    for (index in rev(seq_len(width))) {
      field[[index]] <- as.raw(value %% 256L)
      value <- value %/% 256L
    }
    field[[1L]] <- as.raw(bitwOr(as.integer(field[[1L]]), 128L))
    field
  }

  header <- raw(512L)
  name <- charToRaw("matrix.mtx")
  header[seq_along(name)] <- name
  header[101:108] <- c(charToRaw("0000644"), as.raw(0))
  header[125:136] <- encode_base256(2L, 12L)
  header[137:148] <- c(charToRaw("00000000000"), as.raw(0))
  header[[157L]] <- charToRaw("0")
  header[258:262] <- charToRaw("ustar")
  header[263:264] <- charToRaw("00")
  header[149:156] <- charToRaw("        ")
  checksum <- sum(as.integer(header))
  header[149:156] <- c(
    charToRaw(sprintf("%06o", checksum)),
    as.raw(0),
    charToRaw(" ")
  )
  connection <- gzfile(archive_file, open = "wb")
  writeBin(c(header, charToRaw("1\n"), raw(510L), raw(1024L)), connection)
  close(connection)

  listed <- list_tar_archive_entries(archive_file)
  expect_true(listed$uses_base256_numeric)

  data_dir <- decompress_matrix_input(
    basename(archive_file),
    archive_file,
    temp_root = temp_root
  )

  expect_true(file.exists(file.path(data_dir, "matrix.mtx")))
})

test_that("tar directories with payload sizes are rejected before extraction", {
  decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  root_dir <- tempfile("tar_directory_payload_")
  archive_file <- file.path(root_dir, "directory-payload.tar.gz")
  temp_root <- file.path(root_dir, "extract")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  header <- raw(512L)
  name <- charToRaw("safe-directory/")
  header[seq_along(name)] <- name
  size <- charToRaw(sprintf("%011o", 512L))
  header[seq.int(125L, length.out = length(size))] <- size
  header[[136L]] <- as.raw(0)
  header[[157L]] <- charToRaw("5")
  connection <- gzfile(archive_file, open = "wb")
  writeBin(c(header, raw(512L), raw(1024L)), connection)
  close(connection)

  expect_error(
    decompress_matrix_input(
      basename(archive_file),
      archive_file,
      temp_root = temp_root
    ),
    "unsafe entries"
  )
  expect_false(dir.exists(temp_root) && length(list.files(temp_root)) > 0L)
})

test_that("zip expanded-size limits are enforced before extraction", {
  skip_if_not_installed("zip")

  decompress_matrix_input <- getFromNamespace(
    "decompress_matrix_input",
    "scSpotlight"
  )
  root_dir <- tempfile("oversized_archive_")
  source_dir <- file.path(root_dir, "source")
  temp_root <- file.path(root_dir, "extract")
  dir.create(source_dir, recursive = TRUE)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  writeLines(strrep("x", 128L), file.path(source_dir, "README.txt"))
  archive_file <- file.path(root_dir, "oversized.zip")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(source_dir)
  zip::zipr(archive_file, "README.txt")
  withr::local_options(scSpotlight.archive.max_expanded_bytes = 64)

  expect_error(
    decompress_matrix_input(
      basename(archive_file),
      archive_file,
      temp_root = temp_root
    ),
    "expanded-size limit"
  )
  expect_false(dir.exists(temp_root) && length(list.files(temp_root)) > 0L)
})

test_that("convert_to_bpcells_bundle writes relative output beside caller cwd", {
  skip_if_not_installed("zip")
  skip_if_not_installed("BPCells")
  skip_if_not_installed("Seurat")

  convert_to_bpcells_bundle <- getFromNamespace(
    "convert_to_bpcells_bundle",
    "scSpotlight"
  )
  ensure_assay5 <- getFromNamespace("ensure_assay5", "scSpotlight")

  root_dir <- tempfile("bundle_convert_root_")
  dir.create(root_dir)
  on.exit(unlink(root_dir, recursive = TRUE, force = TRUE), add = TRUE)

  input_dir <- file.path(root_dir, "input")
  output_dir <- file.path(root_dir, "output")
  dir.create(input_dir)
  dir.create(output_dir)

  counts <- methods::as(
    Matrix::Matrix(matrix(c(1, 0, 2, 3), nrow = 2), sparse = TRUE),
    "dgCMatrix"
  )
  rownames(counts) <- c("g1", "g2")
  colnames(counts) <- c("c1", "c2")

  object <- Seurat::CreateSeuratObject(counts = counts)
  object <- ensure_assay5(object, assay = "RNA")
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts
  object[["percent.mt"]] <- c(0, 0)
  object[["pca"]] <- SeuratObject::CreateDimReducObject(
    embeddings = matrix(
      c(1, 2, 3, 4),
      ncol = 2,
      dimnames = list(colnames(counts), c("PC_1", "PC_2"))
    ),
    assay = "RNA",
    key = "PC_"
  )

  input_file <- file.path(input_dir, "object.Rds")
  saveRDS(object, input_file)

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(output_dir)

  output_file <- convert_to_bpcells_bundle(
    input_file,
    output_file = "converted.zip"
  )

  expect_equal(
    output_file,
    file.path(
      normalizePath(output_dir, winslash = "/", mustWork = TRUE),
      "converted.zip"
    )
  )
  expect_true(file.exists(output_file))
})
