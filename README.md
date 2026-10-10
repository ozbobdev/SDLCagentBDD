# SDLCagentBDD

Document-driven software development lifecycle repository. The workflow uses GitHub Copilot CLI and Squad CLI to support intake, BDD authoring, issue management, and documentation maintenance.

## Repository contents

- `sub-agents.md`, `github.md` — architecture proposals and GitHub integration notes.
- `agents/` — agent prompt material.
- `samples/` — sample squad and sample application.
- `infra/`, `azure-harness/` — an experimental Azure Container Apps harness scaffold; it is not a Microsoft Foundry deployment.

The repository does not currently contain a Foundry `azure.yaml`, a Foundry Prompt Agent definition, hosted-agent application source, or a container build. Do not treat the legacy harness scaffold as a reproducible Foundry deployment.

## Local repository workflow

Install Node.js/npm, GitHub CLI, GitHub Copilot CLI, and authenticate GitHub CLI for the repository where you will work:

```bash
gh auth login
npm install -g @bradygaster/squad-cli
copilot --agent squad
```

Use the Squad leader to iterate on the repository's documentation and SDLC workflows. `samples/sample-squad.json` provides a sample team definition. See the [Copilot CLI getting-started guide](https://docs.github.com/en/copilot/how-tos/copilot-cli/cli-getting-started) for installing and authenticating Copilot CLI.

## Microsoft Foundry deployment choices

The recommended Foundry starting point is a **Prompt Agent**, provided its instructions, model, and configured tools can perform the required work. The repository's GitHub/Copilot workflow remains local; creating a Prompt Agent does not grant it access to a developer's checkout, GitHub, or a test runner. Connect only the tools it needs, with appropriately scoped permissions. Move to a hosted agent only when a verified requirement needs custom application code.

### Path A — Prompt Agent (recommended)

Prompt Agents are managed by Foundry and need no custom runtime code, container, or image registry.

1. In the [Microsoft Foundry portal](https://ai.azure.com), create or select a Foundry project and deploy a chat-capable model. Use an account with permission to create agents in the project and provision the model.
2. Create a Prompt Agent in that project. Define and version its instructions, select the model deployment, and configure only the tools it needs.
3. Test it in the Foundry playground. If it must interact with GitHub or other services, first connect and test the required supported tool or MCP endpoint; do not assume repository access.
4. For repeatable, reviewed agent-definition changes, use the Foundry SDK or REST API rather than treating a portal-only definition as source controlled.

Use a coding-agent host rather than a deployed Prompt Agent when the task needs local repository access. The optional [Microsoft Foundry Skill](https://learn.microsoft.com/en-us/azure/foundry/how-to/develop/use-microsoft-foundry-skill) guides coding agents through Foundry workflows; it is not an agent runtime or a substitute for configuring agent tools. Install it with:

```bash
npx skills add https://github.com/microsoft/azure-skills --skill microsoft-foundry
```

### Path B — Hosted Agent deployed from source (optional)

Choose this only when custom agent code or orchestration is necessary. The current [`azd` code-deployment flow](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-code) uploads a source ZIP for Foundry to build and deploy; you do not build or publish a container image yourself.

Install the current Foundry Dev Pack (`azd` 1.27.1 or later), then in a **separate, empty workspace** follow the current [Hosted Agent quickstart](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/quickstart-hosted-agent) with the maintained basic sample:

```bash
azd auth login
azd ai agent init -m "https://github.com/microsoft-foundry/foundry-samples/blob/main/samples/python/hosted-agents/agent-framework/responses/01-basic/azure.yaml" --deploy-mode code
cd agent-framework-agent-basic-responses
azd provision
azd ai agent run
azd deploy
azd ai agent invoke "Hello from my hosted agent"
```

Use the agent name created by initialization if it differs from the sample name. The quickstart currently requires `azd` 1.27.1 or later; check its prerequisites for updated version and permission requirements. This sample is a starting point, not code already present in this repository.

### Path C — Hosted Agent deployed from a container (optional)

Use an image deployment only when the implementation needs an image/runtime not supported by source deployment, or you already have a prebuilt image to deploy. Foundry consumes the agent image; the registry is not used by Prompt Agents. Microsoft's current container workflow builds and pushes to **Azure Container Registry (ACR)**, then Foundry pulls the image; the `azd` and VS Code tooling can automate the build, push, versioning, and registry permissions. The current Foundry guidance does not recommend GHCR as a Foundry registry. See the [hosted-agent deployment guide](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent), [ACR private-network guidance](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry), and [external private-registry guidance](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/private-registry-connections) for the selected flow.

Build and publish only through the documented `azd`/Foundry workflow. Use immutable image tags (for example, a commit SHA or digest), least-privilege registry access, and retain build provenance, an SBOM, and vulnerability-scan results. Never put registry credentials in the repository or use a mutable tag such as `latest` for a release. This project has no hosted-agent image or build pipeline, so this path is not currently reproducible here.

### Local development with Aspire

Aspire is an optional local development/orchestration experience, not a Foundry agent deployment mode or an infrastructure-provisioning replacement. See the maintained [Aspire Foundry Agent playground](https://github.com/dotnet/aspire/tree/main/playground/FoundryAgentBasic) for its local development model.

### Infrastructure, identity, and CI/CD

Agent choice and infrastructure provisioning are separate decisions. The `azd` hosted-agent sample provisions resources using its Bicep configuration. Use Terraform only when you need Terraform-managed Foundry resources; Microsoft's [standard-agent Terraform sample](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-terraform/41-standard-agent-setup) provisions a Foundry project and supporting resources, not this repository's Container Apps.

For local development, sign in interactively with `az login` and, for `azd`, `azd auth login`. Do not create a client secret just to run the local quickstart. For GitHub Actions deployment, follow Microsoft's [Hosted Agent CI/CD guidance](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/set-up-cicd-hosted-agent) and use its federated/OIDC identity setup instead of long-lived client secrets. Grant only the roles required by the selected Foundry and infrastructure operations. The legacy `infra/001SetupAzure.ps1` script creates a client secret; it is not needed for this Foundry workflow.

## Legacy Azure Container Apps scaffold

`azure-harness/infra` and `infra/002SetupAzure.ps1` are a separate, experimental deployment of two Azure Container Apps. Those apps—not Foundry—consume the `orchestrator_image` and `bdd_agent_image` references. Existing script and workflow defaults point to `ghcr.io/ozbobdev/...:latest`, but this repository contains no corresponding agent sources or image build/publish workflow, and does not document registry authentication, provenance, or scanning. GHCR is therefore an existing scaffold detail, not a Foundry requirement or Microsoft recommendation. Do not use these scripts or `.github/workflows/deploy-azure-harness.yml` as the Foundry setup path.

## Further reading

- [Microsoft Foundry Agent Service overview](https://learn.microsoft.com/en-us/azure/foundry/agents/overview)
- [Choose how to build an agent](https://learn.microsoft.com/en-us/azure/foundry/what-is-foundry#start-by-building-an-agent)
- [Microsoft Foundry SDK overview](https://learn.microsoft.com/en-us/azure/foundry/how-to/develop/sdk-overview)
- [Azure Developer CLI agent development](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/cli-agent-development)
- [Microsoft Agent Framework](https://learn.microsoft.com/en-us/agent-framework/)
- [Foundry Skill scenarios and example prompts](https://learn.microsoft.com/en-us/azure/foundry/how-to/develop/foundry-skills-scenarios-example-prompts)
- [Microsoft Foundry hosted-agent samples](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/csharp/hosted-agents)
- [Foundry hosted-agent CI/CD quickstart](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/set-up-cicd-hosted-agent)

## Contributing

- Product owners: open issues for new features and workflow changes.
- Developers: follow the relevant project checklist and update the BDD and product documentation with changes.
- Squad leader: review and merge pull requests that update SDLC workflows.
