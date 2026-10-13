resource "azurerm_log_analytics_workspace" "sdlc" {
  name                = var.log_analytics_name
  location            = azurerm_resource_group.agents.location
  resource_group_name = azurerm_resource_group.agents.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "sdlc" {
  name                = "sdlc-appinsights"
  location            = azurerm_resource_group.agents.location
  resource_group_name = azurerm_resource_group.agents.name
  workspace_id        = azurerm_log_analytics_workspace.sdlc.id
  application_type    = "web"
}

# Foundry account logs and metrics go to the same workspace that backs Application Insights
data "azurerm_monitor_diagnostic_categories" "harness" {
  resource_id = azurerm_cognitive_account.harness.id
}

resource "azurerm_monitor_diagnostic_setting" "harness" {
  name                       = "sdlc-harness-to-loganalytics"
  target_resource_id         = azurerm_cognitive_account.harness.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.sdlc.id

  dynamic "enabled_log" {
    for_each = toset(data.azurerm_monitor_diagnostic_categories.harness.log_category_types)
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Foundry connection so agents, tracing and evaluations in the project log to sdlc-appinsights
resource "azapi_resource" "appinsights_connection" {
  type      = "Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview"
  name      = "sdlc-appinsights"
  parent_id = azurerm_cognitive_account.harness.id

  body = {
    properties = {
      category      = "AppInsights"
      target        = azurerm_application_insights.sdlc.id
      authType      = "ApiKey"
      isSharedToAll = true
      credentials = {
        key = azurerm_application_insights.sdlc.connection_string
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_application_insights.sdlc.id
      }
    }
  }
}
