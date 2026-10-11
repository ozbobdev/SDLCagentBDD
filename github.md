# GitHub Integration with Azure AI Harness and BYOM/BYOK

This document explains how to connect GitHub to Azure AI Harness and what secrets/credentials are required to allow Copilot or automation to execute Terraform or Bicep deployments.

## Goals
- Allow GitHub Actions or Copilot-driven automation to call Azure AI Harness endpoints.
- Allow GitHub workflows to run Terraform or Bicep to provision or update Azure resources.
- Support BYOM (Bring Your Own Model) and BYOK (Bring Your Own Key) patterns.

## Required Azure identities and tokens
1. **Azure Service Principal** (recommended for GitHub Actions)
   - Create a service principal with least privilege for the target subscription/resource group.
   - Required values to store in GitHub Secrets:
     - `AZURE_CLIENT_ID`
     - `AZURE_CLIENT_SECRET`
     - `AZURE_TENANT_ID`
     - `AZURE_SUBSCRIPTION_ID`
2. **Azure AI Harness API Key or Token**
   - If Azure AI Harness exposes an API key for model endpoints, store it as:
     - `AZURE_HARNESS_API_KEY` or `AZURE_AI_HARNESS_KEY`
3. **Key Vault access**
   - If workflows need to read secrets from Key Vault, either:
     - Grant the service principal access to Key Vault, or
     - Use a short-lived token flow and store only minimal secrets in GitHub.
4. **Optional: Managed Identity**
   - If using self-hosted runners in Azure, use a managed identity instead of client secret.

## GitHub Secrets to set
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `TF_BACKEND_RESOURCE_GROUP`
- `AZURE_HARNESS_API_KEY` (or equivalent)
- `AZURE_STORAGE_CONNECTION_STRING` (if workflows upload screenshots/artifacts)
- `AZURE_KEYVAULT_NAME` (if workflows reference Key Vault)
- `TF_BACKEND_STORAGE_ACCOUNT` and `TF_BACKEND_CONTAINER` (if using Terraform remote state)
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` (alternate names used by some Terraform providers)

## Azure resources required before first deployment
Before running deployment automation, create:
1. **Service principal** with least-privilege roles:
   - Contributor on target deployment resource groups
   - Storage Blob Data Contributor on the Terraform state container
2. **Terraform backend resources**:
   - Resource group for Terraform state
   - Storage account for Terraform state
   - Blob container for Terraform state
3. **Target resource groups**:
   - Agent harness resource group (for Terraform-managed agent infrastructure)
   - Sample app resource group (separate resource group for sample app deployment)

## First-use scripts
- Use `infra/001SetupAzure.ps1` to:
  - Create/update required Azure prerequisites
  - Configure required GitHub secrets
- Use `infra/002SetupAzure.ps1` to:
  - Run Terraform init/plan/apply for `azure-harness/infra`
  - Configure optional GitHub secrets from deployment outputs/resources
- Use `infra/003ConfigureBYOK.ps1 -Organization "<org>"` to verify GitHub CLI authentication and get guided BYOK setup steps. It logs the command it runs to a temporary file and never accepts or stores a provider key.

## GitHub Actions patterns
- **Login to Azure**: use `azure/login` action with the service principal secrets.
- **Terraform**: use `hashicorp/setup-terraform` and run `terraform init` with backend configured to use Azure Storage.
- **Bicep**: use `azure/cli` to run `az deployment group create` or `az deployment sub create`.
- **Azure AI Harness calls**: call the Harness endpoint using `curl` or a small script that uses `AZURE_HARNESS_API_KEY`.

## Copilot execution considerations
- GitHub's BYOK documentation currently describes enterprise custom models as available in Copilot Chat, Copilot CLI, and IDEs. Supported providers include Anthropic, AWS Bedrock, Google AI Studio, Microsoft Foundry, OpenAI, OpenAI-compatible providers, and xAI. Enterprise custom models are in public preview; an enterprise owner can add a provider key and models in **AI controls > Copilot > Configure custom models**, then manage organization access. Organization owners can configure models if their enterprise policy permits it. See [GitHub's BYOK guide](https://docs.github.com/en/copilot/concepts/models/bring-your-own-key) and [enterprise custom models setup](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-for-enterprise/enable-custom-models).
- Cloud Agent documentation describes model selection in supported entrypoints but does not list enterprise BYOK custom models among its supported models. Do not assume Cloud Agent uses a configured BYOK key; verify availability in the Cloud Agent model picker and current GitHub documentation before relying on it. See [changing the AI model for Cloud Agent](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/changing-the-ai-model).
- Copilot in Visual Studio will call the orchestrator endpoint; the orchestrator must have permission to call Azure AI Harness and GitHub.
- For Copilot to trigger infra changes, the orchestrator or CI pipeline must use the service principal credentials stored in GitHub Secrets.

## Security best practices
- Use short-lived credentials where possible.
- Store only non-sensitive references in repo; keep secrets in GitHub Secrets or Key Vault.
- Limit service principal permissions to required resource groups.
- Audit and rotate keys regularly.

End of GitHub integration guidance.
