terraform {
  required_version = ">= 1.6.0"

  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "azapi" {}

resource "azurerm_resource_group" "agents" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_cognitive_account" "harness" {
  name                          = var.ai_services_account_name
  location                      = azurerm_resource_group.agents.location
  resource_group_name           = azurerm_resource_group.agents.name
  kind                          = "AIServices"
  sku_name                      = var.ai_services_sku
  custom_subdomain_name         = var.ai_services_account_name
  local_auth_enabled            = true
  public_network_access_enabled = true
  project_management_enabled    = true

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_cognitive_deployment" "chat" {
  name                 = var.model_deployment_name
  cognitive_account_id = azurerm_cognitive_account.harness.id

  model {
    format  = "OpenAI"
    name    = var.model_name
    version = var.model_version
  }

  sku {
    name     = var.model_sku_name
    capacity = var.model_capacity
  }
}

resource "azurerm_cognitive_account_project" "harness" {
  name                 = var.foundry_project_name
  cognitive_account_id = azurerm_cognitive_account.harness.id
  location             = azurerm_resource_group.agents.location
  display_name         = var.foundry_project_display_name
  description          = var.foundry_project_description

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_storage_account" "harness" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.agents.name
  location                 = azurerm_resource_group.agents.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}
