test_that("dev pull requests run the release quality gates without deployment", {
  workflow_path <- scspotlight_test_source_path(
    ".github",
    "workflows",
    "pr-quality.yaml"
  )
  skip_if_not(
    file.exists(workflow_path),
    "GitHub workflows are intentionally excluded from built source archives."
  )

  workflow <- paste(readLines(workflow_path, warn = FALSE), collapse = "\n")

  expect_match(workflow, "pull_request:", fixed = TRUE)
  expect_match(workflow, "branches: [dev]", fixed = TRUE)
  expect_match(workflow, "pixi run test-r", fixed = TRUE)
  expect_match(workflow, "pixi run r-check", fixed = TRUE)
  expect_match(workflow, "pixi run test-js", fixed = TRUE)
  expect_match(workflow, "pixi run build-js", fixed = TRUE)
  expect_match(
    workflow,
    "git diff --exit-code -- inst/app/www/index.js inst/app/www/index.js.map",
    fixed = TRUE
  )
  expect_match(workflow, "pixi run install-e2e-browser-ci", fixed = TRUE)
  expect_match(workflow, "pixi run test-e2e", fixed = TRUE)
  expect_match(workflow, "pixi run test-e2e-llm", fixed = TRUE)
  expect_match(workflow, "pixi run check-optional-llm", fixed = TRUE)
  expect_no_match(workflow, "github-pages-deploy-action", fixed = TRUE)
  expect_no_match(workflow, "gh-pages", fixed = TRUE)
})

test_that("optional dependency profiles stay outside normal setup", {
  dependency_utils_path <- scspotlight_test_source_path("dev", "r_dep_utils.R")
  pixi_path <- scspotlight_test_source_path("pixi.toml")
  skip_if_not(
    all(file.exists(c(dependency_utils_path, pixi_path))),
    "Development setup tooling is intentionally excluded from built source archives."
  )

  dependency_environment <- new.env(parent = baseenv())
  sys.source(dependency_utils_path, envir = dependency_environment)
  pixi_text <- paste(readLines(pixi_path, warn = FALSE), collapse = "\n")
  old_wd <- setwd(scspotlight_test_source_path())
  on.exit(setwd(old_wd), add = TRUE)

  expect_identical(
    dependency_environment$optional_packages_for_profile("performance"),
    "presto"
  )
  expect_identical(
    dependency_environment$optional_packages_for_profile("llm"),
    c("ellmer", "later", "shinychat")
  )
  expect_error(
    dependency_environment$optional_packages_for_profile("unknown"),
    "Unknown optional package profile",
    fixed = TRUE
  )
  expect_match(pixi_text, "install-optional-llm", fixed = TRUE)
  expect_match(pixi_text, "check-optional-llm", fixed = TRUE)
  expect_match(pixi_text, "test-e2e-llm", fixed = TRUE)

  setup_lines <- readLines(pixi_path, warn = FALSE)
  setup_lines <- setup_lines[grepl("^(setup|setup-r) =", setup_lines)]
  expect_no_match(
    paste(setup_lines, collapse = "\n"),
    "install_optional_packages",
    fixed = TRUE
  )
})
