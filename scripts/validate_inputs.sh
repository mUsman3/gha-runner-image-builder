#!/usr/bin/env bash
# Validate workflow inputs and compute idempotent request_id.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd jq
require_env REQUEST_TYPE
require_env ECOSYSTEM
require_env NAME
require_env VERSION
require_env APP_ID

REQUEST_TYPE="${REQUEST_TYPE}"
ECOSYSTEM="${ECOSYSTEM}"
NAME="${NAME}"
VERSION="${VERSION}"
APP_ID="${APP_ID}"
RITM_NUMBER="${RITM_NUMBER:-}"

case "$REQUEST_TYPE" in
  package|runtime) ;;
  *) die "Invalid request_type '${REQUEST_TYPE}'. Expected: package|runtime" ;;
esac

case "$ECOSYSTEM" in
  pip|npm|maven|nuget|cargo) ;;
  *) die "Invalid ecosystem '${ECOSYSTEM}'. Expected: pip|npm|maven|nuget|cargo" ;;
esac

[[ -n "$NAME" ]] || die "name must not be empty"
# Semver-ish: 1.2.3, 1.2.3-jre, 13.0.3, 4.17.21
if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}([.-][A-Za-z0-9]+)*$ ]]; then
  die "version '${VERSION}' is not a sane semver-ish value (e.g. 2.31.0, 33.0.0-jre)"
fi

APPIDS_FILE="${REPO_ROOT}/fixtures/appids.json"
[[ -f "$APPIDS_FILE" ]] || die "Missing AppID fixture: ${APPIDS_FILE}"

if ! jq -e --arg id "$APP_ID" '.appids[] | select(.id == $id)' "$APPIDS_FILE" >/dev/null; then
  die "AppID '${APP_ID}' was not found in fixtures/appids.json. Valid examples: APP-1001, APP-1002."
fi

OWNER="$(jq -r --arg id "$APP_ID" '.appids[] | select(.id == $id) | .owner' "$APPIDS_FILE")"
REQUEST_ID="$(compute_request_id "$APP_ID" "$REQUEST_TYPE" "$ECOSYSTEM" "$NAME" "$VERSION")"
REQUEST_ID_SHORT="${REQUEST_ID:0:12}"

log "Validated request app_id=${APP_ID} owner=${OWNER} type=${REQUEST_TYPE} ${ECOSYSTEM}/${NAME}@${VERSION}"
log "request_id=${REQUEST_ID} short=${REQUEST_ID_SHORT}"

set_output "request_id" "$REQUEST_ID"
set_output "request_id_short" "$REQUEST_ID_SHORT"
set_output "app_owner" "$OWNER"
set_output "valid" "true"
set_output "ritm_number" "$RITM_NUMBER"

append_summary "## Validation"
append_summary ""
append_summary "| Field | Value |"
append_summary "|-------|-------|"
append_summary "| request_id | \`${REQUEST_ID}\` |"
append_summary "| app_id | \`${APP_ID}\` |"
append_summary "| owner | \`${OWNER}\` |"
append_summary "| request_type | \`${REQUEST_TYPE}\` |"
append_summary "| package | \`${ECOSYSTEM}/${NAME}@${VERSION}\` |"
if [[ -n "$RITM_NUMBER" ]]; then
  append_summary "| ritm_number | \`${RITM_NUMBER}\` |"
fi
append_summary ""
append_summary "Validation **passed**."
