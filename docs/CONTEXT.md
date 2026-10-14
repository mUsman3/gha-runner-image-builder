# Context: Runner Dependency Request Automation

Last updated: October 2026
Owner: Platform Engineering

This file captures the problem, decisions and proposed design for automating how developers get packages and runtimes onto GitHub Actions runners that aren't in the golden image. Use it to onboard teammates or to give an AI assistant full context.

Items are marked **[Decided]** when agreed by the platform team, and **[Proposed]** when they're starting points still awaiting confirmation.

---

## 1. Environment

- GitHub Actions self-hosted runners run on **EKS**, managed with **Actions Runner Controller (ARC)** runner scale sets.
- Runners use a hardened **golden image** maintained by Platform Engineering.
- The golden image is built on a **base image released by the Product Engineering team**.
- The golden image currently includes several versions of Python, .NET, Java, JavaScript/Node and other common tooling.
- All packages are installed from the internal **JFrog Artifactory**. Nothing is pulled from public registries directly.
- Packages not yet in Artifactory must go through the **curation and security layer** (a separate team), which vets them and publishes approved packages to Artifactory.
- Request intake uses **ServiceNow RITMs**.
- Scale: about **15,000 developers**. Manual triage is not acceptable; the process must be automated.

## 2. Problem

- The golden image can't hold every language, version and library. Including everything would push it toward ~10 GB, slow jobs and widen the security surface.
- Most jobs are served by the golden image, but some teams need unusual stacks (legacy apps, Rust, Scala and so on) or specific runtime versions.
- There is no standard, automated path for these requests today.

## 3. Core principles [Decided]

1. **Separate runtime versions from libraries.** Runtime versions (Python, Java, .NET) are handled by a version manager. Libraries go through Artifactory.
2. **Artifactory is the only source.** If something isn't in Artifactory, it goes to curation first.
3. **GitHub Actions is the engine.** One workflow validates, builds, scans, deploys and reports status.
4. **ServiceNow is optional.** The workflow can be triggered by ServiceNow or run manually through `workflow_dispatch` with the same required inputs.
5. **People step in at two points only:** curation decisions and golden image release approval.

## 4. Architecture

```
Developer --raises RITM--> ServiceNow --triggers--> GitHub Actions workflow
Developer --or runs manually------------------------> GitHub Actions workflow
GitHub Actions workflow --checks package--> JFrog Artifactory
GitHub Actions workflow --builds, scans, pushes--> Container registry --> ARC scale sets on EKS
GitHub Actions workflow --status updates--> ServiceNow RITM (only when ritm_number is set)
Developer --if package missing--> Curation and security team --publishes--> Artifactory
```

### Workflow input contract [Decided in principle, fields Proposed]

ServiceNow calls the same `workflow_dispatch` a human would use, so there is one input contract and one code path.

```yaml
on:
  workflow_dispatch:
    inputs:
      request_type: { type: choice, options: [package, runtime], required: true }
      ecosystem:    { type: choice, options: [pip, npm, maven, nuget, cargo], required: true }
      name:         { type: string, required: true }
      version:      { type: string, required: true }
      app_id:       { type: string, required: true }
      ritm_number:  { type: string, required: false }  # set by ServiceNow, blank for manual runs
```

- Steps that write to ServiceNow run only when `ritm_number` is set (`if: inputs.ritm_number != ''`).
- On manual runs, the same status messages go to the workflow job summary.

## 5. Request flow

1. Request arrives with type, ecosystem, name, version, AppID and optional RITM number.
2. **Validate inputs:** AppID exists, version format is sane. On failure, stop with a clear error.
3. **Route by type:** runtime requests go to section 6. Package requests continue below.
4. **Check Artifactory.**
5. **Not in Artifactory** [Decided]:
   - The workflow reports back automatically (on the RITM or job summary): the package isn't available, with a link to raise a curation request.
   - The developer raises the curation request themselves.
   - Request status becomes "awaiting curation."
   - **Approved:** curation publishes the package to Artifactory, the request is re-checked automatically and continues from step 4.
   - **Rejected:** the request is cancelled or closed, with the rejection reason passed to the developer.
   - **No action in 14 days** [Proposed]: the request auto-closes as stale.
6. **In Artifactory:** check whether the package is common across teams.
   - **Common** (requested by 5+ AppIDs [Proposed]): queue it for the next golden image release. The developer still gets an interim custom image right away so they aren't blocked [Proposed].
   - **Not common:** build a custom image.
7. **Build custom image** from a pinned golden image tag, tagged with the AppID.
8. **Security scan.** On failure, stop and report findings.
9. **Push** to the container registry.
10. **Deploy a dedicated ARC runner scale set** for the AppID, with `minRunners: 0` so idle runners cost nothing [Proposed].
11. **Report done** with the `runs-on` label the developer should use.

## 6. Runtime version flow [Decided in principle]

1. Runtime version requested, for example Python 3.13.
2. If it's already in the golden image, report that it's supported.
3. If it's in Artifactory, the version manager in the golden image installs it at job start (pyenv for Python, SDKMAN for Java, dotnet-install for .NET). The developer gets a setup snippet for their workflow. No new image is needed.
4. If it isn't in Artifactory, it follows the same curation path as packages.

## 7. Golden image release [Proposed]

- Promotions are batched on a fixed cadence (monthly proposed), never one request at a time.
- Each candidate is security scanned, then regression tested on canary runners.
- Release requires approval through a protected GitHub Environment (platform lead + security proposed).
- After rollout, all custom AppID images are rebuilt on the new golden image tag, so security patches reach every team.
- Interim custom images now covered by the golden image are retired.

## 8. Scheduled housekeeping [Proposed]

A nightly workflow:
- Re-checks requests awaiting curation. If the package is now in Artifactory, it resumes the request.
- Auto-closes requests awaiting curation for more than 14 days.
- Finds custom images and scale sets unused for 90 days, notifies the AppID owner, then removes them.

## 9. Guardrails

- Every package comes from Artifactory, so nothing bypasses curation.
- Every custom image is built on the golden image, scanned before push and tagged to an AppID for ownership and cost tracking.
- Manual runs that push images or touch the golden image require approval through a protected GitHub Environment.
- Workflows are idempotent, keyed on the request ID, so retries never build twice or post duplicate updates.
- ServiceNow write-backs use a dedicated service account with scoped permissions, stored as a GitHub secret or retrieved through OIDC. Never personal credentials.

## 10. Rollout plan [Proposed]

1. **Self-service workflow:** manual `workflow_dispatch` with input checks, Artifactory validation and the curation hand-off.
2. **Custom images and ServiceNow:** AppID image builds, scanning, dedicated scale sets and RITM integration.
3. **Golden image lifecycle:** batched promotions, canary testing, custom image rebuilds and nightly housekeeping.

## 11. Decisions needed from management

| Decision | Proposed | Why it matters |
|---|---|---|
| When a package counts as common | 5+ AppIDs | Sets how fast the golden image grows |
| Golden image release cadence | Monthly | Balances freshness against risk to every runner |
| Golden image release approvers | Platform lead + security | The one change that reaches all developers |
| Stale request timeout | 14 days | Keeps the queue clean |
| Unused custom image retention | 90 days | Controls registry cost and sprawl |

## 12. Success metrics

- Time from request to a working runner.
- Share of requests completed with no human involvement.
- Number of active custom images.
- Golden image size over time.

## 13. Open questions

- Which container registry hosts custom images (ECR or Artifactory's Docker registry)?
- How does ServiceNow learn the curation outcome: linked records, a webhook, or only the nightly re-check?
- Can AppID be validated through an existing CMDB or API lookup?
- Which security scanner gates custom image pushes?
- Should one AppID be limited in how many custom images or scale sets it can have?

## 14. Glossary

- **Golden image:** the hardened, shared runner image maintained by Platform Engineering.
- **Custom image:** an AppID-specific image built on top of the golden image.
- **ARC:** Actions Runner Controller, which runs GitHub Actions runners on Kubernetes.
- **Scale set:** an ARC group of runners that share an image and a `runs-on` label.
- **RITM:** a ServiceNow requested item.
- **AppID:** the application identifier used for ownership, tagging and cost tracking.
- **Curation layer:** the team and process that vets packages before they're published to Artifactory.
