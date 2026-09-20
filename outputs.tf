output "resource_group_name" {
  description = "Resource group containing everything."
  value       = azurerm_resource_group.main.name
}

output "static_web_app_name" {
  description = "Static Web App name (for the SWA CLI / GitHub Action)."
  value       = azurerm_static_web_app.frontend.name
}

output "static_web_app_url" {
  description = "Public URL of the frontend."
  value       = "https://${azurerm_static_web_app.frontend.default_host_name}"
}

output "static_web_app_deployment_token" {
  description = "Deployment token for publishing edit30app (GitHub secret AZURE_STATIC_WEB_APPS_API_TOKEN, or `swa deploy --deployment-token`)."
  value       = azurerm_static_web_app.frontend.api_key
  sensitive   = true
}

output "backend_app_name" {
  description = "App Service name (for `az webapp up --name ...`)."
  value       = azurerm_linux_web_app.backend.name
}

output "backend_url" {
  description = "Base URL of the backend."
  value       = "https://${azurerm_linux_web_app.backend.default_hostname}"
}

output "frontend_api_url" {
  description = "Value to use for REACT_APP_API_URL when building edit30app (CRA bakes it in at build time)."
  value       = "https://${azurerm_linux_web_app.backend.default_hostname}/api"
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL server."
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the SQL database."
  value       = azapi_resource.sql_database.name
}

output "sql_connection_string" {
  description = "SQL_CONNECTION_STRING for edit30backend (contains the generated admin password)."
  value       = local.sql_connection_string
  sensitive   = true
}

output "storage_account_name" {
  description = "Storage account name."
  value       = azurerm_storage_account.main.name
}

output "storage_blob_endpoint" {
  description = "Primary blob endpoint."
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_connection_string" {
  description = "Storage account connection string."
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}
