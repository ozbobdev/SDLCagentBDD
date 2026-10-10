# SDLCdocs

Document driven software development lifecycle repository.

## Purpose
SDLCdocs defines a document-first SDLC where Product Owners, Developer agents, and Project Managers collaborate via a Product Catalog wiki and a BDD wiki. Agents automate intake, issue creation, BDD generation, and documentation maintenance.

## Repo structure
- AGENT_PROMPT.txt
- sub-agents.md
- github.md
- agents/
  - monitor_and_fix_bugs.md
- infra/
  - 001SetupAzure.ps1
  - 002SetupAzure.ps1
- samples/
  - README.md
  - sample-squad.json
  - sample-app/
    - openapi-v0.1.yaml
    - openapi-v1.0.yaml
    - dotnet-api/
    - angular-web/
- screenshots/

## Squad
This repo needs a Squad team leader who iterates on documentation and SDLC workflows.

Install squad CLI
- npm install -g @bradygaster/squad-cli

Start copilot agent for squad
- copilot --agent squad --yolo

## First use (GitHub + Azure setup)
1. Install prerequisites:
   - Azure CLI (`az`)
   - GitHub CLI (`gh`), authenticated with permission to manage secrets in the target repo
   - Terraform 1.6+
   - PowerShell 7+
2. Run script `.\infra\001SetupAzure.ps1` to create prerequisites and required GitHub secrets.
3. Use either Azure Portal or Azure CLI sign-in values (`TenantId`, `SubscriptionId`, `Location`) when invoking the script.
4. Required secrets written by `001SetupAzure.ps1`:
   - `AZURE_CLIENT_ID`
   - `AZURE_CLIENT_SECRET`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `TF_BACKEND_RESOURCE_GROUP`
   - `TF_BACKEND_STORAGE_ACCOUNT`
   - `TF_BACKEND_CONTAINER`
5. Script `001SetupAzure.ps1` sets least-privilege roles:
   - Contributor on harness and sample-app resource groups
   - Storage Blob Data Contributor on Terraform backend container
6. Run script `.\infra\002SetupAzure.ps1` to apply Terraform for `azure-harness/infra`, provision remaining setup, and store:
   - `AZURE_HARNESS_API_KEY`
   - `AZURE_STORAGE_CONNECTION_STRING`
   - `AZURE_KEYVAULT_NAME`

### Container images
The Azure harness deploys two separate Azure Container Apps:
- `ghcr.io/ozbobdev/orchestrator:latest` runs the orchestrator (`ca-orchestrator`).
- `ghcr.io/ozbobdev/bdd-agent:latest` runs the BDD specialized agent (`ca-bdd-agent`).

This repository only references these images; it does not build or publish them. Publish both images to GHCR before deploying, and ensure each image is available to Azure Container Apps. The current Terraform configuration does not set GHCR credentials, so these package references must be publicly pullable; private GHCR packages require adding registry authentication to the deployment configuration. Both apps are configured for internal-only ingress on port 8080, so the images must provide services that listen on that port.

GHCR is the current default because this project and its deployment workflow are hosted on GitHub, making GHCR a convenient home for the OCI images without adding an Azure registry to the scaffold. It is a configurable registry choice, not a Microsoft Foundry requirement. The Container Apps can use images from another registry, such as Azure Container Registry (ACR), provided the apps can pull them and any required registry authentication is configured.

The image-based Container Apps are also an architectural choice. The [Microsoft Foundry Skills scenarios](https://learn.microsoft.com/en-us/azure/foundry/how-to/develop/foundry-skills-scenarios-example-prompts) describe alternatives including **hosted agents**, where Foundry Agent Service manages deployment of agent code, and **Prompt Agents**, which are configured in Foundry rather than run as these custom containers. These alternatives would require adapting the harness and deployment workflow; they are not drop-in registry replacements.

The scripts and GitHub Actions workflow default to the `latest` tags above. To deploy different tags or image names, pass `-OrchestratorImage` and `-BddAgentImage` to `Invoke-SdlcDocsHarnessDeployment`, or change `ORCHESTRATOR_IMAGE` and `BDD_AGENT_IMAGE` in `.github/workflows/deploy-azure-harness.yml`. The Terraform variables are `orchestrator_image` and `bdd_agent_image`.

### Setup assumptions
- The Azure account used by the setup scripts can create resource groups, storage resources, a service principal, and role assignments in the selected subscription. The scripts grant the deployment principal Contributor on the harness and sample-app resource groups, and Storage Blob Data Contributor on the Terraform state container.
- `gh` is authenticated to the repository passed as `GitHubRepo`. The deployment workflow uses GitHub Actions OIDC (`azure/login`); configure an Azure federated identity credential for this GitHub repository and the workflow's triggering branch/environment. `001SetupAzure.ps1` creates the service principal and secrets but does not configure that federation.
- The deployment workflow runs when a pull request changes `azure-harness/**`, or when manually dispatched. It applies Terraform using the configured images and Azure backend; it does not build or publish container images.

### Script usage
```powershell
. .\infra\001SetupAzure.ps1
Initialize-SdlcDocsEnvironment `
  -TenantId "<tenant-id>" `
  -SubscriptionId "<subscription-id>" `
  -Location "australiaeast" `
  -GitHubRepo "owner/repo"

. .\infra\002SetupAzure.ps1
Invoke-SdlcDocsHarnessDeployment `
  -TenantId "<tenant-id>" `
  -SubscriptionId "<subscription-id>" `
  -Location "australiaeast" `
  -GitHubRepo "owner/repo"
```

## How to contribute
- Product Owners: open issues for new features using the intake template.
- Developers: follow the Developer checklist in AGENT_PROMPT.txt.
- Squad leader: review and merge PRs that update SDLC workflows.

End of README.
