#!/usr/bin/env bash
# Mock ARC RunnerScaleSet deploy for an AppID (minRunners: 0).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env APP_ID
require_env IMAGE_TAG

REMOTE_TAG="${REMOTE_TAG:-registry.example.internal/gha-runners/${IMAGE_TAG}}"
RUNS_ON_LABEL="appid-${APP_ID}"
RUNS_ON="[self-hosted, ${RUNS_ON_LABEL}]"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/.poc-output}"
mkdir -p "$OUT_DIR"

SCALE_SET_FILE="${OUT_DIR}/scaleset-${APP_ID}.yaml"
cat >"$SCALE_SET_FILE" <<EOF
# MOCK ARC RunnerScaleSet — not applied to any cluster
apiVersion: actions.github.com/v1alpha1
kind: AutoscalingRunnerSet
metadata:
  name: gha-runner-${APP_ID}
  namespace: arc-runners
  labels:
    app_id: "${APP_ID}"
    request_id: "${REQUEST_ID:-unknown}"
spec:
  githubConfigUrl: https://github.com/example/org
  minRunners: 0
  maxRunners: 5
  template:
    spec:
      containers:
        - name: runner
          image: ${REMOTE_TAG}
      # runners accept jobs with:
      # runs-on: ${RUNS_ON}
EOF

log "MOCK deploy scale set for ${APP_ID} -> ${SCALE_SET_FILE}"
set_output "runs_on" "$RUNS_ON"
set_output "runs_on_label" "$RUNS_ON_LABEL"
set_output "scale_set_file" "$SCALE_SET_FILE"
set_output "deployed" "true"

append_summary "## ARC scale set (mock)"
append_summary ""
append_summary "Deployed dedicated scale set for \`${APP_ID}\` with \`minRunners: 0\` (stubbed)."
append_summary ""
append_summary "Use this in your workflow:"
append_summary ""
append_summary '```yaml'
append_summary "jobs:"
append_summary "  build:"
append_summary "    runs-on: ${RUNS_ON}"
append_summary '```'
append_summary ""
append_summary "Manifest written to \`${SCALE_SET_FILE}\`."
