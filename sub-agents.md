# Sub Agents and Microsoft Foundry Integration

This document describes the separate Azure-hosted agent architecture and its relationship to GitHub Copilot cloud agent. The GitHub cloud agent and the Azure-hosted orchestrator have separate runtimes, credentials, model selection, and permissions.

## Overview
- **Azure-hosted architecture**: A generalist orchestrator can route to specialized agents for BDD authoring, GitHub project management, code analysis, screenshot analysis, and test orchestration.
- **Platform**: Microsoft Foundry (https://ai.azure.com/) hosts the Azure-side agents and model deployments.
- **GitHub Copilot cloud agent**: A GitHub-managed repository coding agent for issue investigation, code/documentation changes, and pull requests under repository policy. It is not the Azure orchestrator and does not inherit its model or credentials.

## GitHub Copilot cloud-agent boundary

GitHub documents BYOK for the Copilot SDK, not as a way to select the model used by GitHub's hosted cloud-agent service. Keep ordinary repository work on the cloud agent's supported GitHub model configuration. Do not add the Foundry API key as an **Agents** secret: GitHub exposes those secrets as environment variables to the cloud agent.

The agent may request that a maintainer run a dedicated, manually dispatched workflow. Foundry connectivity is tested only by the `foundry-byok` Actions environment, whose secrets are available to a single smoke-test step after environment approval. Azure infrastructure deployment is separate and gated by the `azure-harness-deploy` environment. A workflow approval is not permission to expose Actions secrets to the agent.

See [github.md](./github.md) for the environment setup, smoke-test invocation, and current BYOK limitation.

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

## Local Copilot SDK BYOK

The Copilot SDK can use a Microsoft Foundry endpoint with BYOK for a **local SDK process**. This is separate from the hosted GitHub cloud agent and from the Azure-hosted Foundry agents below. Follow the current [Copilot SDK BYOK guide](https://docs.github.com/en/copilot/how-tos/copilot-sdk/auth/byok) for SDK provider/model compatibility.

## Azure-hosted agent configuration

- A separate client or integration can call a custom agent endpoint hosted in Microsoft Foundry, subject to that client's supported configuration.
- Steps (high level):
  1. Provision a Microsoft Foundry project and model endpoint.
  2. Create a secure API endpoint for the orchestrator agent (HTTPS, token-protected).
  3. Configure the supported client or integration with a credential stored in an appropriate protected secret store.
  4. Ensure the orchestrator endpoint accepts requests from that client and returns the response format it supports.

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
- **Model routing**: requests to model `sdlc-auto` are routed by task type, complexity and volume; see [azure-harness/README.md](./azure-harness/README.md) and [plan.md](./plan.md).
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
