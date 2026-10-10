# Legacy Azure Container Apps scaffold

This experimental Terraform scaffold deploys two Azure Container Apps from externally supplied image references: an orchestrator and a BDD agent. It does not provision Microsoft Foundry Agent Service resources, and the repository does not contain the corresponding agent source or image build/publish workflow.

The image variables are consumed by Azure Container Apps, not by Foundry. Their current defaults in the setup script and GitHub Actions workflow are not a supported Foundry deployment path. Do not use this scaffold as the Foundry setup; see the repository [README](../../README.md#microsoft-foundry-deployment-choices) for the current Prompt Agent and optional Hosted Agent paths.
