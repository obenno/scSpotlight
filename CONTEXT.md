# scSpotlight Domain Context

This context defines the domain language for scSpotlight's single-cell analysis and visualization workflow. It separates scientific data and derived analysis state from temporary user interaction state.

## Core Concepts

**Dataset Artifact**:
An immutable, addressable package of single-cell data with its schema and provenance. It is the stable object that can be loaded, shared, queried, or used to create an Analysis.
_Avoid_: raw dataset, live object, input file

**Analysis**:
A versioned scientific interpretation of a Dataset Artifact, including derived measurements, reductions, annotations, filters, and analysis choices.
_Avoid_: session state, view, object state

**Session**:
A temporary user workspace that references a Dataset Artifact and an Analysis while holding interaction choices such as selections, active views, and pending work.
_Avoid_: analysis, dataset, browser state

**View**:
A user-facing projection of an Analysis for visual exploration. A View may change without changing the underlying Analysis.
_Avoid_: plot state, rendering, visualization object

**Filter**:
A temporary restriction on a View that changes what the user sees without changing the underlying Analysis.
_Avoid_: subset, permanent selection

**Subset**:
An intentional transformation that creates a new Analysis containing a reduced cell population from an existing Analysis.
_Avoid_: filter, hidden cells

**Mutation Intent**:
A Session request describing a proposed change to an Analysis before that change has been validated and applied.
_Avoid_: browser mutation, applied change

**Analysis Version**:
A named scientific state in the lineage of an Analysis. A new version is published only after a successful Analysis mutation or restore.
_Avoid_: object copy, session revision, browser version

**Restore**:
An operation that creates a new Analysis Version using the state of an earlier Analysis Version while preserving a forward-moving lineage.
_Avoid_: rollback, pointer rewind, undo

**Analysis Mutation**:
A validated operation that changes the scientific state of an Analysis and may publish a new Analysis Version.
_Avoid_: UI event, browser update, view change

**Change-set**:
A server-owned summary of the scientific areas affected by a successful Analysis Mutation. It describes what must be refreshed without becoming a separate browser protocol message.
_Avoid_: refresh event, payload message, client diff

**Cell ID**:
The stable domain identity of a cell within a Dataset Artifact. Cell IDs remain meaningful across Views and are validated against the active Analysis before mutation.
_Avoid_: row number, point index, array position

**Analysis Lineage**:
The forward history connecting Analysis Versions and the operations that produced them, including Restore operations that reuse an earlier scientific state.
_Avoid_: undo stack, rollback chain, browser history

**Atomic Analysis Mutation**:
An Analysis Mutation that either publishes a complete new Analysis Version or leaves the current Analysis unchanged.
_Avoid_: partial update, best-effort mutation

## Workflow Modes

**Analysis Mode**:
The workflow in which a user can create or modify an Analysis from supported single-cell inputs.
_Avoid_: editable mode, processing mode

**Explore Mode**:
The read-only workflow for inspecting a processed Dataset Artifact and its available Analysis data.
_Avoid_: viewer mode, static mode
