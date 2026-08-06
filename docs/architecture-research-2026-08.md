# Architecture Research: Million-Cell Single-Cell Analyzer and Visualizer

**Research date:** August 6, 2026
**Question:** For a fast, memory-efficient single-cell transcriptome analyzer and visualizer that must handle millions of cells, should the existing R/Shiny application be retained, hybridized, or replaced?

## Scope and Source Policy

This note uses only primary sources: official project documentation, formal specifications, official source repositories, and original research papers. Secondary comparisons, vendor summaries, blog posts, and benchmark aggregations were excluded.

The terms **stable** and **version-sensitive** are used deliberately:

- **Stable** means a design property specified by a format, protocol, or long-standing project contract. It is still subject to implementation bugs.
- **Version-sensitive** means an API, maturity label, benchmark, browser capability, or implementation detail that must be rechecked before making a release decision.

The note evaluates architecture, not a product implementation plan. It assumes that the application needs both analysis workflows and interactive browser visualization, and that the raw expression matrix may be larger than RAM.

## Executive Conclusion

The strongest evidence favors **hybridization rather than a wholesale rewrite**.

1. **Retain R/Shiny and Seurat/BPCells for Seurat-centric analysis and the existing user workflow.** Seurat's current official workflows keep large assay layers on disk, load only selected or sketched cells into memory, and demonstrate 1.3 million-cell analysis. BPCells documents lazy, streaming operations and bit-packed disk storage. These properties address the main matrix-size problem without abandoning the R ecosystem. [S1][S2][S3]
2. **Move the scalable query boundary away from a live, fully materialized session object.** A query-ready store such as TileDB-SOMA, or a deliberately designed combination of Zarr, Parquet, and Arrow, is better suited to shared data, cloud/object storage, cross-language access, and bounded slices. The most direct precedent is CZ CELLxGENE Census, which combines TileDB-SOMA, out-of-core iteration, Arrow-compatible outputs, and R/Python interoperability. [S10][S11][S12][S13]
3. **Retain WebGL/deck.gl as the production browser rendering path.** The current deck.gl documentation provides concrete guidance for million-point rendering, binary attributes, workers, and chunked asynchronous loading. Its current WebGPU documentation still labels WebGPU support as work in progress and notes that picking is unavailable on that path. WebGPU should therefore be an optional capability, not the baseline contract. [S18][S19][S20][S21]
4. **Replace the application only if the primary product requirement changes to a shared, cloud-scale corpus service with many concurrent users and first-class Python/scverse interoperability.** CELLxGENE demonstrates that architecture, but replacing the application would also replace Seurat behavior, R package compatibility, Shiny interaction semantics, and existing deployment assumptions. [S12][S22]

The central architectural fact is that **out-of-core storage does not imply out-of-core computation or out-of-core browser state**. A disk-backed matrix can still be materialized by a downstream operation; a chunked server response can still be concatenated in the browser; and a GPU buffer can still exceed browser or device limits. The system must bound memory at every boundary.

## Decision Criteria

| Requirement | Decisive architectural question | Consequence |
| --- | --- | --- |
| Matrix larger than RAM | Can the source matrix and every expensive intermediate be read incrementally? | Use a disk/object-store representation and algorithms that do not require a full dense result. |
| Millions of cells in a plot | Is the browser receiving a reduction and selected attributes, or the expression matrix? | Transfer only reductions, categorical codes, and requested feature vectors; use binary buffers and chunks. |
| Several users | Is state local to a session, a worker, or a shared query service? | Do not assume that a live Seurat, AnnData, or query object is safe to share across requests. |
| Cross-language analysis | Is there a stable interchange and query contract? | Arrow, Zarr, Parquet, and SOMA reduce language coupling; RDS and package-specific directories do not. |
| Cloud or object storage | Can the format perform selective reads without local-file assumptions? | Prefer object-store-aware stores and range/chunk reads; validate network request amplification. |
| Seurat fidelity | Are existing Seurat methods, plots, and R extensions part of the product contract? | Retaining an R analysis plane has substantial value. |
| Deployment simplicity | Can the deployment provide enough memory per worker and isolate long jobs? | Shiny remains viable for controlled deployments, but worker count multiplies memory pressure. |

## 1. Seurat v5, BPCells, and R/Shiny

### Seurat and BPCells strengths

Seurat v5 explicitly supports on-disk storage for large single-cell datasets. Its sketch-analysis documentation describes an on-disk connection created by `BPCells::open_matrix_dir`, reports a 1.3 million-cell object whose in-memory Seurat representation is under 1 GB in the example environment, and keeps a 50,000-cell sketch in memory while retaining the full dataset on disk. The same workflow projects learned reductions and labels back to the full dataset. These are architectural patterns, not merely faster matrix routines: keep the full assay cold and make a bounded working set interactive. [S1][S28]

The Seurat/BPCells interaction vignette describes a Seurat object that remains in memory while counts are accessed from on-disk BPCells matrices. It also shows multiple h5ad-derived layers forming a 1.5 million-cell object and explicitly demonstrates coercing a layer to an in-memory `dgCMatrix` when desired. The last operation is important: the memory boundary is controlled by the caller, and a conversion can undo the disk-backed benefit. [S2]

BPCells' own documentation describes two relevant properties:

- **Streaming:** only a minimal amount of data is held while a computation runs, with little intermediate state.
- **Lazy evaluation:** matrix or fragment work is delayed until an R object or disk output is requested.

The official repository also reports bit-packing, C++-based disk-backed processing, AnnData interoperability, and project-specific benchmarks ranging from 1.3 million cells to a 44 million-cell Census matrix. Those benchmark numbers are useful evidence that the design can scale, but they are version-sensitive, workload-specific, and not a guarantee for arbitrary Seurat functions or hardware. [S3][S4]

**Architectural implication:** Seurat plus BPCells is a credible analysis engine for million-cell datasets when the application preserves the on-disk boundary, limits in-memory assays to sketches or selected subsets, and audits every operation that returns a full vector, matrix, graph, or data frame. It is not accurate to treat the entire Seurat object as automatically out-of-core.

### R memory behavior

R's official internals document that assignment can share an object until mutation, after which duplication may be required. This preserves R's call-by-value programming model but means that seemingly harmless transformations, coercions, subsetting, or mutation of large vectors can create additional memory pressure. The exact allocation behavior is implementation- and expression-dependent, so the design should measure peak resident memory rather than infer it from object size alone. [S5]

This matters at the following boundaries:

- A sparse on-disk assay can be turned into an in-memory sparse or dense matrix by an explicit coercion or by a function that requires one.
- Cell metadata and reductions are often naturally represented as one value per cell; at several million cells, repeated copies or string-heavy representations can dominate the assay itself.
- Graphs and neighbor structures can scale with cell count and may have very different memory behavior from the expression layer.
- Passing a live object into a background process can serialize or duplicate more state than passing a path and a query description.

The last two points are architectural inferences from the object and transfer semantics. They should be validated with peak-memory measurements for the specific workflows rather than treated as a universal property of every Seurat function.

### Shiny execution and concurrency

Posit's official Shiny documentation states that long-running work inside a reactive context blocks the rest of the application, including other users sharing the affected R process. The documented `ExtendedTask` pattern moves the slow work outside the reactive graph and, with `future_promise()` and a multisession plan, into a separate R process. Inputs must be passed as explicit, eagerly evaluated task arguments; reactive values cannot be read directly in the background function. A single `ExtendedTask` object queues a later invocation instead of running the same task concurrently. [S6]

These semantics are useful, but they do not make a live Seurat object a scalable shared service:

- Background work needs a bounded input contract, ideally a path, version, selection predicate, and operation parameters rather than a copied object graph.
- A separate R process improves responsiveness but adds process memory and serialization costs.
- Per-session or per-worker analysis state remains process-local unless an explicit shared storage/query layer is introduced.
- A queued task is appropriate for expensive user actions, but it is not a general-purpose high-concurrency query scheduler.

Shiny deployment documentation describes R worker processes, configurable worker and connection counts, multiple application instances, and termination when a process exceeds its memory limit. The shinyapps.io documentation further states that each instance has its own copy of code, packages, and data, and that local files are not shared between instances. This is a practical constraint for large local artifacts: scaling workers or instances can multiply cold-start and resident-memory footprints unless the large data is externalized or shared through a suitable storage layer. [S7][S8]

**Assessment of R/Shiny:**

| Dimension | Assessment |
| --- | --- |
| Out-of-core assay access | Strong with BPCells, but operation-specific. |
| Chunked computation | Strong when BPCells or explicit chunked writers are used; ordinary R returns can still materialize. |
| Multi-user concurrency | Adequate for controlled worker/process scaling; weak as an implicit shared query engine. |
| Seurat compatibility | Strongest option. |
| Deployment | Mature and straightforward for R organizations; memory limits and worker isolation remain important. |
| Cross-language interchange | Possible through h5ad, Arrow, Parquet, and other bridges, but not inherent in RDS or a live Seurat object. |

The current repository's documented boundary already follows the favorable pattern: Seurat/BPCells as the Analysis Mode source of truth, Arrow IPC for browser transfer, Parquet for Explore artifacts, and deck.gl for the main scatter path. The research evidence supports retaining that conceptual split while making its memory and concurrency contracts explicit.

## 2. AnnData, Zarr, and the Python Ecosystem

### AnnData's object model and backing modes

AnnData is an annotated observations-by-variables matrix. Its documented structure aligns `obs`, `var`, `obsm`, `varm`, `obsp`, `varp`, and `layers` to the matrix dimensions. Subsetting returns a lazy view with little additional memory, while modifying a view can create a real object through copy-on-modify. The API exposes `chunked_X` for iteration over matrix rows and `to_memory` for explicitly loading non-memory arrays. [S9][S29]

AnnData can use an h5ad backing file, HDF5 datasets, Zarr arrays, and sparse dataset abstractions. The current documentation is explicit that backed data remains on disk but can be automatically loaded into memory when needed. The current `scanpy.read_h5ad` documentation distinguishes backed mode from fully loaded memory mode, supports chunked reading for some dense-to-sparse conversions, and states that only `X` updates are currently supported in backed mode. These details make backed AnnData useful, but not equivalent to a query server or a guarantee that every Scanpy operation is out-of-core. [S9][S10]

Scanpy's official documentation describes the toolkit as capable of handling datasets above one million cells and says that many functions have compatibility with Dask for datasets too large to fit in memory, while warning that this support is experimental. The original Scanpy paper establishes the scalable Python analysis toolkit, but current Dask coverage and function behavior are version-sensitive. [S11][S30]

### Zarr's storage contract

The Zarr v3.1 specification defines a format for multidimensional typed arrays. An array has a hierarchy location, shape, data type, chunk grid, chunk-key encoding, codecs, and a store. The specification explicitly motivates parallel and distributed computing and allows stores backed by ordinary files or object storage such as S3. It also defines partial value reads and extensibility points. [S13]

Zarr therefore supplies a strong physical storage substrate for chunked array access, but it does not itself define:

- A single-cell schema for observations, variables, embeddings, graphs, and assays.
- A query planner for cell metadata predicates.
- A concurrency policy for an application server.
- A guarantee that a chosen chunk shape is efficient for both cell-oriented and gene-oriented access.

Those responsibilities belong to AnnData conventions, SOMA, or an application-specific query layer. Chunk shape is an architectural decision: chunks optimized for row-wise cell retrieval can be poor for gene-wise expression queries, and vice versa. Object storage also makes request count and range-read amplification part of the performance budget.

### Python ecosystem tradeoffs

The Python path has the strongest native alignment with AnnData, Zarr, Scanpy, Dask, and TileDB-SOMA. It is attractive when the application must expose current scverse workflows, Python machine-learning libraries, or cloud-hosted single-cell collections.

The tradeoff is that Python ecosystem compatibility does not automatically prevent materialization. Converting to NumPy or pandas, calling `AnnData.to_memory`, requesting a full query result, or using a function that is not Dask-aware can move the workload back into RAM. The important distinction is between:

- A lazy or backed representation.
- A chunked algorithm that consumes that representation incrementally.
- A convenience API that returns a conventional in-memory object.

Replacing R with Python without changing those boundaries would not, by itself, solve the memory problem.

## 3. TileDB-SOMA and Comparable Scalable Storage

### SOMA's architectural value

The SOMA specification defines a general model for one or more annotated two-dimensional matrices, motivated by single-cell data. The official project description identifies larger-than-memory storage and access, query-ready data management, cloud-scale low-latency access, and R/Python APIs as design goals. The TileDB-SOMA implementation uses TileDB Embedded and represents data frames plus sparse and dense multidimensional arrays. Its in-memory type and schema system is based on Apache Arrow. [S14][S15]

Compared with a plain AnnData file or a raw Zarr hierarchy, SOMA adds domain-level concepts that matter to a query service:

- Separate observation and variable axes.
- Coordinate and value-filter queries.
- Sparse measurement layers.
- Query objects that can expose data incrementally.
- Interoperable Arrow-based tables and language bindings.

The current `ExperimentAxisQuery` documentation states that an experiment can be sliced by observation or variable coordinates and value filters, and that sparse `X` layers can be read incrementally. It also states three important limitations: the query class is not thread-safe, it assumes the full results of both axis dataframe queries can be held in memory, and dense `X` slicing is not supported by that API at the time of the documentation snapshot. It can export a query to an in-memory AnnData object, which is convenient but explicitly materializing. [S16]

These limitations do not negate SOMA's value. They define the boundary that a service must respect: create isolated query objects, bound axis metadata, stream measurement chunks, and avoid exporting a large result to an in-memory convenience object unless the result is intentionally small.

### Census as a primary precedent

The CZ CELLxGENE Discover paper describes a platform that ingests h5ad data, produces an internal visualization format, makes Seurat and AnnData downloads available, and uses TileDB-SOMA for scalable programmatic access. It reports an Explorer path for individual datasets up to 4.3 million cells, a custom WebGL renderer, and a Census architecture based on out-of-core data access. The paper describes fixed-size chunks, incremental algorithms, and examples of computing over more than 65 million cells within an 8 GB laptop memory budget. These are reported system results under specified workloads, not universal performance guarantees. [S12]

The current Census documentation describes a cloud-hosted SOMA object and API, cell-based slicing, query access by cell or gene metadata, and exports to AnnData, Seurat, SingleCellExperiment, PyArrow, R Arrow, sparse matrices, NumPy, pandas, and standard R data structures. It is a concrete example of a shared storage/query layer serving both Python and R consumers without requiring the browser to receive the full corpus. [S17]

### SOMA versus AnnData/Zarr versus BPCells

| Property | BPCells plus Seurat | AnnData plus Zarr | TileDB-SOMA |
| --- | --- | --- | --- |
| Primary abstraction | R/Seurat assay and matrix operations | Python annotated matrix | Queryable annotated collections, axes, and measurement arrays |
| Out-of-core goal | Disk-backed streaming matrix operations | Backed/chunked arrays; operation-dependent | Explicit larger-than-memory query and slice access |
| Sparse matrix support | Strong for supported BPCells paths | Supported through sparse arrays/datasets; operation-dependent | Explicit sparse measurement arrays and incremental reads |
| Cloud/object storage | Not the core abstraction | Zarr stores can target object storage | Explicit local and cloud storage/query use case |
| Cross-language contract | R first, bridges available | Python first, broad ecosystem | Arrow-based; R/Python APIs and exports |
| Main caveat | Seurat functions can materialize or densify | Backed mode is not universal lazy execution | Query objects and axis results have current thread-safety/memory limits |

SOMA is the strongest candidate when the product needs a shared query plane over many datasets. It is not a drop-in replacement for Seurat's analysis semantics or BPCells' local matrix representation. Introducing it creates a second data model and requires explicit schema and provenance rules.

## 4. Arrow, Parquet, DuckDB, and IPC Paths

### Arrow

The Apache Arrow specification defines a language-agnostic columnar in-memory format, metadata serialization, and transport protocols. It is designed for sequential scans, random access, SIMD-friendly layouts, relocatability, and zero-copy access in appropriate shared-memory contexts. Arrow IPC serializes record batches as a schema followed by binary buffers; the specification describes reconstructing arrays from message metadata without copying the record-batch body. Large logical arrays can be represented as multiple chunks. [S18]

This makes Arrow a strong boundary between R, C++, Python, and JavaScript for:

- Cell metadata columns.
- Reduction coordinates.
- Selected expression vectors.
- Sparse coordinate batches.
- Query results that should be consumed incrementally.

Arrow IPC is **not** a storage engine, query planner, or memory budget. A producer can still build a full data frame before writing the first record batch, and a client can still concatenate every batch into one large object. End-to-end zero-copy into a browser GPU buffer is not implied by the Arrow format; it depends on the implementation and the subsequent decode/upload path.

### Parquet

The Parquet specification defines a column-oriented file format organized into row groups, column chunks, and pages. File metadata identifies the locations of column chunks, and readers are expected to inspect metadata and read only the column chunks of interest. The format supports compression, encoding, statistics, and parallelization at row-group and column-chunk boundaries. [S19]

Parquet is therefore well suited to:

- Cell metadata stored in columns and partitioned by a predictable cell or dataset key.
- Reduction tables.
- Feature summaries.
- Long-form or block-oriented expression payloads where the query pattern is known.

Parquet is not, by itself, a natural replacement for an arbitrary sparse gene-by-cell matrix. A naive one-row-per-cell wide table creates very wide reads, while a one-row-per-nonzero long table can create large index and filter costs. A sparse array store or BPCells-like representation is usually a better primary assay substrate; Parquet can remain a query and interchange layer around it.

### DuckDB

The DuckDB paper describes an embedded analytical database designed for efficient query execution, and current DuckDB documentation describes larger-than-memory processing through disk spilling, row-group-based parallelism, predicate/filter pushdown for remote Parquet, and query-plan inspection. The same documentation lists limitations for some blocking operators and aggregates, and states that DuckDB is not primarily optimized for many small concurrent queries. [S20][S21][S31]

DuckDB's current concurrency documentation is especially relevant to a Shiny deployment: in-process read-write mode is contained within one process; multiple processes can read in read-only mode; multi-process writes require a different architecture. The documentation also describes a beta remote protocol in the current version snapshot. These details are version-sensitive. [S22]

**Recommended architectural role:** use DuckDB as an embedded query and transformation engine over Parquet or Arrow when its vectorized SQL model fits the access pattern. Do not make a single DuckDB file the implicit multi-process session database or a mirror of the Seurat source of truth without a deliberate concurrency and lifecycle design.

### Combined query and transfer path

The strongest division of responsibilities is:

| Layer | Suitable responsibility | Avoid |
| --- | --- | --- |
| BPCells, Zarr, or SOMA | Primary sparse/out-of-core assay access | Returning a full dense matrix by convenience. |
| Parquet | Columnar metadata, reductions, summaries, and block-oriented artifacts | Treating arbitrary sparse matrix access as a free consequence of columnar storage. |
| DuckDB | Filter, aggregate, join, and inspect columnar artifacts | Shared multi-process mutable state by accident. |
| Arrow IPC | Bounded record-batch transport between processes/languages/browser | Assuming serialization alone controls producer or consumer memory. |
| Browser TypedArrays/GPU buffers | Rendering-ready reductions and selected attributes | Keeping all metadata as repeated JavaScript strings or rebuilding all GPU buffers on every interaction. |

The current repository's Arrow IPC and Parquet boundaries are therefore architecturally sound. The main risk is not the formats; it is whether each writer and reader preserves bounded, chunked behavior.

## 5. Browser Visualization: WebGL, deck.gl, and WebGPU

### WebGL and deck.gl

Khronos describes WebGL as a cross-platform, royalty-free web standard based on OpenGL ES and exposed through the HTML canvas. It is mature enough to be the compatibility baseline for GPU scatter rendering. [S23]

The official deck.gl performance documentation provides several facts directly relevant to millions of cells:

- Its example expectations describe fluid basic layers up to about one million items on older laptop hardware, with materially lower frame rates near ten million.
- Browser contiguous-allocation limits can cause failures during GPU buffer generation well before the data is conceptually too large; the documentation gives Chrome's individual allocation cap as an example and recommends chunking into multiple layers.
- Updating a layer's `data` can regenerate all GPU buffers, so repeated full-array replacement is expensive.
- Async iterables or one layer per chunk allow incremental loading without rebuilding earlier buffers.
- Binary typed-array data, worker transfer, and externally supplied attributes avoid JavaScript object-array overhead and CPU-side accessor generation.
- Picking has a per-layer item limit and incurs an additional rendering pass; pickability should be disabled when it is not required.

These facts imply that a million-cell viewer should treat the data plane and render plane separately. The server should return stable, compact buffers; the browser should retain them and update only changed attributes; and the application should degrade picking, point size, or detail before attempting to upload an unbounded full-resolution representation. [S18][S20]

### WebGPU

The W3C WebGPU specification exposes rendering and compute operations on a GPU through adapters, devices, buffers, textures, command encoders, render pipelines, and compute pipelines. The current specification snapshot is a Candidate Recommendation Draft dated July 14, 2026. This status and the exact feature set are version-sensitive. [S24]

The current deck.gl WebGPU documentation is more restrictive than the existence of the WebGPU API itself: deck.gl v9 support is described as work in progress and not production ready; support is layer-by-layer; picking is currently skipped on WebGPU; and many extensions and composite layers remain WebGL-only. `ScatterplotLayer` is listed as having a current WebGPU implementation, but that does not make the whole deck.gl feature surface portable. [S21]

**Assessment:** keep WebGL as the production path and design the rendering contract so a future WebGPU implementation can consume the same typed buffers. A WebGPU-first rewrite would add browser capability, shader, picking, and fallback risk without addressing server-side matrix materialization.

## 6. Roles for R, Python, C++, Rust, and JavaScript

The evidence does not support choosing one language as universally superior. It supports assigning each language to the boundary where its ecosystem and memory model are most valuable.

| Language | Strong role | Realistic tradeoff |
| --- | --- | --- |
| R | Seurat workflows, statistical methods, existing package compatibility, Shiny session orchestration | Live objects and ordinary vector/data-frame operations can be memory-heavy; reactive work must be isolated; scaling workers multiplies process footprints. |
| Python | AnnData/Scanpy/scverse, SOMA clients, ML and GPU ecosystems, query-service orchestration | Backed/lazy data can be materialized by NumPy/pandas/convenience APIs; Dask coverage is function-dependent and currently documented as experimental in Scanpy. |
| C++ | Existing high-performance kernels in BPCells, TileDB Embedded, and DuckDB; native extensions for hot loops | ABI, compiler, packaging, cross-platform debugging, and ownership boundaries increase maintenance cost. |
| Rust | New memory-safe query/storage services, Arrow record-batch pipelines, async streaming, and explicit ownership boundaries | The surveyed single-cell application ecosystems are primarily R/Python; a Rust core still needs bindings, schema decisions, and reimplementation of domain algorithms. The official Arrow Rust API does provide zero-copy slices and lazy iterator/stream patterns. [S25] |
| JavaScript/TypeScript | Browser protocol, TypedArrays, WebGL/deck.gl rendering, workers, interaction state | Browser and GPU memory are separate constraints; object arrays, full buffer rebuilds, and overdraw can dominate even when the server is efficient. |

Rust's official language documentation describes ownership rules checked by the compiler and automatic cleanup at scope boundaries. That is valuable for a new long-lived service, but memory safety does not eliminate algorithmic materialization or network transfer costs. [S26]

The practical conclusion is to avoid a language rewrite as a proxy for an architecture fix. A C++ or Rust kernel is justified when profiling identifies a hot path that existing native libraries cannot cover, or when a shared service needs stronger control over concurrency and memory ownership. It is not justified merely because R or Python appears in the user-facing layer.

## 7. Existing Official Single-Cell Viewer Architectures

### CZ CELLxGENE Discover and Census

The CELLxGENE paper is the closest primary precedent for the full problem. It separates:

- Standardized uploaded data and downloadable AnnData/Seurat representations.
- An internal visualization representation.
- A query/API layer for cross-dataset access.
- A custom WebGL renderer for millions of points.

Its Explorer path reports dynamic exploration of individual datasets up to 4.3 million cells, while its Census path uses TileDB-SOMA and chunked out-of-core access across tens of millions of cells. The paper explicitly describes redesigning calculations that need random access or multiple passes into incremental or online algorithms. [S12]

This is evidence for a hybrid boundary even when the eventual product is Python-heavy: the viewer, query representation, and analysis/export objects need not be the same physical object.

### Vitessce

Vitessce's official documentation describes a modular framework for linked visualization of multimodal and spatial single-cell data. A JSON view configuration defines how data is retrieved, which views are rendered, and how views coordinate. The documentation states that datasets can be hosted as static files or object storage, including AnnData-Zarr stores, and that the framework can be used from JavaScript, Python, RStudio, and R Shiny. [S27]

Vitessce is therefore a strong precedent for a viewer component or viewer replacement, especially for multimodal/spatial requirements. It is not itself a replacement for Seurat, Scanpy, or a scalable query engine; its architecture assumes that suitable files and view configuration are available.

### What these precedents imply

The established systems do not send a raw, full expression matrix to a browser and ask the browser to solve scale. They standardize data, precompute or store query-ready representations, stream bounded slices, and use GPU rendering for the final point cloud. That pattern is compatible with the current scSpotlight direction and does not require an immediate application rewrite.

## 8. Stable Facts and Version-Sensitive Facts

### Relatively stable facts

- BPCells is designed around lazy and streaming matrix operations and disk-backed compressed data. [S2]
- AnnData has aligned observation, variable, layer, embedding, graph, and unstructured components. [S9]
- Zarr defines chunked multidimensional arrays, codecs, stores, and metadata. [S13]
- SOMA defines annotated matrix/query concepts and is designed for larger-than-memory single-cell data. [S14]
- Arrow defines a cross-language columnar memory layout and record-batch IPC. [S18]
- Parquet defines row groups, column chunks, pages, encodings, and metadata-driven selective reads. [S19]
- WebGL is a browser GPU standard suitable as a broad compatibility baseline. [S23]
- Browser rendering scale is constrained by CPU attribute generation, GPU buffers, overdraw, picking, and client memory, not only by backend query speed. [S20]

### Version-sensitive facts to recheck before committing to an architecture

- Exact Seurat, SeuratObject, BPCells, AnnData, Scanpy, TileDB-SOMA, Arrow, DuckDB, deck.gl, and browser versions.
- Which Seurat and Scanpy operations preserve disk-backed/lazy behavior.
- AnnData backed-mode write support and Dask-compatible function coverage.
- TileDB-SOMA API maturity, thread-safety rules, dense-array support, R API coverage, and cloud authentication behavior.
- DuckDB spill behavior, remote-file caching, concurrency features, and release status of any server protocol.
- deck.gl WebGPU layer coverage, picking, extensions, and fallback behavior.
- Browser allocation limits, WebGL/WebGPU availability, mobile memory pressure, and GPU driver behavior.
- Benchmark hardware, data sparsity, chunk shape, network path, and whether a benchmark measures server compute, transfer, or rendering.

The documentation snapshots consulted here include Seurat 5.5.1, BPCells 0.3.1, AnnData 0.13.2, Arrow format 1.5 in Apache Arrow documentation v25.0.0, Zarr core specification 3.1, and a WebGPU Candidate Recommendation Draft dated July 14, 2026. These values are historical observations for this note, not permanent compatibility requirements. [S1][S2][S9][S10][S13][S24]

## Conclusion: Options

### Option A: Retain R/Shiny and harden the existing boundary

**Best fit:** local or controlled deployments, one or a few datasets per analysis, strong Seurat fidelity, and a team already invested in R.

**Evidence:** Seurat/BPCells already demonstrate on-disk million-cell workflows; Shiny provides explicit mechanisms for moving expensive work to separate processes; Arrow and deck.gl address the browser boundary. [S1][S2][S6][S20]

**Cost and risk:** the application must continue to reject accidental dense conversions, bound metadata and reduction materialization, isolate long jobs, and manage worker memory. This option does not naturally become a shared cloud-scale corpus service.

### Option B: Hybridize the application and query plane

**Best fit:** the current product direction, where Seurat analysis and Shiny interaction remain valuable but datasets, sessions, or users are expected to scale beyond a single R process.

**Shape of the option:** retain R/Shiny and Seurat/BPCells for analysis semantics; use SOMA or a carefully specified Zarr/Parquet query representation for shared or read-only data access; use Arrow record batches for process and browser transfer; retain WebGL/deck.gl with typed, chunked buffers.

**Evidence:** this matches the explicit division demonstrated by CELLxGENE/Census and the current repository's documented Seurat, Arrow, Parquet, and deck.gl seams. It also lets Python/SOMA consumers be added without forcing every Seurat workflow into Python. [S12][S13][S17][S18][S20]

**Cost and risk:** two data models and conversion/provenance rules must be maintained. SOMA's current query limitations and API maturity need to be treated as explicit contracts, not hidden implementation details. [S16]

### Option C: Replace the application with a Python/browser service or a new systems core

**Best fit:** a product centered on a shared cloud corpus, many concurrent users, first-class scverse/ML integration, and query APIs rather than Seurat-specific interactive analysis.

**Evidence:** CELLxGENE/Census demonstrates a Python/R interoperable, TileDB-SOMA-backed, WebGL-rendered architecture at tens of millions of cells. Vitessce demonstrates a modular browser-first viewer that can consume object-store-hosted AnnData-Zarr data and integrate with R Shiny. [S12][S17][S27]

**Cost and risk:** a replacement must reimplement or substitute Seurat analysis behavior, R package integrations, Shiny interaction contracts, deployment workflows, and data provenance. A Rust or C++ core can improve ownership and kernel control, but it does not remove the need for domain APIs, bindings, and a browser data contract.

**Overall judgment:** choose **Option B** unless the product requirements clearly favor either the controlled Seurat workflow of Option A or the corpus-service model of Option C. The evidence does not justify replacing R/Shiny solely because the target datasets contain millions of cells.

## Sources

All web documentation sources below were checked on August 6, 2026. URLs are included so versioned pages and specifications can be rechecked.

- **[S1]** Satija Lab. *Sketch-based analysis in Seurat v5*. Official Seurat documentation. https://satijalab.org/seurat/articles/seurat5_sketch_analysis
- **[S2]** Satija Lab. *Using BPCells with Seurat Objects*. Official Seurat documentation. https://satijalab.org/seurat/articles/seurat5_bpcells_interaction_vignette
- **[S3]** Parks, B. *How BPCells works*. Official BPCells documentation. https://bnprks.github.io/BPCells/articles/web-only/how-it-works.html
- **[S4]** Parks, B. *BPCells*. Official source repository and project documentation. https://github.com/bnprks/BPCells
- **[S5]** R Core Team. *R Internals*, section on object sharing and duplication. Official R manual. https://cran.r-project.org/doc/manuals/r-release/R-ints.html
- **[S6]** Cheng, J. *Non-blocking operations*. Official Shiny documentation. https://shiny.posit.co/r/articles/improve/nonblocking/
- **[S7]** Posit. *Deploying Shiny apps to the web*. Official Shiny documentation. https://shiny.posit.co/r/articles/share/deployment-web/
- **[S8]** Posit. *shinyapps.io: Applications*. Official deployment documentation. https://docs.posit.co/shinyapps.io/guide/applications/
- **[S9]** scverse. *anndata.AnnData*. Official AnnData API documentation. https://anndata.readthedocs.io/en/stable/generated/anndata.AnnData.html
- **[S10]** scverse. *scanpy.read_h5ad*. Official Scanpy API documentation. https://scanpy.readthedocs.io/en/stable/generated/scanpy.read_h5ad.html
- **[S11]** scverse. *Scanpy: Single-Cell Analysis in Python*. Official Scanpy documentation. https://scanpy.readthedocs.io/en/stable/
- **[S12]** Abdulla, S. et al. *CZ CELLxGENE Discover: a single-cell data platform for scalable exploration, analysis and modeling of aggregated data*. Nucleic Acids Research (2025). DOI: https://doi.org/10.1093/nar/gkae1142
- **[S13]** Zarr Development Team. *Zarr core specification v3.1*. Official format specification. https://zarr-specs.readthedocs.io/en/latest/v3/core/
- **[S14]** single-cell-data project. *SOMA abstract specification and project README*. Official specification repository. https://github.com/single-cell-data/SOMA/blob/main/abstract_specification.md
- **[S15]** TileDB-SOMA project. *The tiledbsoma module*. Official API documentation. https://tiledbsoma.readthedocs.io/en/latest/python-tiledbsoma.html
- **[S16]** TileDB-SOMA project. *tiledbsoma.ExperimentAxisQuery*. Official API documentation. https://tiledbsoma.readthedocs.io/en/latest/python-tiledbsoma-experimentaxisquery.html
- **[S17]** Chan Zuckerberg Initiative. *CZ CELLxGENE Discover Census*. Official API documentation. https://chanzuckerberg.github.io/cellxgene-census/
- **[S18]** Apache Arrow project. *Arrow Columnar Format and IPC specification*. Official format specification. https://arrow.apache.org/docs/format/Columnar.html
- **[S19]** Apache Parquet project. *Parquet format specification*. Official format repository. https://github.com/apache/parquet-format/blob/master/README.md
- **[S20]** vis.gl. *Performance Optimization*. Official deck.gl documentation. https://deck.gl/docs/developer-guide/performance
- **[S21]** vis.gl. *WebGPU*. Official deck.gl documentation. https://deck.gl/docs/developer-guide/webgpu
- **[S22]** DuckDB Foundation. *Concurrency* and *Tuning Workloads*. Official DuckDB documentation. https://duckdb.org/docs/current/connect/concurrency and https://duckdb.org/docs/current/guides/performance/how_to_tune_workloads
- **[S23]** Khronos Group. *WebGL: 3D Graphics for the Web*. Official standard/project documentation. https://www.khronos.org/webgl/
- **[S24]** W3C GPU for the Web Working Group. *WebGPU*. Candidate Recommendation Draft, July 14, 2026. https://www.w3.org/TR/webgpu/
- **[S25]** Apache Arrow Rust implementation. *arrow_array*. Official API documentation. https://arrow.apache.org/rust/arrow_array/
- **[S26]** Rust Project. *What Is Ownership?* The Rust Programming Language. Official language documentation. https://doc.rust-lang.org/book/ch04-01-what-is-ownership.html
- **[S27]** Keller, M. S. et al. *Vitessce: integrative visualization of multimodal and spatially resolved single-cell data*. Nature Methods (2025). DOI: https://doi.org/10.1038/s41592-024-02436-x; official documentation: https://vitessce.io/docs/
- **[S28]** Hao, Y. et al. *Dictionary learning for integrative, multimodal and scalable single-cell analysis*. Nature Biotechnology (2024). DOI: https://doi.org/10.1038/s41587-023-01767-y
- **[S29]** Virshup, I. et al. *anndata: Access and store annotated data matrices*. Journal of Open Source Software (2024). DOI: https://doi.org/10.21105/joss.04371
- **[S30]** Wolf, F. A. et al. *SCANPY: large-scale single-cell gene expression data analysis*. Genome Biology (2018). DOI: https://doi.org/10.1186/s13059-017-1382-0
- **[S31]** Raasveldt, M. and Muehleisen, H. *DuckDB: an Embeddable Analytical Database*. Proceedings of the 2019 International Conference on Management of Data. DOI: https://doi.org/10.1145/3299869.3320232
