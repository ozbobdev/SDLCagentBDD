# GitHub Copilot cloud agent and Foundry BYOK

This guide separates GitHub Copilot cloud-agent work from Microsoft Foundry credentials and privileged GitHub Actions operations.

## What BYOK applies to

GitHub documents BYOK for the **Copilot SDK**. Its Microsoft Foundry provider can use an Azure endpoint and API key from the SDK process. That does not configure the model used by GitHub's hosted Copilot cloud-agent service. A repository secret is not a cloud-agent model-provider setting.

Do not add the Foundry API key as a Copilot **Agents** secret. GitHub documents that Agents secrets are exposed to the cloud agent as environment variables in its development environment. The Foundry key is not needed for ordinary cloud-agent repository work.

The cloud agent may investigate issues, propose code and documentation changes, and open pull requests, subject to the repository's Copilot availability, organization policy, and repository permissions. A repository maintainer must verify the applicable Copilot plan/seat and enablement in GitHub settings; this repository cannot inspect account entitlements. Use GitHub's supported cloud-agent model selection and configuration, not the local SDK BYOK flow, for cloud-agent tasks.

References:

- [Copilot SDK BYOK](https://docs.github.com/en/copilot/how-tos/copilot-sdk/auth/byok)
- [Configure secrets and variables for Copilot cloud agent](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/configure-secrets-and-variables)
- [Configure cloud-agent settings](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/configuring-agent-settings)
- [Give cloud agent access to approved resources](https://docs.github.com/en/copilot/tutorials/cloud-agent/give-access-to-resources)

## Provision the Foundry endpoint

Run [002SetupAzure.ps1](./infra/002SetupAzure.ps1) to provision the Terraform resources in [azure-harness/infra/](./azure-harness/infra/):

```powershell
. .\infra\002SetupAzure.ps1
Invoke-SdlcDocsHarnessDeployment `
  -TenantId "<tenant-guid>" `
  -SubscriptionId "<subscription-guid>" `
  -Location "australiaeast" `
  -GitHubRepo "ozbobdev/SDLCagentBDD"
```

The script stores the Foundry API key, endpoint, and deployment name in Azure Key Vault and, by default, in the current Windows user's environment for local use. It does **not** copy them to GitHub Actions or Agents secrets. Pass `-SetLocalUserEnvironment:$false` if those local environment variables are not wanted.

## Optional protected Actions environment

The repository includes a manual Foundry connectivity smoke test. It checks that an explicitly approved Actions job can call the model; it does not make the cloud agent use that model or perform agent-requested code changes.

1. In repository **Settings → Environments**, create `foundry-byok`.
2. Add required reviewers and, where appropriate, limit deployment branches. Environment protection must be configured before running the setup script.
3. Authenticate Azure CLI and GitHub CLI as an operator with Key Vault secret-read and repository environment-secret write permissions.
4. Run the setup script. Its command log records command names and non-secret arguments only; secret values are piped to GitHub CLI over stdin and are never written to the log.

```powershell
az login
gh auth login
. .\infra\003ConfigureBYOK.ps1 `
  -KeyVaultName "<key-vault-name>" `
  -GitHubRepo "ozbobdev/SDLCagentBDD"
```

The script copies only `harness-api-key`, `harness-endpoint`, and `harness-model-deployment` to **Actions environment secrets** in `foundry-byok`. It verifies the required-reviewer rule and verifies secret names only. Review its redacted command log under `infra/logs/`; those logs are ignored by Git.

A maintainer can then choose **Actions → Foundry BYOK smoke test → Run workflow**. The workflow has no repository token permissions, requires approval through the environment, sends a fixed harmless prompt, validates the response shape, and never prints the model response or request credentials. The cloud agent can request that a maintainer run this smoke test; it does not receive the environment secrets or dispatch authority.

The infrastructure deployment workflow is also manual and uses the `azure-harness-deploy` environment. Configure required reviewers for that environment before running it. Do not make infrastructure deployment an automatic result of a pull request or an agent-authored workflow change.

## Local Copilot SDK usage

For local SDK development, use the Azure values from Key Vault in the local process configuration as described by the [Copilot SDK BYOK guide](https://docs.github.com/en/copilot/how-tos/copilot-sdk/auth/byok). Keep the key in an OS-protected local secret store or environment variable; do not hard-code it, commit it, or copy it into cloud-agent Agents secrets.

## Rotation and troubleshooting

- Rotate the Azure AI Services account key through Azure, update the `harness-api-key` Key Vault secret, then rerun `003ConfigureBYOK.ps1` to update the protected Actions environment secret. Avoid revoking the old key until the update is confirmed.
- For a setup failure, check `az account show` and `gh auth status` without printing access tokens. Confirm Key Vault access and that the `foundry-byok` environment has a required-reviewer protection rule.
- For a failed smoke test, inspect only its HTTP status and generic error. The workflow suppresses response bodies and does not log credentials. Confirm that the deployment name, endpoint, model availability, and API version are valid for the Azure resource.
- The command log in `infra/logs/` records the commands and exit status, not stdout, stderr, or secret values. Treat the log as operational metadata nonetheless and do not commit it.

Do not commit API keys, tokens, Terraform plans, or Terraform state. Prefer federated identity for Azure automation. Rotate long-lived keys promptly if they may have been exposed.
