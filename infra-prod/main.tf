resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false

  # Regenerate the suffix when the region changes so globally-unique names
  # (Key Vault, ACR, storage, ML workspace) don't collide with the prior
  # region's resources. The purge-protected Key Vault in particular keeps its
  # name reserved for 90 days after deletion and cannot be reused elsewhere.
  keepers = {
    location = var.location
  }
}

locals {
  name_prefix = "${var.project}-prod-${random_string.suffix.result}"
  common_tags = {
    project     = var.project
    environment = "prod"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}
