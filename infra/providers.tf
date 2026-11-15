terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # State remoto em Azure Storage (criado por infra/bootstrap.sh).
  # Os valores entram no "terraform init -backend-config=..." — nada de state no repositório.
  backend "azurerm" {
    container_name   = "tfstate"
    key              = "belka.tfstate"
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}
  # O usuário/identidade de deploy só tem Contributor no resource group;
  # os resource providers são registrados uma vez pelo bootstrap.
  resource_provider_registrations = "none"
}
