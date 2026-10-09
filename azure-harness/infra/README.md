# Azure Harness Infrastructure (Terraform scaffold)

This folder contains a minimal Terraform scaffold for deploying an Azure AI Harness-oriented agent setup:
- Orchestrator container app
- BDD specialized agent container app
- Shared resource group placeholder

## Secrets and variables
Configure credentials through environment variables or GitHub Actions secrets documented in `/github.md`:
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_HARNESS_API_KEY`

## Quick start
```bash
terraform init
terraform plan \
  -var="resource_group_name=rg-sdlcdocs" \
  -var="location=australiaeast" \
  -var="orchestrator_image=ghcr.io/ozbobdev/orchestrator:latest" \
  -var="bdd_agent_image=ghcr.io/ozbobdev/bdd-agent:latest"
```
