# Azure AI Harness: model router and Copilot provider

Routes each request or sub-task to a Foundry model deployment by task type, complexity and volume.

| Path | Purpose |
|---|---|
| `models/routing.json` | Routing table, escalation, volume threshold, fallback chain, senior/junior levels |
| `router/router.js` | `selectModel(config, request)`, `VolumeTracker`, `CircuitBreaker` |
| `provider/server.js` | OpenAI-compatible gateway (`/v1/chat/completions`, `/v1/models`, `/healthz`); virtual model `sdlc-auto` |
| `infra/` | Terraform: Foundry account, project, model deployments (`additional_model_deployments`) |
| `Dockerfile` | Container image for Azure Container Apps (build context is this folder) |
| `../.github/workflows/squad-dispatch.yml` | Label/comment-driven dispatch of work items to the orchestrator |

## Test

```powershell
cd azure-harness\router
npm test
```

## Run the provider locally

```powershell
$env:AZURE_HARNESS_ENDPOINT = "https://<account>.cognitiveservices.azure.com/"
$env:AZURE_HARNESS_API_KEY = "<from Key Vault>"
$env:AZURE_HARNESS_MODEL_DEPLOYMENTS = "gpt-4o-mini,gpt-5.6-terra,gpt-6.1-sol,gpt-6-sol,gpt-6-astra"
$env:PROVIDER_CLIENT_TOKEN = "<local token>"
node azure-harness\provider\server.js
```

Point the local Copilot SDK (BYOK) at `http://localhost:8080/v1` with model `sdlc-auto`. Optional request headers: `x-sdlc-task-type`, `x-sdlc-complexity` (`low|medium|high`), `x-sdlc-level` (`senior|junior`), `x-sdlc-volume` (`normal|high`). A response header `x-sdlc-model` reports the deployment used. Any model name other than `sdlc-auto` passes through.

This provider serves the local SDK and the Azure orchestrator only. The GitHub-hosted cloud agent cannot use it; see [plan.md](../plan.md).

## Dispatch workflow setup

`squad-dispatch.yml` runs in the `azure-harness-dispatch` environment (add required reviewers as needed). Configure environment secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (OIDC federated identity, no stored keys) and variables `ORCHESTRATOR_URL`, `ORCHESTRATOR_AUDIENCE`. Labels: `squad`, `squad:{member}`, `level:senior|junior`, `complexity:low|medium|high`, `type:{taskType}`, `volume:high`. The orchestrator intake (`POST /work-items`) is not implemented yet.
