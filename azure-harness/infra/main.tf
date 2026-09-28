terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

resource "azurerm_resource_group" "agents" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_container_app_environment" "agents" {
  name                = "cae-sdlcdocs"
  location            = azurerm_resource_group.agents.location
  resource_group_name = azurerm_resource_group.agents.name
}

resource "azurerm_container_app" "orchestrator" {
  name                         = "ca-orchestrator"
  container_app_environment_id = azurerm_container_app_environment.agents.id
  resource_group_name          = azurerm_resource_group.agents.name
  revision_mode                = "Single"

  template {
    container {
      name   = "orchestrator"
      image  = var.orchestrator_image
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

resource "azurerm_container_app" "bdd_agent" {
  name                         = "ca-bdd-agent"
  container_app_environment_id = azurerm_container_app_environment.agents.id
  resource_group_name          = azurerm_resource_group.agents.name
  revision_mode                = "Single"

  template {
    container {
      name   = "bdd-agent"
      image  = var.bdd_agent_image
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
