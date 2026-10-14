#!/usr/bin/env bash
# Build a custom runner image from the golden-image stand-in (ubuntu:22.04).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd docker
require_env ECOSYSTEM
require_env NAME
require_env VERSION
require_env APP_ID
require_env REQUEST_ID_SHORT

BASE_IMAGE="${BASE_IMAGE:-ubuntu:22.04}"
IMAGE_NAME="${IMAGE_NAME:-runner-custom-${APP_ID}}"
IMAGE_TAG="${IMAGE_TAG:-${IMAGE_NAME}:${REQUEST_ID_SHORT}}"
DOCKERFILE="${DOCKERFILE:-${REPO_ROOT}/Dockerfile.custom}"
SKIP_DOCKER_BUILD="${SKIP_DOCKER_BUILD:-0}"

log "Building custom image ${IMAGE_TAG} FROM ${BASE_IMAGE}"
log "Package ${ECOSYSTEM}/${NAME}@${VERSION}"

if [[ "$SKIP_DOCKER_BUILD" == "1" ]]; then
  log "SKIP_DOCKER_BUILD=1 — recording tag only (no docker build)"
else
  docker build \
    -f "$DOCKERFILE" \
    --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
    --build-arg "ECOSYSTEM=${ECOSYSTEM}" \
    --build-arg "PACKAGE_NAME=${NAME}" \
    --build-arg "PACKAGE_VERSION=${VERSION}" \
    --build-arg "APP_ID=${APP_ID}" \
    --build-arg "REQUEST_ID=${REQUEST_ID:-${REQUEST_ID_SHORT}}" \
    --label "org.company.appid=${APP_ID}" \
    --label "org.company.request_id=${REQUEST_ID:-${REQUEST_ID_SHORT}}" \
    --label "org.company.package=${ECOSYSTEM}/${NAME}@${VERSION}" \
    -t "$IMAGE_TAG" \
    "$REPO_ROOT"
fi

set_output "image_tag" "$IMAGE_TAG"
set_output "image_name" "$IMAGE_NAME"
set_output "built" "true"

append_summary "## Custom image build"
append_summary ""
append_summary "| Field | Value |"
append_summary "|-------|-------|"
append_summary "| base | \`${BASE_IMAGE}\` |"
append_summary "| image_tag | \`${IMAGE_TAG}\` |"
append_summary "| package | \`${ECOSYSTEM}/${NAME}@${VERSION}\` |"
append_summary ""
if [[ "$SKIP_DOCKER_BUILD" == "1" ]]; then
  append_summary "Build was **skipped** (\`SKIP_DOCKER_BUILD=1\`); tag recorded for downstream mock steps."
else
  append_summary "Build **succeeded**."
fi
