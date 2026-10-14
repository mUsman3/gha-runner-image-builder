#!/usr/bin/env bash
# Runtime path: golden image → Artifactory version manager → curation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd jq
require_env ECOSYSTEM
require_env NAME
require_env VERSION

RUNTIMES_FILE="${REPO_ROOT}/fixtures/artifactory/runtimes.json"
[[ -f "$RUNTIMES_FILE" ]] || die "Missing runtimes fixture: ${RUNTIMES_FILE}"

in_list() {
  local key="$1"
  jq -e --arg eco "$ECOSYSTEM" --arg name "$NAME" --arg ver "$VERSION" \
    --arg key "$key" '
      .[$key][]
      | select(.ecosystem == $eco and .name == $name and .version == $ver)
    ' "$RUNTIMES_FILE" >/dev/null 2>&1
}

setup_snippet() {
  case "$ECOSYSTEM:$NAME" in
    pip:python)
      cat <<EOF
\`\`\`yaml
- name: Install Python ${VERSION} via pyenv
  run: |
    pyenv install -s ${VERSION}
    pyenv global ${VERSION}
    python --version
\`\`\`
EOF
      ;;
    maven:java)
      cat <<EOF
\`\`\`yaml
- name: Install Java ${VERSION} via SDKMAN
  run: |
    source "\$HOME/.sdkman/bin/sdkman-init.sh"
    sdk install java ${VERSION}-tem
    java -version
\`\`\`
EOF
      ;;
    nuget:dotnet)
      cat <<EOF
\`\`\`yaml
- name: Install .NET ${VERSION}
  run: |
    curl -fsSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --version ${VERSION}
    export PATH="\$HOME/.dotnet:\$PATH"
    dotnet --info
\`\`\`
EOF
      ;;
    npm:node)
      cat <<EOF
\`\`\`yaml
- name: Install Node ${VERSION}
  run: |
    # Prefer internal Artifactory node distro in production
    nvm install ${VERSION}
    nvm use ${VERSION}
    node --version
\`\`\`
EOF
      ;;
    *)
      cat <<EOF
\`\`\`yaml
- name: Install ${NAME} ${VERSION}
  run: echo "Use the golden-image version manager for ${ECOSYSTEM}/${NAME}@${VERSION}"
\`\`\`
EOF
      ;;
  esac
}

append_summary "## Runtime lookup"
append_summary ""

if in_list "golden_image"; then
  log "Runtime already in golden image"
  set_output "result" "in_golden_image"
  set_output "status" "supported"
  set_output "needs_image" "false"
  set_output "curation_url" ""
  append_summary "Runtime \`${ECOSYSTEM}/${NAME}@${VERSION}\` is **already in the golden image**."
  append_summary ""
  append_summary "No custom image is required. Use the standard shared runners."
  exit 0
fi

if in_list "artifactory"; then
  log "Runtime in Artifactory; version manager installs at job start"
  set_output "result" "in_artifactory"
  set_output "status" "setup_snippet"
  set_output "needs_image" "false"
  set_output "curation_url" ""
  append_summary "Runtime \`${ECOSYSTEM}/${NAME}@${VERSION}\` is in Artifactory but not baked into the golden image."
  append_summary ""
  append_summary "Install it at job start with the golden-image version manager. No new image is needed."
  append_summary ""
  append_summary "### Suggested workflow snippet"
  append_summary ""
  setup_snippet | while IFS= read -r line; do append_summary "$line"; done
  exit 0
fi

URL="$(curation_request_url "$ECOSYSTEM" "$NAME" "$VERSION")"
log "Runtime missing; awaiting curation"
set_output "result" "missing"
set_output "status" "awaiting_curation"
set_output "needs_image" "false"
set_output "curation_url" "$URL"
append_summary "Runtime \`${ECOSYSTEM}/${NAME}@${VERSION}\` is **not** in Artifactory."
append_summary ""
append_summary "- Status: \`awaiting_curation\`"
append_summary "- Raise a curation request: ${URL}"
