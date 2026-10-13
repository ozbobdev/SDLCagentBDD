resource "azurerm_container_registry" "orchestrator" {
  name                = var.container_registry_name
  resource_group_name = azurerm_resource_group.agents.name
  location            = azurerm_resource_group.agents.location
  sku                 = "Basic"
  admin_enabled       = false
}

resource "azurerm_user_assigned_identity" "orchestrator" {
  name                = "id-sdlc-orchestrator"
  resource_group_name = azurerm_resource_group.agents.name
  location            = azurerm_resource_group.agents.location
}

resource "azurerm_role_assignment" "orchestrator_acr_pull" {
  scope                = azurerm_container_registry.orchestrator.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}

resource "azurerm_container_app_environment" "harness" {
  name                       = "cae-sdlc-harness"
  resource_group_name        = azurerm_resource_group.agents.name
  location                   = azurerm_resource_group.agents.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.sdlc.id
}

resource "azurerm_container_app" "orchestrator" {
  count                        = var.orchestrator_image == "" ? 0 : 1
  name                         = "ca-sdlc-orchestrator"
  resource_group_name          = azurerm_resource_group.agents.name
  container_app_environment_id = azurerm_container_app_environment.harness.id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.orchestrator.id]
  }

  registry {
    server   = azurerm_container_registry.orchestrator.login_server
    identity = azurerm_user_assigned_identity.orchestrator.id
  }

  secret {
    name  = "harness-api-key"
    value = azurerm_cognitive_account.harness.primary_access_key
  }
  secret {
    name  = "appinsights-connection-string"
    value = azurerm_application_insights.sdlc.connection_string
  }
  secret {
    name  = "github-app-private-key"
    value = var.github_app_private_key == "" ? "unset" : var.github_app_private_key
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3

    container {
      name   = "orchestrator"
      image  = var.orchestrator_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "AZURE_HARNESS_ENDPOINT"
        value = azurerm_cognitive_account.harness.endpoint
      }
      env {
        name        = "AZURE_HARNESS_API_KEY"
        secret_name = "harness-api-key"
      }
      env {
        name  = "AZURE_HARNESS_MODEL_DEPLOYMENTS"
        value = join(",", concat([azurerm_cognitive_deployment.chat.name], [for d in azurerm_cognitive_deployment.router : d.name]))
      }
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-connection-string"
      }
      env {
        name  = "ENTRA_TENANT_ID"
        value = var.tenant_id
      }
      env {
        name  = "ORCHESTRATOR_AUDIENCE"
        value = var.orchestrator_audience
      }
      env {
        name  = "ALLOWED_CLIENT_IDS"
        value = join(",", var.orchestrator_allowed_client_ids)
      }
      env {
        name  = "ALLOWED_REPOS"
        value = join(",", var.orchestrator_allowed_repos)
      }
      env {
        name  = "GITHUB_APP_ID"
        value = var.github_app_id
      }
      env {
        name  = "GITHUB_APP_INSTALLATION_ID"
        value = var.github_app_installation_id
      }
      env {
        name        = "GITHUB_APP_PRIVATE_KEY"
        secret_name = "github-app-private-key"
      }

      liveness_probe {
        transport = "HTTP"
        path      = "/healthz"
        port      = 8080
      }
    }
  }

  depends_on = [azurerm_role_assignment.orchestrator_acr_pull]
}
