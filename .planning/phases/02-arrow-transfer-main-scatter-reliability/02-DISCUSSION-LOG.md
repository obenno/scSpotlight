# Phase 2: Arrow Transfer & Main Scatter Reliability - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-20
**Phase:** 2-Arrow Transfer & Main Scatter Reliability
**Areas discussed:** Transfer failure visibility, Versioned cache and stale payloads, Expression transfer behavior, Main scatter rendering reliability, Lasso and selection synchronization

---

## Transfer Failure Visibility

| Option | Description | Selected |
|--------|-------------|----------|
| Visible plot-state failures | Surface fetch/decode/write failures in or near the plot with payload context and recovery hint. | ✓ |
| Console-only diagnostics | Keep failures in developer console and logs only. | |
| Full modal workflow | Block the app with modal dialogs for every transfer failure. | |

**User's choice:** Auto-selected visible plot-state failures.
**Notes:** Matches Phase 2 success criteria for visible in-plot errors and avoids stuck waiters.

---

## Versioned Cache And Stale Payloads

| Option | Description | Selected |
|--------|-------------|----------|
| Strict versioned cache with stale ignore | Require cache versions and ignore late payloads from older requests. | ✓ |
| Opportunistic cache reuse | Reuse cached payloads without strict version comparison. | |
| Disable browser cache | Refetch all payloads to avoid cache consistency issues. | |

**User's choice:** Auto-selected strict versioned cache with stale ignore.
**Notes:** Carries forward Phase 1 browser payload manifest and cache-version contract tests.

---

## Expression Transfer Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| First-selected-gene Arrow vector | Keep main scatter expression to one selected gene and transfer typed Arrow IPC vectors. | ✓ |
| Multi-gene main scatter coloring | Add composite expression coloring in the main scatter. | |
| JSON expression vectors | Simplify transport by using JSON arrays. | |

**User's choice:** Auto-selected first-selected-gene Arrow vector.
**Notes:** Multi-gene views remain floating-panel scope; JSON vectors violate large-payload constraints.

---

## Main Scatter Rendering Reliability

| Option | Description | Selected |
|--------|-------------|----------|
| Harden deck.gl path | Keep deck.gl as the primary renderer and test adaptive settings, panels, labels, legends, and expression/category modes. | ✓ |
| Add canvas fallback | Add non-WebGL fallback for main scatter reliability. | |
| Defer scatter tests | Focus only on transfer payloads in this phase. | |

**User's choice:** Auto-selected harden deck.gl path.
**Notes:** Required by AGENTS.md and Phase 2 scatter requirements.

---

## Lasso And Selection Synchronization

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-panel synchronized lasso | Verify lasso selection across panels with synchronized highlights and counts. | ✓ |
| Single-panel only | Restrict lasso behavior to the active panel. | |
| Disable lasso while split | Avoid split-panel complexity by turning lasso off. | |

**User's choice:** Auto-selected cross-panel synchronized lasso.
**Notes:** Directly maps to `SCAT-03` and existing scatter interaction patterns.

---

## the agent's Discretion

Planning agents may choose exact helper boundaries, test-file grouping, and the minimal implementation locations across R transfer producers, `srcjs/index.js`, scatter lifecycle/model code, and deck.gl renderer code.

## Deferred Ideas

None.
