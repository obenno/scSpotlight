#!/usr/bin/env bash
set -euo pipefail

scratch_root="${SCSPOTLIGHT_TEMP_ROOT:-/media/xzx/zflow13_sd/tmp/20260810_scSpotlight}"
real_explore_root="${SCSPOTLIGHT_REAL_EXPLORE_ROOT:-${scratch_root}/cellxgene-explore}"
source_run_id="${SCSPOTLIGHT_REAL_EXPLORE_SOURCE_RUN_ID:-20260811-real-explore-streaming-fix}"
timing_run_id="${SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_RUN_ID:-20260811-real-explore-startup-timing}"
timing_root="${SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_ROOT:-${real_explore_root}/startup-timings}"
input_mode="${SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_INPUT_MODE:-server_data_dir}"
source_root="${real_explore_root}/runs/${source_run_id}"
archive_file="${SCSPOTLIGHT_REAL_EXPLORE_TIMING_ARCHIVE_FILE:-${source_root}/aa6ebee3-68cc-41b4-80b2-5ef5c3317e14.explore-parquet.zip}"
descriptor_file="${SCSPOTLIGHT_REAL_EXPLORE_TIMING_DESCRIPTOR_FILE:-${source_root}/artifact.json}"
run_root="${timing_root}/${timing_run_id}"

if [[ ! -f "${archive_file}" || ! -f "${descriptor_file}" ]]; then
  printf 'Retained Explore archive or descriptor is missing.\n' >&2
  exit 1
fi
if [[ "${input_mode}" != "server_data_dir" && "${input_mode}" != "browser_upload" ]]; then
  printf 'SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_INPUT_MODE must be server_data_dir or browser_upload.\n' >&2
  exit 1
fi
if [[ -e "${run_root}/startup-timing.json" || -e "${run_root}/server-events.jsonl" ]]; then
  printf 'Startup timing output already exists for this run ID. Choose a new SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_RUN_ID.\n' >&2
  exit 1
fi

mkdir -p "${scratch_root}/r-tmp" "${scratch_root}/xdg-cache" "${run_root}/browser"

export SCSPOTLIGHT_TEMP_ROOT="${scratch_root}"
export SCSPOTLIGHT_REAL_H5AD_ROOT="${SCSPOTLIGHT_REAL_H5AD_ROOT:-${scratch_root}/cellxgene-h5ad}"
export SCSPOTLIGHT_REAL_EXPLORE_ROOT="${real_explore_root}"
export SCSPOTLIGHT_REAL_EXPLORE_SOURCE_RUN_ID="${source_run_id}"
export SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_RUN_ID="${timing_run_id}"
export SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_ROOT="${timing_root}"
export SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_INPUT_MODE="${input_mode}"
export SCSPOTLIGHT_REAL_EXPLORE_TIMING_ARCHIVE_FILE="${archive_file}"
export SCSPOTLIGHT_REAL_EXPLORE_TIMING_DESCRIPTOR_FILE="${descriptor_file}"
export SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_RESULTS_FILE="${run_root}/startup-timing.json"
export SCSPOTLIGHT_BENCHMARK_STARTUP_TIMING_EVENT_FILE="${run_root}/server-events.jsonl"
export SCSPOTLIGHT_REAL_EXPLORE_STARTUP_TIMING_EVENT_FILE="${SCSPOTLIGHT_BENCHMARK_STARTUP_TIMING_EVENT_FILE}"
export SCSPOTLIGHT_BENCHMARK_STARTUP_TIMING="true"
export SCSPOTLIGHT_BENCHMARK_PORT="${SCSPOTLIGHT_BENCHMARK_PORT:-8903}"
export SCSPOTLIGHT_BENCHMARK_TEST_MATCH="**/real-explore-startup-timing.spec.js"
export SCSPOTLIGHT_BENCHMARK_APP_COMMAND="pixi run Rscript benchmarks/run_real_explore_startup_timing_app.R"
export SCSPOTLIGHT_PLAYWRIGHT_OUTPUT_DIR="${run_root}/browser/playwright-output"
export TMPDIR="${scratch_root}/r-tmp"
export TMP="${TMPDIR}"
export TEMP="${TMPDIR}"
export XDG_CACHE_HOME="${scratch_root}/xdg-cache"

npm exec -- playwright install chromium
npm run build
npx playwright test -c playwright.benchmark.config.js
