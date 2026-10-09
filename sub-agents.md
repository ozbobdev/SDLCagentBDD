# Sub Agents and Azure AI Harness Integration

This document describes how to configure Copilot in Visual Studio (not VS Code) to use Bring Your Own Model (BYOM) via Azure AI Harness, how to design a one-agent then specialized-agent architecture, and recommended infrastructure and model choices.

## Overview
- **Goal**: Provide a layered agent architecture where a generalist "orchestrator" agent handles intake and routing, and specialized agents handle tasks such as BDD authoring, GitHub project management, code analysis, screenshot analysis, and test orchestration.
- **Platform**: Azure AI Harness (https://ai.azure.com/) as the agent hosting and model serving environment.
- **IDE integration**: Configure Copilot in Visual Studio to call the orchestrator agent via secure endpoints and keys.

## Agent architecture
1. **Orchestrator agent**
   - Responsibilities: intake, routing, project creation, issue creation, high-level validation.
   - Interfaces: GitHub API, Azure Key Vault, Azure AI Harness endpoints, storage for screenshots and artifacts.
2. **Specialized agents**
   - **BDD agent**: generates Gherkin scenarios and maps to test cases.
   - **Project agent**: creates GitHub projects and issues, manages labels and milestones.
   - **Developer planner agent**: breaks issues into tasks and generates implementation plans.
   - **Code analyzer agent**: reads code, OpenAPI3, and comments to update docs.
   - **Screenshot agent**: crops, tags, and stores screenshots; generates references for wiki pages.
   - **CI/CD agent**: triggers Terraform/Bicep deployments and validates infra state.

## Visual Studio Copilot BYOM configuration
- Visual Studio Copilot can be configured to call a custom agent endpoint (the orchestrator) hosted in Azure AI Harness.
- Steps (high level):
  1. Provision Azure AI Harness project and model endpoints.
  2. Create a secure API endpoint for the orchestrator agent (HTTPS, token-protected).
  3. In Visual Studio Copilot settings, configure the "Bring Your Own Model" endpoint and provide the token or secret stored in Windows Credential Manager or Visual Studio secure settings.
  4. Ensure the orchestrator endpoint accepts requests from the Copilot client and returns structured responses (JSON) that Copilot can render or use.

## Azure AI Harness project structure recommendations
- **Project root**: `azure-harness/`
  - `orchestrator/` — code and deployment for orchestrator agent
  - `agents/` — each specialized agent as a subproject (bdd-agent, project-agent, code-agent, screenshot-agent)
  - `infra/` — Terraform or Bicep definitions for the Harness environment, storage accounts, Key Vault, App Service or Container Apps
  - `models/` — model configuration files and prompts
  - `pipelines/` — CI/CD pipelines to deploy agents and infra
- **State and secrets**
  - Use Azure Key Vault for secrets and model keys.
  - Use a storage account or Azure Files for screenshots and artifacts.
  - Use Application Insights for telemetry and logging.

## Infrastructure as code options
- **Terraform**: mature, cross-cloud, good for complex infra. Example: use foundry-samples Terraform modules as a starting point.
- **Bicep**: Azure-native, concise, and integrates well with Azure DevOps and GitHub Actions.
- **Combination**: Use Terraform for cross-account or multi-cloud pieces and Bicep for Azure-native resources where you want concise templates.
- **Aspire**: If Aspire is an orchestration or management layer you prefer, it can be used to manage deployments on top of Terraform/Bicep. Evaluate based on team familiarity.

## Architectural layers
1. **Agent orchestration layer**: Orchestrator agent, routing, authentication.
2. **Model serving layer**: Azure AI Harness model endpoints, model selection, scaling.
3. **Data and artifact layer**: Storage for screenshots, wiki artifacts, logs.
4. **Integration layer**: GitHub, CI/CD, Key Vault, OpenAPI storage.
5. **Infra provisioning layer**: Terraform/Bicep pipelines and state management.
6. **Monitoring and observability**: App Insights, logs, and dashboards.

## Model choices
- **Generalist LLM**: for orchestrator and natural language tasks.
- **Specialized models**: smaller or fine-tuned models for BDD generation, code analysis, or screenshot captioning.
- **Vision models**: for screenshot analysis and cropping.
- **Hybrid**: route heavy NLP to larger models and deterministic tasks to smaller, cheaper models.

## Security and governance
- Use Key Vault for secrets and rotate keys regularly.
- Use role-based access control for Azure resources.
- Audit GitHub actions and agent access to repositories.

## Deployment pattern
- CI/CD pipeline builds agent containers and deploys to Azure Container Apps or App Service.
- Terraform/Bicep manages infra; GitHub Actions or Azure Pipelines trigger deployments.
- Canary or blue/green deployments for agent updates.

## Example minimal project to start
- Deploy orchestrator + one specialized agent (BDD agent).
- Provide a secure endpoint and a GitHub Actions workflow that runs tests and deploys to Azure.
- Expand agents incrementally.

End of sub-agents guidance.
