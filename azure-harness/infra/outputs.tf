output "harness_api_key" {
  value       = azurerm_cognitive_account.harness.primary_access_key
  sensitive   = true
  description = "Primary API key for the Azure AI Foundry account"
}

output "harness_endpoint" {
  value       = azurerm_cognitive_account.harness.endpoint
  description = "Endpoint for Foundry-compatible chat completions"
}

output "model_deployment_name" {
  value       = azurerm_cognitive_deployment.chat.name
  description = "Model deployment name for chat completions"
}

output "model_deployment_names" {
  value       = concat([azurerm_cognitive_deployment.chat.name], [for d in azurerm_cognitive_deployment.router : d.name])
  description = "All model deployment names available to the router"
}

output "appinsights_connection_string" {
  value       = azurerm_application_insights.sdlc.connection_string
  sensitive   = true
  description = "Connection string for sdlc-appinsights"
}

output "appinsights_name" {
  value       = azurerm_application_insights.sdlc.name
  description = "Application Insights resource name"
}

output "container_registry_name" {
  value       = azurerm_container_registry.orchestrator.name
  description = "ACR hosting the orchestrator image"
}

output "container_registry_login_server" {
  value       = azurerm_container_registry.orchestrator.login_server
  description = "ACR login server"
}

output "orchestrator_url" {
  value       = length(azurerm_container_app.orchestrator) > 0 ? "https://${azurerm_container_app.orchestrator[0].ingress[0].fqdn}" : ""
  description = "Public HTTPS URL of the orchestrator (POST /work-items)"
}

output "ai_services_account_name" {
  value       = azurerm_cognitive_account.harness.name
  description = "Azure AI Foundry account name"
}

output "foundry_project_name" {
  value       = azurerm_cognitive_account_project.harness.name
  description = "Azure AI Foundry project name"
}

output "foundry_project_id" {
  value       = azurerm_cognitive_account_project.harness.id
  description = "Azure AI Foundry project resource ID"
}

output "foundry_project_endpoints" {
  value       = azurerm_cognitive_account_project.harness.endpoints
  description = "Azure AI Foundry project endpoints"
}

output "storage_connection_string" {
  value       = azurerm_storage_account.harness.primary_connection_string
  sensitive   = true
  description = "Connection string for the harness storage account"
}

output "key_vault_name" {
  value       = var.key_vault_name
  description = "Key Vault name"
}
