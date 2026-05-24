terraform {
  required_version = ">= 1.5"

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstatestorageacc0904ft"
    container_name       = "tfstate"
    key                  = "project-white-orchid-ml-prod.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = "7d6b25b0-6d1c-49a8-8790-6af7c8f3fadc"
  resource_provider_registrations = "none"
}

provider "azuread" {}
