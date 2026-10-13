# AI Squad: architecture and workflow

An event-driven SDLC squad. GitHub issue labels trigger a workflow, the workflow calls an Azure-hosted orchestrator, and the orchestrator routes each task to the right model (`sdlc-auto`) and writes the result back through a GitHub App. The GitHub cloud agent stays out of the loop, so it spends few tokens. It also can't use a custom model provider (BYOK is local SDK/CLI only).

Related: [plan.md](plan.md) (routing rules, limits, Squad alignment), [azure-harness/README.md](azure-harness/README.md), [samples/sample-squad.json](samples/sample-squad.json).

## Architecture

```
GitHub issue / PR  --label squad:* / comment-->  Actions: squad-dispatch.yml
                                                     | environment: azure-harness-dispatch (reviewers)
                                                     | OIDC (no stored secret) -> Entra token, aud = ORCHESTRATOR_AUDIENCE
                                                     v
                              POST {ORCHESTRATOR_URL}/work-items      (Container Apps: ca-sdlc-orchestrator)
                                   | verify JWT: tenant, audience, client id, role "Dispatch", repo allow-list
                                   | 202 + Idempotency-Key, process async
                                   v
                      router.js + models/routing.json  (task type x complexity x volume)
                                   v
                      Azure AI Foundry deployments: gpt-4o-mini, gpt-5.6-terra, gpt-6-sol, gpt-6.1-sol, gpt-6-astra
                                   v
                      GitHub App: comment, labels, branch + commits + PR (never pushes to default branch)

Every step -> Application Insights `sdlc-appinsights` (custom events); Foundry account logs/metrics -> Log Analytics
```

| Layer | Where |
| --- | --- |
| Routing engine and config | [azure-harness/router/router.js](azure-harness/router/router.js), [azure-harness/models/routing.json](azure-harness/models/routing.json) |
| OpenAI-compatible gateway (`sdlc-auto`, local/BYOK use) | [azure-harness/provider/server.js](azure-harness/provider/server.js) |
| Orchestrator | [azure-harness/orchestrator/](azure-harness/orchestrator) |
| Infrastructure | [azure-harness/infra/](azure-harness/infra) (Terraform) |
| Deployment script | [infra/002SetupAzure.ps1](infra/002SetupAzure.ps1) |
| Dispatch workflow | [.github/workflows/squad-dispatch.yml](.github/workflows/squad-dispatch.yml) |

## End-to-end workflow

1. A maintainer labels an issue (or PR), for example `squad:senior` or `squad:junior`, or runs `workflow_dispatch`. Labels `squad:in-progress`, `squad:needs-review`, `squad:blocked` are written by the orchestrator and ignored by the workflow, which prevents loops.
2. `squad-dispatch.yml` runs in the `azure-harness-dispatch` environment, logs in with OIDC and gets an Entra token for the orchestrator.
3. It POSTs the work item (repo, number, level, role, task type, complexity, volume) with an `Idempotency-Key`.
4. The orchestrator validates it, answers `202`, then works asynchronously: labels `squad:in-progress`, reads the issue, calls the router per sub-task, posts a triage comment (or opens a PR in `mode: "pr"`), then sets `squad:needs-review` (or `squad:blocked` with the error).
5. Role mapping: `level:senior` means medium/high complexity at normal volume; `level:junior` means low complexity at high volume (see `sample-squad.json`, which duplicates each role as senior and junior).

Routing in short: an explicit model passes through; the task type gives the base model; high complexity escalates; low-complexity/high-volume work goes to the cheap model; a fallback chain with a circuit breaker covers failures.

## Feature 1: dispatch environment, OIDC, and `POST /work-items`

**Workflow.** `azure-harness-dispatch` is a GitHub environment. Add required reviewers there so a human approves each dispatch. The job uses `azure/login@v2` with `allow-no-subscriptions: true` (the dispatch identity has no Azure subscription access, only an app role on the orchestrator API).

**Entra identities** (created by `002SetupAzure.ps1 -DeployOrchestrator`):

| Object | Purpose |
| --- | --- |
| `sdlc-orchestrator-api` | Audience `api://<appId>`, app role `Dispatch` |
| `sdlc-dispatch` | Federated credential, subject `repo:<owner>/<repo>:environment:azure-harness-dispatch`; assigned the `Dispatch` role |

**Environment values** (secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`; variables: `ORCHESTRATOR_URL`, `ORCHESTRATOR_AUDIENCE`). The Foundry key is never given to GitHub.

**Endpoint.** `POST /work-items` with `Authorization: Bearer <token>`:

```json
{ "repo": "owner/repo", "number": 12, "level": "junior", "role": "tester", "taskType": "code_generation", "complexity": "low", "volume": "high", "mode": "triage|pr" }
```

Responses: `202 {id}`, `200 {duplicate}` (same Idempotency-Key), `400` invalid or repo not allowed, `401` bad token, `503` GitHub App not configured. `GET /healthz` is unauthenticated.

**Stored outputs.** After apply, 002 writes these to Key Vault (`kv-sdlcdocs-<sub8>`) and to user environment variables:

| Key Vault secret | Env var |
| --- | --- |
| `orchestrator-url` | `ORCHESTRATOR_URL` |
| `orchestrator-audience` | `ORCHESTRATOR_AUDIENCE` |
| `dispatch-client-id` | `AZURE_DISPATCH_CLIENT_ID` |
| `appinsights-connection-string` | `APPLICATIONINSIGHTS_CONNECTION_STRING` |
| `appinsights-name`, `container-registry-login-server` | `AZURE_APPINSIGHTS_NAME`, `AZURE_CONTAINER_REGISTRY` |

By default 002 changes no GitHub settings and prints the `gh` commands. Add `-ConfigureGitHubEnvironment` to run them.

## Feature 2: orchestrator intake, Container Apps, GitHub App

**Hosting.** Terraform ([orchestrator.tf](azure-harness/infra/orchestrator.tf)) creates an Azure Container Registry, a user-assigned identity with `AcrPull`, a Container Apps environment and `ca-sdlc-orchestrator` (external ingress, port 8080, `/healthz` probe). The app is created only when `orchestrator_image` is set. 002 builds the image with `az acr build` (after a targeted apply of the registry), then applies the full configuration. The Foundry key, App Insights connection string and GitHub App key are Container Apps secrets.

**Intake** ([server.js](azure-harness/orchestrator/server.js), [auth.js](azure-harness/orchestrator/auth.js)): validates the Entra JWT (RS256 via tenant JWKS; tenant, audience, caller client id, `Dispatch` role), checks the repo allow-list (`ALLOWED_REPOS`), deduplicates by `Idempotency-Key` (in memory), and returns 202.

**GitHub App** ([github.js](azure-harness/orchestrator/github.js)). Setup:

1. Create a GitHub App with repository permissions Issues, Pull requests, Contents: read/write (and Metadata: read). No webhook needed.
2. Install it on the repo; note the App ID and Installation ID.
3. Store the private key (PEM) in Key Vault as secret `github-app-private-key`.
4. Run 002 with `-GitHubAppId` and `-GitHubAppInstallationId`.

PRs go to a new `squad/issue-<n>-<id>` branch; the model cannot write to `.github/`, absolute or `..` paths, or `.ps1` files.

## Feature 3: Application Insights `sdlc-appinsights`

[monitoring.tf](azure-harness/infra/monitoring.tf) creates:

- Log Analytics workspace `log-sdlc-harness`.
- Workspace-based Application Insights `sdlc-appinsights`.
- A diagnostic setting sending the Foundry (AI Services) account's logs and metrics to Log Analytics.
- A Foundry connection `sdlc-appinsights` (category `AppInsights`, via `azapi`) so the Foundry project can trace into it.

The orchestrator sends custom events through the ingestion API ([telemetry.js](azure-harness/orchestrator/telemetry.js)): `sdlc.workitem.accepted|done|failed|denied`, `sdlc.model.route` (deployment, task type, complexity, volume tier, latency, tokens) and `sdlc.model.fallback`. Example query:

```kusto
customEvents | where name == "sdlc.model.route"
| summarize requests=count(), tokens=sum(todouble(customMeasurements.totalTokens)) by tostring(customDimensions.deployment)
```

## Deploy

```powershell
. .\infra\002SetupAzure.ps1
Invoke-SdlcDocsHarnessDeployment -TenantId <tenant> -SubscriptionId <sub> -Location australiaeast `
  -HarnessResourceGroup rg-sdlcdocs-harness-aue -GitHubRepo ozbobdev/SDLCagentBDD `
  -DeployOrchestrator -GitHubAppId <id> -GitHubAppInstallationId <id>   # add -ConfigureGitHubEnvironment to set GitHub env values
```

Creating the Entra role assignment needs rights to manage app registrations and grant app roles.

## Security boundaries

- Cloud agent: no custom provider, no Foundry key in Agents secrets.
- Dispatch: OIDC federation scoped to one environment; reviewers on that environment; role-based access to the orchestrator.
- Orchestrator: repo allow-list, idempotency, request size cap, protected paths, PRs only (no default-branch pushes).

## Limitations

- v0 orchestrator triages and opens PRs from model output; it has no sandboxed code execution or test running. Treat PRs as drafts for review.
- Idempotency is in memory (lost on restart or multiple replicas; run a single replica or add a store).
- The Foundry-to-App Insights connection (`azapi`, preview API) and the orchestrator deployment have not yet been applied or run end to end; `squad-dispatch.yml` has not run.
- The unit tests mock the model and GitHub (`npm test` in `azure-harness/orchestrator`).
