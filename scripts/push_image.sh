#!/usr/bin/env bash
# Mock container registry push (no network).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env IMAGE_TAG
require_env APP_ID

REGISTRY="${REGISTRY:-registry.example.internal/gha-runners}"
REMOTE_TAG="${REGISTRY}/${IMAGE_TAG}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/.poc-output}"
mkdir -p "$OUT_DIR"

log "MOCK push ${IMAGE_TAG} -> ${REMOTE_TAG}"
jq -n \
  --arg local "$IMAGE_TAG" \
  --arg remote "$REMOTE_TAG" \
  --arg app "$APP_ID" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{mock: true, local_tag: $local, remote_tag: $remote, app_id: $app, pushed_at: $ts}' \
  >"${OUT_DIR}/push-${APP_ID}.json"

set_output "remote_tag" "$REMOTE_TAG"
set_output "pushed" "true"

append_summary "## Registry push (mock)"
append_summary ""
append_summary "Pushed \`${IMAGE_TAG}\` → \`${REMOTE_TAG}\` (stubbed; no real registry call)."
