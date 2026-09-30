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
1. Create or choose an Azure subscription for this repo.
2. Create a service principal with rights to deploy:
   - Agent harness resource group
   - Sample app resource group
   - Terraform state storage account/container
3. Create Terraform backend storage (Azure Storage account + blob container).
4. Add required GitHub repository secrets:
   - `AZURE_CLIENT_ID`
   - `AZURE_CLIENT_SECRET`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `TF_BACKEND_RESOURCE_GROUP`
   - `TF_BACKEND_STORAGE_ACCOUNT`
   - `TF_BACKEND_CONTAINER`
5. Add integration secrets if needed:
   - `AZURE_HARNESS_API_KEY`
   - `AZURE_STORAGE_CONNECTION_STRING`
   - `AZURE_KEYVAULT_NAME`
6. Run workflow:
   - `.github/workflows/first-use-bootstrap.yml`
   - Provide `harness_resource_group`, `sample_app_resource_group`, and container image inputs.

## How to contribute
- Product Owners: open issues for new features using the intake template.
- Developers: follow the Developer checklist in AGENT_PROMPT.txt.
- Squad leader: review and merge PRs that update SDLC workflows.

End of README.
