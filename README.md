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
   - GitHub CLI (`gh`) authenticated to the target repo
   - Terraform
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
