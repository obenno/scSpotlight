---
phase: 02-arrow-transfer-main-scatter-reliability
reviewed: 2026-06-21T17:54:00Z
resolved: 2026-06-22T01:03:38Z
depth: deep
files_reviewed: 26
files_reviewed_list:
  - DEVELOPMENT.md
  - R/fct_backend_transfer_adapter.R
  - R/mod_InputFeature.R
  - R/mod_UpdateMetaData.R
  - R/mod_UpdateReduction.R
  - inst/app/www/index.js
  - inst/app/www/index.js.map
  - inst/protocol/browser-payload-contracts.json
  - srcjs/index.js
  - srcjs/index.test.js
  - srcjs/modules/arrowReader.js
  - srcjs/modules/deckScatter.js
  - srcjs/modules/deckScatter.test.js
  - srcjs/modules/featureSparkLine.js
  - srcjs/modules/featureSparkLine.test.js
  - srcjs/modules/lasso.js
  - srcjs/modules/lasso.test.js
  - srcjs/modules/scatter/scatterDeckController.js
  - srcjs/modules/scatter/scatterLayout.js
  - srcjs/modules/scatter/scatterLayout.test.js
  - srcjs/modules/scatter/scatterModel.js
  - srcjs/modules/scatter/scatterModel.test.js
  - tests/testthat/test-bpcells-expression-transfer.R
  - tests/testthat/test-browser-payload-contracts.R
  - tests/testthat/test-development-contract-docs.R
  - tests/testthat/test-explore-bundle.R
findings:
  critical: 2
  warning: 2
  info: 0
  total: 4
status: fixed
---

# Phase 02: Code Review Report

**Reviewed:** 2026-06-21T17:54:00Z
**Depth:** deep
**Files Reviewed:** 26
**Status:** fixed

## Summary

Reviewed the Phase 02 Arrow transfer and main scatter reliability changes across the R transfer producers, browser payload handlers, scatter model/rendering code, generated browser bundle, contract manifest, docs, and paired R/JS tests. The implementation improves many transfer-failure paths, but several correctness and security defects remain: one DOM XSS sink still renders untrusted gene/metadata labels with `innerHTML`, multi-split scatter assembly still includes missing split levels despite the new contract, PCA transfer state can be overwritten by stale async results, and stored feature identity can be corrupted for escaped gene names.

## Resolution After Review

All four findings were fixed and verified on 2026-06-22.

| Finding | Resolution | Evidence |
|---|---|---|
| CR-01 | Replaced VlnPlot dropdown `innerHTML` interpolation with text nodes and a text-only type badge. | `srcjs/index.js`, `srcjs/index.test.js` malicious-label regression |
| CR-02 | Reused filtered `getMetaLevels()` for multi-split XY/Z assembly so missing split levels stay excluded. | `srcjs/modules/scatter/scatterModel.js`, `srcjs/modules/scatter/scatterModel.test.js` multi-split missing-level regression |
| WR-01 | Added PCA request/version tracking and stale guards for async success/error paths and `transfer_error`. | `srcjs/index.js`, `srcjs/index.test.js` stale PCA success/error regression |
| WR-02 | Changed stored feature collection to use the existing text-based sparkline label helper. | `srcjs/index.js`, `srcjs/index.test.js` escaped-feature identity regression |

**Fix verification:**

- `pixi run npm test -- srcjs/index.test.js srcjs/modules/scatter/scatterModel.test.js` - PASS, 51 tests.
- `pixi run build-js` - PASS.
- `pixi run npm test -- srcjs/modules/deckScatter.test.js srcjs/modules/scatter/scatterModel.test.js srcjs/modules/scatter/scatterLayout.test.js srcjs/modules/lasso.test.js srcjs/modules/scatter/scatterCoordinates.test.js srcjs/modules/scatter/scatterRelayout.test.js srcjs/index.test.js srcjs/modules/featureSparkLine.test.js` - PASS, 90 tests.
- `pixi run Rscript -e "devtools::test(filter = 'development-contract-docs|browser-payload-contracts|bpcells-expression-transfer|explore-bundle|analysis-backend-contract')"` - PASS, 272 tests.

## Narrative Findings (AI reviewer)

### Critical Issues

#### CR-01: VlnPlot dropdown still injects untrusted labels as HTML

**Classification:** BLOCKER
**File:** `srcjs/index.js:2861-2872`
**Issue:** `option.label` is derived from metadata column names and selected gene names, both of which can originate from user-loaded objects or uploaded feature inputs. The code interpolates that label into `a.innerHTML`, so a crafted label such as `<img src=x onerror=...>` is parsed as DOM instead of text. This bypasses the safer `textContent` handling added for sparkline labels and creates a browser-side XSS sink in the floating VlnPlot menu.
**Fix:** Build the label and type badge as text nodes/elements, not HTML strings.

```javascript
const labelText = document.createTextNode(option.label);
const typeBadge = document.createElement("span");
typeBadge.classList.add("text-muted");
typeBadge.textContent = ` (${option.type})`;
a.replaceChildren(labelText, typeBadge);
```

#### CR-02: Multi-split scatter data still creates panels for missing split levels

**Classification:** BLOCKER
**File:** `srcjs/modules/scatter/scatterModel.js:356,381,458`
**Issue:** `derivePlotMetaData()` counts split panels with `getMetaLevels()`, which filters `null`, empty strings, and literal `undefined`. But the multi-split data builders recompute `splitLevels` from the raw expanded split vector with `new Set(splitByArray)`, so missing values are reintroduced when there are more than two real split levels. That makes `nPanels` disagree with `pointsData`/`panelTitles`, can render blank or wrong split panels, and violates the Phase 02 missing-level contract. The current added test only covers the two-split branch, so this multi-split bug is not caught.
**Fix:** Use the same filtered level source in `prepareZData()` and `prepareXYData()` as mode derivation, and add a regression with `>2` valid split levels plus missing values.

```javascript
const splitLevels = this.utils.getMetaLevels(metaData[split_by]);
// use splitLevels in cluster+multiSplit, cluster+expr+multiSplit, and XY multi-split assembly
```

### Warnings

#### WR-01: PCA transfer handlers do not ignore stale async results or errors

**Classification:** WARNING
**File:** `srcjs/index.js:963-990,993-1001`
**Issue:** `pca_ready` starts an async Arrow fetch/decode and then unconditionally writes `pcaStdev`; `transfer_error` with `payloadType === "pca"` unconditionally flips `pcaTransferFailed`. Unlike metadata, reductions, and expressions, PCA does not record/check the active version after async work. A slow or failed older PCA payload can overwrite a newer PCA summary or leave the ElbowPlot stuck in an unavailable state after a newer reduction update succeeds.
**Fix:** Track the active PCA version/request and re-check it before mutating state in both success and failure paths.

```javascript
let activePcaVersion = null;
const isCurrentPcaVersion = (version) => (
  activePcaVersion == null || Number(version) >= Number(activePcaVersion)
);

Shiny.addCustomMessageHandler("pca_ready", (msg) => {
  activePcaVersion = msg.reductionVersion;
  const requestVersion = msg.reductionVersion;
  // ... after await readArrowIPC(...):
  if (requestVersion !== activePcaVersion) return;
  pcaTransferFailed = false;
  reglElementData.updatePcaStdev(stdevArray);
});

// For transfer_error payloadType === "pca", return early when version is stale.
```

#### WR-02: Stored feature identity is read from escaped HTML instead of text

**Classification:** WARNING
**File:** `srcjs/index.js:723-739`
**Issue:** `createSparkLine()` now writes gene labels with `textContent`, but the message handler still collects stored features via `e.querySelector("span").innerHTML`. Gene names containing `&`, `<`, or `>` are sent back to Shiny as escaped HTML (`Gene&lt;unsafe&gt;`) instead of their real feature name. That breaks duplicate-query suppression and cache/state identity for valid feature names that contain HTML-significant characters.
**Fix:** Read the explicit gene label's `textContent`, preferably through the existing helper.

```javascript
const storedFeatures = sparkLineArray.map((e) => getFeatureSparkLineGene(e));
```

---

_Reviewed: 2026-06-21T17:54:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: deep_
