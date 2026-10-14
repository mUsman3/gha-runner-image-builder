#!/usr/bin/env bash
# Mock Artifactory package lookup + commonality check.
# Set ARTIFACTORY_MODE=live later to call a real API (not implemented in POC).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd jq
require_env ECOSYSTEM
require_env NAME
require_env VERSION
require_env APP_ID

ARTIFACTORY_MODE="${ARTIFACTORY_MODE:-fixture}"
COMMONALITY_THRESHOLD="${COMMONALITY_THRESHOLD:-5}"
PACKAGES_FILE="${REPO_ROOT}/fixtures/artifactory/packages.json"

if [[ "$ARTIFACTORY_MODE" == "live" ]]; then
  die "ARTIFACTORY_MODE=live is reserved for a future real Artifactory integration"
fi

[[ -f "$PACKAGES_FILE" ]] || die "Missing packages fixture: ${PACKAGES_FILE}"

MATCH="$(jq -c --arg eco "$ECOSYSTEM" --arg name "$NAME" --arg ver "$VERSION" \
  '.packages[] | select(.ecosystem == $eco and .name == $name and .version == $ver)' \
  "$PACKAGES_FILE" || true)"

if [[ -z "$MATCH" ]]; then
  URL="$(curation_request_url "$ECOSYSTEM" "$NAME" "$VERSION")"
  log "Package ${ECOSYSTEM}/${NAME}@${VERSION} NOT found in Artifactory (fixture)"
  set_output "present" "false"
  set_output "status" "awaiting_curation"
  set_output "curation_url" "$URL"
  set_output "is_common" "false"
  set_output "request_count" "0"
  append_summary "## Artifactory check"
  append_summary ""
  append_summary "Package \`${ECOSYSTEM}/${NAME}@${VERSION}\` is **not** in Artifactory."
  append_summary ""
  append_summary "- Status: \`awaiting_curation\`"
  append_summary "- Raise a curation request: ${URL}"
  append_summary ""
  append_summary "After curation publishes the package, re-run this workflow (or wait for nightly housekeeping)."
  exit 0
fi

# Ensure requesting AppID is counted for commonality when not already listed.
REQUEST_COUNT="$(jq -r --arg eco "$ECOSYSTEM" --arg name "$NAME" --arg ver "$VERSION" --arg app "$APP_ID" '
  .packages[]
  | select(.ecosystem == $eco and .name == $name and .version == $ver)
  | (.requested_by + [$app] | unique | length)
' "$PACKAGES_FILE")"

IS_COMMON="false"
if [[ "$REQUEST_COUNT" -ge "$COMMONALITY_THRESHOLD" ]]; then
  IS_COMMON="true"
fi

log "Package present. request_count=${REQUEST_COUNT} is_common=${IS_COMMON} threshold=${COMMONALITY_THRESHOLD}"
set_output "present" "true"
set_output "status" "in_artifactory"
set_output "is_common" "$IS_COMMON"
set_output "request_count" "$REQUEST_COUNT"
set_output "curation_url" ""

append_summary "## Artifactory check"
append_summary ""
append_summary "Package \`${ECOSYSTEM}/${NAME}@${VERSION}\` is **available** in Artifactory."
append_summary ""
append_summary "| Metric | Value |"
append_summary "|--------|-------|"
append_summary "| requesting AppIDs (incl. this) | ${REQUEST_COUNT} |"
append_summary "| commonality threshold | ${COMMONALITY_THRESHOLD} |"
append_summary "| common | ${IS_COMMON} |"
append_summary ""
if [[ "$IS_COMMON" == "true" ]]; then
  append_summary "This package is **common** and will be queued for the next golden image release."
  append_summary "An **interim custom image** will still be built so you are not blocked."
else
  append_summary "Not yet common across teams — proceeding with a dedicated custom image."
fi
