#!/usr/bin/env bash
# Mock security scan gated by fixture (or FORCE_SCAN_FAIL=true).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd jq
require_env IMAGE_TAG

FORCE_SCAN_FAIL="${FORCE_SCAN_FAIL:-false}"
SCAN_FIXTURE="${SCAN_FIXTURE:-}"

if [[ "$FORCE_SCAN_FAIL" == "true" || "$FORCE_SCAN_FAIL" == "1" ]]; then
  SCAN_FIXTURE="${REPO_ROOT}/fixtures/scanner/fail.json"
else
  SCAN_FIXTURE="${SCAN_FIXTURE:-${REPO_ROOT}/fixtures/scanner/pass.json}"
fi

[[ -f "$SCAN_FIXTURE" ]] || die "Missing scanner fixture: ${SCAN_FIXTURE}"

STATUS="$(jq -r '.status' "$SCAN_FIXTURE")"
FINDINGS_COUNT="$(jq '.findings | length' "$SCAN_FIXTURE")"

append_summary "## Security scan"
append_summary ""
append_summary "Scanner: \`$(jq -r '.scanner' "$SCAN_FIXTURE")\`"
append_summary "Image: \`${IMAGE_TAG}\`"
append_summary "Result: **${STATUS}** (${FINDINGS_COUNT} finding(s))"
append_summary ""

if [[ "$STATUS" != "pass" ]]; then
  append_summary "### Findings"
  append_summary ""
  append_summary '```json'
  jq '.findings' "$SCAN_FIXTURE" | while IFS= read -r line; do append_summary "$line"; done
  append_summary '```'
  set_output "scan_status" "fail"
  set_output "passed" "false"
  die "Security scan failed for ${IMAGE_TAG} — blocking push/deploy"
fi

set_output "scan_status" "pass"
set_output "passed" "true"
log "Scan passed for ${IMAGE_TAG}"
