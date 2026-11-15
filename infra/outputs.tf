output "api_url" {
  description = "URL pública do MVP."
  value       = "https://${azurerm_container_app.api.ingress[0].fqdn}"
}

output "application_insights" {
  value = azurerm_application_insights.main.name
}

output "workbook_sinais_de_ouro" {
  value = azurerm_application_insights_workbook.golden_signals.display_name
}
