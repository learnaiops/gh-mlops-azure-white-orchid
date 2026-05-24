locals {
  suffix      = "8bx7s6"
  name_prefix = "white-orchid-${local.suffix}"
  common_tags = {
    project     = "white-orchid"
    environment = "preprod"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}
