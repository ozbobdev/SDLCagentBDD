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
