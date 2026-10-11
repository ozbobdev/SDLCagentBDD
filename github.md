# GitHub BYOK integration for Azure harness

This guide documents how to connect GitHub Copilot BYOK to the Azure resources provisioned by this repository.

## 1) Provision Azure resources and capture outputs

Run [002SetupAzure.ps1](/c:/dev/s/ozbobdev/SDLCagentBDD/infra/002SetupAzure.ps1), which provisions Terraform infrastructure from [azure-harness/infra/](/c:/dev/s/ozbobdev/SDLCagentBDD/azure-harness/infra/) and sets secrets:

```powershell
. .\infra\002SetupAzure.ps1
Invoke-SdlcDocsHarnessDeployment `
  -TenantId "<tenant-guid>" `
  -SubscriptionId "<subscription-guid>" `
  -Location "australiaeast" `
  -GitHubRepo "ozbobdev/SDLCagentBDD"
```

Expected Terraform outputs:

- `harness_api_key`
- `harness_endpoint`
- `model_deployment_name`

The script writes those values to:

- Azure Key Vault (`harness-api-key`, `harness-endpoint`, `harness-model-deployment`)
- GitHub repository secrets
- Local user environment variables (by default)

## 2) GitHub secrets required for Copilot BYOK

Set these repository secrets (the script does this automatically):

- `AZURE_HARNESS_API_KEY`
- `AZURE_HARNESS_ENDPOINT`
- `AZURE_HARNESS_MODEL_DEPLOYMENT`
- `AZURE_FOUNDRY_PROJECT_NAME`
- `AZURE_FOUNDRY_PROJECT_ID`

For Terraform backend and Azure auth (if your workflows deploy infra):

- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `TF_BACKEND_RESOURCE_GROUP`
- `TF_BACKEND_STORAGE_ACCOUNT`
- `TF_BACKEND_CONTAINER`

## 3) Configure Copilot BYOK

Follow the official GitHub documentation:

- [Bring your own key for Copilot SDK](https://docs.github.com/en/copilot/how-tos/copilot-sdk/auth/byok)

When mapping BYOK values, use:

- Endpoint: `AZURE_HARNESS_ENDPOINT`
- Key: `AZURE_HARNESS_API_KEY`
- Deployment/model: `AZURE_HARNESS_MODEL_DEPLOYMENT`

This enables GitHub-side Copilot agent workflows (including issue-driven flows where supported by your Copilot setup) to call the Azure-hosted model.

## 4) Local developer provider configuration

Each developer should set local environment variables:

```powershell
[Environment]::SetEnvironmentVariable("AZURE_HARNESS_API_KEY","<value>","User")
[Environment]::SetEnvironmentVariable("AZURE_HARNESS_ENDPOINT","<value>","User")
[Environment]::SetEnvironmentVariable("AZURE_HARNESS_MODEL_DEPLOYMENT","<value>","User")
[Environment]::SetEnvironmentVariable("AZURE_FOUNDRY_PROJECT_NAME","<value>","User")
[Environment]::SetEnvironmentVariable("AZURE_FOUNDRY_PROJECT_ID","<value>","User")
```

Then configure local Copilot provider settings (Copilot CLI / VS Code) to reference those values instead of hard-coded credentials.

## Security recommendations

- Do not commit keys, tokens, tfplan files, or Terraform state.
- Prefer OIDC/federated identity in CI/CD instead of long-lived client secrets.
- Rotate `AZURE_HARNESS_API_KEY` on a regular schedule.
