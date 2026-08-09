# scSpotlight (development version)

- Category-selected subsets now resolve their membership server-side from active metadata rather than sending derived Cell IDs through the browser (#25).
- Lasso-selected Cell ID subsets now create guarded Analysis Versions and reject stale or invalid selections without altering the active Analysis (#23).
- Explore Mode now only accepts `.explore-parquet.zip` archives and no longer shows the Data Conversion panel.
- Explore Mode now streams metadata, reduction, and expression transfers from Parquet through chunked Arrow IPC writers to reduce server memory usage for large datasets.
- LLM Assistant can now be enabled with `run_app(enableLLM = TRUE)` for server-side, summary-only chat over the current scSpotlight state.
- Added duckerdb support in the R backend
- Used webR to handle the featurePlot on the clientside
- Gene expression transferred asynchronously
- Added gene expression sparkline
- Scatterplot and featureplot logic optimized
- Changed regular array to typed array to store reduction, meta and expression data in javascript
  
# scSpotlight 0.0.5

- Fixed a layout issue after updating bslib to v0.8.0

# scSpotlight 0.0.4

- Added cluster label widget to the scatter plot
- Added download function for main cluster plot
- Re-organized javascript code

# scSpotlight 0.0.2.9000

* Initial release of the app
