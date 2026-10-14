#!/usr/bin/env bash
# Write status to job summary and optionally stub a ServiceNow RITM update.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

STATUS="${STATUS:-unknown}"
MESSAGE="${MESSAGE:-}"
RITM_NUMBER="${RITM_NUMBER:-}"
REQUEST_ID="${REQUEST_ID:-}"
APP_ID="${APP_ID:-}"
RUNS_ON="${RUNS_ON:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
CURATION_URL="${CURATION_URL:-}"
SERVICENOW_STUB="${SERVICENOW_STUB:-1}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/.poc-output}"

mkdir -p "$OUT_DIR"

append_summary "## Status update"
append_summary ""
append_summary "| Field | Value |"
append_summary "|-------|-------|"
append_summary "| status | \`${STATUS}\` |"
[[ -n "$REQUEST_ID" ]] && append_summary "| request_id | \`${REQUEST_ID}\` |"
[[ -n "$APP_ID" ]] && append_summary "| app_id | \`${APP_ID}\` |"
[[ -n "$IMAGE_TAG" ]] && append_summary "| image | \`${IMAGE_TAG}\` |"
[[ -n "$RUNS_ON" ]] && append_summary "| runs-on | \`${RUNS_ON}\` |"
[[ -n "$CURATION_URL" ]] && append_summary "| curation | ${CURATION_URL} |"
append_summary ""
if [[ -n "$MESSAGE" ]]; then
  append_summary "$MESSAGE"
  append_summary ""
fi

PAYLOAD="$(jq -n \
  --arg status "$STATUS" \
  --arg message "$MESSAGE" \
  --arg ritm "$RITM_NUMBER" \
  --arg request_id "$REQUEST_ID" \
  --arg app_id "$APP_ID" \
  --arg image_tag "$IMAGE_TAG" \
  --arg runs_on "$RUNS_ON" \
  --arg curation_url "$CURATION_URL" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    status: $status,
    message: $message,
    ritm_number: $ritm,
    request_id: $request_id,
    app_id: $app_id,
    image_tag: $image_tag,
    runs_on: $runs_on,
    curation_url: $curation_url,
    updated_at: $ts
  }')"

echo "$PAYLOAD" >"${OUT_DIR}/status-${REQUEST_ID:-manual}.json"
log "Wrote status artifact ${OUT_DIR}/status-${REQUEST_ID:-manual}.json"

if [[ -n "$RITM_NUMBER" && "$SERVICENOW_STUB" == "1" ]]; then
  STUB_FILE="${OUT_DIR}/servicenow-${RITM_NUMBER}.json"
  echo "$PAYLOAD" | jq --arg ritm "$RITM_NUMBER" '. + {servicenow_stub: true, work_note: ("[POC] " + .status + ": " + .message)}' >"$STUB_FILE"
  log "ServiceNow stub update for ${RITM_NUMBER} -> ${STUB_FILE}"
  append_summary "### ServiceNow stub"
  append_summary ""
  append_summary "RITM \`${RITM_NUMBER}\` would be updated with status \`${STATUS}\` (stubbed; no live API call)."
  append_summary ""
elif [[ -n "$RITM_NUMBER" ]]; then
  die "Live ServiceNow write-back is not implemented in this POC (set SERVICENOW_STUB=1)"
else
  log "No ritm_number; skipped ServiceNow write-back"
fi

set_output "status" "$STATUS"
set_output "artifact" "${OUT_DIR}/status-${REQUEST_ID:-manual}.json"
