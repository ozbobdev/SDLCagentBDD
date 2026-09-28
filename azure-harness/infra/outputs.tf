output "orchestrator_fqdn" {
  value       = azurerm_container_app.orchestrator.latest_revision_fqdn
  description = "Public FQDN for orchestrator endpoint"
}

output "bdd_agent_fqdn" {
  value       = azurerm_container_app.bdd_agent.latest_revision_fqdn
  description = "Public FQDN for BDD agent endpoint"
}
