variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant ID"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for agent resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "australiaeast"
}

variable "ai_services_account_name" {
  description = "Globally unique Azure AI Foundry account name"
  type        = string
  default     = "aisdlcdocsharness001"
}

variable "ai_services_sku" {
  description = "SKU for the Azure AI Foundry account"
  type        = string
  default     = "S0"
}

variable "model_deployment_name" {
  description = "Deployment name used by clients for chat completions"
  type        = string
  default     = "gpt-4o-mini"
}

variable "model_name" {
  description = "Foundry model name to deploy"
  type        = string
  default     = "gpt-4o-mini"
}

variable "model_version" {
  description = "Model version for the deployment"
  type        = string
  default     = "2024-07-18"
}

variable "model_capacity" {
  description = "Provisioned capacity units for the model deployment"
  type        = number
  default     = 10
}

variable "model_sku_name" {
  description = "SKU name for model deployment (for example, GlobalStandard)"
  type        = string
  default     = "GlobalStandard"
}

variable "additional_model_deployments" {
  description = "Extra model deployments used by the model router, keyed by deployment name"
  type = map(object({
    model_name = string
    version    = string
    sku_name   = optional(string, "GlobalStandard")
    capacity   = optional(number, 10)
  }))
  default = {
    "gpt-5.6-terra" = { model_name = "gpt-5.6-terra", version = "2026-07-09" }
    "gpt-6.1-sol"   = { model_name = "gpt-6.1-sol", version = "2026-09-29" }
    "gpt-6-sol"     = { model_name = "gpt-6-sol", version = "2026-09-22" }
    "gpt-6-astra"   = { model_name = "gpt-6-astra", version = "2026-09-03" }
  }
}

variable "log_analytics_name" {
  description = "Log Analytics workspace backing sdlc-appinsights"
  type        = string
  default     = "log-sdlc-harness"
}

variable "container_registry_name" {
  description = "Globally unique Azure Container Registry name for the orchestrator image"
  type        = string
  default     = "acrsdlcdocsharness001"
}

variable "orchestrator_image" {
  description = "Full orchestrator image reference; empty skips creating the Container App (the script builds the image first)"
  type        = string
  default     = ""
}

variable "orchestrator_audience" {
  description = "Entra audience (Application ID URI) expected in tokens sent to the orchestrator"
  type        = string
  default     = ""
}

variable "orchestrator_allowed_client_ids" {
  description = "Client IDs (the dispatch app registration) allowed to call POST /work-items"
  type        = list(string)
  default     = []
}

variable "orchestrator_allowed_repos" {
  description = "owner/repo values the orchestrator accepts work for"
  type        = list(string)
  default     = []
}

variable "github_app_id" {
  description = "GitHub App ID used to comment, label, commit and open PRs"
  type        = string
  default     = ""
}

variable "github_app_installation_id" {
  description = "Installation ID of the GitHub App on the repository"
  type        = string
  default     = ""
}

variable "github_app_private_key" {
  description = "GitHub App private key (PEM). Read from Key Vault secret github-app-private-key by 002SetupAzure.ps1"
  type        = string
  default     = ""
  sensitive   = true
}

variable "foundry_project_name" {
  description = "Azure AI Foundry project name"
  type        = string
  default     = "sdlcagentbdd-project"
}

variable "foundry_project_display_name" {
  description = "Display name for the Azure AI Foundry project"
  type        = string
  default     = "SDLCagentBDD Project"
}

variable "foundry_project_description" {
  description = "Description for the Azure AI Foundry project"
  type        = string
  default     = "Foundry project for SDLCagentBDD prompt-agent workflows"
}

variable "storage_account_name" {
  description = "Globally unique storage account name for harness data"
  type        = string
  default     = "sdlcdocsharness001"
}

variable "key_vault_name" {
  description = "Key Vault name (created outside Terraform, exposed as an output)"
  type        = string
  default     = "kv-sdlcdocs-harness"
}
