provider "azurerm" {
  features {}
}

terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 2.20"
    }
  }
}
