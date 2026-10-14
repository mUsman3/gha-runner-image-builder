#!/usr/bin/env bash
# Shared helpers for runner-dependency POC scripts.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

die() {
  echo "::error::$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Required environment variable not set: $name"
}

# request_id = sha256(app_id|request_type|ecosystem|name|version)
compute_request_id() {
  local app_id="$1" request_type="$2" ecosystem="$3" name="$4" version="$5"
  local payload="${app_id}|${request_type}|${ecosystem}|${name}|${version}"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$payload" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$payload" | shasum -a 256 | awk '{print $1}'
  fi
}

set_output() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "${key}<<EOF"
      echo "${value}"
      echo "EOF"
    } >>"$GITHUB_OUTPUT"
  fi
  echo "output.${key}=${value}"
}

append_summary() {
  local text="$1"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$text" >>"$GITHUB_STEP_SUMMARY"
  else
    printf '%s\n' "$text"
  fi
}

curation_request_url() {
  local ecosystem="$1" name="$2" version="$3"
  # Placeholder portal URL for POC demos.
  echo "https://curation.example.internal/request?ecosystem=${ecosystem}&name=${name}&version=${version}"
}
