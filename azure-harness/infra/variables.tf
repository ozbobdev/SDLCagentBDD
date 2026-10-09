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

variable "orchestrator_image" {
  description = "Container image for orchestrator agent"
  type        = string
}

variable "bdd_agent_image" {
  description = "Container image for BDD specialized agent"
  type        = string
}
