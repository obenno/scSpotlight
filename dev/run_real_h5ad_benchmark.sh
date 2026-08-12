#!/usr/bin/env bash
set -euo pipefail

scratch_root="${SCSPOTLIGHT_TEMP_ROOT:-/media/xzx/zflow13_sd/tmp/20260810_scSpotlight}"
real_h5ad_root="${SCSPOTLIGHT_REAL_H5AD_ROOT:-${scratch_root}/cellxgene-h5ad}"
run_id="${SCSPOTLIGHT_REAL_H5AD_RUN_ID:-20260810-real-h5ad}"

mkdir -p "${scratch_root}/r-tmp" "${scratch_root}/xdg-cache" \
  "${real_h5ad_root}/runs/${run_id}/browser"

export SCSPOTLIGHT_TEMP_ROOT="${scratch_root}"
export SCSPOTLIGHT_REAL_H5AD_ROOT="${real_h5ad_root}"
export SCSPOTLIGHT_REAL_H5AD_RUN_ID="${run_id}"
export SCSPOTLIGHT_RSS_LIMIT_BYTES="${SCSPOTLIGHT_RSS_LIMIT_BYTES:-6000000000}"
export SCSPOTLIGHT_BENCHMARK_PORT="${SCSPOTLIGHT_BENCHMARK_PORT:-8901}"
export SCSPOTLIGHT_BENCHMARK_TEST_MATCH="**/real-h5ad.spec.js"
export SCSPOTLIGHT_BENCHMARK_APP_COMMAND="pixi run Rscript benchmarks/run_real_h5ad_app.R"
export SCSPOTLIGHT_PLAYWRIGHT_OUTPUT_DIR="${real_h5ad_root}/runs/${run_id}/browser/playwright-output"
export TMPDIR="${scratch_root}/r-tmp"
export TMP="${TMPDIR}"
export TEMP="${TMPDIR}"
export XDG_CACHE_HOME="${scratch_root}/xdg-cache"

npm exec -- playwright install chromium
npm run benchmark:real-h5ad
