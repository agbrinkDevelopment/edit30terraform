locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      managed_by  = "terraform"
    },
    var.tags,
  )

  # Origins the backend accepts. server.ts splits CORS_ORIGIN on commas.
  cors_origins = concat(
    ["https://${azurerm_static_web_app.frontend.default_host_name}"],
    var.additional_cors_origins,
  )

  # ADO.NET-style string read by edit30backend (SQL_CONNECTION_STRING). The
  # 60 s timeout is a safety margin — normally unneeded now that auto-pause is
  # disabled by default, but still covers a cold start if it's ever re-enabled.
  sql_connection_string = join(";", [
    "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433",
    "Database=${azapi_resource.sql_database.name}",
    "User Id=${azurerm_mssql_server.main.administrator_login}",
    "Password=${random_password.sql_admin.result}",
    "Encrypt=true",
    "TrustServerCertificate=false",
    "Connection Timeout=60",
  ])
}

# Web app and storage account names are globally unique in Azure, so add a
# short stable suffix.
resource "random_string" "suffix" {
  length  = 4
  lower   = true
  numeric = true
  upper   = false
  special = false
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

# -----------------------------------------------------------------------------
# Frontend: edit30app (Create React App) on Azure Static Web Apps
# -----------------------------------------------------------------------------
resource "azurerm_static_web_app" "frontend" {
  name                = "stapp-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.static_web_app_location
  sku_tier            = var.static_web_app_sku
  sku_size            = var.static_web_app_sku
  tags                = local.tags
}

# -----------------------------------------------------------------------------
# Backend: edit30backend (Fastify) on Azure App Service (Linux, Node)
# -----------------------------------------------------------------------------
resource "azurerm_service_plan" "backend" {
  name                = "asp-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = local.tags
}

resource "azurerm_linux_web_app" "backend" {
  name                = "app-${local.name_prefix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.backend.id
  https_only          = true
  tags                = local.tags

  site_config {
    # Free/Shared plans do not support Always On.
    always_on        = !contains(["F1", "D1"], var.app_service_sku)
    app_command_line = "npm run start"
    ftps_state       = "Disabled"

    # The provider requires the eviction time whenever a path is set.
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 5

    application_stack {
      node_version = var.node_version
    }
  }

  app_settings = {
    SQL_CONNECTION_STRING = local.sql_connection_string
    PORT                  = "8080"
    HOST                  = "0.0.0.0"
    CORS_ORIGIN           = join(",", local.cors_origins)

    # Build (npm install + npm run build) on the server during deployment.
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
  }
}

# -----------------------------------------------------------------------------
# Database: Azure SQL Database, serverless, free offer
#
# The free offer gives 100,000 vCore-seconds and 32 GB of storage per month for
# one database per subscription. Auto-pause is disabled (sql_auto_pause_delay_minutes
# = -1 by default) so the database stays always-on instead of cold-starting on
# the first request after being idle; sql_min_capacity raises the floor it runs
# at while idle. Together these mean the free monthly allowance is used up in
# about a day of continuous runtime, after which — since
# sql_free_limit_exhaustion_behavior defaults to BillOverUsage, not AutoPause —
# it keeps running and bills for the rest of the month rather than pausing
# (which would undo the whole point of disabling auto-pause).
# -----------------------------------------------------------------------------
resource "random_password" "sql_admin" {
  length  = 32
  special = false # keeps the value safe inside the connection string
}

resource "azurerm_mssql_server" "main" {
  name                          = "sql-${local.name_prefix}-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  version                       = "12.0"
  administrator_login           = var.sql_admin_login
  administrator_login_password  = random_password.sql_admin.result
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true
  tags                          = local.tags
}

# The free-offer flags are not exposed by azurerm_mssql_database, hence azapi.
resource "azapi_resource" "sql_database" {
  type      = "Microsoft.Sql/servers/databases@2024-05-01-preview"
  name      = var.sql_database_name
  parent_id = azurerm_mssql_server.main.id
  location  = azurerm_resource_group.main.location
  tags      = local.tags

  body = {
    sku = {
      name     = "GP_S_Gen5"
      tier     = "GeneralPurpose"
      family   = "Gen5"
      capacity = 2
    }
    properties = {
      useFreeLimit                = true
      freeLimitExhaustionBehavior = var.sql_free_limit_exhaustion_behavior
      autoPauseDelay              = var.sql_auto_pause_delay_minutes
      minCapacity                 = var.sql_min_capacity
      maxSizeBytes                = 34359738368 # 32 GB, the free-offer limit
    }
  }
}

# 0.0.0.0 is Azure's special "allow Azure services" rule, which lets the
# backend App Service reach the database.
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "client" {
  for_each = toset(var.sql_client_ip_addresses)

  name             = "client-${replace(each.value, ".", "-")}"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = each.value
  end_ip_address   = each.value
}

# -----------------------------------------------------------------------------
# Storage account (private blob containers, e.g. for uploaded images)
# -----------------------------------------------------------------------------
resource "azurerm_storage_account" "main" {
  # 3-24 chars, lowercase alphanumeric only.
  name                = "st${var.project_name}${var.environment}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  tags = local.tags
}

resource "azurerm_storage_container" "main" {
  for_each = toset(var.storage_containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}
