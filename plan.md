# Plan: GitHub Copilot Cloud Agent with BYOK and GitHub Secrets

## Goal

Enable the GitHub Copilot cloud agent to perform approved repository work using the configured bring-your-own-key (BYOK) model setup, while allowing related automation to use repository secrets without exposing their values to the agent.

## Current context

- `github.md` documents Azure AI Foundry BYOK configuration and the `AZURE_HARNESS_*` repository secrets.
- `sub-agents.md` describes an Azure-hosted orchestrator and specialized agents, while the current request is about the GitHub Copilot cloud agent.
- The Terraform deployment and setup scripts provision Azure resources and configure GitHub secrets.
- Confirm whether the cloud agent's model configuration supports the intended BYOK provider; do not assume that a repository secret configures the model used by the cloud agent.

## Proposed work

1. **Confirm supported product configuration**
   - Verify the account/organization/repository settings and plan requirements for the GitHub Copilot cloud agent.
   - Verify whether BYOK applies to the cloud agent's model runtime or only to an external Azure AI Foundry agent/service.
   - Document the selected supported arrangement and any limitations before changing workflows.

2. **Define the agent's repository role**
   - Specify the repository tasks the cloud agent may perform, such as investigating issues, proposing code/documentation changes, and opening pull requests.
   - Keep infrastructure deployment, secret rotation, and other privileged operations outside the agent's direct execution unless explicitly approved.
   - Describe how the cloud agent can request a dedicated workflow run rather than receiving credentials itself.

3. **Separate model credentials from workflow credentials**
   - Store BYOK/API credentials and Azure/GitHub automation credentials only in the appropriate protected settings or GitHub Secrets.
   - Expose secrets only to the specific workflow step that needs them, using least-privilege token permissions and protected environments or approvals for sensitive operations.
   - Never pass secret values into agent prompts, generated files, logs, artifacts, or pull-request comments.

4. **Implement a controlled workflow**
   - Add or adapt a dedicated workflow for approved tasks, with constrained inputs and explicit permission scopes.
   - Have it call the selected Azure AI Foundry endpoint only if that integration is supported and required for the task.
   - Mask sensitive values, validate required inputs, and fail safely when a secret is missing or an operation is unauthorized.

5. **Document setup and operations**
   - Update `github.md` with the supported cloud-agent/BYOK arrangement, required settings and secrets, workflow invocation, approvals, and key rotation.
   - Update `sub-agents.md` to distinguish the GitHub cloud agent from the Azure-hosted orchestrator and its specialized agents.
   - Include a troubleshooting path that does not require printing secret values.

6. **Validate incrementally**
   - Test a harmless, non-production repository task end to end.
   - Verify that the cloud agent can complete the intended repository work, and that the workflow can use only its explicitly granted secrets and permissions.
   - Review workflow logs, artifacts, and pull-request output to ensure secrets are not disclosed.

## Acceptance criteria

- The selected BYOK configuration is documented with its actual product support and limitations.
- Cloud-agent responsibilities and privileged workflow responsibilities are clearly separated.
- Required secrets are narrowly scoped to approved workflow steps and are never made available as agent-readable values.
- A non-production end-to-end test demonstrates the intended task path and confirms secret non-disclosure.
