terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # The azurerm provider cannot yet enable the Azure SQL Database free offer,
    # so the database itself is created through the raw Azure API with azapi.
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# azurerm 4.x needs a subscription. Leave var.subscription_id null to use the
# ARM_SUBSCRIPTION_ID environment variable instead.
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}

provider "azapi" {
  subscription_id = var.subscription_id
}
