# Run the scSpotlight App

Run the scSpotlight App

## Usage

``` r
run_app(
  onStart = set_options,
  options = list(),
  enableBookmarking = NULL,
  uiPattern = "/",
  dataDir = NULL,
  runningMode = "processing",
  maxSize = 20 * 1000 * 1024^2,
  nCores = 2,
  ...
)
```

## Arguments

- onStart:

  A function that will be called before the app is actually run. This is
  only needed for `shinyAppObj`, since in the `shinyAppDir` case, a
  `global.R` file can be used for this purpose.

- options:

  Named options that should be passed to the `runApp` call (these can be
  any of the following: "port", "launch.browser", "host", "quiet",
  "display.mode" and "test.mode"). You can also specify `width` and
  `height` parameters which provide a hint to the embedding environment
  about the ideal height/width for the app.

- enableBookmarking:

  Can be one of `"url"`, `"server"`, or `"disable"`. The default value,
  `NULL`, will respect the setting from any previous calls to
  [`enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html).
  See
  [`enableBookmarking()`](https://rdrr.io/pkg/shiny/man/enableBookmarking.html)
  for more information on bookmarking your app.

- uiPattern:

  A regular expression that will be applied to each `GET` request to
  determine whether the `ui` should be used to handle the request. Note
  that the entire request path must match the regular expression in
  order for the match to be considered successful.

- dataDir:

  Direcotry path of the input data, user could put the large dataset in
  the direcoty to avoid uploading files

- runningMode:

  The running mode of the app. This could be "processing" (default) or
  "viewer". The "processing" mode allows users to process input data by
  Seurat package while in "viewer" mode, user will only be able to view
  the dimension reduction result and query gene expressions.

- maxSize:

  Maximum allowed total size (in bytes) of global variables identified,
  see future.globals.maxSize.

- nCores:

  Number of the threads to use (by
  [`future::plan()`](https://future.futureverse.org/reference/plan.html)).

- ...:

  arguments to pass to golem_opts. See
  [`?golem::get_golem_options`](https://thinkr-open.github.io/golem/reference/get_golem_options.html)
  for more details.

## Examples

``` r
if (FALSE) { # \dontrun{
 ## Run app in processing mode
 run_app()

 ## Run app in viewer mode and load data in dataDir
 run_app(runningMode = "viewer", dataDir = "/path/to/data")

 ## Run app on port 8081, shiny::runApp() options need to be wrapped in a list
 run_app(options = list(port = 8081, host ="0.0.0.0", launch.browser = FALSE), runningMode = "processing")
} # }
```
