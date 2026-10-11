# Azure Prompt Agent support infrastructure (Terraform)

This Terraform module provisions baseline Azure resources for **Path A — Prompt Agent**:

- Resource group
- Azure AI Foundry account (`kind = AIServices`)
- Chat model deployment
- Azure AI Foundry project
- Storage account (optional harness artifacts)

The Prompt Agent itself is managed in Microsoft Foundry. Terraform here provisions the endpoint and keys that your local tooling and GitHub BYOK flow can use.

## Key outputs

- `harness_api_key` — Azure AI Services primary key (sensitive)
- `harness_endpoint` — Azure OpenAI-compatible endpoint
- `model_deployment_name` — model deployment to call from clients
- `foundry_project_name` / `foundry_project_id` / `foundry_project_endpoints` — Foundry project metadata

The account is configured according to Microsoft Foundry upgrade guidance:
- `kind = AIServices`
- `project_management_enabled = true`
- system-assigned managed identity enabled

Provider configuration includes AzureRM (primary) and AzAPI compatibility with the upgrade guidance that supports either provider path.

## Notes

- Model availability and versions vary by region/subscription quota.
- Prompt Agent definitions/instructions remain in Foundry; this module does not create a Foundry agent resource.
