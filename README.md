# Runner Dependency Request Automation (POC)

GitHub Actions proof of concept for automating how developers get **packages** and **runtimes** onto self-hosted runners when they are not already in the golden image.

Full design context: [docs/CONTEXT.md](docs/CONTEXT.md).

## What this POC covers

Phase 1 + Phase 2 of the rollout plan, with **stubbed** Artifactory, ServiceNow, container registry, and ARC:

1. Validate `workflow_dispatch` inputs and AppID
2. Route **package** vs **runtime** requests
3. Mock Artifactory / golden-image lookups
4. Hand off to curation when the package/runtime is missing
5. Build a custom image on `ubuntu:22.04` (stand-in for the golden image)
6. Mock security scan, registry push, and ARC scale-set deploy
7. Report status to the job summary (and a ServiceNow stub when `ritm_number` is set)

No real credentials are required.

## Quick start

1. Push this repo to GitHub (Actions must be enabled).
2. Open **Actions → Request Runner Dependency → Run workflow**.
3. Fill in the inputs (examples below) and run.

Optional: create a GitHub Environment named `image-publish` if you want the publish/deploy job to use that environment name (can be unprotected for a personal fork).

## Workflow inputs

| Input | Required | Description |
|-------|----------|-------------|
| `request_type` | yes | `package` or `runtime` |
| `ecosystem` | yes | `pip`, `npm`, `maven`, `nuget`, or `cargo` |
| `name` | yes | Package or runtime name (e.g. `requests`, `python`) |
| `version` | yes | Semver-ish version (e.g. `2.31.0`, `3.13.0`) |
| `app_id` | yes | Must exist in [fixtures/appids.json](fixtures/appids.json) |
| `ritm_number` | no | When set, ServiceNow stub write-back runs |
| `force_scan_fail` | no | Set `true` to demo a failed security scan |

Idempotency key: `sha256(app_id|request_type|ecosystem|name|version)`. Retries reuse the same request ID / image tag suffix.

## Demo scenarios

### 1. Package present → custom image path

| Field | Value |
|-------|-------|
| request_type | `package` |
| ecosystem | `pip` |
| name | `requests` |
| version | `2.31.0` |
| app_id | `APP-1001` |

Expected: Artifactory hit → build → scan pass → mock push/deploy → `runs-on: [self-hosted, appid-APP-1001]`.

### 2. Package missing → awaiting curation

| Field | Value |
|-------|-------|
| request_type | `package` |
| ecosystem | `pip` |
| name | `obscure-lib` |
| version | `1.0.0` |
| app_id | `APP-1001` |

Expected: workflow stops with curation link and status `awaiting_curation`.

### 3. Runtime already in golden image

| Field | Value |
|-------|-------|
| request_type | `runtime` |
| ecosystem | `pip` |
| name | `python` |
| version | `3.11.0` |
| app_id | `APP-1001` |

Expected: no new image; summary says already supported.

### 4. Runtime in Artifactory only → setup snippet

| Field | Value |
|-------|-------|
| request_type | `runtime` |
| ecosystem | `pip` |
| name | `python` |
| version | `3.13.0` |
| app_id | `APP-1001` |

Expected: no new image; pyenv-style setup snippet in the job summary.

### 5. Validation failure

Use `app_id: APP-9999` or `version: not-a-version`.

Expected: clear validation error; no build.

### 6. Scan failure (optional)

Same as scenario 1, but set `force_scan_fail: true`.

Expected: build succeeds, scan fails, push/deploy skipped.

### Common package (queued for golden image)

`requests@2.31.0` is requested by 5+ AppIDs in fixtures. The summary notes it is queued for the next golden image release, but an interim custom image is still built.

## Local smoke tests

Scripts are plain bash and can be exercised without GitHub Actions (requires `jq`; Docker only for build):

```bash
export REPO_ROOT="$PWD"
export REQUEST_TYPE=package ECOSYSTEM=pip NAME=requests VERSION=2.31.0 APP_ID=APP-1001
./scripts/validate_inputs.sh
./scripts/check_artifactory.sh
```

## Repository layout

```
.github/workflows/request-dependency.yml   # main entrypoint
.github/workflows/housekeeping.yml         # nightly stub
scripts/                                   # validate, artifactory, build, scan, ...
fixtures/                                  # mock AppIDs, packages, runtimes, scanner
Dockerfile.custom                          # ubuntu:22.04 stand-in for golden image
docs/CONTEXT.md                            # full product context
```

## Swapping stubs for real systems later

| Concern | POC today | Later |
|---------|-----------|--------|
| Artifactory | `fixtures/artifactory/*.json` | set `ARTIFACTORY_MODE=live` + API URL/token |
| ServiceNow | stub file + job summary | OIDC / dedicated SA secrets |
| Registry | mock push log | ECR or Artifactory Docker |
| ARC | mock scale-set YAML | real RunnerScaleSet apply |
| Base image | `ubuntu:22.04` | pinned golden image tag |

## Guardrails in this POC

- Artifactory is the only package source (fixture = curated catalog).
- Custom images are AppID-tagged and scanned before "push".
- Publish/deploy job uses environment `image-publish`.
- Status always lands in `$GITHUB_STEP_SUMMARY`.
- ServiceNow steps run only when `ritm_number` is non-empty.
