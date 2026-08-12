browser_payload_contract_path <- scspotlight_test_source_path(
  "inst",
  "protocol",
  "browser-payload-contracts.json"
)

browser_payload_messages <- c(
  "meta_ready",
  "meta_patch_ready",
  "reduction_ready",
  "reductions_ready",
  "pca_ready",
  "expr_ready",
  "reduction_cached",
  "expr_cached",
  "transfer_error"
)

read_browser_payload_contract <- function() {
  skip_if_not_installed("jsonlite")
  expect_true(file.exists(browser_payload_contract_path))
  jsonlite::fromJSON(browser_payload_contract_path, simplifyVector = FALSE)
}

make_browser_payload_contract_object <- function() {
  counts <- Matrix::Matrix(
    c(
      1,
      0,
      2,
      0,
      3,
      0,
      4,
      0,
      5,
      0,
      6,
      1
    ),
    nrow = 3,
    sparse = TRUE
  )
  rownames(counts) <- c("GeneA", "GeneB", "GeneC")
  colnames(counts) <- paste0("Cell", seq_len(ncol(counts)))

  object <- Seurat::CreateSeuratObject(counts = counts)
  object <- getFromNamespace("ensure_assay5", "scSpotlight")(
    object,
    assay = "RNA"
  )
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- counts
  object$cluster <- factor(c("alpha", "beta", "alpha", "gamma"))
  object$quality <- c(0.1, Inf, NaN, 0.4)

  object[["umap"]] <- Seurat::CreateDimReducObject(
    embeddings = matrix(
      c(
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8
      ),
      nrow = 4,
      dimnames = list(colnames(counts), c("UMAP_1", "UMAP_2"))
    ),
    key = "UMAP_",
    assay = "RNA"
  )
  object[["pca"]] <- Seurat::CreateDimReducObject(
    embeddings = matrix(
      c(
        11,
        12,
        13,
        14,
        21,
        22,
        23,
        24
      ),
      nrow = 4,
      dimnames = list(colnames(counts), c("PC_1", "PC_2"))
    ),
    stdev = c(2.5, 1.25),
    key = "PC_",
    assay = "RNA"
  )

  object
}

flatten_payload_fields <- function(payload) {
  unlist(payload, recursive = TRUE, use.names = TRUE)
}

add_test_resource_prefix <- function(
  payload,
  resource_prefix = "data-test-session"
) {
  payload$resourcePrefix <- resource_prefix
  payload
}

payload_leaf_names <- function(payload) {
  flattened_names <- names(flatten_payload_fields(payload))
  unique(sub("^.*\\.", "", flattened_names))
}

expect_browser_payload_hides_local_paths <- function(contract, payload) {
  policy <- contract$browser_path_policy
  flattened_payload <- flatten_payload_fields(payload)
  forbidden_fields <- policy$forbidden_payload_fields
  file_fields <- policy$file_fields

  expect_false(any(payload_leaf_names(payload) %in% forbidden_fields))

  if (length(flattened_payload)) {
    path_like <- vapply(
      flattened_payload,
      function(value) {
        if (!is.character(value) || !length(value) || is.na(value)) {
          return(FALSE)
        }
        grepl("^(~|/|[A-Za-z]:[\\\\/])", value) ||
          grepl("[\\\\/]", value)
      },
      logical(1)
    )
    expect_false(any(path_like))

    flattened_names <- names(flattened_payload)
    for (file_field in file_fields) {
      matching <- flattened_payload[
        sub("^.*\\.", "", flattened_names) == file_field
      ]
      for (value in matching) {
        if (is.null(value) || is.na(value)) {
          next
        }
        expect_identical(value, basename(value))
      }
    }
  }
}

expect_payload_satisfies_contract <- function(contract, message_name, payload) {
  message_contract <- contract$messages[[message_name]]
  expect_false(is.null(message_contract), info = message_name)
  expect_true(
    all(message_contract$required_fields %in% names(payload)),
    info = message_name
  )
  expect_browser_payload_hides_local_paths(contract, payload)

  entry_required_fields <- message_contract$entry_required_fields
  if (!is.null(entry_required_fields) && "reductions" %in% names(payload)) {
    expect_true(length(payload$reductions) > 0)
    for (reduction_payload in payload$reductions) {
      expect_true(all(entry_required_fields %in% names(reduction_payload)))
      expect_browser_payload_hides_local_paths(contract, reduction_payload)
    }
  }
}

test_that("browser payload manifest enumerates XFER-05 message contracts", {
  contract <- read_browser_payload_contract()

  expect_true(all(
    c(
      "messages",
      "ipc_columns",
      "cache_versions",
      "browser_path_policy"
    ) %in%
      names(contract)
  ))
  expect_setequal(names(contract$messages), browser_payload_messages)

  for (message_name in browser_payload_messages) {
    expect_false(is.null(contract$messages[[message_name]]$required_fields))
  }

  expect_equal(
    contract$cache_versions$reduction$key_shape,
    "{reductionVersion}::{reductionName}"
  )
  expect_equal(
    contract$cache_versions$expression$key_shape,
    "{exprVersion}::{assay}::{geneName}"
  )
  expect_false(contract$browser_path_policy$allow_absolute_paths)
  expect_true(all(
    c(
      "filePath",
      "output_file",
      "matrix_dir",
      "path",
      "trace",
      "stack",
      "message",
      "conditionMessage"
    ) %in%
      contract$browser_path_policy$forbidden_payload_fields
  ))

  expect_equal(
    unlist(contract$messages$transfer_error$required_fields, use.names = FALSE),
    c("payloadType", "reasonCode", "version")
  )
  expect_true(all(
    c(
      "resourcePrefix",
      "reductionName",
      "activeReduction",
      "geneName",
      "assay",
      "cols"
    ) %in%
      unlist(
        contract$messages$transfer_error$optional_fields,
        use.names = FALSE
      )
  ))
})

test_that("transfer error payload helper satisfies the browser path policy", {
  contract <- read_browser_payload_contract()
  make_transfer_error_payload <- getFromNamespace(
    "make_transfer_error_payload",
    "scSpotlight"
  )

  raw_context <- list(
    filePath = "/tmp/scspotlight/meta.arrow",
    output_file = "/tmp/scspotlight/out.arrow",
    matrix_dir = "/tmp/scspotlight/matrix",
    path = "/tmp/scspotlight/raw-path",
    trace = "trace mentions /tmp/scspotlight/raw-path",
    stack = "stack mentions secret-frame",
    message = "raw condition message with /tmp/scspotlight/meta.arrow",
    conditionMessage = "raw condition text should not be exposed",
    reductionName = "/tmp/scspotlight/umap",
    activeReduction = "pca",
    geneName = "GeneA",
    assay = "RNA",
    cols = c("cluster", "/tmp/scspotlight/batch")
  )

  payloads <- list(
    make_transfer_error_payload("metadata", "write_failed", 100L, raw_context),
    make_transfer_error_payload(
      "reduction",
      "decode_failed",
      101L,
      raw_context
    ),
    make_transfer_error_payload(
      "reductions",
      "fetch_failed",
      102L,
      raw_context
    ),
    make_transfer_error_payload("pca", "write_failed", 103L, raw_context),
    make_transfer_error_payload(
      "metadata_patch",
      "write_failed",
      104L,
      raw_context
    ),
    make_transfer_error_payload(
      "expression",
      "write_failed",
      105L,
      raw_context
    )
  )

  for (payload in payloads) {
    expect_payload_satisfies_contract(contract, "transfer_error", payload)
    expect_true(
      payload$payloadType %in%
        c(
          "metadata",
          "metadata_patch",
          "reduction",
          "reductions",
          "pca",
          "expression"
        )
    )
    expect_equal(payload$reasonCode, as.character(payload$reasonCode))
    expect_false(any(
      payload_leaf_names(payload) %in%
        c(
          "filePath",
          "output_file",
          "matrix_dir",
          "path",
          "trace",
          "stack",
          "message",
          "conditionMessage"
        )
    ))

    flattened <- unname(flatten_payload_fields(payload))
    character_values <- flattened[vapply(flattened, is.character, logical(1))]
    expect_false(any(grepl(
      "raw condition|secret-frame|/tmp/scspotlight",
      character_values
    )))
  }

  expect_equal(payloads[[1]]$payloadType, "metadata")
  expect_equal(payloads[[2]]$reductionName, "umap")
  expect_equal(payloads[[5]]$cols, c("cluster", "batch"))
  expect_equal(payloads[[6]]$payloadType, "expression")
  expect_equal(payloads[[6]]$geneName, "GeneA")
  expect_equal(payloads[[6]]$assay, "RNA")
})

test_that("R browser payload producers satisfy the contract manifest", {
  skip_if_not_installed("Seurat")
  skip_if_not_installed("SeuratObject")
  skip_if_not_installed("arrow")
  skip_if_not_installed("BPCells")

  contract <- read_browser_payload_contract()
  ensure_bpcells_backing <- getFromNamespace(
    "ensure_bpcells_backing",
    "scSpotlight"
  )
  prepare_backend_metadata_transfer <- getFromNamespace(
    "prepare_backend_metadata_transfer",
    "scSpotlight"
  )
  write_backend_metadata_transfer <- getFromNamespace(
    "write_backend_metadata_transfer",
    "scSpotlight"
  )
  prepare_backend_reduction_transfer <- getFromNamespace(
    "prepare_backend_reduction_transfer",
    "scSpotlight"
  )
  write_backend_reduction_transfer <- getFromNamespace(
    "write_backend_reduction_transfer",
    "scSpotlight"
  )
  write_backend_pca_stdev_transfer <- getFromNamespace(
    "write_backend_pca_stdev_transfer",
    "scSpotlight"
  )
  prepare_backend_expression_transfer <- getFromNamespace(
    "prepare_backend_expression_transfer",
    "scSpotlight"
  )
  write_backend_expression_transfer <- getFromNamespace(
    "write_backend_expression_transfer",
    "scSpotlight"
  )

  object <- make_browser_payload_contract_object()
  work_dir <- tempfile("browser_payload_contract_")
  backend_root <- file.path(work_dir, "backend")
  transfer_dir <- file.path(work_dir, "transfer")
  dir.create(file.path(transfer_dir, "meta"), recursive = TRUE)
  dir.create(file.path(transfer_dir, "reduction"), recursive = TRUE)
  dir.create(file.path(transfer_dir, "expr"), recursive = TRUE)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  object <- ensure_bpcells_backing(
    object,
    root_dir = backend_root,
    assays = "RNA",
    layers = "data"
  )

  metadata_transfer <- prepare_backend_metadata_transfer(
    object,
    dir_path = file.path(transfer_dir, "meta"),
    meta_version = 10L,
    resource_prefix = "data-test-session"
  )
  metadata_payload <- write_backend_metadata_transfer(metadata_transfer)
  expect_payload_satisfies_contract(contract, "meta_ready", metadata_payload)
  metadata_table <- arrow::read_ipc_stream(metadata_transfer$filePath)
  expect_true(all(
    contract$ipc_columns$meta_ready$required %in% names(metadata_table)
  ))
  expect_equal(as.character(metadata_table$cells), colnames(object))

  patch_transfer <- prepare_backend_metadata_transfer(
    object,
    dir_path = file.path(transfer_dir, "meta"),
    meta_version = 11L,
    cols = "cluster",
    resource_prefix = "data-test-session"
  )
  patch_payload <- write_backend_metadata_transfer(patch_transfer)
  expect_payload_satisfies_contract(contract, "meta_patch_ready", patch_payload)
  expect_equal(patch_payload$cols, "cluster")
  patch_table <- arrow::read_ipc_stream(patch_transfer$filePath)
  expect_true(all(c("cells", "cluster") %in% names(patch_table)))
  expect_false("quality" %in% names(patch_table))
  expect_equal(as.character(patch_table$cells), colnames(object))

  reduction_transfer <- prepare_backend_reduction_transfer(
    object,
    reduction_name = "umap",
    dir_path = file.path(transfer_dir, "reduction"),
    reduction_version = 12L,
    resource_prefix = "data-test-session"
  )
  reduction_payload <- write_backend_reduction_transfer(reduction_transfer)
  expect_payload_satisfies_contract(
    contract,
    "reduction_ready",
    reduction_payload
  )
  reduction_table <- arrow::read_ipc_stream(reduction_transfer$filePath)
  expect_true(all(
    contract$ipc_columns$reduction_ready$required %in% names(reduction_table)
  ))
  expect_identical(names(reduction_table), c("X", "Y"))

  reductions_ready_payload <- list(
    reductions = list(reduction_payload),
    activeReduction = "umap",
    reductionVersion = 12L,
    resourcePrefix = "data-test-session"
  )
  expect_payload_satisfies_contract(
    contract,
    "reductions_ready",
    reductions_ready_payload
  )

  pca_payload <- write_backend_pca_stdev_transfer(
    object,
    dir_path = file.path(transfer_dir, "reduction"),
    reduction_version = 12L,
    resource_prefix = "data-test-session"
  )
  expect_payload_satisfies_contract(contract, "pca_ready", pca_payload)
  pca_table <- arrow::read_ipc_stream(
    file.path(transfer_dir, "reduction", pca_payload$stdevFile)
  )
  expect_true(all(
    contract$ipc_columns$pca_ready$required %in% names(pca_table)
  ))
  expect_identical(names(pca_table), "stdev")

  expression_transfer <- prepare_backend_expression_transfer(
    object,
    assay = "RNA",
    feature = "GeneC",
    dir_path = file.path(transfer_dir, "expr"),
    expr_version = 13L,
    backend_root = backend_root,
    resource_prefix = "data-test-session"
  )
  expression_payload <- write_backend_expression_transfer(expression_transfer)
  expect_payload_satisfies_contract(contract, "expr_ready", expression_payload)
  expect_identical(
    names(expression_payload),
    c("geneName", "assay", "exprVersion", "exprFile", "resourcePrefix")
  )
  expression_table <- arrow::read_ipc_stream(expression_transfer$output_file)
  expect_true(all(
    contract$ipc_columns$expr_ready$required %in% names(expression_table)
  ))
  expect_identical(names(expression_table), "expr")

  expect_payload_satisfies_contract(
    contract,
    "reduction_cached",
    list(reductionName = "umap", reductionVersion = 12L)
  )
  expect_payload_satisfies_contract(
    contract,
    "expr_cached",
    list(geneName = "GeneC", assay = "RNA", exprVersion = 13L)
  )

  payloads <- list(
    metadata_payload,
    patch_payload,
    reduction_payload,
    reductions_ready_payload,
    pca_payload,
    expression_payload
  )
  for (payload in payloads) {
    expect_false(any(
      c("filePath", "output_file", "matrix_dir") %in% names(payload)
    ))
  }
})

test_that("assignment metadata mutation reuses existing scoped patch contract", {
  contract <- read_browser_payload_contract()
  expect_true("meta_patch_ready" %in% names(contract$messages))
  expect_false("assignment_ready" %in% names(contract$messages))

  app_server_path <- scspotlight_test_source_path("R", "app_server.R")
  expect_true(file.exists(app_server_path))
  app_server_source <- paste(
    readLines(app_server_path, warn = FALSE),
    collapse = "\n"
  )

  expect_true(
    grepl("renameCluster-assignmentIntent", app_server_source, fixed = TRUE),
    info = "app_server.R must consume the bounded browser assignment intent"
  )
  expect_true(
    grepl("validate_assignment_intent", app_server_source, fixed = TRUE),
    info = "assignment intent must be validated before Seurat metadata mutation"
  )
  expect_true(
    grepl("metaPatchRequest", app_server_source, fixed = TRUE),
    info = "assignment completion should request an existing meta_patch_ready update"
  )
  expect_false(
    grepl("newMetaColData", app_server_source, fixed = TRUE),
    info = "assignment must not accept a browser-built full metadata column"
  )
})

test_that("browser IPC payload contracts require a session resource prefix", {
  contract <- read_browser_payload_contract()

  file_backed_messages <- c(
    "meta_ready",
    "meta_patch_ready",
    "reduction_ready",
    "reductions_ready",
    "pca_ready",
    "expr_ready"
  )

  for (message_name in file_backed_messages) {
    message_contract <- contract$messages[[message_name]]
    expect_true(
      "resourcePrefix" %in% message_contract$required_fields,
      info = paste(
        message_name,
        "must include the session-scoped resource prefix"
      )
    )
  }

  expect_equal(
    contract$browser_path_policy$allowed_path_shape,
    "resource_prefix_plus_basename"
  )

  index_source <- paste(
    readLines(
      scspotlight_test_source_path("srcjs", "index.js"),
      warn = FALSE
    ),
    collapse = "\n"
  )
  expect_match(
    index_source,
    "resourcePrefix",
    info = "browser fetch handlers must use the message resourcePrefix field"
  )
  expect_false(
    grepl("/data/(meta|reduction|expr)", index_source, perl = TRUE),
    info = "browser fetch handlers must not hard-code the global /data resource root"
  )
})
